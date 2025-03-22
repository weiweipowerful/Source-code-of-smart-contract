// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import './interfaces/IMultiFeeDistribution.sol';

/**
 * @title MultiFeeDistributionV3
 * @author UwULend
 * @notice Vesting and distributing contract for UWU rewards.
 */
contract MultiFeeDistributionV3 is IMultiFeeDistribution, Ownable {
  using SafeMath for uint;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  struct Balances {
    uint earned; // balance reward tokens earned
  }
  struct LockedBalance {
    uint amount;
    uint unlockTime;
  }

  /// @notice The duration by which we set beginning of the vesting period.
  uint public constant ONE_WEEK = 86400 * 7; // 7 days;

  /// @notice The duration of the vesting period for new UWU rewards.
  uint public vestingDuration = ONE_WEEK * 4; // 28 days

  /// Addresses approved to call mint
  EnumerableSet.AddressSet private minters;

  /// @notice UwU token.
  IERC20 public immutable rewardToken;
  /// @notice Issuer of UwU tokens.
  address public immutable rewardTokenVault;
  /// @notice Users' exit delegatees.
  mapping(address => address) public exitDelegatee;

  // Private mappings for balance data
  mapping(address => Balances) private balances;
  mapping(address => LockedBalance[]) private userEarnings; // vesting UwU tokens

  /*****  EVENTS  *****/

  event Minted(address indexed user, uint amount);

  event ExitedEarly(address indexed user, uint amount, uint penaltyAmount);

  event Withdrawn(address indexed user, uint amount);

  event TeamRewardVaultSet(address indexed vault);

  event VestingDurationSet(uint256 indexed duration);

  event MinterSet(address indexed minter);

  event ExitDelegateeSet(address indexed user, address indexed delegatee);

  /*****  SETUP  *****/

  constructor(IERC20 _rewardToken, address _rewardTokenVault) Ownable() {
    rewardToken = _rewardToken;
    rewardTokenVault = _rewardTokenVault;
  }

  /*****  ONLY OWNER  *****/

  /**
   * @notice Set the duration of the vesting period for new UWU rewards.
   * @param durationInWeeks Duration in weeks for the vesting period.
   */
  function setVestingDuration(uint durationInWeeks) external onlyOwner {
    require(durationInWeeks > 0, 'Duration is zero');
    vestingDuration = durationInWeeks * ONE_WEEK;
    emit VestingDurationSet(vestingDuration);
  }

  /**
   * @notice Set the minters for the contract.
   * @param _minters Array of addresses to set as minters.
   */
  function setMinters(address[] calldata _minters) external onlyOwner {
    delete minters;
    for (uint i = 0; i < _minters.length; i++) {
      minters.add(_minters[i]);
      emit MinterSet(_minters[i]);
    }
  }

  /*****  EXTERNAL  *****/

  /**
   * @notice Mint new UwU tokens for a user and start their vesting.
   * @param user Address of the user to vest tokens for.
   * @param amount Amount of tokens to vest.
   */
  function mint(address user, uint amount) external {
    require(minters.contains(msg.sender), '!minter');
    if (amount == 0) return;
    rewardToken.safeTransferFrom(rewardTokenVault, address(this), amount);
    if (user == address(this)) {
      user = owner();
    }
    Balances storage bal = balances[user];
    bal.earned = bal.earned.add(amount);
    uint unlockTime = block.timestamp.div(ONE_WEEK).mul(ONE_WEEK).add(vestingDuration);
    LockedBalance[] storage earnings = userEarnings[user];
    uint idx = earnings.length;
    if (idx == 0 || earnings[idx - 1].unlockTime < unlockTime) {
      earnings.push(LockedBalance({amount: amount, unlockTime: unlockTime}));
    } else {
      earnings[idx - 1].amount = earnings[idx - 1].amount.add(amount);
    }
    emit Minted(user, amount);
  }

  /**
   * @notice Delegate the ability to exit early to another address.
   * @param delegatee The address to delegate the exit to.
   */
  function delegateExit(address delegatee) external {
    exitDelegatee[msg.sender] = delegatee;
    emit ExitDelegateeSet(msg.sender, delegatee);
  }

  /**
   * @notice Exit early from the vesting contract losing 50% of the rewards.
   * @param onBehalfOf The address to exit early for.
   */
  function exitEarly(address onBehalfOf) external {
    require(onBehalfOf == msg.sender || exitDelegatee[onBehalfOf] == msg.sender);
    (uint amount, uint penaltyAmount, ) = withdrawableBalance(onBehalfOf);
    delete userEarnings[onBehalfOf];
    Balances storage bal = balances[onBehalfOf];
    bal.earned = 0;
    rewardToken.safeTransfer(onBehalfOf, amount);
    if (penaltyAmount > 0) {
      rewardToken.safeTransfer(owner(), penaltyAmount);
    }
    emit ExitedEarly(onBehalfOf, amount, penaltyAmount);
  }

  /**
   * @notice Withdraw fully vested tokens.
   */
  function withdraw() external {
    Balances storage bal = balances[msg.sender];
    if (bal.earned > 0) {
      uint amount;
      uint length = userEarnings[msg.sender].length;
      if (userEarnings[msg.sender][length - 1].unlockTime <= block.timestamp) {
        amount = bal.earned;
        delete userEarnings[msg.sender];
      } else {
        for (uint i = 0; i < length; i++) {
          uint earnedAmount = userEarnings[msg.sender][i].amount;
          if (earnedAmount == 0) continue;
          if (userEarnings[msg.sender][i].unlockTime > block.timestamp) {
            break;
          }
          amount = amount.add(earnedAmount);
          delete userEarnings[msg.sender][i];
        }
      }
      if (amount > 0) {
        bal.earned = bal.earned.sub(amount);
        rewardToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
      }
    }
  }

  /*****  VIEW  *****/

  /**
   * @notice Get all the minters
   */
  function getMinters() external view returns (address[] memory) {
    return minters.values();
  }

  /**
   * @notice Get the total locked user balances.
   */
  function earnedBalances(
    address user
  ) external view returns (uint total, LockedBalance[] memory earningsData) {
    LockedBalance[] storage earnings = userEarnings[user];
    uint idx;
    for (uint i = 0; i < earnings.length; i++) {
      if (earnings[i].unlockTime > block.timestamp) {
        if (idx == 0) {
          earningsData = new LockedBalance[](earnings.length - i);
        }
        earningsData[idx] = earnings[i];
        idx++;
        total = total.add(earnings[i].amount);
      }
    }
    return (total, earningsData);
  }

  /**
   * @notice Get the total withdrawable balance for a user, including penalties for early exit.
   */
  function withdrawableBalance(
    address user
  ) public view returns (uint amount, uint penaltyAmount, uint amountWithoutPenalty) {
    Balances storage bal = balances[user];
    uint earned = bal.earned;
    if (earned > 0) {
      uint length = userEarnings[user].length;
      for (uint i = 0; i < length; i++) {
        uint earnedAmount = userEarnings[user][i].amount;
        if (earnedAmount == 0) continue;
        if (userEarnings[user][i].unlockTime > block.timestamp) {
          break;
        }
        amountWithoutPenalty = amountWithoutPenalty.add(earnedAmount);
      }
      penaltyAmount = earned.sub(amountWithoutPenalty).div(2);
    }
    amount = earned.sub(penaltyAmount);
  }
}