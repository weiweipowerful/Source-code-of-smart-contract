// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {TokenTransferrer} from "./TokenTransferrer.sol";

import {Pool, NewReward, NewRewardBatchERC1155, Reward, RewardItemType, ClaimRequest, PoolRequest} from "./types/NiftyIslandReward.sol";

/**
 *  @title Nifty Island Reward
 *  @notice Allows reward distributors to create reward pools from which eligible users can claim rewards.
 *  @custom:version v1.0.0
 */
contract NiftyIslandReward is
    Pausable,
    ReentrancyGuard,
    AccessControl,
    EIP712,
    TokenTransferrer,
    ERC721Holder,
    ERC1155Holder
{
    using ECDSA for bytes32;

    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 private constant CLAIM_REQUEST_TYPE_HASH =
        // prettier-ignore
        keccak256(
            "ClaimRequest("
                "uint256 startTimestamp,"
                "uint256 endTimestamp,"
                "uint256 platformFee,"
                "address platformFeeRecipient,"
                "address to,"
                "uint256[] claimIds,"
                "uint256[] rewardIds,"
                "uint256[] amounts"
            ")"
        );
    bytes32 private constant POOL_REQUEST_TYPE_HASH =
        // prettier-ignore
        keccak256(
            "PoolRequest("
                "uint256 poolId,"
                "uint256 expiration,"
                "address owner,"
                "address signer"
            ")"
        );

    mapping(uint256 poolId => Pool pool) public poolByPoolId;
    mapping(uint256 rewardId => Reward reward) public rewardByRewardId;
    mapping(uint256 claimId => bool status) public claimStatusByClaimId;

    address public poolRequestSigner;

    constructor(address _defaultAdmin, address _poolRequestSigner) EIP712("NiftyIslandReward", "1") {
        if (_defaultAdmin == address(0) || _poolRequestSigner == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(PAUSER_ROLE, _defaultAdmin);
        poolRequestSigner = _poolRequestSigner;
    }

    /**
     * @notice Invoked by pool admin to deposit rewards into the pool.
     * @dev Requires the pool to be active.
     * The contract must have necessary approvals to transfer ERC20, ERC721, and ERC1155 tokens on behalf of the pool owner.
     * The function must be called with sufficient ETH to cover the reward deposit, if necessary.
     * @param poolId The unique identifier of the pool to which rewards are being deposited.
     * @param rewards An array of rewards to be deposited into the pool.
     * @param batchERC1155Rewards An array of batch ERC1155 rewards, allowing multiple ERC1155 tokens to be deposited at once.
     */
    function depositRewards(
        uint256 poolId,
        NewReward[] calldata rewards,
        NewRewardBatchERC1155[] calldata batchERC1155Rewards
    ) external payable nonReentrant whenNotPaused {
        _depositRewards(poolId, rewards, batchERC1155Rewards);
    }

    /**
     * @notice Creates or updates a reward pool and deposits new rewards into it.
     * @dev This function allows a pool owner to create a new reward pool or update an existing one, and deposit rewards at the same time.
     * The pool details are specified in the `request` parameter, and the rewards to be deposited can include various token types like ERC20, ERC721, and ERC1155.
     * A valid signature is required from the `poolRequestSigner` to authorize the creation of the pool.
     * The function must be called with sufficient ETH to cover the reward deposit, if necessary.
     * @param request The pool details, including owner, signer, rewards, and expiration time.
     * @param rewards An array of rewards to be deposited into the pool.
     * @param batchERC1155Rewards An array of batch ERC1155 rewards, allowing multiple ERC1155 tokens to be deposited at once.
     * @param signature A signature from the `poolRequestSigner` for pool creation. Use `0x` for updates.
     */
    function upsertPoolAndDepositRewards(
        PoolRequest calldata request,
        NewReward[] calldata rewards,
        NewRewardBatchERC1155[] calldata batchERC1155Rewards,
        bytes calldata signature
    ) external payable nonReentrant whenNotPaused {
        upsertPool(request, signature);
        _depositRewards(request.poolId, rewards, batchERC1155Rewards);
    }

    /**
     * @notice Claims rewards from a specified pool.
     * @dev This function allows an eligible user to claim rewards from a pool by
     * providing a valid claim request and signature from the designated pool signer.
     * @param poolId The unique identifier of the pool from which rewards are being claimed.
     * @param request The data structure containing the details of the claim.
     * @param signature The signature from the designated pool signer authorizing the claim.
     */
    function claimRewards(
        uint256 poolId,
        ClaimRequest calldata request,
        bytes calldata signature
    ) external payable nonReentrant whenNotPaused {
        _validateClaimRequest(poolId, request, signature);

        uint256 claimIdsLength = request.claimIds.length;

        if (claimIdsLength == 0) {
            revert ArrayEmpty();
        }

        if (claimIdsLength != request.rewardIds.length || claimIdsLength != request.amounts.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < claimIdsLength; i++) {
            uint256 claimId = request.claimIds[i];
            uint256 rewardId = request.rewardIds[i];
            uint256 amount = request.amounts[i];

            if (amount == 0) {
                revert InvalidRewardAmount(rewardId, amount);
            }

            if (claimStatusByClaimId[claimId]) {
                revert ClaimRequestUsed(claimId);
            }

            claimStatusByClaimId[claimId] = true;

            Reward storage existingReward = rewardByRewardId[rewardId];

            if (existingReward.total < amount) {
                revert InsufficientRewardBalance(existingReward.total, amount);
            }

            existingReward.total -= amount;

            _transferRewardToCaller(existingReward.token, existingReward.tokenId, amount, existingReward.itemType);
        }

        // Transfer platformFee to platformFeeRecipient
        if (request.platformFee > 0) {
            _performNativeTransfer(request.platformFeeRecipient, request.platformFee);
        }

        emit ClaimRequestFulfilled(poolId, request.to, request);
    }

    /**
     * @notice Withdraws all remaining rewards from a specified pool.
     * @dev Only the pool owner can call this function.
     * Rewards can only be withdrawn if the pool is inactive or if the pool is permanent (no expiry).
     * Rewards must belong to the specified pool.
     * @param poolId The unique identifier of the pool from which all rewards are being withdrawn.
     * @param rewardIds An array of reward IDs to be withdrawn from the pool.
     */
    function withdrawRewards(uint256 poolId, uint256[] calldata rewardIds) external nonReentrant {
        uint256 rewardIdsLength = rewardIds.length;

        if (rewardIdsLength == 0) {
            revert ArrayEmpty();
        }

        if (poolByPoolId[poolId].owner != msg.sender) {
            revert UnauthorizedCaller(poolByPoolId[poolId].owner, msg.sender);
        }

        if (!_isPoolRewardsWithdrawalAllowed(poolId)) {
            revert PoolActive(poolId);
        }

        for (uint256 i = 0; i < rewardIdsLength; i++) {
            Reward storage existingReward = rewardByRewardId[rewardIds[i]];

            // Ensure the reward belongs to the specified pool before withdrawing
            if (poolId != existingReward.poolId) {
                revert InvalidRewardPool(poolId, existingReward.poolId);
            }

            uint256 amountToTransfer = existingReward.total;

            if (amountToTransfer > 0) {
                existingReward.total = 0;
                _transferRewardToCaller(
                    existingReward.token,
                    existingReward.tokenId,
                    amountToTransfer,
                    existingReward.itemType
                );
            }
        }

        emit RewardsWithdrawn(poolId, rewardIds);
    }

    function getRewardsByRewardIds(uint256[] calldata rewardIds) external view returns (Reward[] memory rewards) {
        rewards = new Reward[](rewardIds.length);

        for (uint256 i = 0; i < rewardIds.length; i++) {
            rewards[i] = rewardByRewardId[rewardIds[i]];
        }

        return rewards;
    }

    /**
     * @notice Creates a new pool or updates an existing pool for reward distribution.
     * @dev This function allows a reward distributor to create a new reward pool or update an existing one.
     * A valid signature is required from the `poolRequestSigner` to authorize the creation of the pool.
     * @param request The data structure containing the details of the pool.
     * @param signature A signature from the `poolRequestSigner` for pool creation. Use `0x` for updates.
     */
    function upsertPool(PoolRequest calldata request, bytes calldata signature) public whenNotPaused {
        if (request.poolId == 0) {
            revert InvalidPoolId();
        }

        if (request.owner == address(0) || request.signer == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        Pool storage existingPool = poolByPoolId[request.poolId];

        address existingOwner = existingPool.owner;

        // Pool Creation
        if (existingOwner == address(0)) {
            if (request.expiration != 0 && request.expiration <= block.timestamp) {
                revert InvalidPoolExpiration(request.expiration, block.timestamp);
            }

            _validatePoolRequest(request, signature);

            poolByPoolId[request.poolId] = Pool({
                expiration: request.expiration,
                owner: request.owner,
                signer: request.signer
            });
        } else {
            // Update existing pool
            if (existingOwner != msg.sender) {
                revert UnauthorizedCaller(existingOwner, msg.sender);
            }

            uint256 existingExpiration = existingPool.expiration;

            if (
                existingExpiration >= request.expiration &&
                existingOwner == request.owner &&
                existingPool.signer == request.signer
            ) {
                revert StateUnchanged();
            }

            existingPool.owner = request.owner;
            existingPool.signer = request.signer;

            // Update expiration only if the request meets valid conditions
            if (existingExpiration == 0) {
                // Revert if attempting to set expiration on a permanent pool
                if (request.expiration != 0) {
                    revert PermanentPoolExpirationImmutable();
                }
            } else if (request.expiration > existingExpiration) {
                // Update expiration for a time-bounded pool only if it’s being extended
                existingPool.expiration = request.expiration;
            }
        }

        emit PoolUpserted(request.poolId, request);
    }

    function verifyClaimRequestSignature(
        uint256 poolId,
        ClaimRequest calldata request,
        bytes calldata signature
    ) public view returns (bool, address) {
        address recoveredSigner = _hashTypedDataV4(_hashClaimRequest(request)).recover(signature);

        return (recoveredSigner == poolByPoolId[poolId].signer, recoveredSigner);
    }

    function verifyPoolRequestSignature(
        PoolRequest calldata request,
        bytes calldata signature
    ) public view returns (bool, address) {
        address recoveredSigner = _hashTypedDataV4(_hashPoolRequest(request)).recover(signature);

        return (recoveredSigner == poolRequestSigner, recoveredSigner);
    }

    function _depositRewards(
        uint256 poolId,
        NewReward[] calldata rewards,
        NewRewardBatchERC1155[] calldata batchERC1155Rewards
    ) internal {
        if (poolByPoolId[poolId].owner != msg.sender) {
            revert UnauthorizedCaller(poolByPoolId[poolId].owner, msg.sender);
        }

        if (!_isPoolActive(poolId)) {
            revert PoolInactive(poolId);
        }

        uint256 rewardsLength = rewards.length;
        uint256 batchERC1155RewardsLength = batchERC1155Rewards.length;

        if (rewardsLength == 0 && batchERC1155RewardsLength == 0) {
            revert RewardDepositArraysEmpty();
        }

        uint256 nativeRewardsBalance = msg.value;

        uint256[] memory rewardIds = new uint256[](rewardsLength);

        // Transfer rewards from `msg.sender` into the contract
        for (uint256 i = 0; i < rewardsLength; i++) {
            NewReward calldata reward = rewards[i];

            // Special case for native rewards
            if (reward.itemType == RewardItemType.NATIVE) {
                if (nativeRewardsBalance < reward.total) {
                    revert InsufficientNativeRewardBalance(nativeRewardsBalance, reward.total);
                }

                unchecked {
                    nativeRewardsBalance -= reward.total;
                }
            }

            _handleRewardDeposit(poolId, reward);

            rewardIds[i] = reward.rewardId;
        }

        uint256[][] memory batchRewardIds = new uint256[][](batchERC1155RewardsLength);

        // Transfer batch ERC1155 rewards from `msg.sender` into the contract.
        // Used for gas efficiency with ERC1155 reawards.
        for (uint256 i = 0; i < batchERC1155RewardsLength; i++) {
            _handleBatchERC1155RewardDeposit(poolId, batchERC1155Rewards[i]);

            batchRewardIds[i] = batchERC1155Rewards[i].rewardIds;
        }

        if (nativeRewardsBalance > 0) {
            revert ExcessNativeRewardBalance(nativeRewardsBalance);
        }

        emit RewardsDeposited(poolId, rewardIds, batchRewardIds);
    }

    function _handleRewardDeposit(uint256 poolId, NewReward calldata _reward) internal {
        if (_reward.total == 0 || (_reward.itemType == RewardItemType.ERC721 && _reward.total != 1)) {
            revert InvalidRewardTotal(_reward.rewardId, _reward.total);
        }

        Reward storage existingReward = rewardByRewardId[_reward.rewardId];
        if (existingReward.poolId == 0) {
            // Create a new reward
            existingReward.tokenId = _reward.tokenId;
            existingReward.total = _reward.total;
            existingReward.poolId = poolId;
            existingReward.token = _reward.token;
            existingReward.itemType = _reward.itemType;
        } else if (existingReward.poolId == poolId) {
            // If the reward already exists, update its total.
            if (
                existingReward.token == _reward.token &&
                existingReward.tokenId == _reward.tokenId &&
                existingReward.itemType == _reward.itemType
            ) {
                existingReward.total += _reward.total;
            } else {
                revert RewardDetailsMismatch(_reward.rewardId);
            }
        } else {
            revert InvalidRewardPool(poolId, existingReward.poolId);
        }

        // Handle the transfer of non-native tokens
        if (_reward.itemType != RewardItemType.NATIVE) {
            _transferRewardFromCaller(_reward);
        }
    }

    function _handleBatchERC1155RewardDeposit(
        uint256 poolId,
        NewRewardBatchERC1155 calldata _batchERC1155Reward
    ) internal {
        uint256 batchLength = _batchERC1155Reward.rewardIds.length;

        if (batchLength == 0) {
            revert BatchERC1155RewardEmpty();
        }

        if (_batchERC1155Reward.tokenIds.length != batchLength || _batchERC1155Reward.totals.length != batchLength) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < batchLength; i++) {
            uint256 rewardId = _batchERC1155Reward.rewardIds[i];
            uint256 total = _batchERC1155Reward.totals[i];

            // Ensure that the reward total is not zero
            if (total == 0) {
                revert InvalidRewardTotal(rewardId, total);
            }

            Reward storage existingReward = rewardByRewardId[rewardId];

            if (existingReward.poolId == 0) {
                // Create a new reward
                existingReward.tokenId = _batchERC1155Reward.tokenIds[i];
                existingReward.total = total;
                existingReward.poolId = poolId;
                existingReward.token = _batchERC1155Reward.token;
                existingReward.itemType = RewardItemType.ERC1155;
            } else if (existingReward.poolId == poolId) {
                // If the reward already exists, update its total.
                if (
                    existingReward.token == _batchERC1155Reward.token &&
                    existingReward.tokenId == _batchERC1155Reward.tokenIds[i] &&
                    existingReward.itemType == RewardItemType.ERC1155
                ) {
                    existingReward.total += total;
                } else {
                    revert RewardDetailsMismatch(rewardId);
                }
            } else {
                revert InvalidRewardPool(poolId, existingReward.poolId);
            }
        }

        _performERC1155BatchTransfer(
            _batchERC1155Reward.token,
            msg.sender,
            address(this),
            _batchERC1155Reward.tokenIds,
            _batchERC1155Reward.totals
        );
    }

    function _isPoolActive(uint256 poolId) internal view returns (bool) {
        uint256 poolExpiration = poolByPoolId[poolId].expiration;

        return poolExpiration == 0 || block.timestamp < poolExpiration;
    }

    function _isPoolRewardsWithdrawalAllowed(uint256 poolId) internal view returns (bool) {
        uint256 poolExpiration = poolByPoolId[poolId].expiration;

        return poolExpiration == 0 || block.timestamp > poolExpiration;
    }

    function _validateClaimRequest(
        uint256 poolId,
        ClaimRequest calldata request,
        bytes calldata signature
    ) internal view {
        if (msg.value != request.platformFee) {
            revert InsufficientPlatformFee(msg.value, request.platformFee);
        }

        if (msg.sender != request.to) {
            revert UnauthorizedClaimer(request.to, msg.sender);
        }

        if (block.timestamp < request.startTimestamp) {
            revert ClaimRequestInactive(block.timestamp, request.startTimestamp);
        }

        if (block.timestamp > request.endTimestamp) {
            revert ClaimRequestExpired(block.timestamp, request.endTimestamp);
        }

        // Claim Request must fall within the pool's active window
        if (!_isPoolActive(poolId)) {
            revert PoolInactive(poolId);
        }

        (bool isValidSignature, address recoveredSigner) = verifyClaimRequestSignature(poolId, request, signature);

        if (!isValidSignature) {
            revert UnauthorizedSigner(recoveredSigner);
        }
    }

    function _validatePoolRequest(PoolRequest calldata request, bytes calldata signature) internal view {
        (bool isValidSignature, address recoveredSigner) = verifyPoolRequestSignature(request, signature);

        if (!isValidSignature) {
            revert UnauthorizedSigner(recoveredSigner);
        }
    }

    function _hashClaimRequest(ClaimRequest calldata request) internal pure returns (bytes32) {
        return
            keccak256(
                bytes.concat(
                    abi.encode(
                        CLAIM_REQUEST_TYPE_HASH,
                        request.startTimestamp,
                        request.endTimestamp,
                        request.platformFee,
                        request.platformFeeRecipient,
                        request.to,
                        keccak256(abi.encodePacked(request.claimIds)),
                        keccak256(abi.encodePacked(request.rewardIds)),
                        keccak256(abi.encodePacked(request.amounts))
                    )
                )
            );
    }

    function _hashPoolRequest(PoolRequest calldata request) internal pure returns (bytes32) {
        return
            keccak256(
                bytes.concat(
                    abi.encode(
                        POOL_REQUEST_TYPE_HASH,
                        request.poolId,
                        request.expiration,
                        request.owner,
                        request.signer
                    )
                )
            );
    }

    /**
     * @notice Sets the address of the `poolRequestSigner`.
     * @dev This function allows the admin to set a new address for the `poolRequestSigner`.
     * The signer address cannot be the zero address.
     * Can only be called by an address with the `DEFAULT_ADMIN_ROLE`.
     * @param _poolRequestSigner The new address to be set as the `poolRequestSigner`.
     */
    function setPoolRequestSigner(address _poolRequestSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_poolRequestSigner == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        poolRequestSigner = _poolRequestSigner;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC1155Holder) returns (bool) {
        return AccessControl.supportsInterface(interfaceId) || ERC1155Holder.supportsInterface(interfaceId);
    }
}