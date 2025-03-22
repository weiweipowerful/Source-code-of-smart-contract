//SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IContractInfo} from "./IContractInfo.sol";
import {IAccountInfo} from "./IAccountInfo.sol";

// import "hardhat/console.sol";

contract SQRVesting is Ownable, ReentrancyGuard, IContractInfo, IAccountInfo {
  using SafeERC20 for IERC20;

  //Variables, structs, errors, modifiers, events------------------------

  string public constant VERSION = "2.6";

  IERC20 public erc20Token;
  uint32 public startDate;
  uint32 public cliffPeriod;
  uint256 public firstUnlockPercent;
  uint32 public unlockPeriod;
  uint256 public unlockPeriodPercent;
  bool public availableRefund;
  uint32 public refundStartDate;
  uint32 public refundCloseDate;

  mapping(address account => Allocation allocation) public allocations;
  address[] private _accountAddresses;

  uint256 public constant PERCENT_DIVIDER = 1e18 * 100;

  constructor(ContractParams memory contractParams) Ownable(contractParams.newOwner) {
    if (contractParams.erc20Token == address(0)) {
      revert ERC20TokenNotZeroAddress();
    }

    if (contractParams.firstUnlockPercent > PERCENT_DIVIDER) {
      revert FirstUnlockPercentMustBeLessThanPercentDivider();
    }

    if (contractParams.startDate < uint32(block.timestamp)) {
      revert StartDateMustBeGreaterThanCurrentTime();
    }

    if (contractParams.unlockPeriod == 0) {
      revert UnlockPeriodNotZero();
    }

    if (contractParams.unlockPeriodPercent == 0) {
      revert UnlockPeriodPercentNotZero();
    }

    if (contractParams.availableRefund) {
      if (contractParams.refundStartDate < uint32(block.timestamp)) {
        revert RefundStartDateMustBeGreaterThanCurrentTime();
      }

      if (contractParams.refundStartDate > contractParams.refundCloseDate) {
        revert RefundCloseDateMustBeGreaterThanRefundStartDate();
      }
    }

    erc20Token = IERC20(contractParams.erc20Token);
    startDate = contractParams.startDate;
    cliffPeriod = contractParams.cliffPeriod;
    firstUnlockPercent = contractParams.firstUnlockPercent;
    unlockPeriod = contractParams.unlockPeriod;
    unlockPeriodPercent = contractParams.unlockPeriodPercent;
    availableRefund = contractParams.availableRefund;
    refundStartDate = contractParams.refundStartDate;
    refundCloseDate = contractParams.refundCloseDate;
  }

  uint256 public totalReserved;
  uint256 public totalAllocated;
  uint256 public totalClaimed;
  uint32 public allocationCount;
  uint32 public refundCount;

  modifier accountExist() {
    if (!allocations[_msgSender()].exist) {
      revert AccountNotExist();
    }
    _;
  }

  modifier alreadyRefunded() {
    if (allocations[_msgSender()].refunded) {
      revert AlreadyRefunded();
    }
    _;
  }

  struct ContractParams {
    address newOwner;
    address erc20Token;
    uint32 startDate;
    uint32 cliffPeriod;
    uint256 firstUnlockPercent;
    uint32 unlockPeriod;
    uint256 unlockPeriodPercent;
    bool availableRefund;
    uint32 refundStartDate;
    uint32 refundCloseDate;
  }

  struct Allocation {
    uint256 amount;
    uint256 claimed;
    uint32 claimCount;
    uint32 claimedAt;
    bool exist;
    bool refunded;
  }

  struct ClaimInfo {
    uint256 amount;
    bool canClaim;
    uint256 claimed;
    uint32 claimCount;
    uint32 claimedAt;
    bool exist;
    uint256 available;
    uint256 remain;
    uint256 nextAvailable;
    uint32 nextClaimAt;
    bool canRefund;
    bool refunded;
  }

  event Claim(address indexed account, uint256 amount);
  event Refund(address indexed account);
  event SetAllocation(address indexed account, uint256 amount);
  event WithdrawExcessAmount(address indexed to, uint256 amount);
  event ForceWithdraw(address indexed token, address indexed to, uint256 amount);
  event SetAvailableRefund(address indexed account, bool value);
  event SetRefundStartDate(address indexed account, uint32 value);
  event SetRefundCloseDate(address indexed account, uint32 value);

  error ERC20TokenNotZeroAddress();
  error FirstUnlockPercentMustBeLessThanPercentDivider();
  error UnlockPeriodNotZero();
  error UnlockPeriodPercentNotZero();
  error StartDateMustBeGreaterThanCurrentTime();
  error ArrayLengthsNotEqual();
  error AccountNotZeroAddress();
  error ContractMustHaveSufficientFunds();
  error AccountNotExist();
  error NothingToClaim();
  error CantChangeOngoingVesting();
  error AlreadyRefunded();
  error AlreadyClaimed();
  error RefundStartDateMustBeGreaterThanCurrentTime();
  error RefundStartDateMustBeLessThanRefundCloseDate();
  error RefundCloseDateMustBeGreaterThanCurrentTime();
  error RefundCloseDateMustBeGreaterThanRefundStartDate();
  error RefundUnavailable();
  error TooEarlyToRefund();
  error TooLateToRefund();

  //Read methods-------------------------------------------
  //IContractInfo implementation
  function getContractName() external pure returns (string memory) {
    return "Vesting";
  }

  function getContractVersion() external pure returns (string memory) {
    return VERSION;
  }

  //IAccountInfo implementation
  function getAccountCount() public view returns (uint32) {
    return (uint32)(_accountAddresses.length);
  }

  function getAccountByIndex(uint32 index) public view returns (address) {
    return _accountAddresses[index];
  }

  //Custom
  function getBalance() public view returns (uint256) {
    return erc20Token.balanceOf(address(this));
  }

  function canClaim(address account) public view returns (bool) {
    return (calculateClaimAmount(account, 0) > 0);
  }

  function calculatePassedPeriod() public view returns (uint32) {
    uint32 timestamp = (uint32)(block.timestamp);
    if (timestamp > startDate + cliffPeriod) {
      return (timestamp - startDate - cliffPeriod) / unlockPeriod;
    }
    return 0;
  }

  function calculateMaxPeriod() public view returns (uint256) {
    return PERCENT_DIVIDER / unlockPeriodPercent;
  }

  function calculateFinishDate() public view returns (uint32) {
    return startDate + cliffPeriod + (uint32)(calculateMaxPeriod()) * unlockPeriod;
  }

  function calculateClaimAmount(
    address account,
    uint32 periodOffset
  ) public view returns (uint256) {
    // Before startDate
    if (block.timestamp < startDate && periodOffset == 0) {
      return 0;
    }

    Allocation memory allocation = allocations[account];

    uint256 firstUnlockAmount = (allocation.amount * firstUnlockPercent) / PERCENT_DIVIDER;
    uint256 claimed = allocation.claimed;
    uint256 amount = allocation.amount;

    // Before cliff and claim
    if (block.timestamp < startDate + cliffPeriod && claimed == 0) {
      return firstUnlockAmount;
    } else {
      uint256 claimAmount = ((calculatePassedPeriod() + periodOffset) *
        (amount * unlockPeriodPercent)) /
        PERCENT_DIVIDER +
        firstUnlockAmount -
        claimed;

      if (claimAmount > amount - claimed) {
        return amount - claimed;
      }

      return claimAmount;
    }
  }

  function isAllocationFinished(address account) public view returns (bool) {
    return (allocations[account].claimed == allocations[account].amount);
  }

  function isAfterRefundCloseDate() public view returns (bool) {
    return block.timestamp > refundCloseDate;
  }

  function calculateClaimAt(address account, uint32 periodOffset) public view returns (uint32) {
    if (isAllocationFinished(account)) {
      return 0;
    }

    if (allocations[account].claimed == 0) {
      return startDate;
    } else {
      if (block.timestamp - startDate < cliffPeriod) {
        return startDate + cliffPeriod + unlockPeriod;
      }

      uint32 passedPeriod = calculatePassedPeriod();
      return (uint32)(startDate + cliffPeriod + (passedPeriod + periodOffset) * unlockPeriod);
    }
  }

  function calculateRemainAmount(address account) public view returns (uint256) {
    return allocations[account].amount - allocations[account].claimed;
  }

  function canRefund(address account) public view returns (bool) {
    return
      availableRefund &&
      refundStartDate <= (uint32)(block.timestamp) &&
      (uint32)(block.timestamp) <= refundCloseDate &&
      allocations[account].claimed == 0 &&
      !allocations[account].refunded;
  }

  function fetchClaimInfo(address account) external view returns (ClaimInfo memory) {
    Allocation memory allocation = allocations[account];
    bool canClaim_ = canClaim(account);
    uint256 available = calculateClaimAmount(account, 0);
    uint256 remain = calculateRemainAmount(account);
    uint256 nextAvailable = calculateClaimAmount(account, 1);
    uint32 nextClaimAt = calculateClaimAt(account, 1);
    bool canRefund_ = canRefund(account);

    return
      ClaimInfo(
        allocation.amount,
        canClaim_,
        allocation.claimed,
        allocation.claimCount,
        allocation.claimedAt,
        allocation.exist,
        available,
        remain,
        nextAvailable,
        nextClaimAt,
        canRefund_,
        allocation.refunded
      );
  }

  function calculatedRequiredAmount() public view returns (uint256) {
    uint256 contractBalance = getBalance();
    if (totalReserved > contractBalance) {
      return totalReserved - contractBalance;
    }
    return 0;
  }

  function calculateExcessAmount() public view returns (uint256) {
    uint256 contractBalance = getBalance();
    if (contractBalance > totalReserved) {
      return contractBalance - totalReserved;
    }
    return 0;
  }

  //Write methods-------------------------------------------

  function _setAllocation(address account, uint256 amount) private nonReentrant {
    if (account == address(0)) {
      revert AccountNotZeroAddress();
    }

    Allocation storage allocation = allocations[account];

    if (!allocation.exist) {
      allocationCount++;
      _accountAddresses.push(account);
    }

    totalAllocated -= allocation.amount;
    totalReserved -= allocation.amount;

    allocation.amount = amount;
    allocation.exist = true;

    totalAllocated += amount;
    totalReserved += amount;

    emit SetAllocation(account, amount);
  }

  function setAllocation(address account, uint256 amount) public onlyOwner {
    if (block.timestamp > startDate) {
      revert CantChangeOngoingVesting();
    }

    _setAllocation(account, amount);
  }

  function setAllocations(
    address[] calldata recipients,
    uint256[] calldata amounts
  ) external onlyOwner {
    if (recipients.length != amounts.length) {
      revert ArrayLengthsNotEqual();
    }

    for (uint32 i = 0; i < recipients.length; i++) {
      setAllocation(recipients[i], amounts[i]);
    }
  }

  function claim() external nonReentrant accountExist alreadyRefunded {
    address sender = _msgSender();
    uint256 claimAmount = calculateClaimAmount(sender, 0);

    if (claimAmount == 0) {
      revert NothingToClaim();
    }

    if (getBalance() < claimAmount) {
      revert ContractMustHaveSufficientFunds();
    }

    Allocation storage allocation = allocations[sender];

    allocation.claimed += claimAmount;
    allocation.claimCount += 1;
    allocation.claimedAt = (uint32)(block.timestamp);

    totalReserved -= claimAmount;

    totalClaimed += claimAmount;

    erc20Token.safeTransfer(sender, claimAmount);

    emit Claim(sender, claimAmount);
  }

  function refund() external alreadyRefunded {
    if (!availableRefund) {
      revert RefundUnavailable();
    }

    if ((uint32)(block.timestamp) < refundStartDate) {
      revert TooEarlyToRefund();
    }

    if ((uint32)(block.timestamp) > refundCloseDate) {
      revert TooLateToRefund();
    }

    address sender = _msgSender();
    Allocation storage allocation = allocations[sender];

    if (allocation.claimed > 0) {
      revert AlreadyClaimed();
    }

    allocation.refunded = true;

    _setAllocation(sender, 0);

    refundCount++;

    emit Refund(sender);
  }

  function setAvailableRefund(bool value) external onlyOwner {
    availableRefund = value;
    emit SetAvailableRefund(_msgSender(), value);
  }

  function setRefundStartDate(uint32 value) external onlyOwner {
    if (value < uint32(block.timestamp)) {
      revert RefundStartDateMustBeGreaterThanCurrentTime();
    }

    if (value > refundCloseDate) {
      revert RefundStartDateMustBeLessThanRefundCloseDate();
    }

    refundStartDate = value;
    emit SetRefundStartDate(_msgSender(), value);
  }

  function setRefundCloseDate(uint32 value) external onlyOwner {
    if (value < uint32(block.timestamp)) {
      revert RefundCloseDateMustBeGreaterThanCurrentTime();
    }

    if (value < refundStartDate) {
      revert RefundCloseDateMustBeGreaterThanRefundStartDate();
    }

    refundCloseDate = value;
    emit SetRefundCloseDate(_msgSender(), value);
  }

  function withdrawExcessAmount() external onlyOwner {
    uint256 amount = calculateExcessAmount();
    address to = owner();
    erc20Token.safeTransfer(to, amount);
    emit WithdrawExcessAmount(to, amount);
  }

  function forceWithdraw(address token, address to, uint256 amount) external onlyOwner {
    IERC20 _token = IERC20(token);
    _token.safeTransfer(to, amount);
    emit ForceWithdraw(token, to, amount);
  }
}