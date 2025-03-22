// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import "./interfaces/IVotingEscrow.sol";

import "./libraries/VeHistoryLib.sol";

import "./libraries/MiniHelpers.sol";
import "./libraries/Errors.sol";

import "./VotingEscrowTokenBase.sol";

contract VotingEscrowZK is VotingEscrowTokenBase, IVotingEscrow {
    using SafeERC20 for IERC20;
    using VeBalanceLib for VeBalance;
    using VeBalanceLib for LockedPosition;
    using Checkpoints for Checkpoints.History;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    IERC20 public immutable zk;

    uint128 public lastSlopeChangeAppliedAt;

    // [wTime] => slopeChanges
    mapping(uint128 => uint128) public slopeChanges;

    // Saving totalSupply checkpoint for each week, later can be used for reward accounting
    // [wTime] => totalSupply
    mapping(uint128 => uint128) public totalSupplyAt;

    // Saving VeBalance checkpoint for users of each week, can later use binary search
    // to ask for their veZK balance at any wTime
    mapping(address => Checkpoints.History) internal userHistory;

    constructor(IERC20 _zk) {
        zk = _zk;
        lastSlopeChangeAppliedAt = WeekMath.getCurrentWeekStart();
    }

    /**
     * @notice increases the lock position of a user (amount and/or expiry). Applicable even when
     * user has no position or the current position has expired.
     * @param additionalAmountToLock ZK amount to be pulled in from user to lock.
     * @param newExpiry new lock expiry. Must be a valid week beginning, and resulting lock
     * duration (since `block.timestamp`) must be within the allowed range.
     * @dev Will revert if resulting position has zero lock amount.
     * @dev See `_increasePosition()` for details on inner workings.
     */
    function increaseLockPosition(
        uint128 additionalAmountToLock,
        uint128 newExpiry
    ) public returns (uint128 newVeBalance) {
        address user = msg.sender;

        if (!WeekMath.isValidWTime(newExpiry)) revert Errors.InvalidWTime(newExpiry);
        if (MiniHelpers.isTimeInThePast(newExpiry)) revert Errors.ExpiryInThePast(newExpiry);

        if (newExpiry < positionData[user].expiry) revert Errors.VENotAllowedReduceExpiry();

        if (newExpiry > block.timestamp + MAX_LOCK_TIME) revert Errors.VEExceededMaxLockTime();
        if (newExpiry < block.timestamp + MIN_LOCK_TIME) revert Errors.VEInsufficientLockTime();

        uint128 newTotalAmountLocked = additionalAmountToLock + positionData[user].amount;
        if (newTotalAmountLocked == 0) revert Errors.VEZeroAmountLocked();

        uint128 additionalDurationToLock = newExpiry - positionData[user].expiry;

        if (additionalAmountToLock > 0) {
            zk.safeTransferFrom(user, address(this), additionalAmountToLock);
        }

        newVeBalance = _increasePosition(user, additionalAmountToLock, additionalDurationToLock);

        emit NewLockPosition(user, newTotalAmountLocked, newExpiry);
    }

    /**
     * @notice Withdraws an expired lock position, returns locked ZK back to user
     * @dev reverts if position is not expired, or if no locked ZK to withdraw
     */
    function withdraw() external returns (uint128 amount) {
        address user = msg.sender;

        if (!_isPositionExpired(user)) revert Errors.VEPositionNotExpired();
        amount = positionData[user].amount;

        if (amount == 0) revert Errors.VEZeroPosition();

        delete positionData[user];

        zk.safeTransfer(user, amount);

        emit Withdraw(user, amount);
    }

    /**
     * @notice update & return the current totalSupply
     */
    function totalSupplyCurrent() public virtual override(IVeToken, VotingEscrowTokenBase) returns (uint128) {
        (VeBalance memory supply, ) = _applySlopeChange();
        return supply.getCurrentValue();
    }

    function getUserHistoryLength(address user) external view returns (uint256) {
        return userHistory[user].length();
    }

    function getUserHistoryAt(address user, uint256 index) external view returns (Checkpoint memory) {
        return userHistory[user].get(index);
    }

    /**
     * @notice increase the locking position of the user
     * @dev works by simply removing the old position from all relevant data (as if the user has
     * never locked) and then add in the new position
     */
    function _increasePosition(
        address user,
        uint128 amountToIncrease,
        uint128 durationToIncrease
    ) internal returns (uint128) {
        LockedPosition memory oldPosition = positionData[user];

        (VeBalance memory newSupply, ) = _applySlopeChange();

        if (!MiniHelpers.isCurrentlyExpired(oldPosition.expiry)) {
            // remove old position not yet expired
            VeBalance memory oldBalance = oldPosition.convertToVeBalance();
            newSupply = newSupply.sub(oldBalance);
            slopeChanges[oldPosition.expiry] -= oldBalance.slope;
        }

        LockedPosition memory newPosition = LockedPosition(
            oldPosition.amount + amountToIncrease,
            oldPosition.expiry + durationToIncrease
        );

        VeBalance memory newBalance = newPosition.convertToVeBalance();
        // add new position
        newSupply = newSupply.add(newBalance);
        slopeChanges[newPosition.expiry] += newBalance.slope;

        _totalSupply = newSupply;
        positionData[user] = newPosition;
        userHistory[user].push(newBalance);
        return newBalance.getCurrentValue();
    }

    /**
     * @notice updates the totalSupply, processing all slope changes of past weeks. At the same time,
     * set the finalized totalSupplyAt
     */
    function _applySlopeChange() internal returns (VeBalance memory, uint128) {
        VeBalance memory supply = _totalSupply;
        uint128 wTime = lastSlopeChangeAppliedAt;
        uint128 currentWeekStart = WeekMath.getCurrentWeekStart();

        if (wTime >= currentWeekStart) {
            return (supply, wTime);
        }

        while (wTime < currentWeekStart) {
            wTime += WEEK;
            supply = supply.sub(slopeChanges[wTime], wTime);
            totalSupplyAt[wTime] = supply.getValueAt(wTime);
        }

        _totalSupply = supply;
        lastSlopeChangeAppliedAt = wTime;

        return (supply, wTime);
    }
}