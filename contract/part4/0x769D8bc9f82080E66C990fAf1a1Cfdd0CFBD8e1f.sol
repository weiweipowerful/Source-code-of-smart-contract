// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@const/Constants.sol";
import {Shaolin} from "@core/Shaolin.sol";
import {Time} from "@utils/Time.sol";
import {wmul, min} from "@utils/Math.sol";
import {IWETH9} from "@interfaces/IWETH9.sol";
import {SwapActions, SwapActionParams} from "@actions/SwapActions.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title ShaolinBuyAndBurn
 * @notice This contract handles the buying and burning of SHAO tokens using Uniswap V3 pools.
 */
contract ShaolinBuyAndBurn is SwapActions {
    using SafeERC20 for *;

    /// @notice Struct to represent intervals for burning
    struct Interval {
        uint256 amountAllocated;
        uint256 amountBurned;
    }

    ///@notice The startTimestamp
    uint32 public immutable startTimeStamp;

    IWETH9 public immutable weth;

    Shaolin public immutable shaolin;

    /// @notice Timestamp of the last burn call
    uint32 public lastBurnedIntervalStartTimestamp;

    /// @notice Total amount of SHAO tokens burnt
    uint256 public totalShaolinBurnt;

    /// @notice The last burned interval
    uint256 public lastBurnedInterval;

    /// @notice Maximum amount of weth to be swapped and then burned
    uint256 public swapCap;

    /// @notice Mapping from interval number to Interval struct
    mapping(uint32 interval => Interval) public intervals;

    /// @notice Last interval number
    uint32 public lastIntervalNumber;

    /// @notice Total WETH tokens distributed
    uint256 public totalWETHDistributed;

    /// @notice That last snapshot timestamp
    uint32 lastSnapshot;

    /// @notice Event emitted when tokens are bought and burnt
    event BuyAndBurn(uint256 indexed wethAmount, uint256 indexed shaolinBurnt, address indexed caller);

    error NotStartedYet();
    error IntervalAlreadyBurned();
    error OnlyEOA();

    constructor(uint32 startTimestamp, address _weth, address _shaolin, SwapActionParams memory _params)
        SwapActions(_params)
    {
        startTimeStamp = startTimestamp;

        shaolin = Shaolin(_shaolin);
        weth = IWETH9(_weth);

        swapCap = type(uint256).max;
    }

    /// @notice Updates the contract state for intervals
    modifier intervalUpdate() {
        _intervalUpdate();
        _;
    }

    function setSwapCap(uint256 _newCap) external onlySlippageAdminOrOwner {
        swapCap = _newCap == 0 ? type(uint256).max : _newCap;
    }

    function getCurrentInterval()
        public
        view
        returns (
            uint32 _lastInterval,
            uint256 _amountAllocated,
            uint32 _missedIntervals,
            uint32 _lastIntervalStartTimestamp,
            uint256 beforeCurrday,
            bool updated
        )
    {
        uint32 startPoint = lastBurnedIntervalStartTimestamp == 0 ? startTimeStamp : lastBurnedIntervalStartTimestamp;
        uint32 timeElapseSinceLastBurn = Time.blockTs() - startPoint;

        if (lastBurnedIntervalStartTimestamp == 0 || timeElapseSinceLastBurn > INTERVAL_TIME) {
            (_lastInterval, _amountAllocated, _missedIntervals, beforeCurrday) =
                _calculateIntervals(timeElapseSinceLastBurn);

            _lastIntervalStartTimestamp = startPoint;
            _missedIntervals += timeElapseSinceLastBurn > INTERVAL_TIME && lastBurnedIntervalStartTimestamp != 0 ? 1 : 0;
            updated = true;
        }
    }

    /**
     * @notice Swaps WETH for SHAO and burns the SHAO tokens
     * @param _deadline The deadline for which the passes should pass
     */
    function swapWETHForShaolinAndBurn(uint32 _deadline) external intervalUpdate notExpired(_deadline) {
        require(msg.sender == tx.origin, OnlyEOA());

        Interval storage currInterval = intervals[lastIntervalNumber];
        require(currInterval.amountBurned == 0, IntervalAlreadyBurned());

        if (currInterval.amountAllocated > swapCap) currInterval.amountAllocated = swapCap;

        currInterval.amountBurned = currInterval.amountAllocated;

        uint256 incentive = wmul(currInterval.amountAllocated, INCENTIVE_FEE);

        uint256 wethToSwapAndBurn = currInterval.amountAllocated - incentive;

        uint256 shaolinAmount =
            swapExactInput(address(weth), address(shaolin), wethToSwapAndBurn, 0, POOL_FEE, _deadline);

        burnShaolin();

        weth.safeTransfer(msg.sender, incentive);

        lastBurnedInterval = lastIntervalNumber;

        emit BuyAndBurn(wethToSwapAndBurn, shaolinAmount, msg.sender);
    }

    /// @notice Burns SHAO tokens held by the contract
    function burnShaolin() public {
        uint256 shaolinToBurn = shaolin.balanceOf(address(this));

        totalShaolinBurnt = totalShaolinBurnt + shaolinToBurn;
        shaolin.burn(shaolinToBurn);
    }

    /**
     * @notice Distributes WETH tokens for burning
     * @param _amount The amount of WETH tokens
     */
    function distributeWETHForBurning(uint256 _amount) external notAmount0(_amount) {
        ///@dev - If there are some missed intervals update the accumulated allocation before depositing new weth

        weth.safeTransferFrom(msg.sender, address(this), _amount);

        if (Time.blockTs() > startTimeStamp && Time.blockTs() - lastBurnedIntervalStartTimestamp > INTERVAL_TIME) {
            _intervalUpdate();
        }
    }

    function getDailyWETHAllocation(uint32 t) public pure returns (uint256 dailyWadAllocation) {
        uint8 weekDay = Time.weekDayByT(t);

        dailyWadAllocation = weekDay == 0 || weekDay == 6 ? 0.08e18 : 0.04e18;
    }

    function _calculateIntervals(uint256 timeElapsedSince)
        internal
        view
        returns (
            uint32 _lastIntervalNumber,
            uint256 _totalAmountForInterval,
            uint32 missedIntervals,
            uint256 beforeCurrDay
        )
    {
        missedIntervals = _calculateMissedIntervals(timeElapsedSince);

        _lastIntervalNumber = lastIntervalNumber + missedIntervals + 1;

        uint32 currentDay = Time.dayGap(startTimeStamp, uint32(block.timestamp));

        uint32 dayOfLastInterval = lastBurnedIntervalStartTimestamp == 0
            ? currentDay
            : Time.dayGap(startTimeStamp, lastBurnedIntervalStartTimestamp);

        if (currentDay == dayOfLastInterval) {
            uint256 dailyAllocation = wmul(totalWETHDistributed, getDailyWETHAllocation(Time.blockTs()));

            _totalAmountForInterval = (dailyAllocation * (missedIntervals + 1)) / INTERVALS_PER_DAY;
        } else {
            uint32 _lastBurnedIntervalStartTimestamp = lastBurnedIntervalStartTimestamp;

            uint32 theEndOfTheDay = Time.getDayEnd(_lastBurnedIntervalStartTimestamp);

            uint256 balanceOf = weth.balanceOf(address(this));

            while (currentDay >= dayOfLastInterval) {
                uint32 end = uint32(Time.blockTs() < theEndOfTheDay ? Time.blockTs() : theEndOfTheDay - 1);

                uint32 accumulatedIntervalsForTheDay = (end - _lastBurnedIntervalStartTimestamp) / INTERVAL_TIME;

                uint256 diff = balanceOf > _totalAmountForInterval ? balanceOf - _totalAmountForInterval : 0;

                //@note - If the day we are looping over the same day as the last interval's use the cached allocation, otherwise use the current balance
                uint256 forAllocation = Time.dayGap(startTimeStamp, lastBurnedIntervalStartTimestamp)
                    == dayOfLastInterval
                    ? totalWETHDistributed
                    : balanceOf >= _totalAmountForInterval + wmul(diff, getDailyWETHAllocation(end)) ? diff : 0;

                uint256 dailyAllocation = wmul(forAllocation, getDailyWETHAllocation(end));

                ///@notice ->  minus INTERVAL_TIME minutes since, at the end of the day the new epoch with new allocation
                _lastBurnedIntervalStartTimestamp = theEndOfTheDay - INTERVAL_TIME;

                ///@notice ->  plus INTERVAL_TIME minutes to flip into the next day
                theEndOfTheDay = Time.getDayEnd(_lastBurnedIntervalStartTimestamp + INTERVAL_TIME);

                if (dayOfLastInterval == currentDay) beforeCurrDay = _totalAmountForInterval;

                _totalAmountForInterval +=
                    uint256((dailyAllocation * accumulatedIntervalsForTheDay) / INTERVALS_PER_DAY);

                dayOfLastInterval++;
            }
        }

        Interval memory prevInt = intervals[lastIntervalNumber];

        //@note - If the last interval was only updated, but not burned add its allocation to the next one.
        uint256 additional = prevInt.amountBurned == 0 ? prevInt.amountAllocated : 0;

        if (_totalAmountForInterval + additional > weth.balanceOf(address(this))) {
            _totalAmountForInterval = uint256(weth.balanceOf(address(this)));
        } else {
            _totalAmountForInterval += additional;
        }
    }

    function _calculateMissedIntervals(uint256 timeElapsedSince) internal view returns (uint32 _missedIntervals) {
        _missedIntervals = uint32(timeElapsedSince / INTERVAL_TIME);

        if (lastBurnedIntervalStartTimestamp != 0) _missedIntervals--;
    }

    function _updateSnapshot(uint256 deltaAmount) internal {
        if (Time.blockTs() < startTimeStamp || lastSnapshot + 24 hours > Time.blockTs()) return;

        uint32 timeElapsed = Time.blockTs() - startTimeStamp;

        uint32 snapshots = timeElapsed / 24 hours;

        uint256 balance = weth.balanceOf(address(this));

        totalWETHDistributed = deltaAmount > balance ? 0 : balance - deltaAmount;
        lastSnapshot = startTimeStamp + (snapshots * 24 hours);
    }

    /// @notice Updates the contract state for intervals
    function _intervalUpdate() private {
        require(Time.blockTs() >= startTimeStamp, NotStartedYet());

        if (lastSnapshot == 0) _updateSnapshot(0);

        (
            uint32 _lastInterval,
            uint256 _amountAllocated,
            uint32 _missedIntervals,
            uint32 _lastIntervalStartTimestamp,
            uint256 beforeCurrentDay,
            bool updated
        ) = getCurrentInterval();

        _updateSnapshot(beforeCurrentDay);

        if (updated) {
            lastBurnedIntervalStartTimestamp = _lastIntervalStartTimestamp + (uint32(_missedIntervals) * INTERVAL_TIME);
            intervals[_lastInterval] = Interval({amountAllocated: _amountAllocated, amountBurned: 0});
            lastIntervalNumber = _lastInterval;
        }
    }
}