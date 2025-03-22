// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../access_controller/PlatformAccessController.sol";

interface IPropcToken {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external returns (uint256);
    function allowance(address owner, address spender) external returns (uint256);
}

/// @title Staking contract version 2 for Propchain's PROPC token
/// @notice Provides different staking pools with custom metrics (e.g. lockup time, rewards, penalties). Allows to stake multiple times in parallel on the same staking pool. Supports decreasing penalties, i.e. even within the lockup time penalties for forced withdrawals may decrease as time progresses.@author
/// @author Propchain Development
contract PROPCStakingV2 is PlatformAccessController  {
    using SafeERC20 for IERC20;

    /// @notice Info of each user.
    struct UserPoolInfo {
        uint256 totalAmountInPool;
    }

    /// @notice object to keep track of different rewards settings for a pool.
    struct APYInfo {
        uint256 apyPercent;     // 500 = 5%, 7545 = 75.45%, 10000 = 100%
        uint256 startTime;      // The block timestamp when this APY set
        uint256 stopTime;       // The block timestamp when the next APY set
    }

    /// @notice Info of each pool.
    struct PoolInfo {
        uint256 startTime;      // The block timestamp when Rewards Token mining starts.
        IERC20 rewardsToken;
        uint256 totalStaked;
        uint256 maxTotalStake;
        bool    active;
        uint256 claimTimeLimit;
        uint256 minStakeAmount;
        uint256 penaltyFee;     // 500 = 5%, 7545 = 75.45%, 10000 = 100%
        uint256 penaltyTimeLimit;
        address penaltyWallet;
        bool isVIPPool;
        mapping (address => bool) isVIPAddress;
        mapping (uint256 => APYInfo) apyInfo;
        uint256 lastAPYIndex;
        bool decreasingPenalty;
    }

    /// @notice dataset stored for each user / staking event
    struct Stake {
        uint256 amount;
        uint256 stakeTimestamp;
        uint256 totalRedeemed;
        uint256 lastClaimTimestamp;
    }

    IPropcToken public immutable propcToken;

    address public rewardsWallet;

    uint256 public totalPools;

    /// @dev Info of each pool.
    mapping(uint256 => PoolInfo) private poolInfo;

    /// @dev Info of each user that stakes tokens.
    mapping (uint256 => mapping (address => UserPoolInfo)) private userPoolInfo;
    mapping (uint256 => mapping(address => Stake[])) public stakes;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Redeem(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardsWalletUpdate(address indexed wallet);
    event PoolSet(
        address indexed admin,
        uint256 indexed pid,
        uint256 _apyPercent,
        uint256 _claimTimeLimit,
        uint256 _penaltyFee,
        uint256 _penaltyTimeLimit,
        bool _active,
        bool _isVIPPool,
        bool _hasDecreasingPenalty
    );
    event NewVIP(address indexed user);
    event NoVIP(address indexed user);
    event DeleteStake(address indexed user, uint256 indexed pid);

    error PoolNotOpened();
    error IndexOutOfBounds();
    error PoolInactive();
    error NotVIPQualified();
    error BelowPoolMinimum();
    error NotEnoughStaked();
    error NoRewardsAvailable();
    error ZeroAddress();
    error InsufficientBalance(uint256);
    error InsufficientRewards();
    error PoolDoesNotExist();
    error InsufficientStakeLimit();
    error APYInvalid();
    error PenaltyTooHigh();
    error NotVIPPool();
    error TooManyStakes(uint256);
    error ZeroAmount();

    /// @dev constant representing one year for rewards and penalty calculations
    uint256 public constant YEAR = 365 days;
    /// @dev constant to unify APY calculations by using a common divider for all APY values
    uint256 internal constant APY_DIVIDER = 10_000;

    /// @dev constructor initializing admin authorization and wallets.
    /// @param _propc the address of the PROPC ERC20 contract
    /// @param _rewardsWallet the wallet rewards are paid out from
    /// @param adminPanel the contract interface authorizing all admins
    constructor(
        IPropcToken _propc,
        address _rewardsWallet,
        address adminPanel
    ) {

        if(adminPanel == address(0))
            revert ZeroAddress();
        if(_rewardsWallet == address(0))
            revert ZeroAddress();

        propcToken = _propc;
        rewardsWallet = _rewardsWallet;

        _initiatePlatformAccessController(adminPanel);
    }

    /// @param _wallet the wallet rewards are paid out from
    function updateRewardsWallet(address _wallet) external onlyPlatformAdmin {
        if(_wallet == address(0))
            revert ZeroAddress();
        rewardsWallet = _wallet;
        emit RewardsWalletUpdate(_wallet);
    }

    /// @return returns the total number of pools ever created.
    function poolLength() public view returns (uint256) {
        return totalPools;
    }

    /// @dev Can only be called by an admin
    // @notice Add a new pool when _pid is 0.
    // @notice Update a pool when _pid is not 0.
    function setPool(
        uint256 _idToChange,
        uint256 _startTime,
        IERC20 _rewardsToken,
        uint256 _apyPercent,
        uint256 _claimTimeLimit,
        uint256 _penaltyFee,
        uint256 _penaltyTimeLimit,
        bool _active,
        address _penaltyWallet,
        bool _isVIPPool,
        bool _hasDecreasingPenalty,
        uint256 _minStakeAmount,
        uint256 _maxTotalStake
    ) external onlyPlatformAdmin {
        uint256 pid = _idToChange == 0 ? ++totalPools : _idToChange;

        PoolInfo storage pool = poolInfo[pid];

        if(_idToChange > 0 && pool.lastAPYIndex == 0)
            revert PoolDoesNotExist();
        if(_idToChange == 0 && _apyPercent == 0)
            revert APYInvalid();
        if(_penaltyFee > 3500)
            revert PenaltyTooHigh();
        if(_maxTotalStake == 0)
            revert InsufficientStakeLimit();
        if(_penaltyWallet == address(0))
            revert ZeroAddress();

        if (_idToChange == 0) {
            pool.startTime = _startTime;
        }

        if (_apyPercent != pool.apyInfo[pool.lastAPYIndex].apyPercent) {
            pool.apyInfo[pool.lastAPYIndex].stopTime = block.timestamp;     // current apy

            pool.lastAPYIndex ++;                                           // new apy
            APYInfo storage apyInfo = pool.apyInfo[pool.lastAPYIndex];
            apyInfo.apyPercent = _apyPercent;
            apyInfo.startTime = block.timestamp;
        }

        pool.rewardsToken       = _rewardsToken;
        pool.minStakeAmount     = _minStakeAmount;
        pool.claimTimeLimit     = _claimTimeLimit;
        pool.penaltyFee         = _penaltyFee;
        pool.penaltyTimeLimit   = _penaltyTimeLimit;
        pool.active             = _active;
        pool.penaltyWallet      = _penaltyWallet;
        pool.isVIPPool          = _isVIPPool;
        pool.decreasingPenalty  = _hasDecreasingPenalty;
        pool.maxTotalStake      = _maxTotalStake;

        emit PoolSet(
            msgSender(),
            pid,
            _apyPercent,
            _claimTimeLimit,
            _penaltyFee,
            _penaltyTimeLimit,
            _active,
            _isVIPPool,
            _hasDecreasingPenalty
        );
    }

    /// @dev only callable by an admin
    /// @notice Adds a VIP address to a specific pool
    function addVIPAddress(uint256 _pid, address _vipAddress) external onlyPlatformAdmin {
        PoolInfo storage pool = poolInfo[_pid];
        if(!pool.isVIPPool)
            revert NotVIPPool();
        if(_vipAddress == address(0))
            revert ZeroAddress();

        pool.isVIPAddress[_vipAddress] = true;
        emit NewVIP(_vipAddress);
    }

    /// @dev only callable by an admin
    /// @notice Adds multiple VIP addresses to a specific pool
    function addVIPAddresses(uint256 _pid, address[] memory _vipAddresses) external onlyPlatformAdmin {
        PoolInfo storage pool = poolInfo[_pid];
        if(!pool.isVIPPool)
            revert NotVIPPool();

        for (uint256 i = 0; i < _vipAddresses.length; i++) {
            if(_vipAddresses[i] == address(0))
                revert ZeroAddress();

            pool.isVIPAddress[_vipAddresses[i]] = true;
            emit NewVIP(_vipAddresses[i]);
        }
    }

    /// @dev only callable by an admin
    /// @notice Removes a VIP address from a specific pool
    function removeVIPAddress(uint256 _pid, address _vipAddress) external onlyPlatformAdmin {
        PoolInfo storage pool = poolInfo[_pid];
        if(!pool.isVIPPool)
            revert NotVIPPool();
        if(_vipAddress == address(0))
            revert ZeroAddress();

        pool.isVIPAddress[_vipAddress] = false;
        emit NoVIP(_vipAddress);
    }

    /// @dev only callable by an admin
    /// @notice Removes multiple VIP addresses from a specific pool
    function removeVIPAddresses(uint256 _pid, address[] memory _vipAddresses) external onlyPlatformAdmin {
        PoolInfo storage pool = poolInfo[_pid];
        if(!pool.isVIPPool)
            revert NotVIPPool();

        for (uint256 i = 0; i < _vipAddresses.length; i++) {
            if(_vipAddresses[i] == address(0))
                revert ZeroAddress();

            pool.isVIPAddress[_vipAddresses[i]] = false;
            emit NoVIP(_vipAddresses[i]);
        }
    }

    /// @notice Return reward multiplier over the given _from to _to block.
    function getTimespanInSeconds(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to - _from;
    }

    /// @dev returns the maximum of two numbers
    /// @param a comparator one
    /// @param b comparator two
    /// @return uint256 being the maximum value of both inputs
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @dev executes a loop over all stakes. To ensure performance the number of stakes on a pool by one user is limited during stake().
    /// @notice returns the total amount of eligible rewards for one user on a specific pool at the current point in time.
    /// @param _pid the pools ID
    /// @param _user the user's address
    /// @return uint256. the accumulated rewards.
    function rewardsForPool(uint _pid, address _user) public view returns (uint256)  {
        Stake[] memory _stakes = stakes[_pid][_user];
        uint256 rewards = 0;
        for(uint256 i = 0; i < _stakes.length; i++) {
            rewards = rewards + _pendingRewardsForStake(_pid, _stakes[i]);
        }
        return rewards;
    }

    /// @dev throws an index out of bounds error, otherwise calculates rewards using internal function.
    /// @notice returns the amount of eligible rewards for one user on a specific pool and for a specific state at the current point in time.
    /// @param _pid the pools ID
    /// @param _user the user's address
    /// @param _stakeId the stake identifier on the pool (increments with each stake() on the pool)
    /// @return uint256. the rewards.
    function pendingRewardsForStake(uint256 _pid, address _user, uint256 _stakeId) external view returns (uint256) {
        Stake[] memory _stakes = stakes[_pid][_user];
        if(_stakes.length <= _stakeId)
            revert IndexOutOfBounds();
        return _pendingRewardsForStake(_pid, _stakes[_stakeId]);
    }

    /// @dev View to retrieve pending rewards for specific stake, used internally to facilitate rewards processing.
    function _pendingRewardsForStake(uint256 _pid, Stake memory _stake) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 pendingRewards = 0;

        for (uint256 apyIndex = pool.lastAPYIndex; apyIndex > 0; apyIndex--) {
            // last claim was after closing of pool --> no rewards
            if (pool.apyInfo[apyIndex].stopTime > 0 && _stake.lastClaimTimestamp >= pool.apyInfo[apyIndex].stopTime) {
                continue;
            }

            // not long enough in pool to retrieve rewards
            if(pool.claimTimeLimit + _stake.lastClaimTimestamp > block.timestamp)  {
                continue;
            }

            // if the period has 0% apy
            if (pool.apyInfo[apyIndex].apyPercent == 0) {
                continue;
            }

            uint256 _fromTime = _max(_stake.lastClaimTimestamp, pool.apyInfo[apyIndex].startTime);
            uint256 _toTime = block.timestamp;

            if (pool.apyInfo[apyIndex].stopTime > 0 && block.timestamp > pool.apyInfo[apyIndex].stopTime) {
                _toTime = pool.apyInfo[apyIndex].stopTime;
            }

            // if start is after end, ignore this timespan
            if (_fromTime >= _toTime) {
                continue;
            }

            uint256 timespanInPool = getTimespanInSeconds(_fromTime, _toTime); // calculates the timespan from to to
            uint256 rewardsPerAPYBlock = (timespanInPool * pool.apyInfo[apyIndex].apyPercent * _stake.amount) / (YEAR * APY_DIVIDER);
            pendingRewards = pendingRewards + rewardsPerAPYBlock;
        }

        return pendingRewards;
    }


    /// @dev Calculates the penalty to be required during withdrawals and unstakes, no penalty returned if outside the lockup timeframe.
    /// @return uint256. penalty amount.
    function _penalty(Stake memory _stake, PoolInfo storage pool, uint256 _amount) internal view returns (uint256) {
        uint256 penaltyAmount = 0;

        if (_stake.stakeTimestamp + pool.penaltyTimeLimit <= block.timestamp) // no penalty applies
            return penaltyAmount;

        if(pool.decreasingPenalty)  {
            uint256 appliedPenalty = block.timestamp - _stake.stakeTimestamp; // time spent in pool
            appliedPenalty = (pool.penaltyTimeLimit - appliedPenalty) * APY_DIVIDER / pool.penaltyTimeLimit;

            penaltyAmount = _amount * pool.penaltyFee * appliedPenalty / (APY_DIVIDER * APY_DIVIDER);
        } else  { // static
            penaltyAmount = _amount * pool.penaltyFee / APY_DIVIDER;
        }

        return penaltyAmount;
    }

    /// @dev Executes a loop over all pools, while rewardsForPool() in turn loops over all stakes on a specific pool for a user.
    /// @notice Returns all rewards available for a user on all active pools the user staked in.
    /// @param _user The user to calculate all pending rewards for.
    /// @return uint256[] List of available rewards per pool.
    function allPendingRewardsToken(address _user) external view returns (uint256[] memory) {
        uint256 length = poolLength();
        uint256[] memory pendingRewards = new uint256[](length);

        for(uint256 _pid = 1; _pid <= length; _pid++) {
            pendingRewards[_pid - 1] = rewardsForPool(_pid, _user);
        }
        return pendingRewards;
    }

    /// @dev Number of stakes per pool is limited for each user to avoid gas limit issues on withdrawals.
    /// @notice Stake tokens to contract for Rewards Token allocation.
    /// @param _pid Pool to stake on
    /// @param _amount Amount to stake
    function stake(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserPoolInfo storage user = userPoolInfo[_pid][msg.sender];

        Stake[] storage _stakes = stakes[_pid][msg.sender];

        if(_amount == 0)
            revert ZeroAmount();
        if(_stakes.length >= 10)
            revert TooManyStakes(_pid);
        if(pool.startTime > block.timestamp)
            revert PoolNotOpened();
        if(!pool.active)
            revert PoolInactive();
        if(pool.isVIPPool && !pool.isVIPAddress[msg.sender])
            revert NotVIPQualified();
        if(user.totalAmountInPool + _amount < pool.minStakeAmount)
            revert BelowPoolMinimum();
        if(_amount + pool.totalStaked > pool.maxTotalStake)
            revert InsufficientStakeLimit();

        propcToken.transferFrom(msg.sender, address(this), _amount);

        _stakes.push(
            Stake(
                _amount,
                block.timestamp,
                0,
                block.timestamp
            )
        );

        user.totalAmountInPool = user.totalAmountInPool + _amount;

        pool.totalStaked = pool.totalStaked + _amount;
        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @dev Internally called methods loop through pools. Potentially expensive transaction, hence number of stakes per pool / user is limited during stake.
    /// @notice Unstake all tokens from pool. Will transfer staked tokens (deducting potential penalties) and rewards to caller.
    /// @param _pid pool id to unstake from.
    function leavePool(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserPoolInfo storage user = userPoolInfo[_pid][msg.sender];
        (uint256 amount, uint256 penaltyAmount, uint256 pendingRewards) = _userPoolMetrics(_pid);

        uint256 availableRewards = IERC20(pool.rewardsToken).allowance(rewardsWallet, address(this));
        if(pendingRewards > availableRewards) {
            revert InsufficientRewards();
        }

        if(pendingRewards > 0) {
            safeRewardTransfer(_pid, msg.sender, pendingRewards);
        }

        propcToken.transfer(msg.sender, amount - penaltyAmount);
        propcToken.transfer(pool.penaltyWallet, penaltyAmount);

        user.totalAmountInPool = user.totalAmountInPool - amount;

        pool.totalStaked = pool.totalStaked - amount;

        emit Withdraw(msg.sender, _pid, amount);
    }

    /// @dev Allows to leave pool without claiming rewards. Rewards are lost from user perspective.
    /// @notice Allows to withdraw tokens in case leavePool() fails due to missing rewards balance. Should not be used except for emergencies.
    /// @param _pid pool id to unstake from.
    function emergencyWithdrawal(uint256 _pid) external  {
        PoolInfo storage pool = poolInfo[_pid];
        UserPoolInfo storage user = userPoolInfo[_pid][msg.sender];
        (uint256 amount, uint256 penaltyAmount, uint256 pendingRewards) = _userPoolMetrics(_pid);

        uint256 availableRewards = IERC20(pool.rewardsToken).allowance(rewardsWallet, address(this));
        if(pendingRewards > availableRewards) {
            pendingRewards = availableRewards;
        }

        if(pendingRewards > 0) {
            safeRewardTransfer(_pid, msg.sender, pendingRewards);
        }

        propcToken.transfer(msg.sender, amount - penaltyAmount);
        propcToken.transfer(pool.penaltyWallet, penaltyAmount);

        user.totalAmountInPool = user.totalAmountInPool - amount;
        pool.totalStaked = pool.totalStaked - amount;

        emit Withdraw(msg.sender, _pid, amount);
    }

    /// @dev Gives an overview on user's stake(s) on a pool containing key data amount, penalty, rewards.
    /// @return uint256. Amount staked in pool
    /// @return uint256. Penalty at current point in time if leaving pool
    /// @return uint256. Rewards available at current point in time
    function _userPoolMetrics(uint256 _pid) internal returns(uint256, uint256, uint256){
        PoolInfo storage pool = poolInfo[_pid];
        Stake[] storage _stakes = stakes[_pid][msg.sender];

        uint256 pendingRewards = 0;
        uint256 penaltyAmount = 0;
        uint256 amount = 0;
        // from new to old stakes
        for(uint256 stakeId = _stakes.length; stakeId > 0; stakeId--)   {
            Stake memory _stake = _stakes[stakeId-1];
            uint256 pendingRewardsStake = _pendingRewardsForStake(_pid, _stake);

            amount = amount + _stake.amount;
            pendingRewards = pendingRewards + pendingRewardsStake;


            penaltyAmount = penaltyAmount + _penalty(_stake, pool, _stake.amount);
            _stakes.pop();
        }

        return (amount, penaltyAmount, pendingRewards);
    }

    /// @dev throws error if stake id is out of bounds, otherwise tries to unstake given amount from pool. Reduces remaining stake.
    /// @notice Unstake set amount from specific stake of pool. Sends rewards and tokens to caller, penalties may be deducted.
    /// @param _pid the pool to unstake from
    /// @param _amount the amount to unstake
    /// @param _stakeId the stake id of the to unstake from
    function unstake(uint256 _pid, uint256 _amount, uint256 _stakeId) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserPoolInfo storage user = userPoolInfo[_pid][msg.sender];
        Stake[] storage _stakes = stakes[_pid][msg.sender];

        if(_stakeId >= _stakes.length)
            revert IndexOutOfBounds();
        if(_amount == 0)
            revert ZeroAmount();

        Stake storage _stake = _stakes[_stakeId];
        if(_amount > _stake.amount)
            revert NotEnoughStaked();

        uint256 penaltyAmount = _penalty(_stake, pool, _amount);
        uint256 pendingRewards = _pendingRewardsForStake(_pid, _stake);

        if(pendingRewards > 0) {
            safeRewardTransfer(_pid, msg.sender, pendingRewards);
        }

        if(_amount == _stake.amount)
            deleteStake(_stakes, _stakeId);
        else    {
            _stake.lastClaimTimestamp = block.timestamp;
            _stake.totalRedeemed = _stake.totalRedeemed + pendingRewards;
            _stake.amount = _stake.amount - _amount;
        }

        propcToken.transfer(msg.sender, _amount - penaltyAmount);
        propcToken.transfer(pool.penaltyWallet, penaltyAmount);

        user.totalAmountInPool = user.totalAmountInPool - _amount;
        pool.totalStaked = pool.totalStaked - _amount;

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /// @dev Deletes a stake by overwriting set index with last element and dropping the last element.
    /// @dev Assumes that outOfBounds check is done before calling.
    function deleteStake(Stake[] storage _stakes, uint256 index) private    {
        _stakes[index] = _stakes[_stakes.length-1];
        _stakes.pop();
        emit DeleteStake(msgSender(), index);
    }

    /// @dev Loops over stakes on a pool. Maximum number of stakes is limited during stake() to avoid gas limit issues.
    /// @notice Redeem currently pending rewards accumulated from all stakes on the pool. Sends tokens to the caller.
    /// @param _pid the pool to redeem from
    function redeem(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        Stake[] storage _stakes = stakes[_pid][msg.sender];

        uint256 pendingRewards = 0;

        for(uint256 stakeId = _stakes.length; stakeId > 0; stakeId--)   {
            Stake storage _stake = _stakes[stakeId-1];

            if(_stake.lastClaimTimestamp + pool.claimTimeLimit > block.timestamp)
                continue;

            uint256 pendingRewardsStake = _pendingRewardsForStake(_pid, _stake);
            pendingRewards = pendingRewards + pendingRewardsStake;

            _stake.lastClaimTimestamp = block.timestamp;
            _stake.totalRedeemed = _stake.totalRedeemed + pendingRewardsStake;
        }

        if(pendingRewards == 0)
            revert NoRewardsAvailable();

        safeRewardTransfer(_pid, msg.sender, pendingRewards);
        emit Redeem(msg.sender, _pid, pendingRewards);
    }

    /// @dev Loops over all pools. Internal call loops over stakes on a pool. Maximum number of stakes is limited during stake() to avoid gas limit issues.
    /// @notice Redeem currently pending rewards accumulated from all pools. Sends tokens to the caller.
    function redeemAll() public {
        for(uint _pid = 1; _pid <= poolLength(); _pid++) {
            redeem(_pid);
        }
    }

    /// @dev internal wrapper function used to send ERC20 compliant tokens as rewards.
    function safeRewardTransfer(uint256 _pid, address _to, uint256 _amount) internal {
        IERC20(poolInfo[_pid].rewardsToken).safeTransferFrom(rewardsWallet, _to, _amount);
    }

    function getUserInfo(uint256 _pid, address _account) external view returns(uint256 amount) {
        UserPoolInfo storage user = userPoolInfo[_pid][_account];
        return (
            user.totalAmountInPool
        );
    }

    function getStakesInfo(uint256 _pid, address _account) external view returns(Stake[] memory) {
        Stake[] memory _stakes = stakes[_pid][_account];
        return _stakes;
    }

    function getPoolInfo(uint256 _pid) external view returns(
        uint256 startTime,
        address rewardsToken,
        address penaltyWallet,
        uint256 apyPercent,
        uint256 totalStaked,
        bool    active,
        uint256 claimTimeLimit,
        uint256 minStakeAmount,
        uint256 penaltyFee,
        uint256 penaltyTimeLimit,
        bool isVIPPool
    ) {
        PoolInfo storage pool = poolInfo[_pid];

        startTime           = pool.startTime;
        penaltyWallet       = pool.penaltyWallet;
        isVIPPool           = pool.isVIPPool;
        rewardsToken        = address(pool.rewardsToken);
        apyPercent          = pool.apyInfo[pool.lastAPYIndex].apyPercent;
        totalStaked         = pool.totalStaked;
        active              = pool.active;
        claimTimeLimit      = pool.claimTimeLimit;
        minStakeAmount      = pool.minStakeAmount;
        penaltyFee          = pool.penaltyFee;
        penaltyTimeLimit    = pool.penaltyTimeLimit;
    }
}