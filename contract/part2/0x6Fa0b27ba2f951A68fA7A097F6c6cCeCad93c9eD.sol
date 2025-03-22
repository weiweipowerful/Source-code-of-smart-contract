// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// Utils /////
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IVoteEscrow.sol";
import "./libraries/VoteEscrowLib.sol";
import "./libraries/WeekMath.sol";
import "./libraries/CheckpointsLib.sol";

///@title VoteEscrow Contract
///@notice This is a modified version of the Pendle VotingEscrowPendleMainchain contract
///        as well as VotingEscrowTokenBase
///        https://github.com/pendle-finance/pendle-core-v2-public/
contract VoteEscrow is IVoteEscrow {
  using SafeERC20 for IERC20;
  using VoteEscrowLib for VeBalance;
  using VoteEscrowLib for LockedPosition;
  using Checkpoints for Checkpoints.History;

  /*//////////////////////////////////////////////////////////////
                             STORAGE
  //////////////////////////////////////////////////////////////*/

  IERC20 public immutable FYDE;

  uint128 public constant WEEK = 1 weeks;
  uint128 public constant MAX_LOCK_TIME = 104 weeks;
  uint128 public constant MIN_LOCK_TIME = 1 weeks;

  VeBalance internal _totalSupply;

  mapping(address => LockedPosition) public positionData;

  uint128 public lastSlopeChangeAppliedAt;

  // [wTime] => slopeChanges
  mapping(uint128 => uint128) public slopeChanges;

  // Saving totalSupply checkpoint for each week, later can be used for reward accounting
  // [wTime] => totalSupply
  mapping(uint128 => uint128) public totalSupplyAt;

  // Saving VeBalance checkpoint for users of each week, can later use binary search
  // to ask for their vePendle balance at any wTime
  mapping(address => Checkpoints.History) internal userHistory;

  /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(address _FYDE) {
    FYDE = IERC20(_FYDE);
    lastSlopeChangeAppliedAt = WeekMath.getCurrentWeekStart();
  }

  /*//////////////////////////////////////////////////////////////
                             ERRORS
  //////////////////////////////////////////////////////////////*/

  error WeekMathInvalidTime(uint256 wTime);

  error UpdateExpiryMustBeCurrent();
  error UpdateExpiryMustIncrease();
  error UpdateExpiryTooLong();
  error UpdateExpiryTooShort();

  error VoteEscrowZeroAmount();
  error VoteEscrowNotExpired();

  /*//////////////////////////////////////////////////////////////
                             EXTERNAL
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice increases the lock position of a user (amount and/or expiry). Applicable even when
   * user has no position or the current position has expired.
   * @param additionalAmountToLock pendle amount to be pulled in from user to lock.
   * @param newExpiry new lock expiry. Must be a valid week beginning, and resulting lock
   * duration (since `block.timestamp`) must be within the allowed range.
   * @dev Will revert if resulting position has zero lock amount.
   * @dev See `_increasePosition()` for details on inner workings.
   * @dev Sidechain broadcasting is not bundled since it can be done anytime after.
   */
  function updateLock(uint128 additionalAmountToLock, uint128 newExpiry)
    public
    returns (uint128 newVeBalance)
  {
    address user = msg.sender;

    if (!WeekMath.isValidWTime(newExpiry)) revert WeekMathInvalidTime(newExpiry);
    if (WeekMath.isCurrentlyExpired(newExpiry)) revert UpdateExpiryMustBeCurrent();

    if (newExpiry < positionData[user].expiry) revert UpdateExpiryMustIncrease();

    if (newExpiry > block.timestamp + MAX_LOCK_TIME) revert UpdateExpiryTooLong();
    if (newExpiry < block.timestamp + MIN_LOCK_TIME) revert UpdateExpiryTooShort();

    uint128 newTotalAmountLocked = additionalAmountToLock + positionData[user].amount;
    if (newTotalAmountLocked == 0) revert VoteEscrowZeroAmount();

    uint128 additionalDurationToLock = newExpiry - positionData[user].expiry;

    if (additionalAmountToLock > 0) {
      FYDE.safeTransferFrom(user, address(this), additionalAmountToLock);
    }

    newVeBalance = _increasePosition(user, additionalAmountToLock, additionalDurationToLock);

    emit UpdateLock(user, newTotalAmountLocked, newExpiry);
  }

  /**
   * @notice Withdraws an expired lock position, returns locked PENDLE back to user
   * @dev reverts if position is not expired, or if no locked PENDLE to withdraw
   * @dev broadcast is not bundled since it can be done anytime after
   */
  function withdraw() external returns (uint128 amount) {
    address user = msg.sender;

    if (!_isPositionExpired(user)) revert VoteEscrowNotExpired();
    amount = positionData[user].amount;

    if (amount == 0) revert VoteEscrowZeroAmount();

    delete positionData[user];

    FYDE.safeTransfer(user, amount);

    emit Withdraw(user, amount);
  }

  /*//////////////////////////////////////////////////////////////
                             GETTERS
  //////////////////////////////////////////////////////////////*/

  function balanceOf(address user) public view returns (uint128) {
    return positionData[user].convertToVeBalance().getCurrentValue();
  }

  function totalSupplyStored() external view returns (uint128) {
    return _totalSupply.getCurrentValue();
  }

  function totalSupplyCurrent() public returns (uint128) {
    (VeBalance memory supply,) = _applySlopeChange();
    return supply.getCurrentValue();
  }

  function totalSupplyAndBalanceCurrent(address user) external returns (uint128, uint128) {
    return (totalSupplyCurrent(), balanceOf(user));
  }

  function getUserHistoryLength(address user) external view returns (uint256) {
    return userHistory[user].length();
  }

  function getUserHistoryAt(address user, uint256 index) external view returns (Checkpoint memory) {
    return userHistory[user].get(index);
  }

  /*//////////////////////////////////////////////////////////////
                             INTERNAL
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice increase the locking position of the user
   * @dev works by simply removing the old position from all relevant data (as if the user has
   * never locked) and then add in the new position
   */
  function _increasePosition(address user, uint128 amountToIncrease, uint128 durationToIncrease)
    internal
    returns (uint128)
  {
    LockedPosition memory oldPosition = positionData[user];

    (VeBalance memory newSupply,) = _applySlopeChange();

    if (!WeekMath.isCurrentlyExpired(oldPosition.expiry)) {
      // remove old position not yet expired
      VeBalance memory oldBalance = oldPosition.convertToVeBalance();
      newSupply = newSupply.sub(oldBalance);
      slopeChanges[oldPosition.expiry] -= oldBalance.slope;
    }

    LockedPosition memory newPosition =
      LockedPosition(oldPosition.amount + amountToIncrease, oldPosition.expiry + durationToIncrease);

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

    if (wTime >= currentWeekStart) return (supply, wTime);

    while (wTime < currentWeekStart) {
      wTime += WEEK;
      supply = supply.sub(slopeChanges[wTime], wTime);
      totalSupplyAt[wTime] = supply.getValueAt(wTime);
    }

    _totalSupply = supply;
    lastSlopeChangeAppliedAt = wTime;

    return (supply, wTime);
  }

  function _isPositionExpired(address user) internal view returns (bool) {
    return WeekMath.isCurrentlyExpired(positionData[user].expiry);
  }
}