// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

/* === SYSTEM === */
import "@actions/SwapActions.sol";

/* === OZ === */
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/* === CONST === */
import "@const/Constants.sol";

/* == UTILS == */
import {wmul} from "@utils/Math.sol";
import {Time} from "@utils/Time.sol";

/* == INTERFACES == */
import {IInferno} from "@interfaces/IInferno.sol";

/**
 * @title FluxBuyAndBurn
 * @author Zyntek
 * @notice This contract handles the buying and burning of Flux tokens using Uniswap V3 pools.
 */
contract FluxBuyAndBurn is SwapActions {
    using SafeERC20 for *;

    //=============STRUCTS============//

    /// @notice Struct to represent intervals for burning
    struct Interval {
        uint128 amountAllocated;
        uint128 amountBurned;
    }

    //===========IMMUTABLE===========//

    ///@notice The startTimestamp
    uint32 public immutable startTimeStamp;

    //===========STATE===========//

    /// @notice Timestamp of the last burn call
    uint32 public lastBurnedIntervalStartTimestamp;

    /// @notice Total amount of Flux tokens burnt
    uint256 public totalFluxBurnt;

    /// @notice Mapping from interval number to Interval struct
    mapping(uint32 interval => Interval) public intervals;

    /// @notice  Last burned interval
    uint32 public lastBurnedInterval;

    ///@notice TitanX Swap cap
    uint128 public swapCap;

    /// @notice Last interval number
    uint32 public lastIntervalNumber;

    uint256 public totalInfernoBurned;

    /// @notice Total TitanX tokens distributed
    uint256 public totalTitanXDistributed;

    uint32 public lastSnapshot;
    uint256 public toDistribute;

    //===========EVENTS===========//

    /// @notice Event emitted when tokens are bought and burnt
    event BuyAndBurn(uint256 indexed titanXAmount, uint256 indexed fluxBurnt, address indexed caller);

    //===========ERRORS===========//

    /// @notice Error when the contract has not started yet
    error NotStartedYet();

    /// @notice Error when interval has already been burned
    error IntervalAlreadyBurned();

    error FluxBuyAndBurn__AuctionsMustStartAt5PMUTC();

    error FluxBuyAndBurn__OnlyEOA();

    //========CONSTRUCTOR========//

    /// @notice Constructor initializes the contract
    constructor(
        uint32 _startTimestamp,
        ERC20Burnable _titanX,
        IInferno _inferno,
        address _flux,
        address _owner,
        address _titanXInfernoPool
    ) SwapActions(_flux, _titanX, _inferno, _titanXInfernoPool, _owner) {
        if ((_startTimestamp - 17 hours) % 1 days != 0) {
            revert FluxBuyAndBurn__AuctionsMustStartAt5PMUTC();
        }

        swapCap = type(uint128).max;

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

    function changeSwapCap(uint128 _newSwapCap) external onlySlippageAdminOrOwner {
        swapCap = _newSwapCap;
    }

    /**
     * @notice Swaps TitanX for Flux and burns the Flux tokens
     * @param _deadline The deadline for which the passes should pass
     */
    function swapTitanXForFluxAndBurn(uint32 _deadline) external intervalUpdate {
        if (msg.sender != tx.origin) revert FluxBuyAndBurn__OnlyEOA();

        Interval storage currInterval = intervals[lastIntervalNumber];

        if (currInterval.amountBurned != 0) revert IntervalAlreadyBurned();

        if (currInterval.amountAllocated > swapCap) {
            uint256 difference = currInterval.amountAllocated - swapCap;

            //@note - Add the difference for the next day
            toDistribute += difference;

            currInterval.amountAllocated = swapCap;
        }

        _updateSnapshot();

        uint256 incentive = wmul(currInterval.amountAllocated, INCENTIVE_FEE);

        currInterval.amountBurned = currInterval.amountAllocated;

        uint256 titanXToSwapAndBurn = currInterval.amountAllocated - incentive;

        uint256 titanXToBurnInferno = wmul(titanXToSwapAndBurn, uint256(0.1178e18));

        uint256 fluxAmount;

        {
            uint256 toBurnInferno = _swapTitanXForInferno(titanXToBurnInferno, _deadline);
            totalInfernoBurned += toBurnInferno;

            inferno.burn(toBurnInferno);
        }
        {
            uint256 infernoAmount = _swapTitanXForInferno(titanXToSwapAndBurn - titanXToBurnInferno, _deadline);

            fluxAmount = _swapInfernoForFlux(infernoAmount, _deadline);

            burnFlux();
        }

        titanX.safeTransfer(msg.sender, incentive);

        lastBurnedInterval = lastIntervalNumber;

        emit BuyAndBurn(titanXToSwapAndBurn, fluxAmount, msg.sender);
    }

    /// @notice Burns Inferno tokens held by the contract
    function burnFlux() public {
        uint256 fluxToBurn = flux.balanceOf(address(this));

        totalFluxBurnt = totalFluxBurnt + fluxToBurn;
        flux.burn(fluxToBurn);
    }

    /**
     * @notice Distributes TitanX tokens for burning
     * @param _amount The amount of TitanX tokens
     */
    function distributeTitanXForBurning(uint256 _amount) external notAmount0(_amount) {
        ///@dev - If there are some missed intervals update the accumulated allocation before depositing new titanX

        if (Time.blockTs() > startTimeStamp && Time.blockTs() - lastBurnedIntervalStartTimestamp > INTERVAL_TIME) {
            _intervalUpdate();
        }

        titanX.safeTransferFrom(msg.sender, address(this), _amount);

        _updateSnapshot();

        toDistribute += _amount;
    }

    //==========================//
    //=========GETTERS==========//
    //==========================//

    /**
     * @notice Get the day count for a timestamp
     * @param t The timestamp from which to get the timestamp
     */
    function dayCountByT(uint32 t) public pure returns (uint32) {
        // Adjust the timestamp to the cut-off time (5 PM UTC)
        uint32 adjustedTime = t - 17 hours;

        // Calculate the number of days since Unix epoch
        return adjustedTime / 86400;
    }

    /**
     * @notice Gets the end of the day with a cut-off hour of 5 pm UTC
     * @param t The time from where to get the day end
     */
    function getDayEnd(uint32 t) public pure returns (uint32) {
        // Adjust the timestamp to the cutoff time (5 PM UTC)
        uint32 adjustedTime = t - 17 hours;

        // Calculate the number of days since Unix epoch
        uint32 daysSinceEpoch = adjustedTime / 86400;

        // Calculate the start of the next day at 5 PM UTC
        uint32 nextDayStartAt5PM = (daysSinceEpoch + 1) * 86400 + 17 hours;

        // Return the timestamp for 17:00:00 PM UTC of the given day
        return nextDayStartAt5PM;
    }

    //==========================//
    //=========INTERNAL=========//
    //==========================//

    function _calculateIntervals(uint256 timeElapsedSince)
        internal
        view
        returns (uint32 _lastIntervalNumber, uint128 _totalAmountForInterval, uint16 missedIntervals)
    {
        missedIntervals = _calculateMissedIntervals(timeElapsedSince);

        _lastIntervalNumber = lastIntervalNumber + missedIntervals + 1;

        uint32 currentDay = dayCountByT(uint32(block.timestamp));

        uint32 _lastBurnedIntervalTimestamp = lastBurnedIntervalStartTimestamp;

        uint32 dayOfLastInterval =
            _lastBurnedIntervalTimestamp == 0 ? currentDay : dayCountByT(_lastBurnedIntervalTimestamp);

        uint256 _totalTitanXDistributed = totalTitanXDistributed;

        if (currentDay == dayOfLastInterval) {
            uint128 _amountPerInterval = uint128(_totalTitanXDistributed / INTERVALS_PER_DAY);

            uint128 additionalAmount = _amountPerInterval * missedIntervals;

            _totalAmountForInterval = _amountPerInterval + additionalAmount;
        } else {
            uint32 _lastBurnedIntervalStartTimestamp = _lastBurnedIntervalTimestamp;

            uint32 theEndOfTheDay = getDayEnd(_lastBurnedIntervalStartTimestamp);

            uint32 accumulatedIntervalsForTheDay = (theEndOfTheDay - _lastBurnedIntervalStartTimestamp) / INTERVAL_TIME;

            //@note - Calculate the remaining intervals from the last one's day
            _totalAmountForInterval +=
                uint128(_totalTitanXDistributed / INTERVALS_PER_DAY) * accumulatedIntervalsForTheDay;

            //@note - Calculate the upcoming intervals with the to distribute shares
            uint128 _intervalsForNewDay =
                missedIntervals > accumulatedIntervalsForTheDay ? missedIntervals - accumulatedIntervalsForTheDay : 0;

            _totalAmountForInterval += (_intervalsForNewDay > INTERVALS_PER_DAY)
                ? uint128(toDistribute)
                : uint128(toDistribute / INTERVALS_PER_DAY) * _intervalsForNewDay;
        }

        Interval memory prevInt = intervals[lastIntervalNumber];

        //@note - If the last interval was only updated, but not burned add its allocation to the next one.
        uint128 additional = prevInt.amountBurned == 0 && prevInt.amountAllocated != 0 ? prevInt.amountAllocated : 0;

        if (_totalAmountForInterval + additional > titanX.balanceOf(address(this))) {
            _totalAmountForInterval = uint128(titanX.balanceOf(address(this)));
        } else {
            _totalAmountForInterval += additional;
        }
    }

    function _calculateMissedIntervals(uint256 timeElapsedSince) internal view returns (uint16 _missedIntervals) {
        _missedIntervals = uint16(timeElapsedSince / INTERVAL_TIME);

        if (lastBurnedIntervalStartTimestamp != 0) _missedIntervals--;
    }

    function _updateSnapshot() internal {
        if (Time.blockTs() < startTimeStamp || lastSnapshot + 24 hours > Time.blockTs()) return;

        if (lastSnapshot != 0 && lastSnapshot + 48 hours < Time.blockTs()) {
            // If we have missed entire snapshot of interacting with the contract
            toDistribute = 0;
        }

        totalTitanXDistributed = toDistribute;

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
            uint128 _amountAllocated,
            uint16 _missedIntervals,
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
            uint128 _amountAllocated,
            uint16 _missedIntervals,
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