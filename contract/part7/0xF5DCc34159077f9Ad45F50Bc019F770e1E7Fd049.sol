// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@const/Constants.sol";
import {Time} from "@utils/Time.sol";
import {IVyper} from "@interfaces/IVyper.sol";
import {wmul, min} from "@utils/Math.sol";
import {SwapActions, SwapActionParams} from "@actions/SwapActions.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title VyperBoostBuyAndBurn
 */
contract VyperBoostBuyAndBurn is SwapActions {
    using SafeERC20 for *;

    /// @notice Struct to represent intervals for burning
    struct Interval {
        uint128 amountAllocated;
        uint128 amountBurned;
    }

    ///@notice The startTimestamp
    uint32 public immutable startTimeStamp;
    IVyper immutable vyper;
    ERC20Burnable public immutable dragonX;

    address public treasury;

    /// @notice Timestamp of the last burn call
    uint32 public lastBurnedIntervalStartTimestamp;

    /// @notice Last interval number
    uint32 public lastIntervalNumber;

    /// @notice That last snapshot timestamp
    uint32 lastSnapshot;

    /// @notice Total vyper burnt by this contract
    uint256 public totalVyperBurnt;

    /// @notice Maximum amount of DragonX to be swapped and then burned
    uint128 public swapCap;

    /// @notice The last burned interval
    uint256 public lastBurnedInterval;

    /// @notice Mapping from interval number to Interval struct
    mapping(uint32 interval => Interval) public intervals;

    /// @notice Total DragonX tokens distributed
    uint256 public totalDragonXDistributed;

    /// @notice Event emitted when tokens are bought and burnt
    event BuyAndBurn(uint256 indexed dragonXAmount, uint256 indexed vyperAmount, address indexed caller);

    error NotStartedYet();
    error IntervalAlreadyBurned();

    constructor(uint32 startTimestamp, address _dragonX, address _vyper, SwapActionParams memory _params)
        SwapActions(_params)
    {
        startTimeStamp = startTimestamp;

        vyper = IVyper(_vyper);

        dragonX = ERC20Burnable(_dragonX);

        swapCap = type(uint128).max;
    }

    /// @notice Updates the contract state for intervals
    modifier intervalUpdate() {
        _intervalUpdate();
        _;
    }

    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function setSwapCap(uint128 _newCap) external onlySlippageAdminOrOwner {
        swapCap = _newCap == 0 ? type(uint128).max : _newCap;
    }

    function getCurrentInterval()
        public
        view
        returns (
            uint32 _lastInterval,
            uint128 _amountAllocated,
            uint16 _missedIntervals,
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
     * @notice Swaps DragonX for VYPER and disitributes the VYPER tokens
     * @param _deadline The deadline for which the passes should pass
     */
    function swapDragonXToVyperAndBurn(uint32 _deadline) external intervalUpdate notExpired(_deadline) {
        require(msg.sender == tx.origin, OnlyEOA());

        Interval storage currInterval = intervals[lastIntervalNumber];
        require(currInterval.amountBurned == 0, IntervalAlreadyBurned());

        if (currInterval.amountAllocated > swapCap) currInterval.amountAllocated = swapCap;

        currInterval.amountBurned = currInterval.amountAllocated;

        uint256 incentive = wmul(currInterval.amountAllocated, INCENTIVE_FEE);

        uint256 dragonXToSwapAndBurn = currInterval.amountAllocated - incentive;

        uint256 vyperAmount = swapExactInput(address(dragonX), address(vyper), dragonXToSwapAndBurn, 0, _deadline);

        {
            ///@note - Allocations
            vyper.transfer(LIQUIDITY_BONDING_ADDR, wmul(vyperAmount, uint256(0.08e18)));
            vyper.transfer(treasury, wmul(vyperAmount, uint256(0.5e18)));
            burnVyper();
        }

        dragonX.safeTransfer(msg.sender, incentive);

        lastBurnedInterval = lastIntervalNumber;

        emit BuyAndBurn(dragonXToSwapAndBurn, vyperAmount, msg.sender);
    }

    /**
     * @notice Distributes DragonX tokens for burning
     * @param _amount The amount of DragonX tokens
     */
    function distributeDragonXForBurning(uint256 _amount) external notAmount0(_amount) {
        dragonX.safeTransferFrom(msg.sender, address(this), _amount);

        if (Time.blockTs() > startTimeStamp && Time.blockTs() - lastBurnedIntervalStartTimestamp > INTERVAL_TIME) {
            _intervalUpdate();
        }
    }

    function burnVyper() public {
        uint256 vyperToBurn = vyper.balanceOf(address(this));

        totalVyperBurnt = totalVyperBurnt + vyperToBurn;
        vyper.burn(vyperToBurn);
    }

    function getDailyDragonXAllocation() public pure returns (uint256 dailyWadAllocation) {
        return 0.15e18;
    }

    function _calculateIntervals(uint256 timeElapsedSince)
        internal
        view
        returns (
            uint32 _lastIntervalNumber,
            uint128 _totalAmountForInterval,
            uint16 missedIntervals,
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
            uint256 dailyAllocation = wmul(totalDragonXDistributed, getDailyDragonXAllocation());

            uint128 _amountPerInterval = uint128(dailyAllocation / INTERVALS_PER_DAY);

            uint128 additionalAmount = _amountPerInterval * missedIntervals;

            _totalAmountForInterval = _amountPerInterval + additionalAmount;
        } else {
            uint32 _lastBurnedIntervalStartTimestamp = lastBurnedIntervalStartTimestamp;

            uint32 theEndOfTheDay = Time.getDayEnd(_lastBurnedIntervalStartTimestamp);

            uint256 balanceOf = dragonX.balanceOf(address(this));

            while (currentDay >= dayOfLastInterval) {
                uint32 end = uint32(Time.blockTs() < theEndOfTheDay ? Time.blockTs() : theEndOfTheDay - 1);

                uint32 accumulatedIntervalsForTheDay = (end - _lastBurnedIntervalStartTimestamp) / INTERVAL_TIME;

                uint256 diff = balanceOf > _totalAmountForInterval ? balanceOf - _totalAmountForInterval : 0;

                //@note - If the day we are looping over the same day as the last interval's use the cached allocation, otherwise use the current balance
                uint256 forAllocation = Time.dayGap(startTimeStamp, lastBurnedIntervalStartTimestamp)
                    == dayOfLastInterval
                    ? totalDragonXDistributed
                    : balanceOf >= _totalAmountForInterval + wmul(diff, getDailyDragonXAllocation()) ? diff : 0;

                uint256 dailyAllocation = wmul(forAllocation, getDailyDragonXAllocation());

                ///@notice ->  minus INTERVAL_TIME minutes since, at the end of the day the new epoch with new allocation
                _lastBurnedIntervalStartTimestamp = theEndOfTheDay - INTERVAL_TIME;

                ///@notice ->  plus INTERVAL_TIME minutes to flip into the next day
                theEndOfTheDay = Time.getDayEnd(_lastBurnedIntervalStartTimestamp + INTERVAL_TIME);

                if (dayOfLastInterval == currentDay) beforeCurrDay = _totalAmountForInterval;

                _totalAmountForInterval +=
                    uint128((dailyAllocation * accumulatedIntervalsForTheDay) / INTERVALS_PER_DAY);

                dayOfLastInterval++;
            }
        }

        Interval memory prevInt = intervals[lastIntervalNumber];

        //@note - If the last interval was only updated, but not burned add its allocation to the next one.
        uint128 additional = prevInt.amountBurned == 0 ? prevInt.amountAllocated : 0;

        if (_totalAmountForInterval + additional > dragonX.balanceOf(address(this))) {
            _totalAmountForInterval = uint128(dragonX.balanceOf(address(this)));
        } else {
            _totalAmountForInterval += additional;
        }
    }

    function _calculateMissedIntervals(uint256 timeElapsedSince) internal view returns (uint16 _missedIntervals) {
        _missedIntervals = uint16(timeElapsedSince / INTERVAL_TIME);

        if (lastBurnedIntervalStartTimestamp != 0) _missedIntervals--;
    }

    function _updateSnapshot(uint256 deltaAmount) internal {
        if (Time.blockTs() < startTimeStamp || lastSnapshot + 24 hours > Time.blockTs()) return;

        uint32 timeElapsed = Time.blockTs() - startTimeStamp;

        uint32 snapshots = timeElapsed / 24 hours;

        uint256 balance = dragonX.balanceOf(address(this));

        totalDragonXDistributed = deltaAmount > balance ? 0 : balance - deltaAmount;
        lastSnapshot = startTimeStamp + (snapshots * 24 hours);
    }

    /// @notice Updates the contract state for intervals
    function _intervalUpdate() private {
        require(Time.blockTs() >= startTimeStamp, NotStartedYet());

        if (lastSnapshot == 0) _updateSnapshot(0);

        (
            uint32 _lastInterval,
            uint128 _amountAllocated,
            uint16 _missedIntervals,
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