// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

/* === UNIV3 === */
import {IUniswapV3Pool} from "../lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "../lib/v3-periphery/contracts/libraries/TransferHelper.sol";
import {INonfungiblePositionManager} from "../lib/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {TickMath} from "../lib/v3-core/contracts/libraries/TickMath.sol";
import {OracleLibrary} from "./library/OracleLibrary.sol";
import {ISwapRouter} from "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/* === OZ === */
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Ownable2Step, Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/* === CONST === */
import "./const/BuyAndBurnConst.sol";

/* === SYSTEM === */
import {Morpheus} from "./Morpheus.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title MorpheusBuyAndBurn
 * @author 0xkmmm
 * @notice This contract handles the buying and burning of Morpheus tokens using Uniswap V2 and V3 pools.
 */
contract MorpheusBuyAndBurn is ReentrancyGuard, Ownable2Step {
    using TransferHelper for IERC20;
    using Math for uint256;
    using Strings for uint256;
    /* == STRUCTS == */

    /// @notice Struct to represent intervals for burning
    struct Interval {
        uint128 amountAllocated;
        uint128 amountBurned;
    }

    struct LP {
        uint248 tokenId;
        bool isDragonxToken0;
    }

    /* == CONTSTANTS == */

    /// @notice Uniswap V3 position manager
    INonfungiblePositionManager public constant POSITION_MANAGER =
        INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER);

    /* == IMMUTABLE == */

    /// @notice Uniswap V3 pool for Dragonx/TitanX tokens
    IUniswapV3Pool private immutable dragonXTitanXPool;

    /// @notice DragonX token contract
    ERC20Burnable private immutable dragonX;

    /// @notice TitanX token contract
    IERC20 private immutable titanX;

    /// @notice Morpheus token contract
    Morpheus public immutable morpheusToken;

    ///@notice The startTimestamp
    uint32 public immutable startTimeStamp;

    /* == STATE == */

    ///@notice The liquidity position after creating the Morpheus/Dragonx Pool
    LP lp;

    /// @notice Indicates if liquidity has been added to the pool
    bool public liquidityAdded;

    /// @notice Timestamp of the last burn call
    uint32 public lastBurnedIntervalStartTimestamp;

    /// @notice Total amount of Morpheus tokens burnt
    uint256 public totalMorpheusBurnt;

    /// @notice Total amount of Dragonx tokens burnt
    uint256 public totalDragonxBurnt;

    /// @notice Mapping from interval number to Interval struct
    mapping(uint32 interval => Interval) public intervals;

    /// @notice Last interval number
    uint32 public lastIntervalNumber;

    /// @notice Total TitanX tokens distributed
    uint256 public totalTitanXForBurn;

    ///@notice The slippage for the second swap in the buy and burn in %
    uint8 dragonxToMorpheusSlippage = 90;
    uint8 titanxToDragonxSlippage = 90;

    ///@notice The daily percentage of titanX used in buy and burn
    uint256 public DAILY_ALLOCATION = 100;

    /* == EVENTS == */

    /// @notice Event emitted when tokens are bought and burnt
    event BuyAndBurn(
        uint256 indexed titanXAmount,
        uint256 indexed morpheusBurnt,
        uint256 dragonXBurnAmount,
        address indexed caller
    );

    /* == ERRORS == */

    /// @notice Error when the contract has not started yet
    error NotStartedYet();

    /// @notice Error when minter is not msg.msg.sender
    error OnlyMinting();

    /// @notice Error when some user input is considered invalid
    error InvalidInput();

    /// @notice Error when we try to create liquidity pool with less than the intial amount
    error NotEnoughTitanXForLiquidity();

    /// @notice Error when liquidity has already been added
    error LiquidityAlreadyAdded();

    /// @notice Error when interval has already been burned
    error IntervalAlreadyBurned();

    /* == CONSTRUCTOR == */

    /// @notice Constructor initializes the contract
    /// @notice Constructor is payable to save gas
    constructor(
        uint32 startTimestamp,
        address _dragonXTitanXPool,
        address _titanX,
        address _dragonX,
        address _owner
    ) payable Ownable(_owner) {
        startTimeStamp = startTimestamp;
        titanX = IERC20(_titanX);
        morpheusToken = Morpheus(msg.sender);
        dragonX = ERC20Burnable(_dragonX);
        dragonXTitanXPool = IUniswapV3Pool(_dragonXTitanXPool);
    }

    /* === MODIFIERS === */

    /// @notice Updates the contract state for intervals
    modifier intervalUpdate() {
        _intervalUpdate();
        _;
    }

    /* == PUBLIC/EXTERNAL == */

    /**
     * @notice Swaps TitanX for Morpheus and burns the Morpheus tokens
     * @param _deadline The deadline for which the passes should pass
     */
    function swapTitanXForDragonXAndMorpheusAndBurn(
        uint32 _deadline
    ) external nonReentrant intervalUpdate {
        if (!liquidityAdded) revert NotStartedYet();
        Interval storage currInterval = intervals[lastIntervalNumber];
        if (currInterval.amountBurned != 0) revert IntervalAlreadyBurned();

        currInterval.amountBurned = currInterval.amountAllocated;

        uint256 incentive = (currInterval.amountAllocated * INCENTIVE_FEE) /
            BPS_DENOM;

        uint256 titanXToSwapAndBurn = currInterval.amountAllocated - incentive;

        uint256 dragonxAmount = _swapTitanxForDragonx(
            titanXToSwapAndBurn,
            _deadline
        );
        uint256 dragonxBurnAmount = dragonxAmount.mulDiv(
            DRAGON_X_BURN_BPS,
            BPS_DENOM,
            Math.Rounding.Ceil
        );
        uint256 morpheusAmount = _swapDragonxForMorpheus(
            dragonxAmount - dragonxBurnAmount,
            _deadline
        );

        burnMorpheus();

        TransferHelper.safeTransfer(address(dragonX), DRAGONX_BURN_ADDRESS, dragonxBurnAmount);
        TransferHelper.safeTransfer(address(titanX), msg.sender, incentive);

        totalDragonxBurnt += dragonxBurnAmount;
        totalTitanXForBurn = titanX.balanceOf(address(this));

        emit BuyAndBurn(titanXToSwapAndBurn, morpheusAmount, dragonxBurnAmount, msg.sender);
    }

    /**
     * @notice Creates a Uniswap V3 pool and adds liquidity
     * @param _deadline The deadline for the liquidity addition
     */
    function addLiquidityToMorpheusDragonxPool(
        uint32 _deadline
    ) external {
        if (liquidityAdded) revert LiquidityAlreadyAdded();
        if (titanX.balanceOf(address(this)) < INITIAL_TITAN_X_FOR_LIQ)
            revert NotEnoughTitanXForLiquidity();
        if (msg.sender != address(morpheusToken.minting()))
            revert OnlyMinting();

        liquidityAdded = true;

        uint256 dragonxReceived = _swapTitanxForDragonx(
            INITIAL_TITAN_X_FOR_LIQ,
            _deadline
        );

        morpheusToken.createDragonXMorpheusPool(DRAGON_X_ADDRESS, UNISWAP_V3_DRAGON_X_TITAN_X_POOL, dragonxReceived);

        morpheusToken.mintTokensForLP();

        (
            uint256 amount0,
            uint256 amount1,
            uint256 amount0Min,
            uint256 amount1Min,
            address token0,
            address token1
        ) = _sortAmounts(dragonxReceived, INITIAL_LP_MINT);

        TransferHelper.safeApprove(token0, address(POSITION_MANAGER), amount0);
        TransferHelper.safeApprove(token1, address(POSITION_MANAGER), amount1);

        // wake-disable-next-line
        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: POOL_FEE,
                tickLower: (TickMath.MIN_TICK / TICK_SPACING) * TICK_SPACING,
                tickUpper: (TickMath.MAX_TICK / TICK_SPACING) * TICK_SPACING,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: address(this),
                deadline: _deadline
            });

        // wake-disable-next-line
        (uint256 tokenId, , , ) = POSITION_MANAGER.mint(params);

        lp = LP({
            tokenId: uint248(tokenId),
            isDragonxToken0: token0 == address(dragonX)
        });

        totalTitanXForBurn = titanX.balanceOf(address(this));
    }

    /**
     * @notice Allows owner to update daily allocation
     * @param _newDailyAllocation The new daily allocation
     */
    function setDailyAllocation(uint256 _newDailyAllocation) public onlyOwner {
        DAILY_ALLOCATION = _newDailyAllocation;
        require(DAILY_ALLOCATION >= 100 && DAILY_ALLOCATION <= 1000, "Min 1 percent, max 10 percent.");
        _intervalUpdate();
    }

    /// @notice Burns Morpheus tokens held by the contract
    function burnMorpheus() public {
        uint256 morpheusToBurn = morpheusToken.balanceOf(address(this));

        totalMorpheusBurnt = totalMorpheusBurnt + morpheusToBurn;
        morpheusToken.burn(morpheusToBurn);
    }

    function setSlippageForDragonxToMorpheus(
        uint8 _newSlippage
    ) external onlyOwner {
        if (_newSlippage > 100 || _newSlippage < 2) revert InvalidInput();

        dragonxToMorpheusSlippage = _newSlippage;
    }

    function setSlippageForTitanxToDragonx(
        uint8 _newSlippage
    ) external onlyOwner {
        if (_newSlippage > 100 || _newSlippage < 2) revert InvalidInput();

        titanxToDragonxSlippage = _newSlippage;
    }

    /**
     * @notice Distributes TitanX tokens for burning
     * @param _amount The amount of TitanX tokens
     */
    function distributeTitanXForBurning(uint256 _amount) external {
        if (_amount == 0) revert InvalidInput();
        if (msg.sender != address(morpheusToken.minting()))
            revert OnlyMinting();

        ///@dev - If there are some missed intervals update the accumulated allocation before depositing new titanX
        if (
            block.timestamp > startTimeStamp &&
            block.timestamp - lastBurnedIntervalStartTimestamp > INTERVAL_TIME
        ) {
            _intervalUpdate();
        }

        TransferHelper.safeTransferFrom(
            address(titanX),
            msg.sender,
            address(this),
            _amount
        );

        totalTitanXForBurn = titanX.balanceOf(address(this));
    }

    /**
     * @notice Burns the fees collected from the Uniswap V3 position
     *
     * @return amount0 The amount of token0 collected
     * @return amount1 The amount of token1 collected
     */
    function burnFees() external returns (uint256 amount0, uint256 amount1) {
        LP memory _lp = lp;

        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: _lp.tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = POSITION_MANAGER.collect(params);

        (uint256 dragonxAmount, ) = _lp.isDragonxToken0
            ? (amount0, amount1)
            : (amount1, amount0);

        dragonX.transfer(GENESIS_WALLET, dragonxAmount);
        burnMorpheus();
    }

    /* == PUBLIC-GETTERS == */

    ///@notice Gets the current week day (0=Sunday, 1=Monday etc etc) wtih a cut-off hour at 2pm UTC
    function currWeekDay() public view returns (uint8 weekDay) {
        weekDay = weekDayByT(uint32(block.timestamp));
    }

    /**
     * @notice Gets the current week day (0=Sunday, 1=Monday etc etc) wtih a cut-off hour at 2pm UTC
     * @param t The timestamp from which to get the weekDay
     */
    function weekDayByT(uint32 t) public pure returns (uint8) {
        return uint8((((t - 14 hours) / 86400) + 4) % 7);
    }

    /**
     * @notice Get the day count for a timestamp
     * @param t The timestamp from which to get the timestamp
     */
    function dayCountByT(uint32 t) public pure returns (uint32) {
        // Adjust the timestamp to the cut-off time (2 PM UTC)
        uint32 adjustedTime = t - 14 hours;

        // Calculate the number of days since Unix epoch
        return adjustedTime / 86400;
    }

    /**
     * @notice Gets the end of the day with a cut-off hour of 2 pm UTC
     * @param t The time from where to get the day end
     */
    function getDayEnd(uint32 t) public pure returns (uint32) {
        // Adjust the timestamp to the cutoff time (2 PM UTC)
        uint32 adjustedTime = t - 14 hours;

        // Calculate the number of days since Unix epoch
        uint32 daysSinceEpoch = adjustedTime / 86400;

        // Calculate the start of the next day at 2 PM UTC
        uint32 nextDayStartAt2PM = (daysSinceEpoch + 1) * 86400 + 14 hours;

        // Return the timestamp for 14:00:00 PM UTC of the given day
        return nextDayStartAt2PM;
    }

    /**
     * @notice Gets the daily TitanX allocation
     * @return dailyBPSAllocation The daily allocation in basis points
     */
    function getDailyTitanXAllocation() public view returns (uint32 dailyBPSAllocation) {
        dailyBPSAllocation = uint32(DAILY_ALLOCATION);
    }
    
    /**
     * @notice Gets a quote for Morpheus tokens in exchange for Dragonx tokens
     * @param baseAmount The amount of Dragonx tokens
     * @return quote The amount of Morpheus tokens received
     */
    function getDragonxQuoteForTitanX(
        uint256 baseAmount
    ) public view returns (uint256 quote) {
        address poolAddress = UNISWAP_V3_DRAGON_X_TITAN_X_POOL;
        uint32 secondsAgo = 15 * 60;
        uint32 oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(
            poolAddress
        );

        if (oldestObservation < secondsAgo) secondsAgo = oldestObservation;

        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(
            poolAddress,
            secondsAgo
        );

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);

        quote = OracleLibrary.getQuoteForSqrtRatioX96(
            sqrtPriceX96,
            baseAmount,
            address(titanX),
            address(dragonX)
        );
    }

    /**
     * @notice Gets a quote for Morpheus tokens in exchange for Dragonx tokens
     * @param baseAmount The amount of Dragonx tokens
     * @return quote The amount of Morpheus tokens received
     */
    function getMorpheusQuoteForDragonx(
        uint256 baseAmount
    ) public view returns (uint256 quote) {
        address poolAddress = morpheusToken.dragonXMorpheusPool();
        uint32 secondsAgo = 15 * 60;
        uint32 oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(
            poolAddress
        );

        if (oldestObservation < secondsAgo) secondsAgo = oldestObservation;

        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(
            poolAddress,
            secondsAgo
        );

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);

        quote = OracleLibrary.getQuoteForSqrtRatioX96(
            sqrtPriceX96,
            baseAmount,
            address(dragonX),
            address(morpheusToken)
        );
    }

    /* == INTERNAL/PRIVATE == */

    /**
     * @notice Swaps Dragonx tokens for Morpheus tokens
     * @param amountTitanx The amount of Dragonx tokens
     * @param _deadline The deadline for when the swap must be executed
     * @return _dragonXAmount The amount of Morpheus tokens received
     */
    function _swapTitanxForDragonx(
        uint256 amountTitanx,
        uint256 _deadline
    ) private returns (uint256 _dragonXAmount) {
        // wake-disable-next-line
        titanX.approve(UNISWAP_V3_ROUTER, amountTitanx);
        // Setup the swap-path, swapp
        bytes memory path = abi.encodePacked(
            address(titanX),
            POOL_FEE,
            address(dragonX)
        );

        uint256 expectedDragonxAmount = getDragonxQuoteForTitanX(
            amountTitanx
        );

        // Adjust for slippage (applied uniformly across both hops)
        uint256 adjustedDragonxAmount = (expectedDragonxAmount *
            (100 - titanxToDragonxSlippage)) / 100;

        // Swap parameters
        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: _deadline,
                amountIn: amountTitanx,
                amountOutMinimum: adjustedDragonxAmount
            });

        // Execute the swap
        return ISwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
    }

    /**
     * @notice Swaps Dragonx tokens for Morpheus tokens
     * @param amountDragonx The amount of Dragonx tokens
     * @param _deadline The deadline for when the swap must be executed
     * @return _morpheusAmount The amount of Morpheus tokens received
     */
    function _swapDragonxForMorpheus(
        uint256 amountDragonx,
        uint256 _deadline
    ) private returns (uint256 _morpheusAmount) {
        // wake-disable-next-line
        dragonX.approve(UNISWAP_V3_ROUTER, amountDragonx);
        // Setup the swap-path, swapp
        bytes memory path = abi.encodePacked(
            address(dragonX),
            POOL_FEE,
            address(morpheusToken)
        );

        uint256 expectedMorpheusAmount = getMorpheusQuoteForDragonx(
            amountDragonx
        );

        // Adjust for slippage (applied uniformly across both hops)
        uint256 adjustedMorpheusAmount = (expectedMorpheusAmount *
            (100 - dragonxToMorpheusSlippage)) / 100;

        // Swap parameters
        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: _deadline,
                amountIn: amountDragonx,
                amountOutMinimum: adjustedMorpheusAmount
            });

        // Execute the swap
        return ISwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
    }

    function _calculateIntervals(
        uint256 timeElapsedSince
    )
        internal
        view
        returns (
            uint32 _lastIntervalNumber,
            uint128 _totalAmountForInterval,
            uint16 missedIntervals
        )
    {
        missedIntervals = _calculateMissedIntervals(timeElapsedSince);

        _lastIntervalNumber = lastIntervalNumber + missedIntervals + 1;

        uint256 dailyAllcation = (totalTitanXForBurn *
                DAILY_ALLOCATION) / BPS_DENOM;

        uint128 _amountPerInterval = uint128(
                dailyAllcation / INTERVALS_PER_DAY
            );

        uint128 additionalAmount = _amountPerInterval * missedIntervals;

        _totalAmountForInterval = _amountPerInterval + additionalAmount;

        if (_totalAmountForInterval > totalTitanXForBurn) {
            _totalAmountForInterval = uint128(totalTitanXForBurn);
        }
    }

    function _calculateMissedIntervals(
        uint256 timeElapsedSince
    ) internal view returns (uint16 _missedIntervals) {
        if (lastBurnedIntervalStartTimestamp == 0) {
            /// @dev - If there is no burned interval, we do no deduct 1 since no intervals is yet claimed
            _missedIntervals = timeElapsedSince <= INTERVAL_TIME
                ? 0
                : uint16(timeElapsedSince / INTERVAL_TIME);
        } else {
            /// @dev - If we already have, a burned interval we remove 1, since the previus interval is already burned
            _missedIntervals = timeElapsedSince <= INTERVAL_TIME
                ? 0
                : uint16(timeElapsedSince / INTERVAL_TIME) - 1;
        }
    }

    /// @notice Updates the contract state for intervals
    function _intervalUpdate() private {
        if (block.timestamp < startTimeStamp) revert NotStartedYet();

        uint32 timeElapseSinceLastBurn = uint32(
            lastBurnedIntervalStartTimestamp == 0
                ? block.timestamp - startTimeStamp
                : block.timestamp - lastBurnedIntervalStartTimestamp
        );

        uint32 _lastInterval;
        uint128 _amountAllocated;
        uint16 _missedIntervals;
        uint32 _lastIntervalStartTimestamp;

        bool updated;

        ///@dev -> If this is the first time burning, Calculate if any intervals were missed and update update the allocated amount
        if (lastBurnedIntervalStartTimestamp == 0) {
            (
                _lastInterval,
                _amountAllocated,
                _missedIntervals
            ) = _calculateIntervals(timeElapseSinceLastBurn);

            _lastIntervalStartTimestamp = startTimeStamp;

            updated = true;

            ///@dev -> If the lastBurnTimeExceeds, calculate how much intervals were skipped (if any) and calculate the amount accordingly
        } else if (timeElapseSinceLastBurn > INTERVAL_TIME) {
            (
                _lastInterval,
                _amountAllocated,
                _missedIntervals
            ) = _calculateIntervals(timeElapseSinceLastBurn);

            _lastIntervalStartTimestamp = lastBurnedIntervalStartTimestamp;

            updated = true;

            _missedIntervals++;
        }

        if (updated) {
            lastBurnedIntervalStartTimestamp =
                _lastIntervalStartTimestamp +
                (_missedIntervals * INTERVAL_TIME);
            intervals[_lastInterval] = Interval({
                amountAllocated: _amountAllocated,
                amountBurned: 0
            });
            lastIntervalNumber = _lastInterval;
        }
    }

    /**
     * @notice Creates a Uniswap V3 pool and returns the parameters
     * @return amount0 The amount of token0
     * @return amount1 The amount of token1
     * @return amount0Min Minimum amount of token0
     * @return amount1Min Minimum amount of token1
     * @return token0 Address of token0
     * @return token1 Address of token1
     */
    function _sortAmounts(
        uint256 dragonxAmount,
        uint256 morpheusAmount
    )
        internal
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 amount0Min,
            uint256 amount1Min,
            address token0,
            address token1
        )
    {
        address _dragonx = address(dragonX);
        address _morpheus = address(morpheusToken);

        (token0, token1) = _dragonx < _morpheus
            ? (_dragonx, _morpheus)
            : (_morpheus, _dragonx);
        (amount0, amount1) = token0 == _dragonx
            ? (dragonxAmount, morpheusAmount)
            : (morpheusAmount, dragonxAmount);
        (amount0Min, amount1Min) = (
            _minus10Perc(amount0),
            _minus10Perc(amount1)
        );
    }

    ///@notice Helper to remove 10% of an amount
    function _minus10Perc(
        uint256 _amount
    ) internal pure returns (uint256 amount) {
        amount = (_amount * 9000) / BPS_DENOM;
    }
}