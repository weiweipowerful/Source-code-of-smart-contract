// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {RewardsLogic, RewardsPeriod} from "src/rewardsPeriod.sol";

/// @title PinLink Staking Contract
/// @author PinLink (@jacopod: https://twitter.com/jacolansac)
/// @notice A staking contract to deposit PIN tokens and get rewards in PIN tokens.
contract PinStaking is Ownable2Step {
    using SafeERC20 for IERC20;
    using RewardsLogic for RewardsPeriod;

    // token to stake, and also reward token
    address public immutable stakedToken;

    // scaling factor using for precision, to minimize rounding errors
    uint256 public constant PRECISION = 1e18;

    // Everytime a unstake is made, a lockup period of 7 days must pass before they can be withdrawn
    uint256 public constant UNSTAKE_LOCKUP_PERIOD = 7 days;

    // The maximum number of active pending unstakes per account
    uint8 public constant MAX_PENDING_UNSTAKES = 50;

    // The info about the rewards period that is currently active, how much, the start and end times, etc.
    RewardsPeriod public rewardsData;

    // The accumulated rewards per staked token over time (in wei, scaled up by PRECISION)
    // updated every time a deposit is made
    uint256 public globalRewardsPerStakedToken;

    // The sum of all staked amounts  // units: wei
    uint256 public totalStakedTokens;

    // Staking info per account
    mapping(address => StakeInfo) public stakeInfo;

    // Array of pending unstakes per account. 
    // The unstakes are sorted by releaseTime, so the last in the array is always the latest unstake.
    mapping(address => Unstake[]) public pendingUnstakes;

    struct StakeInfo {
        // accumulated staked amount by the account
        uint256 balance;
        // accumulated rewards by the account pending to be withdrawn. units: wei (absolute, not per token)
        uint256 pendingRewards;
        // the claimed rewards, as "rewards per staked token", following the global rewards per staked token scaled up by PRECISION
        uint256 updatedRewardsPerStakedToken;
        // number of pending unstakes for this account
        uint256 pendingUnstakesCount;
        // sum of historical reward claims by the account. // units: wei
        uint256 totalRewardsClaimed;
    }

    struct Unstake {
        // amount of unstaked tokens in this operation
        uint128 amount;
        // timestamp when it is possible to withdraw
        uint64 releaseTime;
        // If it has been withdrawn or not
        bool withdrawn;
    }

    //////////////////////// EVENTS ////////////////////////

    event Deposited(uint256 amountDeposited, uint256 amountDistributed, uint256 periodInDays);
    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event ClaimedRewards(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event GlobalRewardsPerStakedTokenUpdated(uint256 amountReleased, uint256 newGlobalRewardsPerToken);

    //////////////////////// MODIFIERS ////////////////////////

    /// @dev this modifier triggers an update in the globalRewardsPerToken,
    //       by triggering a release of rewards since the last update, following the linear schedule
    modifier updateRewards(address account) {
        // if no rewards have been deposited, there is no rewardsData, and therefore there is no update
        if (rewardsData.isInitialized()) {
            // This updates the released rewards, and the global rewards per token, 
            // taking into account the current totalStaked
            uint256 newGlobalRewardsPerToken = _updateGlobalRewardsPerStakedToken();

            // For the first-time stake, first the pendingRewards is updated to 0 (balance==0), 
            // and then the individual rewardsPerTokenStaked is matched to the global, so that the staker doesn't earn past rewards
            // update earned rewards for the account (in absolute value)
            StakeInfo storage accountInfo = stakeInfo[account];
            // global is always larger than the individual updatedRewardsPerStakedToken, so this should never underflow
            accountInfo.pendingRewards += (
                accountInfo.balance * (newGlobalRewardsPerToken - accountInfo.updatedRewardsPerStakedToken)
            ) / PRECISION;

            // now that pendingRewards has been updated, we match the individual updatedRewardsPerStakedToken to the global one
            accountInfo.updatedRewardsPerStakedToken = newGlobalRewardsPerToken;
        }
        _;
    }

    constructor(address _stakedToken) Ownable(msg.sender) {
        stakedToken = _stakedToken;
    }

    //////////////////////// RESTRICTED ACCESS FUNCTIONS ////////////////////////

    /// @notice  Allows an account with the proper role to start a new rewards period and deposit rewards
    /// @dev     The pending rewards that haven't been released yet in this period are bundled with the deposited amount for the next period
    /// @dev     Noticeably, a new deposit can finish an existing period way before its end, and that's why it is a protected function.
    //          Once rewards are deposited, they cannot be withdrawn from this contract. They are fully distributed to stakers.
    //          Admins can only accelerate its distribution by starting a new rewards period before the previous one ends
    function depositRewards(uint256 _amount, uint256 _periodInDays) external onlyOwner {
        // The deposit of rewards to be distributed linearly until the end of the period
        require(_amount > 0, "Invalid input: _amount=0");
        require(_periodInDays >= 1, "Invalid: _periodInDays < 1 day");
        require(_periodInDays < 5 * 365, "Invalid: _periodInDays > 5 years");

        // transfer tokens to the contract, but only register what actually arrives after fees
        uint256 pendingRewards = 0;

        if (rewardsData.isInitialized()) {
            // first update the linear release and the global rewards per token
            // The output of the function deliberately ignored
            _updateGlobalRewardsPerStakedToken();

            // incrase amount with the pending rewards that haven't been released yet
            pendingRewards = rewardsData.nonDistributedRewards();
        }

        uint256 distributedAmount = _amount + pendingRewards;

        // overwrite all fields of the RewardsPeriod info struct
        // the rewardsDeposited includes the remaining rewards from the previous period that were not distributed
        rewardsData.rewardsDeposited = uint128(distributedAmount);
        rewardsData.lastReleasedAmount = 0; // nothing has ben released yet
        rewardsData.startDate = uint64(block.timestamp);
        rewardsData.endDate = uint64(block.timestamp + _periodInDays * 1 days);

        IERC20(stakedToken).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposited(_amount, distributedAmount, _periodInDays);
    }

    //////////////////////// EXTERNAL USER-FACING FUNCTIONS ////////////////////////

    /// @notice  Any account can stake the PIN token
    /// @dev     The modifier triggers a rewards upate for msg.sender and an update of the global rewards per token
    /// @dev     So the rewards are up to date before the staking operation is executed
    /// @dev     If this contract is not excluded from transfer fees, the staked amount will differ from `_amount`
    function stake(uint256 _amount) external updateRewards(msg.sender) {
        require(_amount > 0, "Amount must be greater than 0");

        stakeInfo[msg.sender].balance += _amount;
        totalStakedTokens += _amount;

        IERC20(stakedToken).safeTransferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _amount);
    }

    /// @notice  Any account with positive staking balance can unstake the PIN tokens
    /// @dev     The modifier triggers a rewards upate for msg.sender and update of the global rewards per token,
    ///          so rewards are up to date before the unstake action takes place
    /// @dev     If this contract is not excluded from transfer fees, the unstaked amount will differ from `_amount`
    function unstake(uint256 _amount) external updateRewards(msg.sender) {
        StakeInfo storage accountInfo = stakeInfo[msg.sender];

        require(_amount > 0, "Invalid: _amount=0");
        require(accountInfo.balance >= _amount, "Insufficient staked amount");
        require(accountInfo.pendingUnstakesCount <= MAX_PENDING_UNSTAKES, "Too many pending unstakes");

        uint256 totalStaked = totalStakedTokens;

        accountInfo.balance -= _amount;
        totalStakedTokens = totalStaked - _amount;

        pendingUnstakes[msg.sender].push(
            Unstake({
                amount: uint128(_amount),
                releaseTime: uint64(block.timestamp + UNSTAKE_LOCKUP_PERIOD),
                withdrawn: false
            })
        );

        // the pending unstakes are always at the tail of `pendingUnstakes[msg.sender]`
        // With this counter, we know how long the tail is, and we can iterate only the pending ones
        accountInfo.pendingUnstakesCount++;

        // if we reach totalStaked==0 due to an unstake, during an active period
        // we wrapup the rewards period so rewards in no-mans-land period are pushed forward
        if ((totalStaked == _amount) && (rewardsData.endDate > block.timestamp)) {
            uint256 pendingForDistribution = rewardsData.nonDistributedRewards();
            // the end Date is not altered, only the start date and the remaining rewards
            rewardsData.rewardsDeposited = uint128(pendingForDistribution);
            rewardsData.startDate = uint64(block.timestamp);
            rewardsData.lastReleasedAmount = 0;
        }

        emit Unstaked(msg.sender, _amount);
    }

    /// @notice  Allows an account to claim pending staking rewards
    /// @dev     The modifier triggers a rewards upate for msg.sender, 
    ///          so the `pendingRewards` are updated before sending the rewards
    function claimRewards() external updateRewards(msg.sender) {
        // the pendingRewards have just been upated in the `updateRewards` modifer, so this value is up-to-date
        uint256 pendingRewards = stakeInfo[msg.sender].pendingRewards;

        // delete to get some gas back
        delete stakeInfo[msg.sender].pendingRewards;

        stakeInfo[msg.sender].totalRewardsClaimed += pendingRewards;

        IERC20(stakedToken).safeTransfer(msg.sender, pendingRewards);
        emit ClaimedRewards(msg.sender, pendingRewards);
    }

    /// @notice  This withdraws ALL pending unstakes that have fulfilled the lockup period.
    /// @dev     The modifier updating rewards has no effect in the withdrawn tokens, but better keep the system updated as frequently as possible
    function withdraw() external updateRewards(msg.sender) {
        uint256 totalToWithdraw;
        uint256 stakesWithdrawn;
        uint256 length = pendingUnstakes[msg.sender].length;
        uint256 firstPendingUnstake = length - stakeInfo[msg.sender].pendingUnstakesCount;

        // here we iterate since he first unstake that hasn't been withdrawn yet, and we "break" when we find one that hasn't been released yet
        // this ensures that we never iterate unstakes that have been already withdrawn
        for (uint256 i = firstPendingUnstake; i < length; i++) {
            Unstake storage pendingUnstake = pendingUnstakes[msg.sender][i];
            // as soon as we hit a unstake that is not ready yet, we know that all the following ones are not ready either,
            // because the unstakes are sorted by `releaseTime`
            if (pendingUnstake.releaseTime > block.timestamp) break;

            pendingUnstake.withdrawn = true;
            stakesWithdrawn++;
            totalToWithdraw += pendingUnstake.amount;
        }

        if (totalToWithdraw > 0) {
            // update the storage count only after the loop
            stakeInfo[msg.sender].pendingUnstakesCount -= stakesWithdrawn;
            IERC20(stakedToken).safeTransfer(msg.sender, totalToWithdraw);
            emit Withdrawn(msg.sender, totalToWithdraw);
        }
    }

    /// @notice updates the rewards release, and the global rewards per token 
    /// @dev    The rewards release update is triggered by all functions with the updateRewards modifier.
    /// @dev    But this function allows to manually triggering the rewards update, to minimize the step sizes
    function updateRewardsRelease() external {
        _updateGlobalRewardsPerStakedToken();
    }

    //////////////////////// VIEW FUNCTIONS ////////////////////////

    /// @notice returns the sum of all active pending unstakes that can be withdrawn now
    /// @dev see withdraw() for more info about the for-loop iteration boundaries
    function getWithdrawableAmount(address account) public view returns (uint256 totalWithdrawable) {
        uint256 length = pendingUnstakes[account].length;
        uint256 firstPendingUnstake = length - stakeInfo[account].pendingUnstakesCount;

        for (uint256 i = firstPendingUnstake; i < length; i++) {
            if (pendingUnstakes[account][i].releaseTime > block.timestamp) break;
            totalWithdrawable += pendingUnstakes[account][i].amount;
        }
    }

    /// @notice returns the sum of all active pending unstakes of `account` that cannot be withdrawn yet
    /// @dev see withdraw() for more info about the for-loop iteration boundaries
    function getLockedUnstakedAmount(address account) public view returns (uint256 totalLocked) {
        uint256 length = pendingUnstakes[account].length;
        if (length == 0) return 0;

        uint256 firstPendingUnstake = length - stakeInfo[account].pendingUnstakesCount;

        if (firstPendingUnstake == length) return 0; // all unstakes are withdrawable (or there are no unstakes at all

        // here we start iterating from the tail, and go backwards until we hit an unstake that is already withdrawable
        for (uint256 i = length; i > firstPendingUnstake; i--) {
            uint256 index = i - 1;
            if (pendingUnstakes[account][index].releaseTime <= block.timestamp) break;
            totalLocked += pendingUnstakes[account][index].amount;
        }
        return totalLocked;
    }

    /// @notice returns the sum of all staked tokens for `account`
    function getStakingBalance(address account) public view returns (uint256) {
        return stakeInfo[account].balance;
    }

    // @notice returns the sum of all historical rewards claimed plus the pending rewards.
    function getHistoricalRewardsEarned(address account) public view returns (uint256) {
        return stakeInfo[account].totalRewardsClaimed + getClaimableRewards(account);
    }

    /// @notice  returns the amount of rewards that would be received by `account` if he/she called `claimRewards()`
    /// @dev     includes an estimation of the pending linear release since the last time it was updated,
    //          because we cannot run the updateRewards modifier here as it is a view function
    function getClaimableRewards(address account) public view returns (uint256 estimatedRewards) {
        // the below calculations would revert when the array has no elements
        if (!rewardsData.isInitialized()) return 0;

        StakeInfo storage accountInfo = stakeInfo[account];

        // here we estimate the increase in globalRewardsPerStaked token if the pending rewards were released
        uint256 globalRewardPerToken = globalRewardsPerStakedToken;

        // only update globalRewardPerToken if there are staked tokens to distribute among
        uint256 estimatedRewardsFromUnreleased;
        if (totalStakedTokens > 0) {
            globalRewardPerToken += (rewardsData.releasedSinceLastUpdate() * PRECISION) / totalStakedTokens;
            // this estimated rewards are only relevant if there is any balance in the account (and then necessarily totalStakeTokens>0)
            estimatedRewardsFromUnreleased =
                (accountInfo.balance * (globalRewardPerToken - accountInfo.updatedRewardsPerStakedToken)) / PRECISION;
        }

        return estimatedRewardsFromUnreleased + accountInfo.pendingRewards;
    }

    /// @notice returns an array of Unstake objects that haven't been withdrawn yet.
    /// @dev    This includes the ones that are in lockup period, and the ones that are already withdrawable
    /// @dev    The unstakes that have been already withdrawn are not included here.
    /// @dev    Note that the withdrawn field in the Unstake struct will always be `false` in these ones
    /// @dev    The length of the array can be read in advace with `unstakeInfo[account].pendingUnstakesCount`
    function getPendingUnstakes(address account) public view returns (Unstake[] memory unstakes) {
        uint256 length = pendingUnstakes[account].length;
        uint256 pendingUnstakesCount = stakeInfo[account].pendingUnstakesCount;
        uint256 firstPendingUnstake = length - pendingUnstakesCount;

        // the lenght of the output arrays is known before iteration
        unstakes = new Unstake[](pendingUnstakesCount);

        // item `firstPendinUnstake` goes into index=0 of the output array
        for (uint256 i = firstPendingUnstake; i < length; i++) {
            unstakes[i - firstPendingUnstake] = Unstake({
                amount: pendingUnstakes[account][i].amount,
                releaseTime: pendingUnstakes[account][i].releaseTime,
                withdrawn: false // because we are only returning the pending ones
            });
        }
    }

    /// @notice     gives an approximated APR for the current rewards period and the current totalStakedTokens
    /// @dev        This is only a rough estimation which makes the following assumptions:
    ///             - It uses the current period rewards and duration: as soon as a new period is created, the APR can change.
    ///             - It uses the current totalStakedTokens: the APR will change with every stake/unstake
    ///             - If the period duration is 0, or there are no staked tokens, this function returns APR=0
    function getEstimatedAPR() public view returns (uint256) {
        return rewardsData.estimatedAPR(totalStakedTokens);
    }

    //////////////////////// INTERNAL FUNCTIONS ////////////////////////

    /// @notice     Triggers a release of the linear rewards distribution since the last update, 
    //              and with the released rewards, the global rewards per token is updated
    /// @dev        If there are no staked tokens, there is no update
    function _updateGlobalRewardsPerStakedToken() internal returns (uint256 globalRewardPerToken) {
        // cache storage variables for gas savings
        uint256 totalTokens = totalStakedTokens;
        globalRewardPerToken = globalRewardsPerStakedToken;

        // if there are no staked tokens, there is no distribution, so the global rewards per token is not updated
        if (totalTokens == 0) {
            if (rewardsData.endDate > block.timestamp) {
                // push the start date forward until there are staked tokens
                rewardsData.startDate = uint64(block.timestamp);
            }
            return globalRewardPerToken;
        }

        // The difference between the last distribution and the released tokens following the linear release
        // is what needs to be distributed in this update
        uint256 released = rewardsData.releasedSinceLastUpdate();

        // The rounding error here will be included in the next time `released` is calculated
        uint256 extraRewardsPerToken = (released * PRECISION) / totalTokens;

        // globalRewardsPerStakedToken is always incremented, it can never go down
        globalRewardPerToken += extraRewardsPerToken;

        // update storage
        globalRewardsPerStakedToken = globalRewardPerToken;
        // the actual amount of distributed tokens is (extraRewardsPerToken * totalTokens) / PRECISION, 
        // however, as this result is rounded down, it can break some critical invariants by dust amounts. 
        // Instead we store the last released amount, knowing that the difference between released and actually distributed
        // will be lost as dust wei in the contract
        // trying to keep track of those dust amounts would require more storage operations 
        // and are not be worth the gas spent
        rewardsData.lastReleasedAmount += uint128(released);

        emit GlobalRewardsPerStakedTokenUpdated(released, globalRewardPerToken);
    }
}