// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/IDiamondHand.sol";
import "./utils/constants.sol";
import "./utils/userDefinedType.sol";

contract BlazeStaking is ReentrancyGuard, Context, Ownable2Step {
    using SafeERC20 for IERC20;

    uint32 public immutable _deploymentTimeStamp;
    address private _blazeToken;

    address private _lastDistributionAddress;

    uint32 private _currentDayInContract;

    uint256 private _currentStakingShareRate;

    uint256 private _stakeIdCounter;

    uint256 private _totalShares;

    uint256 private _totalCompletedShares;

    uint256 private _totalBlazeTokenStaked;

    uint256 private _allCompletedStake;

    uint256 private _totalUndistributedCollectedFees;

    /* Distribution Variables*/
    DistributionTriggered private _isGlobalDistributionTriggered;

    //cycle => rewards
    mapping(uint16 => uint256) private _cycleDistributionTotalRewards;

    //cycle ==> index count
    mapping(uint16 => uint32) private _cycleDistributionIndexCount;

    mapping(uint16 => uint32) _nextCycleDistributionDay;

    //cycle => index count => reward Per share
    mapping(uint16 => mapping(uint32 => CycleRewardsPerShare)) private _cycleRewardsPerShare;

    mapping(address => mapping(uint16 => CycleClaimIndexCountForUser)) private _userAddressToCycleToLastClaimIndex;

    /* STaking Related variables */

    mapping(address => uint256) private _userAddressToStakeId;

    mapping(address => mapping(uint256 => uint256)) private _userStakeIdToGlobalStakeId;

    //global stake id to stake info
    mapping(uint256 => StakeInfo) private _stakeInfo;

    mapping(address => uint256) private _userLatestIndex;

    mapping(address => mapping(uint256 => UserSharesInfo)) private _userIndexToSharesInfo;

    mapping(address => mapping(uint256 => uint256)) private _user2888CycleBlazeTokenAmount;

    event ETHDistributed(address indexed caller, uint256 indexed amount);
    event CycleDistributionTriggered(address indexed caller, uint256 indexed cycleNo, uint256 indexed rewardAmount);
    event DistributionRewardsClaimed(address indexed user, uint256 indexed rewardAmount);
    event StakeStarted(address indexed user,uint256 indexed globalStakeId,uint256 __blazeAmount,uint256 __durationInDays);
    event StakeEnded(address indexed user,uint256 indexed globalStakeId,uint256 indexed __blazeAmount);
    
    modifier dailyUpdate() {
        _dailyUpdate();
        _;
    }

    constructor(address _blazeTokenAddress) Ownable(_msgSender()) {
        _blazeToken = _blazeTokenAddress;
        _deploymentTimeStamp = uint32(block.timestamp);
        _currentDayInContract = 1;
        _currentStakingShareRate = START_SHARE_RATE;
        _nextCycleDistributionDay[DAY8] = DAY8;
        _nextCycleDistributionDay[DAY88] = DAY88;
        _nextCycleDistributionDay[DAY288] = DAY288;
    }

    receive() external payable {
        _totalUndistributedCollectedFees += msg.value;
    }

    function setLastDistributionAddress(address __lastDistributionAddress) external onlyOwner {
        require(__lastDistributionAddress != address(0), "blazeStaking:last distribution address can not be zero");
        _lastDistributionAddress = __lastDistributionAddress;
    }

    function stakeBlaze(uint256 __blazeAmount, uint256 __durationInDays) external dailyUpdate nonReentrant {
        // IBlazeToken(_blazeToken).burn(_msgSender(), __blazeAmount);
        // uint8 _isFirstStake = _stakeBlaze(_msgSender(), __blazeAmount, __durationInDays);

        uint256 stakeId = ++_userAddressToStakeId[_msgSender()];

        require(
            __durationInDays >= MINIMUM_STAKING_PERIOD && __durationInDays <= MAXIMUM_STAKING_PERIOD,
            "blazeStaking:blaze stake duration not valid"
        );
        //calculate shares
        (uint256 totalShares, ) = calculateSharesAndBonus(__blazeAmount, __durationInDays);
        uint256 globalStakeId = ++_stakeIdCounter;
        _userStakeIdToGlobalStakeId[_msgSender()][stakeId] = globalStakeId;

        uint32 stakeMaturityTimestamp = uint32(block.timestamp + (__durationInDays * SECONDS_IN_DAY));

        StakeInfo memory stakeInfo = StakeInfo({
            amount: __blazeAmount,
            shares: totalShares,
            stakeDurationInDays: uint16(__durationInDays),
            startTimestamp: uint32(block.timestamp),
            maturityTimestamp: stakeMaturityTimestamp,
            status: StakeStatus.ACTIVE
        });

        _stakeInfo[globalStakeId] = stakeInfo;

        //update shares changes
        uint8 _isFirstStake = _updateSharesStats(_msgSender(), totalShares, __blazeAmount, StakeAction.START);
        if (_isFirstStake == 1) {
            _firstStakeCycleConfig(_msgSender());
        }
        if (__durationInDays == MAXIMUM_STAKING_PERIOD) {
            _setDiamondHand(_msgSender(), __blazeAmount);
        }
        IERC20(_blazeToken).safeTransferFrom(_msgSender(), address(this), __blazeAmount);

        emit StakeStarted(_msgSender(),globalStakeId,__durationInDays,__blazeAmount);
    }

    function unstakeBlaze(address __user, uint256 __id) external dailyUpdate nonReentrant {
        uint256 amount = _unstakeBlaze(__user, __id);

        IERC20(_blazeToken).safeTransfer(__user, amount);

    }

    function dailyDetailsUpdater() external dailyUpdate {}

    // function unstakeBlazeForOthers(address __user, uint256 __id) external dailyUpdate nonReentrant {
    //     uint256 amount = _unstakeBlaze(__user, __id);
    //     IERC20(_blazeToken).safeTransfer(__user, amount);
    // }

    function setFeeRewardsForAllCycle() external dailyUpdate nonReentrant {
        (uint256 lastCycleDistributionPortion, uint256 incentiveAmount) = _distributeCollectedETH();
        require(_lastDistributionAddress != address(0), "blazeStaking:last cycle distribution address not set");
        _transferETH(_lastDistributionAddress, lastCycleDistributionPortion);
        if (incentiveAmount > 0) {
            _transferETH(_msgSender(), incentiveAmount);
        }
    }

    function distributeFeeRewardsForAll() external dailyUpdate nonReentrant {
        uint256 lastCycleDistributionPortion;
        uint256 incentiveAmount;
        if (_totalUndistributedCollectedFees != 0) {
            (lastCycleDistributionPortion, incentiveAmount) = _distributeCollectedETH();
        }

        uint256 currentActivateShares = _totalShares - _totalCompletedShares;
        require(currentActivateShares > 1, "blazeStaking:no active shares");

        uint32 currentDayInContract = _currentDayInContract;
        DistributionTriggered isDistributionCompleted = DistributionTriggered.NO;

        DistributionTriggered completed = _distributeFeeRewardsForCycle(
            DAY8,
            currentDayInContract,
            currentActivateShares
        );
        if (completed == DistributionTriggered.YES && isDistributionCompleted == DistributionTriggered.NO) {
            isDistributionCompleted = DistributionTriggered.YES;
        }

        completed = _distributeFeeRewardsForCycle(DAY88, currentDayInContract, currentActivateShares);
        if (completed == DistributionTriggered.YES && isDistributionCompleted == DistributionTriggered.NO) {
            isDistributionCompleted = DistributionTriggered.YES;
        }

        completed = _distributeFeeRewardsForCycle(DAY288, currentDayInContract, currentActivateShares);
        if (completed == DistributionTriggered.YES && isDistributionCompleted == DistributionTriggered.NO) {
            isDistributionCompleted = DistributionTriggered.YES;
        }

        if (
            isDistributionCompleted == DistributionTriggered.YES &&
            _isGlobalDistributionTriggered == DistributionTriggered.NO
        ) {
            _isGlobalDistributionTriggered = DistributionTriggered.YES;
        }

        require(_lastDistributionAddress != address(0), "blazeStaking:last cycle distribution address not set");
        if(lastCycleDistributionPortion>0){
            _transferETH(_lastDistributionAddress, lastCycleDistributionPortion);
        }
        if (incentiveAmount > 0) {
            _transferETH(_msgSender(), incentiveAmount);
        }
    }

    function claimFeeRewards() external dailyUpdate nonReentrant {
        uint256 reward = _claimCycleDistribution(DAY8);
        reward += _claimCycleDistribution(DAY88);
        reward += _claimCycleDistribution(DAY288);

        if (reward != 0) {
            _transferETH(_msgSender(), reward);
        }
        emit DistributionRewardsClaimed(_msgSender(), reward);
    }

    function getAvailableRewardsForClaim(address __user) external view returns (uint256 __totalRewards) {
        uint256 rewardsPerCycle;
        (rewardsPerCycle, , ) = _calculateUserCycleFeesReward(__user, DAY8);
        __totalRewards += rewardsPerCycle;
        (rewardsPerCycle, , ) = _calculateUserCycleFeesReward(__user, DAY88);
        __totalRewards += rewardsPerCycle;
        (rewardsPerCycle, , ) = _calculateUserCycleFeesReward(__user, DAY288);
        __totalRewards += rewardsPerCycle;
    }

    function getStakes(
        address __user,
        uint256 __cursor,
        uint256 __size
    ) external view returns (CompleteStakeInfo[] memory __stakes, uint256 __counter) {
        uint256 currentUserCounter = _userAddressToStakeId[__user];
        uint256 count = currentUserCounter;
        if (__cursor >= count) {
            return (new CompleteStakeInfo[](0), 0);
        }

        uint256 endIndex = __cursor + __size;
        if (endIndex > count) {
            endIndex = count;
        }

        __stakes = new CompleteStakeInfo[](endIndex - __cursor);

        for (uint256 i = 0; __cursor < endIndex; ++__cursor) {
            __stakes[i] = CompleteStakeInfo({
                userStakeId: __cursor + 1,
                globalStakeId: _userStakeIdToGlobalStakeId[__user][__cursor + 1],
                stakeInfo: getStakeInfoByUserStakeId(__user, __cursor + 1)
            });
            ++i;
        }

        return (__stakes, endIndex);
    }

    function getCurrentSharesOfUser(address __user) external view returns (uint256) {
        return _userIndexToSharesInfo[__user][getUserLatestShareIndex(__user)].currentShares;
    }

    function getUserSharesAtParticularUserIndex(
        address __user,
        uint256 __index
    ) external view returns (uint256 __shares, uint256 __updationDay) {
        return (
            _userIndexToSharesInfo[__user][__index].currentShares,
            _userIndexToSharesInfo[__user][__index].updationDay
        );
    }

    function getTotalStakesInfo()
        external
        view
        returns (uint256 __totalStakes, uint256 __totalCompletedStakes, uint256 __currentActiveStakes)
    {
        return (_stakeIdCounter, _allCompletedStake, _stakeIdCounter - _allCompletedStake);
    }

    function getTotalSharesInfo()
        external
        view
        returns (uint256 __totalSharesAllocated, uint256 __totalCompletedStakeShares, uint256 __currentActiveShares)
    {
        return (_totalShares, _totalCompletedShares, _totalShares - _totalCompletedShares);
    }

    function getTotalStakedTokens() external view returns (uint256 __blazeTokens) {
        return _totalBlazeTokenStaked;
    }

    function getTotalCycleRewards(uint16 __cycle) external view returns (uint256 __totalRewards) {
        return _cycleDistributionTotalRewards[__cycle];
    }

    function getNextCycleDistributionDay(uint16 __cycle) external view returns (uint256 __nextDistributionDay) {
        return _nextCycleDistributionDay[__cycle];
    }

    function getCurrentCycleIndex(uint16 __cycle) external view returns (uint256 __currentCycleIndex) {
        return _cycleDistributionIndexCount[__cycle];
    }

    function getCurrentShareRate() external view returns (uint256 __shareRate) {
        return _currentStakingShareRate;
    }

    function getGlobalDistributionTriggeringStatus() external view returns (DistributionTriggered) {
        return _isGlobalDistributionTriggered;
    }

    function getCurrentDayInContract() external view returns (uint256 __currentDay) {
        return _currentDayInContract;
    }

    function getTotalUndistributedFees() external view returns (uint256 __totalUndistributedFees) {
        return _totalUndistributedCollectedFees;
    }

    function getLastDistributionAddress() external view returns (address __lastDsitributionAddress) {
        return _lastDistributionAddress;
    }

    function getUser2888BlazeToken(address __user, uint256 __cycle) external view returns (uint256 _blazeTokenStaked) {
        return _user2888CycleBlazeTokenAmount[__user][__cycle];
    }

    function getUserLastCycleClaimIndex(
        address __user,
        uint16 __cycle
    ) public view returns (uint32 __cycleIndex, uint96 __sharesIndex) {
        return (
            _userAddressToCycleToLastClaimIndex[__user][__cycle].cycleIndex,
            _userAddressToCycleToLastClaimIndex[__user][__cycle].sharesIndex
        );
    }

    function getStakeInfoByUserStakeId(address __user, uint256 __userStakeId) public view returns (StakeInfo memory) {
        return _stakeInfo[_userStakeIdToGlobalStakeId[__user][__userStakeId]];
    }

    function getRewardsPerShare(
        uint16 __cycle,
        uint32 __index
    ) public view returns (uint256 __rewardsPerShare, uint256 __distributionDay) {
        return (_cycleRewardsPerShare[__cycle][__index].rewardPerShare, _cycleRewardsPerShare[__cycle][__index].day);
    }

    function getUserLatestShareIndex(address __user) public view returns (uint256 __userLatestIndex) {
        return _userLatestIndex[__user];
    }

    function calculateSharesAndBonus(
        uint256 __blazeAmount,
        uint256 __durationInDays
    ) public view returns (uint256 __shares, uint256 __bonus) {
        // Calculate regular shares
        __shares = __blazeAmount;

        // Calculate bonus based on duration
        __bonus = ((__durationInDays - MINIMUM_STAKING_PERIOD) * BASE_1e18) / Percent_In_Days;
        // Add bonus shares to total shares
        __shares = __shares + ((__shares * __bonus) / BASE_1e18);

        __shares = (__shares * BASE_1e18) / _currentStakingShareRate;

        return (__shares, __bonus);
    }

    function _dailyUpdate() private {
        uint32 currentDayInContract = _currentDayInContract;
        uint32 currentDay = uint32(((block.timestamp - _deploymentTimeStamp) / 1 days) + 1);

        if (currentDay > currentDayInContract) {
            uint256 newShareRate = _currentStakingShareRate;

            uint32 dayDifference = currentDay - currentDayInContract;

            uint32 tempDayInContract = currentDayInContract;

            for (uint32 i = 0; i < dayDifference; ++i) {
                ++tempDayInContract;

                if (tempDayInContract % DAY8 == 0) {
                    newShareRate = (newShareRate -
                        (newShareRate * EIGHTH_DAY_SHARE_RATE_DECREASE_PERCENTAGE) /
                        PERCENT_BASE);
                }
            }
            _currentStakingShareRate = newShareRate;
            _currentDayInContract = currentDay;
            _isGlobalDistributionTriggered = DistributionTriggered.NO;
        }
    }

    function _unstakeBlaze(address __user, uint256 __id) private returns (uint256 __blazeAmount) {
        uint256 globalStakeId = _userStakeIdToGlobalStakeId[__user][__id];
        require(globalStakeId != 0, "blazeStaking:blaze staking stake id not valid");

        StakeInfo memory stakeInfo = _stakeInfo[globalStakeId];
        require(stakeInfo.status != StakeStatus.COMPLETED, "blazeStaking:blaze stake has already ended");
        require(block.timestamp >= stakeInfo.maturityTimestamp, "blazeStaking:blaze stake not matured");

        //update shares changes
        uint256 shares = stakeInfo.shares;
        _updateSharesStats(__user, shares, stakeInfo.amount, StakeAction.END);

        ++_allCompletedStake;
        _stakeInfo[globalStakeId].status = StakeStatus.COMPLETED;

        __blazeAmount = stakeInfo.amount;

        emit StakeEnded(__user, globalStakeId,__blazeAmount);
    }

    function _updateSharesStats(
        address __user,
        uint256 __shares,
        uint256 __amount,
        StakeAction __action
    ) private returns (uint8 __firstStake) {
        uint256 index = _userLatestIndex[__user];
        uint256 currentUserShares = _userIndexToSharesInfo[__user][index].currentShares;
        if (__action == StakeAction.START) {
            if (index == 0) {
                __firstStake = 1;
            }
            _userIndexToSharesInfo[__user][++index].currentShares = currentUserShares + __shares;
            _totalShares += __shares;
            _totalBlazeTokenStaked += __amount;
        } else {
            _userIndexToSharesInfo[__user][++index].currentShares = currentUserShares - __shares;
            _totalCompletedShares += __shares;
            _totalBlazeTokenStaked -= __amount;
        }
        _userIndexToSharesInfo[__user][index].updationDay = uint32(
            _isGlobalDistributionTriggered == DistributionTriggered.NO
                ? _currentDayInContract
                : _currentDayInContract + 1
        );

        _userLatestIndex[__user] = index;
    }

    function _firstStakeCycleConfig(address __user) private {
        if (_cycleDistributionIndexCount[DAY8] != 0) {
            _userAddressToCycleToLastClaimIndex[__user][DAY8].cycleIndex = uint32(
                _cycleDistributionIndexCount[DAY8] + 1
            );

            _userAddressToCycleToLastClaimIndex[__user][DAY88].cycleIndex = uint32(
                _cycleDistributionIndexCount[DAY88] + 1
            );

            _userAddressToCycleToLastClaimIndex[__user][DAY288].cycleIndex = uint32(
                _cycleDistributionIndexCount[DAY288] + 1
            );
        }
    }

    function _distributeCollectedETH()
        private
        returns (uint256 __lastCycleDsitributionPortion, uint256 __incentiveAmount)
    {
        uint256 undistributedFees = _totalUndistributedCollectedFees;
        require(undistributedFees > 0, "blazeStaking:No fees to distribute");
        _totalUndistributedCollectedFees = 0;

        __incentiveAmount = (undistributedFees * PUBLIC_CALL_INCENTIVE) / PUBLIC_CALL_INCENTIVE_BASE;
        undistributedFees -= __incentiveAmount;

        uint256 feesPortionForCycle8 = (undistributedFees * PERCENT_FOR_CYCLE_8) / PERCENT_BASE;
        uint256 feesPortionForCycle88 = (undistributedFees * PERCENT_FOR_CYCLE_88) / PERCENT_BASE;
        uint256 feesPortionForCycle288 = (undistributedFees * PERCENT_FOR_CYCLE_288) / PERCENT_BASE;
        __lastCycleDsitributionPortion =
            undistributedFees -
            (feesPortionForCycle8 + feesPortionForCycle88 + feesPortionForCycle288);
        _addCycleDistributionPortion(DAY8, feesPortionForCycle8);
        _addCycleDistributionPortion(DAY88, feesPortionForCycle88);
        _addCycleDistributionPortion(DAY288, feesPortionForCycle288);
        emit ETHDistributed(_msgSender(), undistributedFees);
        return (__lastCycleDsitributionPortion, __incentiveAmount);
    }

    function _addCycleDistributionPortion(uint16 __cycle, uint256 __rewards) private {
        _cycleDistributionTotalRewards[__cycle] += __rewards;
    }

    function _distributeFeeRewardsForCycle(
        uint16 __cycle,
        uint32 __currentDay,
        uint256 __currentActiveShares
    ) private returns (DistributionTriggered __completed) {
        if (__currentDay < _nextCycleDistributionDay[__cycle]) {
            return DistributionTriggered.NO;
        }
        _calculateAndSetNextDistributionDay(__cycle);
        uint256 totalRewardsForThisCycle = _cycleDistributionTotalRewards[__cycle];
        if (totalRewardsForThisCycle == 0) {
            return DistributionTriggered.NO;
        }

        _setCycleRewardsPerShare(__cycle, __currentDay, __currentActiveShares, totalRewardsForThisCycle);
        _cycleDistributionTotalRewards[__cycle] = 0;
        emit CycleDistributionTriggered(_msgSender(), __cycle, totalRewardsForThisCycle);
        return DistributionTriggered.YES;
    }

    function _calculateAndSetNextDistributionDay(uint16 __cycle) private {
        uint32 mDay = _nextCycleDistributionDay[__cycle];
        uint32 currentDay = _currentDayInContract;
        if (currentDay >= mDay) {
            uint32 totalCycles = (((currentDay - mDay) / __cycle) + 1);
            _nextCycleDistributionDay[__cycle] += __cycle * totalCycles;
        }
    }

    function _transferETH(address __to, uint256 __amount) private {
        (bool successful, ) = payable(__to).call{value: __amount}("");
        require(successful, "blazeStaking:eth transfer failed");
    }

    function _setCycleRewardsPerShare(
        uint16 __cycle,
        uint32 __currentDay,
        uint256 __currentActiveShares,
        uint256 __totalRewards
    ) private {
        uint32 _currentCycleindex = ++_cycleDistributionIndexCount[__cycle];
        _cycleRewardsPerShare[__cycle][_currentCycleindex].rewardPerShare =
            (__totalRewards * BASE_1e18) /
            __currentActiveShares;
        _cycleRewardsPerShare[__cycle][_currentCycleindex].day = __currentDay;
    }

    function _claimCycleDistribution(uint16 __cycle) private returns (uint256) {
        (uint256 reward, uint256 userClaimSharesIndex, uint32 userClaimCycleIndex) = _calculateUserCycleFeesReward(
            _msgSender(),
            __cycle
        );

        _updateUserCycleClaimIndexes(_msgSender(), __cycle, userClaimCycleIndex, userClaimSharesIndex);

        return reward;
    }

    function _calculateUserCycleFeesReward(
        address __user,
        uint16 __cycle
    ) private view returns (uint256 _rewards, uint256 _userClaimSharesIndex, uint32 _userClaimCycleIndex) {
        uint32 latestCycleIndex = _cycleDistributionIndexCount[__cycle];

        (_userClaimCycleIndex, _userClaimSharesIndex) = getUserLastCycleClaimIndex(__user, __cycle);
        uint256 latestUserSharesIndex = _userLatestIndex[__user];

        for (uint32 j = _userClaimCycleIndex; j <= latestCycleIndex; ++j) {
            (uint256 rewardsPerShare, uint256 dayofDistribution) = getRewardsPerShare(__cycle, j);
            uint256 shares;

            for (uint256 k = _userClaimSharesIndex; k <= latestUserSharesIndex; ++k) {
                if (_userIndexToSharesInfo[__user][k].updationDay <= dayofDistribution)
                    shares = _userIndexToSharesInfo[__user][k].currentShares;
                else break;

                _userClaimSharesIndex = k;
            }

            if (rewardsPerShare != 0 && shares != 0) {
                //reward has 18 decimals scaling, so here divide by 1e18
                _rewards += (shares * rewardsPerShare) / BASE_1e18;
            }

            _userClaimCycleIndex = j + 1;
        }
    }

    function _updateUserCycleClaimIndexes(
        address __user,
        uint16 __cycle,
        uint32 __userClaimCycleIndex,
        uint256 __userClaimSharesIndex
    ) private {
        if (__userClaimCycleIndex != _userAddressToCycleToLastClaimIndex[__user][__cycle].cycleIndex)
            _userAddressToCycleToLastClaimIndex[__user][__cycle].cycleIndex = (__userClaimCycleIndex);

        if (__userClaimSharesIndex != _userAddressToCycleToLastClaimIndex[__user][__cycle].sharesIndex)
            _userAddressToCycleToLastClaimIndex[__user][__cycle].sharesIndex = uint64(__userClaimSharesIndex);
    }

    function _setDiamondHand(address __user, uint256 __amount) private {
        (uint256 currentDay, uint256 currentCycle, ) = IDiamondHand(_lastDistributionAddress)
            .getCurrentDayAndCycleDetails();
        uint256 cycleStartDay = (currentCycle - 1) * 888;
        uint256 cycleEndDay = cycleStartDay + 365;
        bool isEligible = currentDay <= cycleEndDay;
        if (isEligible) {
            _user2888CycleBlazeTokenAmount[__user][currentCycle] += __amount;
        }
    }
}