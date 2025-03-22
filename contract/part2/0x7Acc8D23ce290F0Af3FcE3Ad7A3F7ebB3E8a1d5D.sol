// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "@actions/SwapActions.sol";
import {wmul} from "@utils/Math.sol";
import {Time} from "@utils/Time.sol";
import {WBTCPool} from "@core/pools/WBTCPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WBTCPoolFeeder is SwapActions {
    using SafeERC20 for *;

    //=============STRUCTS============//

    /// @notice Struct to represent intervals for burning
    struct Interval {
        uint256 amountAllocated;
        uint256 amountBurned;
    }

    //===========IMMUTABLE===========//

    ///@notice The startTimestamp
    uint32 public immutable startTimeStamp;
    IERC20 immutable weth;
    WBTCPool immutable wbtcPool;
    IERC20 immutable wbtc;

    //===========STATE===========//

    /// @notice Timestamp of the last burn call
    uint32 public lastBurnedIntervalStartTimestamp;

    /// @notice Last interval number
    uint32 public lastIntervalNumber;

    /// @notice  Last burned interval
    uint32 public lastBurnedInterval;

    /// @notice That last snapshot timestamp
    uint32 public lastSnapshot;

    ///@notice WETH Swap cap
    uint256 public swapCap;

    /// @notice Mapping from interval number to Interval struct
    mapping(uint32 interval => Interval) public intervals;

    /// @notice Total WETH tokens distributed
    uint256 public totalWETHDistributed;

    uint256 public toDistribute;

    //===========EVENTS===========//

    /// @notice Event emitted when tokens are bought and burnt
    event BuyAndBurn(uint256 indexed wbtcAmount, uint256 indexed vyperReceived, address indexed caller);

    //===========ERRORS===========//

    /// @notice Error when the contract has not started yet
    error NotStartedYet();

    /// @notice Error when interval has already been burned
    error IntervalAlreadyBurned();

    error MustStartAt5PMUTC();

    error BuyAndBurn__OnlyEOA();

    //========CONSTRUCTOR========//

    /// @notice Constructor initializes the contract
    constructor(
        uint32 _startTimestamp,
        address _weth,
        address _wbtc,
        address _wbtcPool,
        SwapActionParams memory _params
    ) SwapActions(_params) {
        swapCap = type(uint256).max;

        wbtcPool = WBTCPool(_wbtcPool);
        weth = IERC20(_weth);
        wbtc = IERC20(_wbtc);
        startTimeStamp = _startTimestamp;
    }

    //========MODIFIERS=======//

    /// @notice Updates the contract state for intervals
    modifier intervalUpdate() {
        _intervalUpdate();
        _;
    }

    //==========================//
    //==========PUBLIC==========//
    //==========================//

    function changeSwapCap(uint256 _newSwapCap) external onlySlippageAdminOrOwner {
        swapCap = _newSwapCap == 0 ? type(uint256).max : _newSwapCap;
    }

    /**
     * @notice Swaps WETH for WBTC and sends to WBTC Pools
     * @param _deadline The deadline for which the passes should pass
     */
    function swapWETHToWBTCAndDistribute(uint32 _deadline) external intervalUpdate {
        if (msg.sender != tx.origin) revert BuyAndBurn__OnlyEOA();

        Interval storage currInterval = intervals[lastIntervalNumber];

        if (currInterval.amountBurned != 0) revert IntervalAlreadyBurned();

        _updateSnapshot();
        if (currInterval.amountAllocated > swapCap) {
            uint256 difference = currInterval.amountAllocated - swapCap;

            //@note - Add the difference for the next day
            toDistribute += difference;

            currInterval.amountAllocated = swapCap;
        }

        uint256 incentive = wmul(currInterval.amountAllocated, INCENTIVE_FEE);

        currInterval.amountBurned = currInterval.amountAllocated;

        uint256 wbtcAmount =
            swapExactInput(address(weth), address(wbtc), currInterval.amountAllocated - incentive, 0, 500, _deadline);

        weth.safeTransfer(msg.sender, incentive);

        wbtc.approve(address(wbtcPool), wbtcAmount);
        wbtcPool.distribute(wbtcAmount);

        lastBurnedInterval = lastIntervalNumber;

        emit BuyAndBurn(currInterval.amountAllocated - incentive, wbtcAmount, msg.sender);
    }

    /**
     * @notice Distributes WETH tokens for burning
     * @param _amount The amount of WETH tokens
     */
    function distributeWETH(uint256 _amount) external notAmount0(_amount) {
        ///@dev - If there are some missed intervals update the accumulated allocation before depositing new WETH

        if (Time.blockTs() > startTimeStamp && Time.blockTs() - lastBurnedIntervalStartTimestamp > INTERVAL_TIME) {
            _intervalUpdate();
        }

        weth.safeTransferFrom(msg.sender, address(this), _amount);

        _updateSnapshot();

        toDistribute += _amount;
    }

    //==========================//
    //=========INTERNAL=========//
    //==========================//

    function _calculateIntervals(uint256 timeElapsedSince)
        internal
        view
        returns (uint32 _lastIntervalNumber, uint256 _totalAmountForInterval, uint32 missedIntervals)
    {
        missedIntervals = _calculateMissedIntervals(timeElapsedSince);

        _lastIntervalNumber = lastIntervalNumber + missedIntervals + 1;

        uint32 currentDay = Time.dayCountByT(uint32(block.timestamp));

        uint32 _lastBurnedIntervalTimestamp = lastBurnedIntervalStartTimestamp;

        uint32 dayOfLastInterval =
            _lastBurnedIntervalTimestamp == 0 ? currentDay : Time.dayCountByT(_lastBurnedIntervalTimestamp);

        uint256 _totalWETHDistributed = totalWETHDistributed;

        if (currentDay == dayOfLastInterval) {
            _totalAmountForInterval = (_totalWETHDistributed * (missedIntervals + 1)) / INTERVALS_PER_DAY;
        } else {
            uint32 _lastBurnedIntervalStartTimestamp = _lastBurnedIntervalTimestamp;

            uint32 theEndOfTheDay = Time.getDayEnd(_lastBurnedIntervalStartTimestamp);

            uint32 accumulatedIntervalsForTheDay = (theEndOfTheDay - _lastBurnedIntervalStartTimestamp) / INTERVAL_TIME;

            //@note - Calculate the remaining intervals from the last one's day
            _totalAmountForInterval +=
                uint256(_totalWETHDistributed * accumulatedIntervalsForTheDay) / INTERVALS_PER_DAY;

            //@note - Calculate the upcoming intervals with the to distribute shares
            uint256 _intervalsForNewDay = missedIntervals >= accumulatedIntervalsForTheDay
                ? (missedIntervals - accumulatedIntervalsForTheDay) + 1
                : 0;
            _totalAmountForInterval += (_intervalsForNewDay > INTERVALS_PER_DAY)
                ? uint256(toDistribute)
                : uint256(toDistribute * _intervalsForNewDay) / INTERVALS_PER_DAY;
        }

        Interval memory prevInt = intervals[lastIntervalNumber];

        //@note - If the last interval was only updated, but not burned add its allocation to the next one.
        uint256 additional = prevInt.amountBurned == 0 && prevInt.amountAllocated != 0 ? prevInt.amountAllocated : 0;

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

    function _updateSnapshot() internal {
        if (Time.blockTs() < startTimeStamp || lastSnapshot + 24 hours > Time.blockTs()) return;

        if (lastSnapshot != 0 && lastSnapshot + 48 hours <= Time.blockTs()) {
            // If we have missed entire snapshot of interacting with the contract
            toDistribute = 0;
        }

        totalWETHDistributed = toDistribute;

        toDistribute = 0;

        uint32 timeElapsed = Time.blockTs() - startTimeStamp;

        uint32 snapshots = timeElapsed / 24 hours;

        lastSnapshot = startTimeStamp + (snapshots * 24 hours);
    }

    /// @notice Updates the contract state for intervals
    function _intervalUpdate() private {
        if (Time.blockTs() < startTimeStamp) revert NotStartedYet();

        if (lastSnapshot == 0) _updateSnapshot();

        (
            uint32 _lastInterval,
            uint256 _amountAllocated,
            uint32 _missedIntervals,
            uint32 _lastIntervalStartTimestamp,
            bool updated
        ) = getCurrentInterval();

        if (updated) {
            lastBurnedIntervalStartTimestamp = _lastIntervalStartTimestamp + (uint32(_missedIntervals) * INTERVAL_TIME);
            intervals[_lastInterval] = Interval({amountAllocated: _amountAllocated, amountBurned: 0});
            lastIntervalNumber = _lastInterval;
        }
    }

    function getCurrentInterval()
        public
        view
        returns (
            uint32 _lastInterval,
            uint256 _amountAllocated,
            uint32 _missedIntervals,
            uint32 _lastIntervalStartTimestamp,
            bool updated
        )
    {
        if (startTimeStamp > Time.blockTs()) return (0, 0, 0, 0, false);

        uint32 startPoint = lastBurnedIntervalStartTimestamp == 0 ? startTimeStamp : lastBurnedIntervalStartTimestamp;

        uint32 timeElapseSinceLastBurn = Time.blockTs() - startPoint;

        if (lastBurnedIntervalStartTimestamp == 0 || timeElapseSinceLastBurn > INTERVAL_TIME) {
            (_lastInterval, _amountAllocated, _missedIntervals) = _calculateIntervals(timeElapseSinceLastBurn);
            _lastIntervalStartTimestamp = startPoint;
            _missedIntervals += timeElapseSinceLastBurn > INTERVAL_TIME && lastBurnedIntervalStartTimestamp != 0 ? 1 : 0;
            updated = true;
        }
    }
}