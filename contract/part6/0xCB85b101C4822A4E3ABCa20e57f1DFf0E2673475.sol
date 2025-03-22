// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./utils/Clonable.sol";
import "./rewards/SDAOSimpleRewardAPI.sol";

/*
 * @title SDAO Locked Staking contract
 * @notice requirements:
 *  1. users lock their tokens for a certain period
 *  2. users can extend their locking period to increase their score
 *  3. users can withdraw after their tokens unlock or withdraw immediately deducting an early unlock fee
 *  4. protocol should be able to query per wallet the score calculated by locked amount times locking period
 *  5. users can claim rewards proportionaly in the ratio of their score in respect to totalScore
 */
contract SDAOLockedStaking is Clonable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 constant public MAX_PERCENTAGE = 10000; // 100.00%
    uint256 constant public MAX_EARLY_UNLOCK_FEE = 5000; // 50.00%
    uint256 public MAX_LOCKING_PERIOD; // 360 days;
    uint256 public MAX_EARLY_UNLOCK_FEE_PER_DAY; // 5 = 0.05%

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 lockDate; // Last date when user locked funds
        uint256 unlockDate; // Unlock date for user funds
        uint256 score; // Aggregation of locked amount times locked days
    }
    // Info of each user that locks tokens.
    mapping(address => UserInfo) public userInfo;

    bool public depositsEnabled; // deposits are enabled
    address public depositToken; // Address of deposit token contract.
    address public rewardToken; // Address of reward token contract.
    address public rewardsAPI;  // Rewards API module
    address public zapperContract; // Zapper contract allowed to deposit on behalf of a user
    uint256 public totalScore; // total score of all users
    uint256 public earlyUnlockFees; // accumulated fees for early withdrawals
    uint256 public earlyUnlockFeePerDay; // Default unlockFeePerDay 0.05%

    event Deposit(address indexed user, uint256 amount, uint256 lockingPeriod);
    event Withdraw(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 claimed);
    event PaidEarlyUnlockFee(address indexed user, uint256 fee, uint256 secondsUntilUnlock);
    event CollectedFees(address admin, uint256 fees);
    event SetDepositsEnabled(address admin, bool depositsEnabled);
    event SetEarlyUnlockFeePerDay(address admin, uint256 earlyUnlockFeePerDay);
    event SetZapperContract(address admin, address zapperContract);
    
    error AlreadyInitialized();
    error MissingToken();
    error MissingAmount();
    error MissingDepositToken();
    error MissingRewardsAPI();
    error MissingZapperContract();
    error DepositsDisabled();
    error DepositTokenRecoveryNotAllowed();
    error SenderIsNotZapper(address sender, address zapper);
    error ExceedsMaxEarlyUnlockFeePerDay(uint256 fee, uint maxFee);
    error ExceedsMaxLockingPeriod(uint256 period, uint256 maxPeriod);
    error WithdrawalRequestExceedsDeposited(uint256 requestedWithdrawal, uint256 currentBalance);
    error RequestedUnlockDateBeforeCurrent(uint256 requestedUnlockDate, uint256 currentUnlockDate);

    /*
     * @dev initialize function to setup cloned instance
     * @notice marked the initialize function as payable, because it costs less gas to execute,
     * since the compiler does not have to add extra checks to ensure that a payment wasn't provided.
     */
    function initialize(
        address _depositToken,
        address _rewardsAPI,
        uint256 maxLockingPeriodInDays,
        uint256 maxEarlyUnlockFeePerDay
    ) external payable onlyOwner {
        if (depositToken != address(0)) {
            revert AlreadyInitialized();
        }
        if (_depositToken == address(0)) {
            revert MissingDepositToken();
        }
        if (_rewardsAPI == address(0)) {
            revert MissingRewardsAPI();
        }

        require(
            maxLockingPeriodInDays > 0 && maxEarlyUnlockFeePerDay > 0,
            "maxLockingPeriodInDays and maxEarlyUnlockFeePerDay must be > 0"
        );

        MAX_LOCKING_PERIOD = maxLockingPeriodInDays * 1 days;
        MAX_EARLY_UNLOCK_FEE_PER_DAY = maxEarlyUnlockFeePerDay;

        depositToken = _depositToken;
        rewardsAPI = _rewardsAPI;      
        rewardToken = SDAOSimpleRewardAPI(_rewardsAPI).rewardToken();
        earlyUnlockFeePerDay = 5;
    }


    /*
     * @dev Deposit tokens
     */
    function deposit(uint256 _amount, uint256 _lockingPeriod) external nonReentrant {
        uint256 _tokens_deposited = _deposit(_amount, msg.sender, msg.sender, _lockingPeriod);
        emit Deposit(msg.sender, _tokens_deposited, _lockingPeriod);
    }

    /*
     * @dev Deposit tokens from zapper contract on behalf of the user
     */
    function depositFor(address _recipient, uint256 _amount, uint256 _lockingPeriod) external nonReentrant {
        if (msg.sender != zapperContract) {
            revert SenderIsNotZapper(msg.sender, zapperContract);
        }
        uint256 _tokens_deposited = _deposit(_amount, msg.sender, _recipient, _lockingPeriod);
        emit Deposit(msg.sender, _tokens_deposited, _lockingPeriod);
    }

    /*
     * @dev Withdraw tokens
     */
    function withdraw(uint256 _amount) external nonReentrant {
        _withdraw(_amount, msg.sender);
        emit Withdraw(msg.sender, _amount);
    }

    /*
     * @dev Pending rewards
     */
    function pending() external view returns(uint256) {
        return SDAOSimpleRewardAPI(rewardsAPI).claimableForUser(msg.sender);
    }

    /*
     * @dev Pending rewards for user
     */
    function pendingFor(address _user) external view returns(uint256) {
        return SDAOSimpleRewardAPI(rewardsAPI).claimableForUser(_user);
    }

    /*
     * @dev Claim rewards
     */
    function claim() external {
        uint256 _claimed = SDAOSimpleRewardAPI(rewardsAPI).claimForUser(msg.sender);
        emit Claimed(msg.sender, _claimed);
    }

    /*
     * @dev withdraw and claim in one transaction
     */
    function withdrawAndClaim(uint256 _amount) external nonReentrant {
        _withdraw(_amount, msg.sender);
        emit Withdraw(msg.sender, _amount);
        SDAOSimpleRewardAPI(rewardsAPI).claimForUser(msg.sender);
    }
  
    /*
     * @dev enable/disable new deposits
     */
    function setDepositsEnabled(bool _depositsEnabled) external onlyOwner {
        depositsEnabled = _depositsEnabled;
        emit SetDepositsEnabled(msg.sender, _depositsEnabled);
    }

    /**
      * @dev change earlyUnlockFeePerDay
      */
    function setEarlyUnlockFeePerDay(uint256 _earlyUnlockFeePerDay) external onlyOwner {
        if (_earlyUnlockFeePerDay > MAX_EARLY_UNLOCK_FEE_PER_DAY) {
            revert ExceedsMaxEarlyUnlockFeePerDay(_earlyUnlockFeePerDay, MAX_EARLY_UNLOCK_FEE_PER_DAY);
        }
        earlyUnlockFeePerDay = _earlyUnlockFeePerDay;
        emit SetEarlyUnlockFeePerDay(msg.sender, _earlyUnlockFeePerDay);
    }
  
    /*
     * @dev Register zapper contract
     */
    function setZapperContract(address _zapperContract) external onlyOwner {
        if (_zapperContract == address(0)) {
            revert MissingZapperContract();
        }
        zapperContract = _zapperContract;
        emit SetZapperContract(msg.sender, _zapperContract);
    }

    /**
      * @dev recover unsupported tokens
      */
    function recoverUnsupportedTokens(address _token, uint256 amount, address to) external onlyOwner {
        if (_token == address(0)) {
            revert MissingToken();
        }
        if (_token == depositToken) {
            revert DepositTokenRecoveryNotAllowed();
        }
        IERC20(_token).safeTransfer(to, amount);
    }
  
    /**
      * @dev collect accumulated early unlock fees
      */
    function collectFees() external onlyOwner {
        uint256 fees = earlyUnlockFees;
        earlyUnlockFees = 0;
        IERC20(depositToken).safeTransfer(msg.sender, fees);
        emit CollectedFees(msg.sender, fees);
    }

    /*
     * @dev internal deposit function
     */
    function _deposit(uint256 _amount, 
                      address _depositor, 
                      address _recipient, 
                      uint256 _lockingPeriod) internal returns (uint256 tokensDeposited) {
        if (_lockingPeriod > MAX_LOCKING_PERIOD) {
            revert ExceedsMaxLockingPeriod(_lockingPeriod, MAX_LOCKING_PERIOD);
        }
        if (!depositsEnabled) {
            revert DepositsDisabled();
        }
        UserInfo memory user = userInfo[_recipient];
        if (_amount == 0 && user.amount == 0) {
            revert MissingAmount();
        }
        uint256 newEndPeriod = block.timestamp + _lockingPeriod;
        if (newEndPeriod < user.unlockDate) {
            revert RequestedUnlockDateBeforeCurrent(newEndPeriod, user.unlockDate);
        }
        uint256 deltaScore;
        
        if (_amount > 0) {
            IERC20 _depositToken = IERC20(depositToken);
            uint256 _before = _depositToken.balanceOf(address(this));
            _depositToken.safeTransferFrom(_depositor, address(this), _amount);
            tokensDeposited = _depositToken.balanceOf(address(this)) - _before;
        } 

        if (user.amount > 0) {
            // extend unlock date
            uint256 extensionPeriod = newEndPeriod - user.unlockDate;
            deltaScore += user.amount * extensionPeriod;
        }

        // handle new deposit
        deltaScore += tokensDeposited * _lockingPeriod;
      
        totalScore += deltaScore;
        user.score += deltaScore;
        SDAOSimpleRewardAPI(rewardsAPI).changeUserShares(_recipient, user.score);
        user.amount += tokensDeposited;
        user.lockDate = block.timestamp;
        user.unlockDate = newEndPeriod;
        userInfo[_recipient] = user;
    }

    /*
     * @dev internal withdraw function
     */
    function _withdraw(uint256 _amount, address _user) internal {
        UserInfo storage user = userInfo[_user];
        if (user.amount < _amount) {
            revert WithdrawalRequestExceedsDeposited(_amount, user.amount);
        }
        if (_amount == 0) {
            revert MissingAmount();
        }
        uint256 originalUnlockDate = user.unlockDate;
        uint256 deltaScore;
        // when unlock date has passed
        if (originalUnlockDate < block.timestamp) {
            // extend unlock date
            uint256 extensionPeriod = block.timestamp - originalUnlockDate; 
            deltaScore = user.amount * extensionPeriod;
            totalScore += deltaScore;
            user.score += deltaScore;
            user.unlockDate = block.timestamp;
        }
        uint256 withdrawalAmount = _amount;
        // score will be reduced proportional to the amount withdrawn
        deltaScore = user.score * withdrawalAmount / user.amount;
        // apply withdrawal amount
        user.amount -= withdrawalAmount;
        // update scores
        totalScore -= deltaScore;
        user.score -= deltaScore;
        SDAOSimpleRewardAPI(rewardsAPI).changeUserShares(_user, user.score);
        // when not yet completely unlocked, apply early unlock fee
        if (user.unlockDate > block.timestamp) {
            uint256 earlyUnlockFee = withdrawalAmount * (originalUnlockDate - block.timestamp) * earlyUnlockFeePerDay 
                                                      / 1 days                                 / MAX_PERCENTAGE;
            earlyUnlockFees += earlyUnlockFee;
            withdrawalAmount -= earlyUnlockFee;
            emit PaidEarlyUnlockFee(_user, earlyUnlockFee, originalUnlockDate - block.timestamp);
        }
        // when completely withdrawn, reset unlockdate
        if (user.amount == 0) {
            user.unlockDate = block.timestamp;
        }
        IERC20(depositToken).safeTransfer(_user, withdrawalAmount);
    }
  
}