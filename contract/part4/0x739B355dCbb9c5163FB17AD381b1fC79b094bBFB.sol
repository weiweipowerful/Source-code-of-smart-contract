// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PresailDeck
 * @dev Contract for distributing tokens using a Merkle tree.
 */
contract PresailDeck {
    using SafeERC20 for IERC20;

    struct Distribution {
        bytes32 merkleRoot;
        uint256 lockedTokens;
        uint256 claimedTokens;
        address token;
        bool invalidated;
        address owner;
        bool markedForReplacement;
        bool replaced;
    }

    mapping(uint256 => Distribution) public distributions;
    mapping(uint256 => BitMaps.BitMap) private claimedBitmaps;
    uint256 public distributionsCount;

    event TokensLocked(uint256 indexed distributionId, address indexed owner, bytes32 indexed merkleRoot, uint256 lockedTokens, address token, bool forceExactAmountTransfer);
    event TokensClaimed(uint256 indexed distributionId, address indexed recipient, uint256 amount, address token, address indexed transferRecipient);
    event TokensReclaimed(uint256 indexed distributionId, uint256 reclaimedTokens, address token);
    event TokensDeposited(uint256 indexed distributionId, uint256 lockedTokens, uint256 depositedTokens, address token, bool forceExactAmountTransfer);
    event DistributionSetInvalidated(uint256 indexed distributionId, bool invalidated);
    event DistributionReplaced(uint256 indexed distributionReplacedId, uint256 indexed distributionId, address indexed owner);

    error UnauthorizedAccess(address caller, address owner);
    error DistributionInvalidated(uint256 distributionId);
    error DistributionNotInvalidated(uint256 distributionId);
    error TokensAlreadyClaimed(address recipient);
    error ClaimedTokensExceedLockedAmount(uint256 claimedTokens, uint256 lockedTokens);
    error InvalidMerkleProof();
    error ArraysLengthMismatch();
    error TokenMismatch();
    error DistributionMarkedForReplacement(uint256 distributionId);
    error DistributionNotMarkedForReplacement(uint256 distributionId);
    error DistributionAlreadyReplaced(uint256 distributionId);
    error NonExactAmountTransfer();

    modifier onlyOwner(uint256 _distributionId) {
        if (distributions[_distributionId].owner != msg.sender)
            revert UnauthorizedAccess(msg.sender, distributions[_distributionId].owner);
        _;
    }

    /**
     * @dev Locks tokens in the contract for distribution.
     * @param _token The address of the token contract.
     * @param _totalTokens The total number of tokens to be distributed.
     * @param _merkleRoot The Merkle root of the Merkle tree containing the token distribution.
     * @param _replacesDistribution If this new distribution replaces an existing one
     * @param _distributionToReplace If _replacesDistribution is true, this is the index of the distribution to replace
     */
    function lockTokens(
        address _token,
        uint256 _totalTokens,
        bytes32 _merkleRoot,
        bool _replacesDistribution,
        uint256 _distributionToReplace,
        bool _forceExactAmountTransfer
    ) external {
        uint256 currentDistributionId = distributionsCount;
        uint256 distributionExistingBalance = 0;

        if (_replacesDistribution) {
            Distribution storage distributionToReplace = distributions[_distributionToReplace];

            if (distributionToReplace.replaced)
                revert DistributionAlreadyReplaced(_distributionToReplace);

            if (!distributionToReplace.markedForReplacement)
                revert DistributionNotMarkedForReplacement(_distributionToReplace);

            if (distributionToReplace.owner != msg.sender)
                revert UnauthorizedAccess(msg.sender, distributionToReplace.owner);

            if (distributionToReplace.token != _token)
                revert TokenMismatch();

            distributionToReplace.replaced = true;
            distributionExistingBalance = distributionToReplace.lockedTokens - distributionToReplace.claimedTokens;

            emit DistributionReplaced(_distributionToReplace, currentDistributionId, msg.sender);
        }
        
        distributionsCount++;
        distributions[currentDistributionId].merkleRoot = _merkleRoot;
        distributions[currentDistributionId].token = _token;
        distributions[currentDistributionId].owner = msg.sender;

        uint256 balanceBefore = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _totalTokens);
        uint256 balanceAfter = IERC20(_token).balanceOf(address(this));
        uint256 netTransferAmount =  balanceAfter - balanceBefore;

        // If we indicated it to force exact amounts, then the total entered and what was actually transferred should be the same.
        if (_forceExactAmountTransfer && _totalTokens != netTransferAmount)
            revert NonExactAmountTransfer();

        distributions[currentDistributionId].lockedTokens = distributionExistingBalance + netTransferAmount;

        emit TokensLocked(currentDistributionId, msg.sender, _merkleRoot, netTransferAmount, _token, _forceExactAmountTransfer);
    }

    /**
     * @dev Claims tokens for a recipient based on a Merkle proof.
     * @param _distributionId The ID of the distribution.
     * @param _index The index of the leaf in the Merkle tree.
     * @param _amount The amount of tokens to claim.
     * @param _proof The Merkle proof for the claimed tokens.
     */
    function claimTokens(uint256 _distributionId, uint256 _index, uint256 _amount, bytes32[] calldata _proof) external {
        _claim(_distributionId, _index, msg.sender, _amount, _proof, msg.sender);
    }

    /**
     * @notice Claims tokens from multiple distributions in a single call.
     * @dev This function allows users to claim tokens from multiple distributions simultaneously, providing an array of distribution IDs, accounts, amounts, and proofs.
     * @param _distributionIds An array of distribution IDs from which tokens will be claimed.
     * @param _indexes An array of indexes for each distribution.
     * @param _amounts An array of amounts of tokens to claim for each distribution.
     * @param _proofs An array of Merkle proofs for each distribution claim.
     */ 
    function claimMultipleTokens(uint256[] calldata _distributionIds, uint256[] calldata _indexes, uint256[] calldata _amounts, bytes32[][] calldata _proofs) external {
        if (_distributionIds.length != _indexes.length ||
            _distributionIds.length != _amounts.length ||
            _distributionIds.length != _proofs.length) {
            revert ArraysLengthMismatch();
        }

        for (uint256 i = 0; i < _distributionIds.length; i++) {
            _claim(_distributionIds[i], _indexes[i], msg.sender, _amounts[i], _proofs[i], msg.sender);
        }
    }

    /**
     * @dev Allows the owner to clawback tokens of a recipient based on a Merkle proof.
     * @param _distributionId The ID of the distribution.
     * @param _index The index of the leaf in the Merkle tree.
     * @param _account The recipient's address to clawback from.
     * @param _amount The amount of tokens to reclaim.
     * @param _proof The Merkle proof for the reclaimed tokens.
     */
    function clawbackTokens(uint256 _distributionId, uint256 _index, address _account, uint256 _amount, bytes32[] calldata _proof) external onlyOwner(_distributionId) {
        Distribution storage distribution = distributions[_distributionId];
        _claim(_distributionId, _index, _account, _amount, _proof, distribution.owner);
    }

    /**
     * @dev Internal function to handle token claims.
     * @param _distributionId The ID of the distribution.
     * @param _index The index of the leaf in the Merkle tree.
     * @param _recipient The recipient's address.
     * @param _amount The amount of tokens to claim.
     * @param _proof The Merkle proof for the claimed tokens.
     * @param _transferRecipient The address to transfer the claimed tokens to.
     */
    function _claim(uint256 _distributionId, uint256 _index, address _recipient, uint256 _amount, bytes32[] calldata _proof, address _transferRecipient) internal {
        Distribution storage distribution = distributions[_distributionId];

        if (distribution.invalidated)
            revert DistributionInvalidated(_distributionId);

        if (isClaimed(_distributionId, _index))
            revert TokensAlreadyClaimed(_recipient);

        if (!MerkleProof.verifyCalldata(_proof, distribution.merkleRoot, _leaf(_index, _recipient, _amount)))
            revert InvalidMerkleProof();   

        BitMaps.BitMap storage claimedBitmap = claimedBitmaps[_distributionId];
        BitMaps.set(claimedBitmap, _index);
        distribution.claimedTokens = distribution.claimedTokens + _amount;
        
        if (distribution.claimedTokens > distribution.lockedTokens)
            revert ClaimedTokensExceedLockedAmount(distribution.claimedTokens, distribution.lockedTokens);

        IERC20(distribution.token).safeTransfer(_transferRecipient, _amount);
        emit TokensClaimed(_distributionId, _recipient, _amount, distribution.token, _transferRecipient);
    }

    /**
     * @dev Allows the owner to reclaim tokens and invalidates a distribution.
     * To be used in case of emergency or after some deadline if beneficiaries are not claiming anymore.
     * @param _distributionId The ID of the distribution.
     */
    function reclaimTokensAndInvalidateDistribution(uint256 _distributionId) external onlyOwner(_distributionId) {
        Distribution storage distribution = distributions[_distributionId];

        if (distribution.invalidated)
            revert DistributionInvalidated(_distributionId);

        distribution.invalidated = true;
        uint256 tokensLeft = distribution.lockedTokens - distribution.claimedTokens;

        IERC20(distribution.token).safeTransfer(distribution.owner, tokensLeft);
        emit TokensReclaimed(_distributionId, tokensLeft, distribution.token);
        emit DistributionSetInvalidated(_distributionId, true);
    }

    /**
     * @dev Allows the owner to invalidate a distribution and mark it for replacement.
     * To be used for creating a distribution that replaces another distribution.
     * Leaves the tokens still locked in the contract so they can be "transferred" to a new distribution that replaces this one.
     * @param _distributionId The ID of the distribution.
     */
    function invalidateDistributionForReplacement(uint256 _distributionId) external onlyOwner(_distributionId) {
        Distribution storage distribution = distributions[_distributionId];

        // Can only invalidate it for replacement if:
        // - it HAS NOT been invalidated AND
        // - it HAS NOT been already replaced AND
        // - it HAS NOT been marked for replacement (using invalidateDistributionForReplacement)

        if (distribution.invalidated)
            revert DistributionInvalidated(_distributionId);
        
        if (distribution.replaced)
            revert DistributionAlreadyReplaced(_distributionId);

        if (distribution.markedForReplacement)
            revert DistributionMarkedForReplacement(_distributionId);

        distribution.invalidated = true;
        distribution.markedForReplacement = true;

        emit DistributionSetInvalidated(_distributionId, true);
    }

    /**
     * @dev Allows the owner to cancel the invalidation of a distribution that has been marked for replacement.
     * @param _distributionId The ID of the distribution.
     */
    function cancelInvalidateDistributionForReplacement(uint256 _distributionId) external onlyOwner(_distributionId) {
        Distribution storage distribution = distributions[_distributionId];

        // Can only cancel it if:
        // - it HAS been invalidated AND
        // - it HAS NOT been already replaced AND
        // - it HAS been marked for replacement (using invalidateDistributionForReplacement)

        if (!distribution.invalidated)
            revert DistributionNotInvalidated(_distributionId);

        if (distribution.replaced)
            revert DistributionAlreadyReplaced(_distributionId);

        if (!distribution.markedForReplacement)
            revert DistributionNotMarkedForReplacement(_distributionId);

        distribution.invalidated = false;
        distribution.markedForReplacement = false;

        emit DistributionSetInvalidated(_distributionId, false);
    }

    /** 
     * @dev Allows owner to deposit tokens into their distribution.
     * Only to be used if for some reason they initially locked less tokens than the sum of all amounts in tree.
     * @param _distributionId The ID of the distribution.
     * @param _tokenAmount The amount of tokens to deposit.
     */
    function depositTokens(uint256 _distributionId, uint256 _tokenAmount,  bool _forceExactAmountTransfer) external onlyOwner(_distributionId) {
        Distribution storage distribution = distributions[_distributionId];

        if (distribution.invalidated)
            revert DistributionInvalidated(_distributionId);

        uint256 balanceBefore = IERC20(distribution.token).balanceOf(address(this));
        IERC20(distribution.token).safeTransferFrom(msg.sender, address(this), _tokenAmount);
        uint256 balanceAfter = IERC20(distribution.token).balanceOf(address(this));
        uint256 netTransferAmount = balanceAfter - balanceBefore;

        // If we indicated it to force exact mounts, then the total entered and what was actually transferred should be the same.
        if (_forceExactAmountTransfer && _tokenAmount != netTransferAmount)
            revert NonExactAmountTransfer();

        distribution.lockedTokens = distribution.lockedTokens + netTransferAmount;
        
        emit TokensDeposited(_distributionId, distribution.lockedTokens, netTransferAmount, distribution.token, _forceExactAmountTransfer);
    }

    /**
     * @dev Internal function to compute the leaf hash for a given index, account, and amount.
     * @param index The index of the leaf in the Merkle tree.
     * @param account The account address.
     * @param amount The token amount.
     * @return The computed leaf hash.
     */
    function _leaf(uint256 index, address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(index, account, amount)))); 
    }

    /**
     * @dev Checks if a recipient has already claimed tokens.
     * @param _distributionId The ID of the distribution.
     * @param _index The index of the leaf in the Merkle tree.
     * @return A boolean indicating whether the tokens are already claimed.
     */
    function isClaimed(uint256 _distributionId, uint256 _index) public view returns (bool) {
        return BitMaps.get(claimedBitmaps[_distributionId], _index);
    }

    /**
     * @dev Checks if multiple recipients have already claimed tokens.
     * @param _distributionId The ID of the distribution.
     * @param _indexes The index of the leaf in the Merkle tree.
     * @return An array of booleans indicating whether the tokens are already claimed.
     */
    function areClaimed(uint256 _distributionId, uint256[] calldata _indexes) public view returns (bool[] memory) {
        bool[] memory results = new bool[](_indexes.length);
        for (uint256 i = 0; i < _indexes.length; i++) {
            results[i] = BitMaps.get(claimedBitmaps[_distributionId], _indexes[i]);
        }
        return results;
    }
}