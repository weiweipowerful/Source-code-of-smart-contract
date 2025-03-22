// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/security/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";

import {ILinearVesting} from "contracts/ILinearVesting.sol";
import {ILinearVestingInternal} from "contracts/ILinearVestingInternal.sol";

import {UserAllocation} from "contracts/LinearVestingStruct.sol";

/** 
* @title LinearVesting contract
* @notice A contract to handle linear vesting of tokens.
* @dev This contract is NOT MADE to be used:
*           - for a crosschain linear vesting. A vesting of a token will always happen on one and single chain,
*           - to claim deflationary tokens.
*/
contract LinearVesting is
    ILinearVesting,
    ILinearVestingInternal,
    Ownable,
    Pausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    IERC20 public immutable ERC20Interface;

    /// @notice total amount of vested tokens over the whole existence of the contract (to be claimed by users)
    uint256 public override totalVested;

    /// @notice total amount of claimed tokens over the whole existence of the contract
    uint256 public override totalClaimed;

    /// @notice merkle root of user allocations
    bytes32 public override merkleRoot;

    uint32 public override startTime;
    uint32 public override endTime;

    /// @notice mapping of user to claimed amount
    mapping(address => uint256) public override userClaims;

    constructor(address _token) {
        if (_token == address(0)) {
            revert ZeroTokenAddress();
        }

        ERC20Interface = IERC20(_token);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /// @inheritdoc ILinearVesting
    function update(
        bytes32 merkleRoot_,
        uint32 startTime_,
        uint32 endTime_,
        uint256 toClaim
    ) external override onlyOwner returns (bool) {
        if (merkleRoot_ == bytes32(0)) {
            revert InvalidMerkleRoot();
        }

        if (endTime_ < startTime_) {
            revert InvalidTimings();
        }

        merkleRoot = merkleRoot_;
        startTime = startTime_;
        endTime = endTime_;

        if (toClaim > 0) {
            ERC20Interface.safeTransferFrom(
                msg.sender,
                address(this),
                toClaim
            );
            totalVested += toClaim;
        }

        emit SettingsUpdated(startTime_, endTime_, totalVested);

        return true;
    }

    /// @inheritdoc ILinearVesting
    function claim(
        UserAllocation calldata alloc,
        bytes32[] calldata proof
    ) external override nonReentrant whenNotPaused returns (bool) {
        if (
            !MerkleProof.verify(
                proof,
                merkleRoot,
                keccak256(abi.encode(alloc))
            )
        ) {
            revert AllocNotFound();
        }

        uint256 tokens = getClaimableAmount(alloc);
        if (tokens == 0) {
            revert NoTokensToClaim();
        }

        userClaims[alloc.user] += tokens;
        totalClaimed += tokens;
        ERC20Interface.safeTransfer(alloc.user, tokens);

        emit Claimed(address(ERC20Interface), alloc.user, tokens);

        return true;
    }

    /// @inheritdoc ILinearVesting
    function getClaimableAmount(
        UserAllocation calldata alloc
    ) public view override returns (uint256 claimableAmount) {
        if (startTime > block.timestamp) return 0;

        uint256 amount = alloc.amount;

        if (block.timestamp < endTime) {
            claimableAmount = _claimableAmount(
                amount,
                alloc.startAmount,
                1e36
            );
        } else {
            claimableAmount = amount;
        }

        claimableAmount -= userClaims[alloc.user];
    }

    /**
     * @dev Internal function to allow test on precision.
     * @param amount Total amount of tokens a user will claim.
     * @param startAmount Initial amount of tokens a user had unlocked before vesting starts.
     * @param precision Precision to use for the calculation - set a 1e36 by default.
     */
    function _claimableAmount(
        uint256 amount,
        uint256 startAmount,
        uint256 precision
    ) internal view returns (uint256) {
        uint256 timePassed = block.timestamp - startTime;
        uint256 totalTime = endTime - startTime; // endTime < startTime, 0 is impossible
        uint256 timePassedRatio = (timePassed * precision) / totalTime; // result on 10^36

        /**
         * @dev with 1e36 precision, calculation safe with tokens up to 10^40,
         *      max uint256 is 2^256-1 = 1.15e77
         */
        return
            (((amount - startAmount) * timePassedRatio) / precision) +
            startAmount;
    }
}