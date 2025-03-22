// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "../abstract/BlastPointsReceiver.sol";

/**
 * @title StakingPool
 * @notice Contract for staking tokens in order to earn rewards.
 * Any user can make multiple stakes. Reward earn period is set and fixed for the whole pool lifetime.
 */

contract StakingPool is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // TYPES

    struct Stake {
        uint256 id;
        address owner;
        uint256 amount;
        uint256 claimed;
        uint256 expectedRewards;
        uint80 apy;
        uint80 unstakedAtBlockTimestamp;
        uint80 timestamp;
    }

    struct MainInfo {
        uint256 globalId;
        uint256 totalSupply;
        uint256 numOfActiveStakes;
        uint256 sumOfActiveAPY;
        uint256 rewardsAvailable;
        uint256 maxPotentialDebt;
        uint256 stakingTokenLimit;
        uint256 contractBalance;
        uint256 currentAPY;
        uint256 stakingPeriod;
        address stakingToken;
    }

    // STATE VARIABLES

    uint256 public constant ONE_HUNDRED = 100_00; // 100%
    uint256 public constant MAX_STAKING_PERIOD = 10 * YEAR;
    uint256 public constant MAX_APY = ONE_HUNDRED * 10000; // 10_000 % apy
    uint256 public constant YEAR = 365 days; // 365 days = 1 year

    // uint256 ~ 10*77 => 10**77 ~ amount * 10000 * 10000 * 10**10 = amount * 10 ** 18 => amount < 10 ** (77 - 18)
    uint256 public constant MAX_STAKE_AMOUNT = 10 ** 55;

    address public stakingToken;

    uint256 public totalSupply;

    uint256 public maxPotentialDebt;

    uint256 public stakingTokenLimit;

    mapping(uint256 => Stake) public stakes;
    mapping(address => uint256[]) public userInactiveStakes;
    mapping(address => EnumerableSetUpgradeable.UintSet) private _idsByUser;
    mapping(address => uint256) public balanceOf;

    uint256 public globalId;

    // number of currenlty active stakes
    uint80 public numOfActiveStakes;
    // sum of apy values over all active stakes
    uint80 public sumOfActiveAPY;
    // staking period, locked for all pool lifetime
    uint80 public stakingPeriod;

    // current pool APY, can be reset
    uint80 public currentAPY;

    event Deposit(uint80 stakingPeriod, address indexed user, uint256 amount);
    event Withdraw(uint80 stakingPeriod, address indexed user, uint256 amount, uint256 reward);
    event SetAPY(uint256 indexed newAPY);
    event SetTokenLimit(uint256 indexed newLimit);
    event Pulled(address indexed token, address indexed recepient, uint256 amount);

    /// @dev Creates a new contract
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param stakingToken_ address of the token to be staked
    /// @param owner_ address of the owner
    /// @param stakingPeriod_ staking period in seconds
    /// @param apy_ apy of the staking pool
    /// @param stakeAmountLimit_ total supply limitter
    /// @param blastPoints_ blast points contract address (or address 0)
    /// @param pointsOperator_ blast points operator address (or address 0)
    function init(
        address stakingToken_,
        address owner_,
        uint256 stakingPeriod_,
        uint256 apy_,
        uint256 stakeAmountLimit_,
        IBlastPoints blastPoints_,
        address pointsOperator_
    ) external initializer {
        require(stakingToken_ != address(0), 'Invalid token');
        require(owner_ != address(0), 'Invalid owner');
        require(stakingPeriod_ != 0, 'Zero period');
        require(stakingPeriod_ <= MAX_STAKING_PERIOD, 'Max period exceeded');
        require(apy_ != 0, 'Zero APY');
        require(apy_ <= MAX_APY, 'Max APY exceeded');
        require(stakeAmountLimit_ != 0, 'Zero staking limit');

        if (address(blastPoints_) != address(0)) {
            if (pointsOperator_ == address(0)) revert('Invalid blast points');
            blastPoints_.configurePointsOperator(pointsOperator_);
        } else if (pointsOperator_ != address(0)) revert('Invalid operator');

        stakingToken = stakingToken_;
        stakingPeriod = uint80(stakingPeriod_);
        currentAPY = uint80(apy_);
        stakingTokenLimit = stakeAmountLimit_;

        _transferOwnership(owner_);
    }

    /// @dev Allows user to stake tokens
    /// @param amount of token to stake
    function stake(uint256 amount) external whenNotPaused {
        require(amount <= MAX_STAKE_AMOUNT, 'Stake amount exceeds limit');
        require(
            totalSupply + amount <= stakingTokenLimit,
            'Staking token limit exceeded'
        );

        totalSupply += amount;
        ++numOfActiveStakes;
        uint80 apy = currentAPY;
        sumOfActiveAPY += apy;

        uint256 expectedReward = _calculateRewardForAPYAndStakingPeriod(
            amount,
            apy,
            stakingPeriod
        );

        require(expectedReward != 0, 'Amount too low');

        maxPotentialDebt += expectedReward + amount;

        require(
            maxPotentialDebt <= contractBalance() + amount,
            'Max potential debt exceeds contract balance'
        );

        uint256 id = ++globalId;

        // uint256 id;
        // address owner;
        // uint256 amount;
        // uint256 claimed
        // uint256 expectedRewards;
        // uint80 apy;
        // uint80 unstakedAtBlockTimestamp;
        // uint80 timestamp;
        stakes[id] = Stake(
            id,
            msg.sender,
            amount,
            0,
            expectedReward,
            apy,
            0,
            uint80(block.timestamp)
        );

        balanceOf[msg.sender] += amount;
        _idsByUser[msg.sender].add(id);

        emit Deposit(stakingPeriod, msg.sender, amount);

        IERC20Upgradeable(stakingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    /// @dev Allows user to withdraw staked tokens + claim earned rewards
    /// @param id Stake id
    function withdraw(uint256 id) external {
        Stake storage _stake = stakes[id];
        uint256 amount = _stake.amount;
        uint256 reward = _stake.expectedRewards;
        require(_stake.unstakedAtBlockTimestamp == 0, 'Already unstaked');
        require(_stake.owner == msg.sender, 'Can`t be called not by stake owner');

        require(
            _stake.timestamp + stakingPeriod <= block.timestamp,
            'Staking period not passed'
        );

        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;

        --numOfActiveStakes;
        sumOfActiveAPY -= _stake.apy;

        // CLAIM ALL EARNED REWARDS
        stakes[id].claimed = reward;

        // stake will no longer gain rewards => substract max possible stake amount + reward
        maxPotentialDebt -= reward + amount;

        _idsByUser[msg.sender].remove(id);
        userInactiveStakes[msg.sender].push(id);

        stakes[id].unstakedAtBlockTimestamp = uint80(block.timestamp);

        // ALL TOKENS TRANSFERS -------------------------------------------------------

        // REWARDS + PRINCIPAL TRANSFERS

        emit Withdraw(stakingPeriod, msg.sender, amount, reward);

        IERC20Upgradeable(stakingToken).safeTransfer(msg.sender, amount + reward);
    }

    /// @dev Allows to set APY
    /// @param apy the new staking pool APY
    function setAPY(uint256 apy) external onlyOwner {
        require(apy != 0, 'Zero APY');
        require(apy <= MAX_APY, 'Max APY exceeded');
        require(apy != currentAPY, 'Duplicate');
        currentAPY = uint80(apy);

        emit SetAPY(apy);
    }

    /// @dev Allows to set token limit for totalsupply
    /// @param limit staking token limit in weis
    function setTokenLimit(uint256 limit) external onlyOwner {
        require(limit != 0, 'Zero staking limit');
        require(limit != stakingTokenLimit, 'Duplicate');
        require(limit >= totalSupply, 'Limit too low');
        stakingTokenLimit = limit;

        emit SetTokenLimit(limit);
    }

    /// @dev Allows owner to pull extra liquidity
    /// @param token address of the token to pull
    /// @param amount amount of the token to pull
    /// @param recepient address of the token receiver
    function pullExtraLiquidity(
        address token,
        uint256 amount,
        address recepient
    ) external onlyOwner {
        require(token != address(0), 'Invalid token');
        require(amount != 0, 'Invalid amount');
        require(recepient != address(0), 'Invalid recepient');

        if (token == address(stakingToken)) {
            require(amount <= getRewardsAvailable(), 'Amount too high');
        } else {
            uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
            require(balance >= amount, 'Amount too high');
        }

        emit Pulled(token, recepient, amount);

        IERC20Upgradeable(token).safeTransfer(recepient, amount);
    }

    /// @dev Sets paused state for the contract (can be called by the owner only)
    /// @param paused paused flag
    function setPaused(bool paused) external onlyOwner {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @dev Allows to view current user earned rewards
    /// @param id to view rewards
    /// @return earned - Amount of rewards for the selected user stake
    function earned(uint256 id) external view returns (uint256) {
        Stake memory _stake = stakes[id];
        if (_stake.unstakedAtBlockTimestamp == 0) {
            // ACTIVE STAKE => calculate amount + increase reward per token
            // amountForDuration >= amount
            return
                _calculateRewardForAPYAndStakingPeriod(
                    _stake.amount,
                    _stake.apy,
                    getStakeRealDuration(id)
                );
        }

        // INACTIVE STAKE
        return 0;
    }

    /// @dev Returns the stake exact hold time
    /// @param id stake id
    /// @return duration - stake exact hold time
    function getStakeRealDuration(uint256 id) public view returns (uint256 duration) {
        Stake storage _stake = stakes[id];
        require(_stake.owner != address(0), 'Invalid stake id');
        uint256 holdTime = block.timestamp - _stake.timestamp;
        uint256 stakingPeriodLocal = stakingPeriod;
        duration = holdTime >= stakingPeriodLocal ? stakingPeriodLocal : holdTime;
    }

    /// @dev Returns rewards which can be distributed to new users
    /// @return Max reward available at the moment
    function getRewardsAvailable() public view returns (uint256) {
        // maxPotentialDebt = sum of principal + sum of max potential reward
        return contractBalance() - maxPotentialDebt;
    }

    /// @dev Allows to view staking token contract balance
    /// @return balance of staking token contract balance
    function contractBalance() public view returns (uint256) {
        return IERC20Upgradeable(stakingToken).balanceOf(address(this));
    }

    /// @dev Allows to view user`s stake ids quantity
    /// @param user user account
    /// @return length of user ids array
    function getUserStakeIdsLength(address user) external view returns (uint256) {
        return _idsByUser[user].length();
    }

    /// @dev Allows to view if a user has a stake with specific id
    /// @param user user account
    /// @param id stake id
    /// @return bool flag (true if a user has owns the id)
    function hasStakeId(address user, uint256 id) external view returns (bool) {
        return _idsByUser[user].contains(id);
    }

    /// @dev Allows to get a slice user stakes array
    /// @param user user account
    /// @param offset Starting index in user ids array
    /// @param length return array length
    /// @return Array-slice of user stakes
    function getUserStakesSlice(
        address user,
        uint256 offset,
        uint256 length
    ) external view returns (Stake[] memory) {
        require(length != 0, 'Zero length');
        require(offset + length <= _idsByUser[user].length(), 'Invalid offset + length');

        Stake[] memory userStakes = new Stake[](length);
        for (uint256 i; i < length; ) {
            uint256 stakeId = _idsByUser[user].at(i + offset);
            userStakes[i] = stakes[stakeId];

            unchecked {
                ++i;
            }
        }

        return userStakes;
    }

    /// @dev Allows to get a slice user stakes history array
    /// @param user user account
    /// @param offset Starting index in user ids array
    /// @param length return array length
    /// @return Array-slice of user stakes history
    function getUserInactiveStakesSlice(
        address user,
        uint256 offset,
        uint256 length
    ) external view returns (Stake[] memory) {
        require(length != 0, 'Zero length');
        require(
            offset + length <= userInactiveStakes[user].length,
            'Invalid offset + length'
        );
        Stake[] memory userStakes = new Stake[](length);

        for (uint256 i; i < length; ) {
            uint256 stakeId = userInactiveStakes[user][i + offset];
            userStakes[i] = stakes[stakeId];

            unchecked {
                ++i;
            }
        }
        return userStakes;
    }

    /// @dev Allows to view user`s closed stakes quantity
    /// @param user user account
    /// @return length of user closed stakes array
    function getUserInactiveStakesLength(address user) external view returns (uint256) {
        return userInactiveStakes[user].length;
    }

    /// @dev Allows to view pool major statistics
    /// @return mainInfo all major params of the pool (instance of MainInfo)
    function getMainInfo() external view returns (MainInfo memory) {
        return
            MainInfo(
                globalId,
                totalSupply,
                numOfActiveStakes,
                sumOfActiveAPY,
                getRewardsAvailable(),
                maxPotentialDebt,
                stakingTokenLimit,
                contractBalance(),
                currentAPY,
                stakingPeriod,
                stakingToken
            );
    }

    /// @dev Calculates the max potential reward after unstake for a stake with a given amount and apy (without substracting penalties)
    /// @param amount - stake amount
    /// @param apy - the stake actual apy
    /// @param duration - stake actual hold period
    /// @return max potential unstaked reward
    function _calculateRewardForAPYAndStakingPeriod(
        uint256 amount,
        uint256 apy,
        uint256 duration
    ) private pure returns (uint256) {
        return (amount * apy * duration) / (YEAR * ONE_HUNDRED);
    }
}