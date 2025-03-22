// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import '@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

import '@openzeppelin/contracts/access/Ownable2Step.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '@marginly/router/contracts/interfaces/IMarginlyRouter.sol';

import './interfaces/IMarginlyPool.sol';
import './interfaces/IMarginlyFactory.sol';
import './interfaces/IWETH9.sol';
import './interfaces/IPriceOracle.sol';
import './dataTypes/MarginlyParams.sol';
import './dataTypes/Position.sol';
import './dataTypes/Mode.sol';
import './libraries/MaxBinaryHeapLib.sol';
import './libraries/OracleLib.sol';
import './libraries/FP48.sol';
import './libraries/FP96.sol';
import './libraries/Errors.sol';
import './dataTypes/Call.sol';

contract MarginlyPool is IMarginlyPool {
  using FP96 for FP96.FixedPoint;
  using MaxBinaryHeapLib for MaxBinaryHeapLib.Heap;
  using LowGasSafeMath for uint256;

  /// @dev FP96 inner value of count of seconds in year. Equal 365.25 * 24 * 60 * 60
  uint256 private constant SECONDS_IN_YEAR_X96 = 2500250661360148260042022567123353600;

  /// @dev Denominator of fee value
  uint24 private constant WHOLE_ONE = 1e6;

  /// @dev Min available leverage
  uint8 private constant MIN_LEVERAGE = 1;

  /// @inheritdoc IMarginlyPool
  address public override factory;

  /// @inheritdoc IMarginlyPool
  uint32 public override defaultSwapCallData;

  /// @inheritdoc IMarginlyPool
  address public override quoteToken;
  /// @inheritdoc IMarginlyPool
  address public override baseToken;
  /// @inheritdoc IMarginlyPool
  address public override priceOracle;
  /// @dev reentrancy guard
  bool private locked;

  Mode public mode;

  MarginlyParams public params;

  /// @dev Sum of all quote token in collateral
  uint256 public discountedQuoteCollateral;
  /// @dev Sum of all quote token in debt
  uint256 public discountedQuoteDebt;
  /// @dev Sum of  all base token collateral
  uint256 public discountedBaseCollateral;
  /// @dev Sum of all base token in debt
  uint256 public discountedBaseDebt;
  /// @dev Timestamp of last reinit execution
  uint256 public lastReinitTimestampSeconds;

  /// @dev Aggregate for base collateral time change calculations
  FP96.FixedPoint public baseCollateralCoeff;
  /// @dev Aggregate for deleveraged base collateral
  FP96.FixedPoint public baseDelevCoeff;
  /// @dev Aggregate for base debt time change calculations
  FP96.FixedPoint public baseDebtCoeff;
  /// @dev Aggregate for quote collateral time change calculations
  FP96.FixedPoint public quoteCollateralCoeff;
  /// @dev Aggregate for deleveraged quote collateral
  FP96.FixedPoint public quoteDelevCoeff;
  /// @dev Accrued interest rate and fee for quote debt
  FP96.FixedPoint public quoteDebtCoeff;
  /// @dev Initial price. Used to sort key and shutdown calculations. Value gets reset for the latter one
  FP96.FixedPoint public initialPrice;
  /// @dev Ratio of best side collaterals before and after margin call of opposite side in shutdown mode
  FP96.FixedPoint public emergencyWithdrawCoeff;

  struct Leverage {
    /// @dev This is a leverage of all long positions in the system
    uint128 shortX96;
    /// @dev This is a leverage of all short positions in the system
    uint128 longX96;
  }

  Leverage public systemLeverage;

  ///@dev Heap of short positions, root - the worst short position. Sort key - leverage calculated with discounted collateral, debt
  MaxBinaryHeapLib.Heap private shortHeap;
  ///@dev Heap of long positions, root - the worst long position. Sort key - leverage calculated with discounted collateral, debt
  MaxBinaryHeapLib.Heap private longHeap;

  /// @notice users positions
  mapping(address => Position) public positions;

  constructor() {
    factory = address(0xdead);
  }

  function _initializeMarginlyPool(
    address _quoteToken,
    address _baseToken,
    address _priceOracle,
    uint32 _defaultSwapCallData,
    MarginlyParams memory _params
  ) internal {
    if (_quoteToken == address(0)) revert Errors.WrongValue();
    if (_baseToken == address(0)) revert Errors.WrongValue();
    if (_priceOracle == address(0)) revert Errors.WrongValue();

    factory = msg.sender;
    quoteToken = _quoteToken;
    baseToken = _baseToken;
    priceOracle = _priceOracle;
    _setParameters(_params);

    baseCollateralCoeff = FP96.one();
    baseDebtCoeff = FP96.one();
    quoteCollateralCoeff = FP96.one();
    quoteDebtCoeff = FP96.one();
    lastReinitTimestampSeconds = getTimestamp();
    initialPrice = getBasePrice();
    defaultSwapCallData = _defaultSwapCallData;

    Position storage techPosition = getTechPosition();
    techPosition._type = PositionType.Lend;
  }

  /// @inheritdoc IMarginlyPool
  function initialize(
    address _quoteToken,
    address _baseToken,
    address _priceOracle,
    uint32 _defaultSwapCallData,
    MarginlyParams calldata _params
  ) external virtual {
    if (factory != address(0)) revert Errors.Forbidden();

    _initializeMarginlyPool(_quoteToken, _baseToken, _priceOracle, _defaultSwapCallData, _params);
  }

  receive() external payable {
    if (msg.sender != getWETH9Address()) revert Errors.NotWETH9();
  }

  function _lock() private view {
    if (locked) revert Errors.Locked();
  }

  /// @dev Protects against reentrancy
  modifier lock() {
    _lock();
    locked = true;
    _;
    delete locked;
  }

  function _onlyFactoryOwner() private view {
    if (msg.sender != Ownable2Step(factory).owner()) revert Errors.AccessDenied();
  }

  modifier onlyFactoryOwner() {
    _onlyFactoryOwner();
    _;
  }

  /// @inheritdoc IMarginlyPoolOwnerActions
  function setParameters(MarginlyParams calldata _params) external override onlyFactoryOwner {
    _setParameters(_params);
  }

  function _setParameters(MarginlyParams memory _params) private {
    if (
      _params.interestRate > WHOLE_ONE ||
      _params.fee > WHOLE_ONE ||
      _params.swapFee > WHOLE_ONE ||
      _params.mcSlippage > WHOLE_ONE ||
      _params.maxLeverage < MIN_LEVERAGE ||
      _params.quoteLimit == 0 ||
      _params.positionMinAmount == 0
    ) revert Errors.WrongValue();

    params = _params;
    emit ParametersChanged();
  }

  /// @dev Swaps tokens to receive exact amountOut and send at most amountInMaximum
  function swapExactOutput(
    bool quoteIn,
    uint256 amountInMaximum,
    uint256 amountOut,
    uint256 swapCalldata
  ) private returns (uint256 amountInActual) {
    address swapRouter = getSwapRouter();
    (address tokenIn, address tokenOut) = quoteIn ? (quoteToken, baseToken) : (baseToken, quoteToken);

    SafeERC20.forceApprove(IERC20(tokenIn), swapRouter, amountInMaximum);

    amountInActual = IMarginlyRouter(swapRouter).swapExactOutput(
      swapCalldata,
      tokenIn,
      tokenOut,
      amountInMaximum,
      amountOut
    );

    SafeERC20.forceApprove(IERC20(tokenIn), swapRouter, 0);
  }

  /// @dev Swaps tokens to spend exact amountIn and receive at least amountOutMinimum
  function swapExactInput(
    bool quoteIn,
    uint256 amountIn,
    uint256 amountOutMinimum,
    uint256 swapCalldata
  ) private returns (uint256 amountOutActual) {
    address swapRouter = getSwapRouter();
    (address tokenIn, address tokenOut) = quoteIn ? (quoteToken, baseToken) : (baseToken, quoteToken);

    SafeERC20.forceApprove(IERC20(tokenIn), swapRouter, amountIn);

    amountOutActual = IMarginlyRouter(swapRouter).swapExactInput(
      swapCalldata,
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMinimum
    );
  }

  /// @dev User liquidation: applies deleverage if needed then enacts MC
  /// @param user User's address
  /// @param position User's position to reinit
  function liquidate(address user, Position storage position, FP96.FixedPoint memory basePrice) private {
    if (position._type == PositionType.Short) {
      uint256 realQuoteCollateral = calcRealQuoteCollateral(
        position.discountedQuoteAmount,
        position.discountedBaseAmount
      );

      // positionRealQuoteCollateral > poolQuoteBalance = poolQuoteCollateral - poolQuoteDebt
      // positionRealQuoteCollateral + poolQuoteDebt > poolQuoteCollateral
      uint256 poolQuoteCollateral = calcRealQuoteCollateral(discountedQuoteCollateral, discountedBaseDebt);
      uint256 posQuoteCollPlusPoolQuoteDebt = quoteDebtCoeff.mul(discountedQuoteDebt).add(realQuoteCollateral);

      if (posQuoteCollPlusPoolQuoteDebt > poolQuoteCollateral) {
        // quoteDebtToReduce = positionRealQuoteCollateral - (poolQuoteCollateral - poolQuoteDebt) =
        // = (positionRealQuoteCollateral + poolQuoteDebt) - poolQuoteCollateral
        uint256 quoteDebtToReduce = posQuoteCollPlusPoolQuoteDebt.sub(poolQuoteCollateral);
        uint256 baseCollToReduce = basePrice.recipMul(quoteDebtToReduce);
        uint256 positionBaseDebt = baseDebtCoeff.mul(position.discountedBaseAmount);
        if (baseCollToReduce > positionBaseDebt) {
          baseCollToReduce = positionBaseDebt;
        }
        deleverageLong(baseCollToReduce, quoteDebtToReduce);

        uint256 disBaseDelta = baseDebtCoeff.recipMul(baseCollToReduce);
        position.discountedBaseAmount = position.discountedBaseAmount.sub(disBaseDelta);
        discountedBaseDebt = discountedBaseDebt.sub(disBaseDelta);

        uint256 disQuoteDelta = quoteCollateralCoeff.recipMul(quoteDebtToReduce.add(quoteDelevCoeff.mul(disBaseDelta)));
        position.discountedQuoteAmount = position.discountedQuoteAmount.sub(disQuoteDelta);
        discountedQuoteCollateral = discountedQuoteCollateral.sub(disQuoteDelta);
      }
    } else if (position._type == PositionType.Long) {
      uint256 realBaseCollateral = calcRealBaseCollateral(
        position.discountedBaseAmount,
        position.discountedQuoteAmount
      );

      // positionRealBaseCollateral > poolBaseBalance = poolBaseCollateral - poolBaseDebt
      // positionRealBaseCollateral + poolBaseDebt > poolBaseCollateral
      uint256 poolBaseCollateral = calcRealBaseCollateral(discountedBaseCollateral, discountedQuoteDebt);
      uint256 posBaseCollPlusPoolBaseDebt = baseDebtCoeff.mul(discountedBaseDebt).add(realBaseCollateral);

      if (posBaseCollPlusPoolBaseDebt > poolBaseCollateral) {
        // baseDebtToReduce = positionRealBaseCollateral - (poolBaseCollateral - poolBaseDebt) =
        // = (positionRealBaseCollateral + poolBaseDebt) - poolBaseCollateral
        uint256 baseDebtToReduce = posBaseCollPlusPoolBaseDebt.sub(poolBaseCollateral);
        uint256 quoteCollToReduce = basePrice.mul(baseDebtToReduce);
        uint256 positionQuoteDebt = quoteDebtCoeff.mul(position.discountedQuoteAmount);
        if (quoteCollToReduce > positionQuoteDebt) {
          quoteCollToReduce = positionQuoteDebt;
        }
        deleverageShort(quoteCollToReduce, baseDebtToReduce);

        uint256 disQuoteDelta = quoteDebtCoeff.recipMul(quoteCollToReduce);
        position.discountedQuoteAmount = position.discountedQuoteAmount.sub(disQuoteDelta);
        discountedQuoteDebt = discountedQuoteDebt.sub(disQuoteDelta);

        uint256 disBaseDelta = baseCollateralCoeff.recipMul(baseDebtToReduce.add(baseDelevCoeff.mul(disQuoteDelta)));
        position.discountedBaseAmount = position.discountedBaseAmount.sub(disBaseDelta);
        discountedBaseCollateral = discountedBaseCollateral.sub(disBaseDelta);
      }
    } else {
      revert Errors.WrongPositionType();
    }
    enactMarginCall(user, position);
  }

  /// @dev All short positions deleverage
  /// @param realQuoteCollateral Total quote collateral to reduce on all short positions
  /// @param realBaseDebt Total base debt to reduce on all short positions
  function deleverageShort(uint256 realQuoteCollateral, uint256 realBaseDebt) private {
    quoteDelevCoeff = quoteDelevCoeff.add(FP96.fromRatio(realQuoteCollateral, discountedBaseDebt));
    baseDebtCoeff = baseDebtCoeff.sub(FP96.fromRatio(realBaseDebt, discountedBaseDebt));

    // this error is highly unlikely to occur and requires lots of big whales liquidations prior to it
    // however if it happens, the ways to fix what seems like a pool deadlock are 'receivePosition' and 'balanceSync'
    if (baseDebtCoeff.inner < FP96.halfPrecision().inner) revert Errors.BigPrecisionLoss();

    emit Deleverage(PositionType.Short, realQuoteCollateral, realBaseDebt);
  }

  /// @dev All long positions deleverage
  /// @param realBaseCollateral Total base collateral to reduce on all long positions
  /// @param realQuoteDebt Total quote debt to reduce on all long positions
  function deleverageLong(uint256 realBaseCollateral, uint256 realQuoteDebt) private {
    baseDelevCoeff = baseDelevCoeff.add(FP96.fromRatio(realBaseCollateral, discountedQuoteDebt));
    quoteDebtCoeff = quoteDebtCoeff.sub(FP96.fromRatio(realQuoteDebt, discountedQuoteDebt));

    // this error is highly unlikely to occur and requires lots of big whales liquidations prior to it
    // however if it happens, the ways to fix what seems like a pool deadlock are 'receivePosition' and 'balanceSync'
    if (quoteDebtCoeff.inner < FP96.halfPrecision().inner) revert Errors.BigPrecisionLoss();

    emit Deleverage(PositionType.Long, realBaseCollateral, realQuoteDebt);
  }

  /// @dev Enact margin call procedure for the position
  /// @param user User's address
  /// @param position User's position to reinit
  function enactMarginCall(address user, Position storage position) private {
    uint256 swapPriceX96;
    // it's guaranteed by liquidate() function, that position._type is either Short or Long
    // else is used to save some contract space
    if (position._type == PositionType.Short) {
      uint256 realQuoteCollateral = calcRealQuoteCollateral(
        position.discountedQuoteAmount,
        position.discountedBaseAmount
      );
      uint256 realBaseDebt = baseDebtCoeff.mul(position.discountedBaseAmount);

      // short position mc
      uint256 swappedBaseDebt;
      if (realQuoteCollateral != 0) {
        uint baseOutMinimum = FP96.fromRatio(WHOLE_ONE - params.mcSlippage, WHOLE_ONE).mul(
          getLiquidationPrice().recipMul(realQuoteCollateral)
        );
        swappedBaseDebt = swapExactInput(true, realQuoteCollateral, baseOutMinimum, defaultSwapCallData);
        swapPriceX96 = getSwapPrice(realQuoteCollateral, swappedBaseDebt);
      }

      FP96.FixedPoint memory factor;
      // baseCollateralCoeff += rcd * (rqc - sqc) / sqc
      if (swappedBaseDebt >= realBaseDebt) {
        // Position has enough collateral to repay debt
        factor = FP96.one().add(
          FP96.fromRatio(
            swappedBaseDebt.sub(realBaseDebt),
            calcRealBaseCollateral(discountedBaseCollateral, discountedQuoteDebt)
          )
        );
      } else {
        // Position's debt has been repaid by pool
        factor = FP96.one().sub(
          FP96.fromRatio(
            realBaseDebt.sub(swappedBaseDebt),
            calcRealBaseCollateral(discountedBaseCollateral, discountedQuoteDebt)
          )
        );
      }
      updateBaseCollateralCoeffs(factor);

      discountedQuoteCollateral = discountedQuoteCollateral.sub(position.discountedQuoteAmount);
      discountedBaseDebt = discountedBaseDebt.sub(position.discountedBaseAmount);

      //remove position
      shortHeap.remove(positions, position.heapPosition - 1);
    } else {
      uint256 realBaseCollateral = calcRealBaseCollateral(
        position.discountedBaseAmount,
        position.discountedQuoteAmount
      );
      uint256 realQuoteDebt = quoteDebtCoeff.mul(position.discountedQuoteAmount);

      // long position mc
      uint256 swappedQuoteDebt;
      if (realBaseCollateral != 0) {
        uint256 quoteOutMinimum = FP96.fromRatio(WHOLE_ONE - params.mcSlippage, WHOLE_ONE).mul(
          getLiquidationPrice().mul(realBaseCollateral)
        );
        swappedQuoteDebt = swapExactInput(false, realBaseCollateral, quoteOutMinimum, defaultSwapCallData);
        swapPriceX96 = getSwapPrice(swappedQuoteDebt, realBaseCollateral);
      }

      FP96.FixedPoint memory factor;
      // quoteCollateralCoef += rqd * (rbc - sbc) / sbc
      if (swappedQuoteDebt >= realQuoteDebt) {
        // Position has enough collateral to repay debt
        factor = FP96.one().add(
          FP96.fromRatio(
            swappedQuoteDebt.sub(realQuoteDebt),
            calcRealQuoteCollateral(discountedQuoteCollateral, discountedBaseDebt)
          )
        );
      } else {
        // Position's debt has been repaid by pool
        factor = FP96.one().sub(
          FP96.fromRatio(
            realQuoteDebt.sub(swappedQuoteDebt),
            calcRealQuoteCollateral(discountedQuoteCollateral, discountedBaseDebt)
          )
        );
      }
      updateQuoteCollateralCoeffs(factor);

      discountedBaseCollateral = discountedBaseCollateral.sub(position.discountedBaseAmount);
      discountedQuoteDebt = discountedQuoteDebt.sub(position.discountedQuoteAmount);

      //remove position
      longHeap.remove(positions, position.heapPosition - 1);
    }

    delete positions[user];
    emit EnactMarginCall(user, swapPriceX96);
  }

  /// @dev Calculate leverage
  function calcLeverage(uint256 collateral, uint256 debt) private pure returns (uint256 leverage) {
    if (collateral > debt) {
      return Math.mulDiv(FP96.Q96, collateral, collateral - debt);
    } else {
      return FP96.INNER_MAX;
    }
  }

  /// @dev Calculate sort key for ordering long/short positions.
  /// Sort key represents value of debt / collateral both in quoteToken.
  /// as FixedPoint with 10 bits for decimals
  function calcSortKey(uint256 collateral, uint256 debt) private pure returns (uint96) {
    uint96 maxValue = type(uint96).max;
    if (collateral != 0) {
      uint256 result = Math.mulDiv(FP48.Q48, debt, collateral);
      if (result > maxValue) {
        return maxValue;
      } else {
        return uint96(result);
      }
    } else {
      return maxValue;
    }
  }

  /// @notice Deposit base token
  /// @param amount Amount of base token to deposit
  /// @param basePrice current oracle base price, got by getBasePrice() method
  /// @param position msg.sender position
  function depositBase(uint256 amount, FP96.FixedPoint memory basePrice, Position storage position) private {
    if (amount == 0) revert Errors.ZeroAmount();

    if (position._type == PositionType.Uninitialized) {
      position._type = PositionType.Lend;
    }

    FP96.FixedPoint memory _baseDebtCoeff = baseDebtCoeff;

    uint256 positionDiscountedBaseAmountPrev = position.discountedBaseAmount;
    if (position._type == PositionType.Short) {
      uint256 realBaseDebt = _baseDebtCoeff.mul(positionDiscountedBaseAmountPrev);
      uint256 discountedBaseDebtDelta;

      if (amount >= realBaseDebt) {
        uint256 newRealBaseCollateral = amount.sub(realBaseDebt);
        if (amount != realBaseDebt)
          if (basePrice.mul(newPoolBaseBalance(newRealBaseCollateral)) > params.quoteLimit)
            revert Errors.ExceedsLimit();

        shortHeap.remove(positions, position.heapPosition - 1);
        // Short position debt <= depositAmount, increase collateral on delta, change position to Lend
        // discountedBaseCollateralDelta = (amount - realDebt)/ baseCollateralCoeff
        uint256 discountedBaseCollateralDelta = baseCollateralCoeff.recipMul(newRealBaseCollateral);
        discountedBaseDebtDelta = positionDiscountedBaseAmountPrev;
        position._type = PositionType.Lend;
        position.discountedBaseAmount = discountedBaseCollateralDelta;

        // update aggregates
        discountedBaseCollateral = discountedBaseCollateral.add(discountedBaseCollateralDelta);
      } else {
        // Short position, debt > depositAmount, decrease debt
        discountedBaseDebtDelta = _baseDebtCoeff.recipMul(amount);
        position.discountedBaseAmount = positionDiscountedBaseAmountPrev.sub(discountedBaseDebtDelta);
      }

      uint256 discountedQuoteCollDelta = quoteCollateralCoeff.recipMul(quoteDelevCoeff.mul(discountedBaseDebtDelta));
      position.discountedQuoteAmount = position.discountedQuoteAmount.sub(discountedQuoteCollDelta);
      discountedBaseDebt = discountedBaseDebt.sub(discountedBaseDebtDelta);
      discountedQuoteCollateral = discountedQuoteCollateral.sub(discountedQuoteCollDelta);
    } else {
      if (basePrice.mul(newPoolBaseBalance(amount)) > params.quoteLimit) revert Errors.ExceedsLimit();

      // Lend position, increase collateral on amount
      // discountedCollateralDelta = amount / baseCollateralCoeff
      uint256 discountedCollateralDelta = baseCollateralCoeff.recipMul(amount);
      position.discountedBaseAmount = positionDiscountedBaseAmountPrev.add(discountedCollateralDelta);

      // update aggregates
      discountedBaseCollateral = discountedBaseCollateral.add(discountedCollateralDelta);
    }

    wrapAndTransferFrom(baseToken, msg.sender, amount);
    emit DepositBase(msg.sender, amount, position._type, position.discountedBaseAmount);
  }

  /// @notice Deposit quote token
  /// @param amount Amount of quote token
  /// @param position msg.sender position
  function depositQuote(uint256 amount, Position storage position) private {
    if (amount == 0) revert Errors.ZeroAmount();

    if (position._type == PositionType.Uninitialized) {
      position._type = PositionType.Lend;
    }

    FP96.FixedPoint memory _quoteDebtCoeff = quoteDebtCoeff;

    uint256 positionDiscountedQuoteAmountPrev = position.discountedQuoteAmount;
    if (position._type == PositionType.Long) {
      uint256 realQuoteDebt = _quoteDebtCoeff.mul(positionDiscountedQuoteAmountPrev);
      uint256 discountedQuoteDebtDelta;

      if (amount >= realQuoteDebt) {
        uint256 newRealQuoteCollateral = amount.sub(realQuoteDebt);
        if (amount != realQuoteDebt)
          if (newPoolQuoteBalance(newRealQuoteCollateral) > params.quoteLimit) revert Errors.ExceedsLimit();

        longHeap.remove(positions, position.heapPosition - 1);
        // Long position, debt <= depositAmount, increase collateral on delta, move position to Lend
        // quoteCollateralChange = (amount - discountedDebt)/ quoteCollateralCoef
        uint256 discountedQuoteCollateralDelta = quoteCollateralCoeff.recipMul(newRealQuoteCollateral);
        discountedQuoteDebtDelta = positionDiscountedQuoteAmountPrev;
        position._type = PositionType.Lend;
        position.discountedQuoteAmount = discountedQuoteCollateralDelta;

        // update aggregates
        discountedQuoteCollateral = discountedQuoteCollateral.add(discountedQuoteCollateralDelta);
      } else {
        // Long position, debt > depositAmount, decrease debt on delta
        discountedQuoteDebtDelta = _quoteDebtCoeff.recipMul(amount);
        position.discountedQuoteAmount = positionDiscountedQuoteAmountPrev.sub(discountedQuoteDebtDelta);
      }

      uint256 discountedBaseCollDelta = baseCollateralCoeff.recipMul(baseDelevCoeff.mul(discountedQuoteDebtDelta));
      position.discountedBaseAmount = position.discountedBaseAmount.sub(discountedBaseCollDelta);
      discountedQuoteDebt = discountedQuoteDebt.sub(discountedQuoteDebtDelta);
      discountedBaseCollateral = discountedBaseCollateral.sub(discountedBaseCollDelta);
    } else {
      if (newPoolQuoteBalance(amount) > params.quoteLimit) revert Errors.ExceedsLimit();

      // Lend position, increase collateral on amount
      // discountedQuoteCollateralDelta = amount / quoteCollateralCoeff
      uint256 discountedQuoteCollateralDelta = quoteCollateralCoeff.recipMul(amount);
      position.discountedQuoteAmount = positionDiscountedQuoteAmountPrev.add(discountedQuoteCollateralDelta);

      // update aggregates
      discountedQuoteCollateral = discountedQuoteCollateral.add(discountedQuoteCollateralDelta);
    }

    wrapAndTransferFrom(quoteToken, msg.sender, amount);
    emit DepositQuote(msg.sender, amount, position._type, position.discountedQuoteAmount);
  }

  /// @notice Withdraw base token
  /// @param realAmount Amount of base token
  /// @param unwrapWETH flag to unwrap WETH to ETH
  /// @param basePrice current oracle base price, got by getBasePrice() method
  /// @param position msg.sender position
  function withdrawBase(
    uint256 realAmount,
    bool unwrapWETH,
    FP96.FixedPoint memory basePrice,
    Position storage position
  ) private {
    if (realAmount == 0) revert Errors.ZeroAmount();

    PositionType _type = position._type;
    if (_type == PositionType.Uninitialized) revert Errors.UninitializedPosition();
    if (_type == PositionType.Short) revert Errors.WrongPositionType();

    uint256 positionBaseAmount = position.discountedBaseAmount;
    uint256 positionQuoteDebt = _type == PositionType.Lend ? 0 : position.discountedQuoteAmount;

    uint256 realBaseAmount = calcRealBaseCollateral(positionBaseAmount, positionQuoteDebt);
    uint256 realAmountToWithdraw;
    bool needToDeletePosition = false;
    uint256 discountedBaseCollateralDelta;
    if (realAmount >= realBaseAmount) {
      // full withdraw
      realAmountToWithdraw = realBaseAmount;
      discountedBaseCollateralDelta = positionBaseAmount;

      needToDeletePosition = position.discountedQuoteAmount == 0;
    } else {
      // partial withdraw
      realAmountToWithdraw = realAmount;
      discountedBaseCollateralDelta = baseCollateralCoeff.recipMul(realAmountToWithdraw);
    }

    if (_type == PositionType.Long) {
      uint256 realQuoteDebt = quoteDebtCoeff.mul(positionQuoteDebt);
      // margin = (baseColl - baseCollDelta) - quoteDebt / price < minAmount
      // minAmount + quoteDebt / price > baseColl - baseCollDelta
      if (basePrice.recipMul(realQuoteDebt).add(params.positionMinAmount) > realBaseAmount.sub(realAmountToWithdraw)) {
        revert Errors.LessThanMinimalAmount();
      }
    }

    position.discountedBaseAmount = positionBaseAmount.sub(discountedBaseCollateralDelta);
    discountedBaseCollateral = discountedBaseCollateral.sub(discountedBaseCollateralDelta);

    if (positionHasBadLeverage(position, basePrice)) revert Errors.BadLeverage();

    if (needToDeletePosition) {
      delete positions[msg.sender];
    }

    unwrapAndTransfer(unwrapWETH, baseToken, msg.sender, realAmountToWithdraw);

    emit WithdrawBase(msg.sender, realAmountToWithdraw, discountedBaseCollateralDelta);
  }

  /// @notice Withdraw quote token
  /// @param realAmount Amount of quote token
  /// @param unwrapWETH flag to unwrap WETH to ETH
  /// @param basePrice current oracle base price, got by getBasePrice() method
  /// @param position msg.sender position
  function withdrawQuote(
    uint256 realAmount,
    bool unwrapWETH,
    FP96.FixedPoint memory basePrice,
    Position storage position
  ) private {
    if (realAmount == 0) revert Errors.ZeroAmount();

    PositionType _type = position._type;
    if (_type == PositionType.Uninitialized) revert Errors.UninitializedPosition();
    if (_type == PositionType.Long) revert Errors.WrongPositionType();

    uint256 positionQuoteAmount = position.discountedQuoteAmount;
    uint256 positionBaseDebt = _type == PositionType.Lend ? 0 : position.discountedBaseAmount;

    uint256 realQuoteAmount = calcRealQuoteCollateral(positionQuoteAmount, positionBaseDebt);
    uint256 realAmountToWithdraw;
    bool needToDeletePosition = false;
    uint256 discountedQuoteCollateralDelta;
    if (realAmount >= realQuoteAmount) {
      // full withdraw
      realAmountToWithdraw = realQuoteAmount;
      discountedQuoteCollateralDelta = positionQuoteAmount;

      needToDeletePosition = position.discountedBaseAmount == 0;
    } else {
      // partial withdraw
      realAmountToWithdraw = realAmount;
      discountedQuoteCollateralDelta = quoteCollateralCoeff.recipMul(realAmountToWithdraw);
    }

    if (_type == PositionType.Short) {
      uint256 realBaseDebt = baseDebtCoeff.mul(positionBaseDebt);
      // margin = (quoteColl - quoteCollDelta) - baseDebt * price < minAmount * price
      // (minAmount + baseDebt) * price > quoteColl - quoteCollDelta
      if (basePrice.mul(realBaseDebt.add(params.positionMinAmount)) > realQuoteAmount.sub(realAmountToWithdraw)) {
        revert Errors.LessThanMinimalAmount();
      }
    }

    position.discountedQuoteAmount = positionQuoteAmount.sub(discountedQuoteCollateralDelta);
    discountedQuoteCollateral = discountedQuoteCollateral.sub(discountedQuoteCollateralDelta);

    if (positionHasBadLeverage(position, basePrice)) revert Errors.BadLeverage();

    if (needToDeletePosition) {
      delete positions[msg.sender];
    }

    unwrapAndTransfer(unwrapWETH, quoteToken, msg.sender, realAmountToWithdraw);

    emit WithdrawQuote(msg.sender, realAmountToWithdraw, discountedQuoteCollateralDelta);
  }

  /// @notice Close position
  /// @param position msg.sender position
  function closePosition(uint256 limitPriceX96, Position storage position, uint256 swapCalldata) private {
    uint256 realCollateralDelta;
    uint256 discountedCollateralDelta;
    address collateralToken;
    uint256 swapPriceX96;
    if (position._type == PositionType.Short) {
      collateralToken = quoteToken;

      uint256 positionDiscountedBaseDebtPrev = position.discountedBaseAmount;
      uint256 realQuoteCollateral = calcRealQuoteCollateral(
        position.discountedQuoteAmount,
        position.discountedBaseAmount
      );
      uint256 realBaseDebt = baseDebtCoeff.mul(positionDiscountedBaseDebtPrev, Math.Rounding.Up);

      {
        // quoteInMaximum is defined by user input limitPriceX96
        uint256 quoteInMaximum = Math.mulDiv(limitPriceX96, realBaseDebt, FP96.Q96);

        realCollateralDelta = swapExactOutput(true, realQuoteCollateral, realBaseDebt, swapCalldata);
        if (realCollateralDelta > quoteInMaximum) revert Errors.SlippageLimit();
        swapPriceX96 = getSwapPrice(realCollateralDelta, realBaseDebt);

        uint256 realFeeAmount = Math.mulDiv(params.swapFee, realCollateralDelta, WHOLE_ONE);
        chargeFee(realFeeAmount);

        realCollateralDelta = realCollateralDelta.add(realFeeAmount);
        discountedCollateralDelta = quoteCollateralCoeff.recipMul(
          realCollateralDelta.add(quoteDelevCoeff.mul(position.discountedBaseAmount))
        );
      }

      discountedQuoteCollateral = discountedQuoteCollateral.sub(discountedCollateralDelta);
      discountedBaseDebt = discountedBaseDebt.sub(positionDiscountedBaseDebtPrev);

      position.discountedQuoteAmount = position.discountedQuoteAmount.sub(discountedCollateralDelta);
      position.discountedBaseAmount = 0;
      position._type = PositionType.Lend;

      uint32 heapIndex = position.heapPosition - 1;
      shortHeap.remove(positions, heapIndex);
    } else if (position._type == PositionType.Long) {
      collateralToken = baseToken;

      uint256 positionDiscountedQuoteDebtPrev = position.discountedQuoteAmount;
      uint256 realBaseCollateral = calcRealBaseCollateral(
        position.discountedBaseAmount,
        position.discountedQuoteAmount
      );
      uint256 realQuoteDebt = quoteDebtCoeff.mul(positionDiscountedQuoteDebtPrev, Math.Rounding.Up);

      uint256 realFeeAmount = Math.mulDiv(params.swapFee, realQuoteDebt, WHOLE_ONE);
      uint256 exactQuoteOut = realQuoteDebt.add(realFeeAmount);

      {
        // baseInMaximum is defined by user input limitPriceX96
        uint256 baseInMaximum = Math.mulDiv(FP96.Q96, exactQuoteOut, limitPriceX96);

        realCollateralDelta = swapExactOutput(false, realBaseCollateral, exactQuoteOut, swapCalldata);
        if (realCollateralDelta > baseInMaximum) revert Errors.SlippageLimit();
        swapPriceX96 = getSwapPrice(exactQuoteOut, realCollateralDelta);

        chargeFee(realFeeAmount);

        discountedCollateralDelta = baseCollateralCoeff.recipMul(
          realCollateralDelta.add(baseDelevCoeff.mul(position.discountedQuoteAmount))
        );
      }

      discountedBaseCollateral = discountedBaseCollateral.sub(discountedCollateralDelta);
      discountedQuoteDebt = discountedQuoteDebt.sub(positionDiscountedQuoteDebtPrev);

      position.discountedBaseAmount = position.discountedBaseAmount.sub(discountedCollateralDelta);
      position.discountedQuoteAmount = 0;
      position._type = PositionType.Lend;

      uint32 heapIndex = position.heapPosition - 1;
      longHeap.remove(positions, heapIndex);
    } else {
      revert Errors.WrongPositionType();
    }

    emit ClosePosition(msg.sender, collateralToken, realCollateralDelta, swapPriceX96, discountedCollateralDelta);
  }

  /// @dev Charge fee (swap or debt fee) in quote token
  /// @param feeAmount amount of token
  function chargeFee(uint256 feeAmount) private {
    TransferHelper.safeTransfer(quoteToken, IMarginlyFactory(factory).feeHolder(), feeAmount);
  }

  /// @notice Get oracle price baseToken / quoteToken
  function getBasePrice() public view returns (FP96.FixedPoint memory) {
    uint256 price = IPriceOracle(priceOracle).getBalancePrice(quoteToken, baseToken);
    return FP96.FixedPoint({inner: price});
  }

  /// @notice Get TWAP price used in mc slippage calculations
  function getLiquidationPrice() public view returns (FP96.FixedPoint memory) {
    uint256 price = IPriceOracle(priceOracle).getMargincallPrice(quoteToken, baseToken);
    return FP96.FixedPoint({inner: price});
  }

  /// @notice Short with leverage
  /// @param realBaseAmount Amount of base token
  /// @param basePrice current oracle base price, got by getBasePrice() method
  /// @param position msg.sender position
  function short(
    uint256 realBaseAmount,
    uint256 limitPriceX96,
    FP96.FixedPoint memory basePrice,
    Position storage position,
    uint256 swapCalldata
  ) private {
    revert Errors.Forbidden();
    // this function guaranties the position is gonna be either Short or Lend with 0 base balance
    sellBaseForQuote(position, limitPriceX96, swapCalldata);

    uint256 positionDisBaseDebt = position.discountedBaseAmount;
    uint256 positionDisQuoteCollateral = position.discountedQuoteAmount;

    {
      uint256 currentQuoteCollateral = calcRealQuoteCollateral(positionDisQuoteCollateral, positionDisBaseDebt);
      if (currentQuoteCollateral < basePrice.mul(params.positionMinAmount)) revert Errors.LessThanMinimalAmount();
    }

    // quoteOutMinimum is defined by user input limitPriceX96
    uint256 quoteOutMinimum = Math.mulDiv(limitPriceX96, realBaseAmount, FP96.Q96);
    uint256 realQuoteCollateralChangeWithFee = swapExactInput(false, realBaseAmount, quoteOutMinimum, swapCalldata);
    uint256 swapPriceX96 = getSwapPrice(realQuoteCollateralChangeWithFee, realBaseAmount);

    uint256 realSwapFee = Math.mulDiv(params.swapFee, realQuoteCollateralChangeWithFee, WHOLE_ONE);
    uint256 realQuoteCollateralChange = realQuoteCollateralChangeWithFee.sub(realSwapFee);

    if (newPoolQuoteBalance(realQuoteCollateralChange) > params.quoteLimit) revert Errors.ExceedsLimit();

    uint256 discountedBaseDebtChange = baseDebtCoeff.recipMul(realBaseAmount);
    position.discountedBaseAmount = positionDisBaseDebt.add(discountedBaseDebtChange);
    discountedBaseDebt = discountedBaseDebt.add(discountedBaseDebtChange);

    uint256 discountedQuoteChange = quoteCollateralCoeff.recipMul(
      realQuoteCollateralChange.add(quoteDelevCoeff.mul(discountedBaseDebtChange))
    );
    position.discountedQuoteAmount = positionDisQuoteCollateral.add(discountedQuoteChange);
    discountedQuoteCollateral = discountedQuoteCollateral.add(discountedQuoteChange);
    chargeFee(realSwapFee);

    if (position._type == PositionType.Lend) {
      if (position.heapPosition != 0) revert Errors.WrongIndex();
      // init heap with default value 0, it will be updated by 'updateHeap' function later
      shortHeap.insert(positions, MaxBinaryHeapLib.Node({key: 0, account: msg.sender}));
      position._type = PositionType.Short;
    }

    if (positionHasBadLeverage(position, basePrice)) revert Errors.BadLeverage();

    emit Short(msg.sender, realBaseAmount, swapPriceX96, discountedQuoteChange, discountedBaseDebtChange);
  }

  /// @notice Long with leverage
  /// @param realBaseAmount Amount of base token
  /// @param basePrice current oracle base price, got by getBasePrice() method
  /// @param position msg.sender position
  function long(
    uint256 realBaseAmount,
    uint256 limitPriceX96,
    FP96.FixedPoint memory basePrice,
    Position storage position,
    uint256 swapCalldata
  ) private {
    if (basePrice.mul(newPoolBaseBalance(realBaseAmount)) > params.quoteLimit) revert Errors.ExceedsLimit();

    // this function guaranties the position is gonna be either Long or Lend with 0 quote balance
    sellQuoteForBase(position, limitPriceX96, swapCalldata);

    uint256 positionDisQuoteDebt = position.discountedQuoteAmount;
    uint256 positionDisBaseCollateral = position.discountedBaseAmount;

    {
      uint256 currentBaseCollateral = calcRealBaseCollateral(positionDisBaseCollateral, positionDisQuoteDebt);
      if (currentBaseCollateral < params.positionMinAmount) revert Errors.LessThanMinimalAmount();
    }

    // realQuoteInMaximum is defined by user input limitPriceX96
    uint256 realQuoteInMaximum = Math.mulDiv(limitPriceX96, realBaseAmount, FP96.Q96);
    uint256 realQuoteAmount = swapExactOutput(true, realQuoteInMaximum, realBaseAmount, swapCalldata);
    uint256 swapPriceX96 = getSwapPrice(realQuoteAmount, realBaseAmount);

    uint256 realSwapFee = Math.mulDiv(params.swapFee, realQuoteAmount, WHOLE_ONE);
    chargeFee(realSwapFee);

    uint256 discountedQuoteDebtChange = quoteDebtCoeff.recipMul(realQuoteAmount.add(realSwapFee));
    position.discountedQuoteAmount = positionDisQuoteDebt.add(discountedQuoteDebtChange);
    discountedQuoteDebt = discountedQuoteDebt.add(discountedQuoteDebtChange);

    uint256 discountedBaseCollateralChange = baseCollateralCoeff.recipMul(
      realBaseAmount.add(baseDelevCoeff.mul(discountedQuoteDebtChange))
    );
    position.discountedBaseAmount = positionDisBaseCollateral.add(discountedBaseCollateralChange);
    discountedBaseCollateral = discountedBaseCollateral.add(discountedBaseCollateralChange);

    if (position._type == PositionType.Lend) {
      if (position.heapPosition != 0) revert Errors.WrongIndex();
      // init heap with default value 0, it will be updated by 'updateHeap' function later
      longHeap.insert(positions, MaxBinaryHeapLib.Node({key: 0, account: msg.sender}));
      position._type = PositionType.Long;
    }

    if (positionHasBadLeverage(position, basePrice)) revert Errors.BadLeverage();

    emit Long(msg.sender, realBaseAmount, swapPriceX96, discountedQuoteDebtChange, discountedBaseCollateralChange);
  }

  /// @notice sells all the base tokens from lend position for quote ones
  /// @dev no liquidity limit check since this function goes prior to 'short' call and it fail there anyway
  /// @dev you may consider adding that check here if this method is used in any other way
  function sellBaseForQuote(Position storage position, uint256 limitPriceX96, uint256 swapCalldata) private {
    PositionType _type = position._type;
    if (_type == PositionType.Uninitialized) revert Errors.UninitializedPosition();
    if (_type == PositionType.Short) return;

    bool isLong = _type == PositionType.Long;

    uint256 posDiscountedBaseColl = position.discountedBaseAmount;
    uint256 posDiscountedQuoteDebt = isLong ? position.discountedQuoteAmount : 0;
    uint256 baseAmountIn = calcRealBaseCollateral(posDiscountedBaseColl, posDiscountedQuoteDebt);
    if (baseAmountIn == 0) return;

    uint256 quoteAmountOut = swapExactInput(
      false,
      baseAmountIn,
      Math.mulDiv(limitPriceX96, baseAmountIn, FP96.Q96),
      swapCalldata
    );
    uint256 fee = Math.mulDiv(params.swapFee, quoteAmountOut, WHOLE_ONE);
    chargeFee(fee);

    uint256 quoteOutSubFee = quoteAmountOut.sub(fee);
    uint256 realQuoteDebt = quoteDebtCoeff.mul(posDiscountedQuoteDebt);
    uint256 discountedQuoteCollateralDelta = quoteCollateralCoeff.recipMul(quoteOutSubFee.sub(realQuoteDebt));

    discountedBaseCollateral -= posDiscountedBaseColl;
    position.discountedBaseAmount = 0;
    discountedQuoteCollateral += discountedQuoteCollateralDelta;
    if (isLong) {
      discountedQuoteDebt -= posDiscountedQuoteDebt;
      position.discountedQuoteAmount = discountedQuoteCollateralDelta;

      position._type = PositionType.Lend;
      uint32 heapIndex = position.heapPosition - 1;
      longHeap.remove(positions, heapIndex);
      emit QuoteDebtRepaid(msg.sender, realQuoteDebt, posDiscountedQuoteDebt);
    } else {
      position.discountedQuoteAmount += discountedQuoteCollateralDelta;
    }

    emit SellBaseForQuote(
      msg.sender,
      baseAmountIn,
      quoteOutSubFee,
      posDiscountedBaseColl,
      discountedQuoteCollateralDelta
    );
  }

  /// @notice sells all the quote tokens from lend position for base ones
  /// @dev no liquidity limit check since this function goes prior to 'long' call and it fail there anyway
  /// @dev you may consider adding that check here if this method is used in any other way
  function sellQuoteForBase(Position storage position, uint256 limitPriceX96, uint256 swapCalldata) private {
    PositionType _type = position._type;
    if (_type == PositionType.Uninitialized) revert Errors.UninitializedPosition();
    if (_type == PositionType.Long) return;

    bool isShort = _type == PositionType.Short;

    uint256 posDiscountedQuoteColl = position.discountedQuoteAmount;
    uint256 posDiscountedBaseDebt = isShort ? position.discountedBaseAmount : 0;
    uint256 quoteAmountIn = calcRealQuoteCollateral(posDiscountedQuoteColl, posDiscountedBaseDebt);
    if (quoteAmountIn == 0) return;

    uint256 fee = Math.mulDiv(params.swapFee, quoteAmountIn, WHOLE_ONE);
    uint256 quoteInSubFee = quoteAmountIn.sub(fee);

    uint256 baseAmountOut = swapExactInput(
      true,
      quoteInSubFee,
      Math.mulDiv(FP96.Q96, quoteInSubFee, limitPriceX96),
      swapCalldata
    );
    chargeFee(fee);

    uint256 realBaseDebt = baseDebtCoeff.mul(posDiscountedBaseDebt);
    uint256 discountedBaseCollateralDelta = baseCollateralCoeff.recipMul(baseAmountOut.sub(realBaseDebt));

    discountedQuoteCollateral -= posDiscountedQuoteColl;
    position.discountedQuoteAmount = 0;
    discountedBaseCollateral += discountedBaseCollateralDelta;
    if (isShort) {
      discountedBaseDebt -= posDiscountedBaseDebt;
      position.discountedBaseAmount = discountedBaseCollateralDelta;

      position._type = PositionType.Lend;
      uint32 heapIndex = position.heapPosition - 1;
      shortHeap.remove(positions, heapIndex);
      emit BaseDebtRepaid(msg.sender, realBaseDebt, posDiscountedBaseDebt);
    } else {
      position.discountedBaseAmount += discountedBaseCollateralDelta;
    }
    emit SellQuoteForBase(
      msg.sender,
      quoteInSubFee,
      baseAmountOut,
      posDiscountedQuoteColl,
      discountedBaseCollateralDelta
    );
  }

  /// @dev Update collateral and debt coeffs in system
  function accrueInterest() private returns (bool) {
    uint256 secondsPassed = getTimestamp() - lastReinitTimestampSeconds;
    if (secondsPassed == 0) {
      return false;
    }
    lastReinitTimestampSeconds = getTimestamp();

    FP96.FixedPoint memory secondsInYear = FP96.FixedPoint({inner: SECONDS_IN_YEAR_X96});
    FP96.FixedPoint memory interestRate = FP96.fromRatio(params.interestRate, WHOLE_ONE);
    FP96.FixedPoint memory onePlusFee = FP96.fromRatio(params.fee, WHOLE_ONE).div(secondsInYear).add(FP96.one());

    // FEE(dt) = (1 + fee)^dt
    FP96.FixedPoint memory feeDt = FP96.powTaylor(onePlusFee, secondsPassed);

    uint256 discountedBaseFee;
    uint256 discountedQuoteFee;

    if (discountedBaseCollateral != 0) {
      FP96.FixedPoint memory baseDebtCoeffPrev = baseDebtCoeff;
      uint256 realBaseDebtPrev = baseDebtCoeffPrev.mul(discountedBaseDebt);
      FP96.FixedPoint memory onePlusIR = interestRate
        .mul(FP96.FixedPoint({inner: systemLeverage.shortX96}))
        .div(secondsInYear)
        .add(FP96.one());

      // AR(dt) =  (1+ ir)^dt
      FP96.FixedPoint memory accruedRateDt = FP96.powTaylor(onePlusIR, secondsPassed);
      baseDebtCoeff = baseDebtCoeffPrev.mul(accruedRateDt).mul(feeDt);
      FP96.FixedPoint memory factor = FP96.one().add(
        FP96.fromRatio(
          accruedRateDt.sub(FP96.one()).mul(realBaseDebtPrev),
          calcRealBaseCollateral(discountedBaseCollateral, discountedQuoteDebt)
        )
      );
      updateBaseCollateralCoeffs(factor);
      discountedBaseFee = baseCollateralCoeff.recipMul(accruedRateDt.mul(feeDt.sub(FP96.one())).mul(realBaseDebtPrev));
    }

    if (discountedQuoteCollateral != 0) {
      FP96.FixedPoint memory quoteDebtCoeffPrev = quoteDebtCoeff;
      uint256 realQuoteDebtPrev = quoteDebtCoeffPrev.mul(discountedQuoteDebt);
      FP96.FixedPoint memory onePlusIR = interestRate
        .mul(FP96.FixedPoint({inner: systemLeverage.longX96}))
        .div(secondsInYear)
        .add(FP96.one());

      // AR(dt) =  (1+ ir)^dt
      FP96.FixedPoint memory accruedRateDt = FP96.powTaylor(onePlusIR, secondsPassed);
      quoteDebtCoeff = quoteDebtCoeffPrev.mul(accruedRateDt).mul(feeDt);
      FP96.FixedPoint memory factor = FP96.one().add(
        FP96.fromRatio(
          accruedRateDt.sub(FP96.one()).mul(realQuoteDebtPrev),
          calcRealQuoteCollateral(discountedQuoteCollateral, discountedBaseDebt)
        )
      );
      updateQuoteCollateralCoeffs(factor);
      discountedQuoteFee = quoteCollateralCoeff.recipMul(
        accruedRateDt.mul(feeDt.sub(FP96.one())).mul(realQuoteDebtPrev)
      );
    }

    // keep debt fee in technical position
    if (discountedBaseFee != 0 || discountedQuoteFee != 0) {
      Position storage techPosition = getTechPosition();
      techPosition.discountedBaseAmount = techPosition.discountedBaseAmount.add(discountedBaseFee);
      techPosition.discountedQuoteAmount = techPosition.discountedQuoteAmount.add(discountedQuoteFee);

      discountedBaseCollateral = discountedBaseCollateral.add(discountedBaseFee);
      discountedQuoteCollateral = discountedQuoteCollateral.add(discountedQuoteFee);
    }

    emit Reinit(lastReinitTimestampSeconds);

    return true;
  }

  /// @dev Accrue interest and try to reinit riskiest accounts (accounts on top of both heaps)
  function reinit() private returns (bool callerMarginCalled, FP96.FixedPoint memory basePrice) {
    basePrice = getBasePrice();
    if (!accrueInterest()) {
      return (callerMarginCalled, basePrice); // (false, basePrice)
    }

    (bool success, MaxBinaryHeapLib.Node memory root) = shortHeap.getNodeByIndex(0);
    if (success) {
      bool marginCallHappened = reinitAccount(root.account, basePrice);
      callerMarginCalled = marginCallHappened && root.account == msg.sender;
    }

    (success, root) = longHeap.getNodeByIndex(0);
    if (success) {
      bool marginCallHappened = reinitAccount(root.account, basePrice);
      callerMarginCalled = callerMarginCalled || (marginCallHappened && root.account == msg.sender); // since caller can be in short or long position
    }
  }

  function calcRealBaseCollateral(uint256 disBaseCollateral, uint256 disQuoteDebt) private view returns (uint256) {
    return baseCollateralCoeff.mul(disBaseCollateral).sub(baseDelevCoeff.mul(disQuoteDebt));
  }

  function calcRealQuoteCollateral(uint256 disQuoteCollateral, uint256 disBaseDebt) private view returns (uint256) {
    return quoteCollateralCoeff.mul(disQuoteCollateral).sub(quoteDelevCoeff.mul(disBaseDebt));
  }

  function newPoolBaseBalance(uint256 extraRealBaseCollateral) private view returns (uint256) {
    return
      calcRealBaseCollateral(discountedBaseCollateral, discountedQuoteDebt).add(extraRealBaseCollateral).sub(
        baseDebtCoeff.mul(discountedBaseDebt, Math.Rounding.Up)
      );
  }

  function newPoolQuoteBalance(uint256 extraRealQuoteCollateral) private view returns (uint256) {
    return
      calcRealQuoteCollateral(discountedQuoteCollateral, discountedBaseDebt).add(extraRealQuoteCollateral).sub(
        quoteDebtCoeff.mul(discountedQuoteDebt, Math.Rounding.Up)
      );
  }

  /// @dev Recalculates and saves user leverage and enact marginal if needed
  function reinitAccount(address user, FP96.FixedPoint memory basePrice) private returns (bool marginCallHappened) {
    Position storage position = positions[user];

    marginCallHappened = positionHasBadLeverage(position, basePrice);
    if (marginCallHappened) {
      liquidate(user, position, basePrice);
    }
  }

  function positionHasBadLeverage(
    Position storage position,
    FP96.FixedPoint memory basePrice
  ) private view returns (bool) {
    uint256 realTotalCollateral;
    uint256 realTotalDebt;
    if (position._type == PositionType.Short) {
      realTotalCollateral = calcRealQuoteCollateral(position.discountedQuoteAmount, position.discountedBaseAmount);
      realTotalDebt = baseDebtCoeff.mul(basePrice).mul(position.discountedBaseAmount);
    } else if (position._type == PositionType.Long) {
      realTotalCollateral = basePrice.mul(
        calcRealBaseCollateral(position.discountedBaseAmount, position.discountedQuoteAmount)
      );
      realTotalDebt = quoteDebtCoeff.mul(position.discountedQuoteAmount);
    } else {
      return false;
    }

    uint256 maxLeverageX96 = uint256(params.maxLeverage) << FP96.RESOLUTION;
    uint256 leverageX96 = calcLeverage(realTotalCollateral, realTotalDebt);
    return leverageX96 > maxLeverageX96;
  }

  function updateBaseCollateralCoeffs(FP96.FixedPoint memory factor) private {
    baseCollateralCoeff = baseCollateralCoeff.mul(factor);
    baseDelevCoeff = baseDelevCoeff.mul(factor);
  }

  function updateQuoteCollateralCoeffs(FP96.FixedPoint memory factor) private {
    quoteCollateralCoeff = quoteCollateralCoeff.mul(factor);
    quoteDelevCoeff = quoteDelevCoeff.mul(factor);
  }

  function updateHeap(Position storage position) private {
    if (position._type == PositionType.Long) {
      uint96 sortKey = calcSortKey(initialPrice.mul(position.discountedBaseAmount), position.discountedQuoteAmount);
      uint32 heapIndex = position.heapPosition - 1;
      longHeap.update(positions, heapIndex, sortKey);
    } else if (position._type == PositionType.Short) {
      uint96 sortKey = calcSortKey(position.discountedQuoteAmount, initialPrice.mul(position.discountedBaseAmount));
      uint32 heapIndex = position.heapPosition - 1;
      shortHeap.update(positions, heapIndex, sortKey);
    }
  }

  /// @notice Liquidate bad position and receive position collateral and debt
  /// @param badPositionAddress address of position to liquidate
  /// @param quoteAmount amount of quote token to be deposited
  /// @param baseAmount amount of base token to be deposited
  function receivePosition(address badPositionAddress, uint256 quoteAmount, uint256 baseAmount) private {
    if (mode != Mode.Regular) revert Errors.EmergencyMode();

    Position storage position = positions[msg.sender];
    if (position._type != PositionType.Uninitialized) revert Errors.PositionInitialized();

    accrueInterest();
    Position storage badPosition = positions[badPositionAddress];

    FP96.FixedPoint memory basePrice = getBasePrice();
    if (!positionHasBadLeverage(badPosition, basePrice)) revert Errors.NotLiquidatable();

    uint32 heapIndex = badPosition.heapPosition - 1;

    // previous require guarantees that position is either long or short
    if (badPosition._type == PositionType.Short) {
      uint256 discountedQuoteCollateralDelta = quoteCollateralCoeff.recipMul(quoteAmount);
      discountedQuoteCollateral = discountedQuoteCollateral.add(discountedQuoteCollateralDelta);
      position.discountedQuoteAmount = badPosition.discountedQuoteAmount.add(discountedQuoteCollateralDelta);

      uint256 badPositionBaseDebt = baseDebtCoeff.mul(badPosition.discountedBaseAmount);
      uint256 discountedBaseDebtDelta;
      if (baseAmount >= badPositionBaseDebt) {
        discountedBaseDebtDelta = badPosition.discountedBaseAmount;

        uint256 discountedBaseCollateralDelta = baseCollateralCoeff.recipMul(baseAmount.sub(badPositionBaseDebt));
        position.discountedBaseAmount = discountedBaseCollateralDelta;
        discountedBaseCollateral = discountedBaseCollateral.add(discountedBaseCollateralDelta);

        position._type = PositionType.Lend;

        shortHeap.remove(positions, heapIndex);
      } else {
        position._type = PositionType.Short;
        position.heapPosition = heapIndex + 1;
        discountedBaseDebtDelta = baseDebtCoeff.recipMul(baseAmount);
        position.discountedBaseAmount = badPosition.discountedBaseAmount.sub(discountedBaseDebtDelta);

        shortHeap.updateAccount(heapIndex, msg.sender);
      }

      discountedBaseDebt = discountedBaseDebt.sub(discountedBaseDebtDelta);
      discountedQuoteCollateralDelta = quoteCollateralCoeff.recipMul(quoteDelevCoeff.mul(discountedBaseDebtDelta));
      discountedQuoteCollateral -= discountedQuoteCollateralDelta;
      position.discountedQuoteAmount -= discountedQuoteCollateralDelta;
    } else {
      uint256 discountedBaseCollateralDelta = baseCollateralCoeff.recipMul(baseAmount);
      discountedBaseCollateral = discountedBaseCollateral.add(discountedBaseCollateralDelta);
      position.discountedBaseAmount = badPosition.discountedBaseAmount.add(discountedBaseCollateralDelta);

      uint256 badPositionQuoteDebt = quoteDebtCoeff.mul(badPosition.discountedQuoteAmount);
      uint256 discountedQuoteDebtDelta;
      if (quoteAmount >= badPositionQuoteDebt) {
        discountedQuoteDebtDelta = badPosition.discountedQuoteAmount;

        uint256 discountedQuoteCollateralDelta = quoteCollateralCoeff.recipMul(quoteAmount.sub(badPositionQuoteDebt));
        position.discountedQuoteAmount = discountedQuoteCollateralDelta;
        discountedQuoteCollateral = discountedQuoteCollateral.add(discountedQuoteCollateralDelta);

        position._type = PositionType.Lend;

        longHeap.remove(positions, heapIndex);
      } else {
        position._type = PositionType.Long;
        position.heapPosition = heapIndex + 1;
        discountedQuoteDebtDelta = quoteDebtCoeff.recipMul(quoteAmount);
        position.discountedQuoteAmount = badPosition.discountedQuoteAmount.sub(discountedQuoteDebtDelta);

        longHeap.updateAccount(heapIndex, msg.sender);
      }

      discountedQuoteDebt = discountedQuoteDebt.sub(discountedQuoteDebtDelta);
      discountedBaseCollateralDelta = baseCollateralCoeff.recipMul(baseDelevCoeff.mul(discountedQuoteDebtDelta));
      discountedBaseCollateral -= discountedBaseCollateralDelta;
      position.discountedBaseAmount -= discountedBaseCollateralDelta;
    }

    updateHeap(position);

    updateSystemLeverages(basePrice);

    delete positions[badPositionAddress];

    if (positionHasBadLeverage(position, basePrice)) revert Errors.BadLeverage();
    wrapAndTransferFrom(baseToken, msg.sender, baseAmount);
    wrapAndTransferFrom(quoteToken, msg.sender, quoteAmount);

    emit ReceivePosition(
      msg.sender,
      badPositionAddress,
      position._type,
      position.discountedQuoteAmount,
      position.discountedBaseAmount
    );
  }

  /// @inheritdoc IMarginlyPoolOwnerActions
  function shutDown(uint256 swapCalldata) external onlyFactoryOwner lock {
    if (mode != Mode.Regular) revert Errors.EmergencyMode();
    accrueInterest();

    syncBaseBalance();
    syncQuoteBalance();

    FP96.FixedPoint memory basePrice = getBasePrice();

    /* We use Rounding.Up in baseDebt/quoteDebt calculation 
       to avoid case when "surplus = quoteCollateral - quoteDebt"
       a bit more than IERC20(quoteToken).balanceOf(address(this))
     */

    uint256 baseDebt = baseDebtCoeff.mul(discountedBaseDebt, Math.Rounding.Up);
    uint256 quoteCollateral = calcRealQuoteCollateral(discountedQuoteCollateral, discountedBaseDebt);

    uint256 quoteDebt = quoteDebtCoeff.mul(discountedQuoteDebt, Math.Rounding.Up);
    uint256 baseCollateral = calcRealBaseCollateral(discountedBaseCollateral, discountedQuoteDebt);

    if (basePrice.mul(baseDebt) > quoteCollateral) {
      // removing all non-emergency position with bad leverages (negative net positions included)
      (bool success, MaxBinaryHeapLib.Node memory root) = longHeap.getNodeByIndex(0);
      if (success) {
        if (reinitAccount(root.account, basePrice)) {
          return;
        }
      }

      setEmergencyMode(
        Mode.ShortEmergency,
        basePrice,
        baseCollateral,
        baseDebt,
        quoteCollateral,
        quoteDebt,
        swapCalldata
      );
      return;
    }

    if (quoteDebt > basePrice.mul(baseCollateral)) {
      // removing all non-emergency position with bad leverages (negative net positions included)
      (bool success, MaxBinaryHeapLib.Node memory root) = shortHeap.getNodeByIndex(0);
      if (success) {
        if (reinitAccount(root.account, basePrice)) {
          return;
        }
      }

      setEmergencyMode(
        Mode.LongEmergency,
        basePrice,
        quoteCollateral,
        quoteDebt,
        baseCollateral,
        baseDebt,
        swapCalldata
      );
      return;
    }

    revert Errors.NotEmergency();
  }

  ///@dev Set emergency mode and calc emergencyWithdrawCoeff
  function setEmergencyMode(
    Mode _mode,
    FP96.FixedPoint memory shutDownPrice,
    uint256 collateral,
    uint256 debt,
    uint256 emergencyCollateral,
    uint256 emergencyDebt,
    uint256 swapCalldata
  ) private {
    mode = _mode;
    initialPrice = shutDownPrice;

    uint256 balance = collateral >= debt ? collateral.sub(debt) : 0;

    if (emergencyCollateral > emergencyDebt) {
      uint256 surplus = emergencyCollateral.sub(emergencyDebt);

      uint256 collateralSurplus = swapExactInput(_mode == Mode.ShortEmergency, surplus, 0, swapCalldata);

      balance = balance.add(collateralSurplus);
    }

    if (mode == Mode.ShortEmergency) {
      // coeff = price * baseBalance / (price * baseCollateral - quoteDebt)
      emergencyWithdrawCoeff = FP96.fromRatio(
        shutDownPrice.mul(balance),
        shutDownPrice.mul(collateral).sub(emergencyDebt)
      );
    } else {
      // coeff = quoteBalance / (quoteCollateral - price * baseDebt)
      emergencyWithdrawCoeff = FP96.fromRatio(balance, collateral.sub(shutDownPrice.mul(emergencyDebt)));
    }

    emit Emergency(_mode);
  }

  /// @notice Withdraw position collateral in emergency mode
  /// @param unwrapWETH flag to unwrap WETH to ETH
  function emergencyWithdraw(bool unwrapWETH) private {
    if (mode == Mode.Regular) revert Errors.NotEmergency();

    Position memory position = positions[msg.sender];
    if (position._type == PositionType.Uninitialized) revert Errors.UninitializedPosition();

    address token;
    uint256 transferAmount;

    if (mode == Mode.ShortEmergency) {
      if (position._type == PositionType.Short) revert Errors.ShortEmergency();

      // baseNet =  baseColl - quoteDebt / price
      uint256 positionBaseNet = calcRealBaseCollateral(position.discountedBaseAmount, position.discountedQuoteAmount)
        .sub(initialPrice.recipMul(quoteDebtCoeff.mul(position.discountedQuoteAmount)));
      transferAmount = emergencyWithdrawCoeff.mul(positionBaseNet);
      token = baseToken;
    } else {
      if (position._type == PositionType.Long) revert Errors.LongEmergency();

      // quoteNet = quoteColl - baseDebt * price
      uint256 positionQuoteNet = calcRealQuoteCollateral(position.discountedQuoteAmount, position.discountedBaseAmount)
        .sub(baseDebtCoeff.mul(initialPrice).mul(position.discountedBaseAmount));
      transferAmount = emergencyWithdrawCoeff.mul(positionQuoteNet);
      token = quoteToken;
    }

    delete positions[msg.sender];
    unwrapAndTransfer(unwrapWETH, token, msg.sender, transferAmount);

    emit EmergencyWithdraw(msg.sender, token, transferAmount);
  }

  function updateSystemLeverageLong(FP96.FixedPoint memory basePrice) private {
    if (discountedBaseCollateral == 0) {
      systemLeverage.longX96 = uint128(FP96.Q96);
      return;
    }

    uint256 realBaseCollateral = basePrice.mul(calcRealBaseCollateral(discountedBaseCollateral, discountedQuoteDebt));
    uint256 realQuoteDebt = quoteDebtCoeff.mul(discountedQuoteDebt);
    uint128 leverageX96 = uint128(Math.mulDiv(FP96.Q96, realBaseCollateral, realBaseCollateral.sub(realQuoteDebt)));
    uint128 maxLeverageX96 = uint128(params.maxLeverage) << FP96.RESOLUTION;
    systemLeverage.longX96 = leverageX96 < maxLeverageX96 ? leverageX96 : maxLeverageX96;
  }

  function updateSystemLeverageShort(FP96.FixedPoint memory basePrice) private {
    if (discountedQuoteCollateral == 0) {
      systemLeverage.shortX96 = uint128(FP96.Q96);
      return;
    }

    uint256 realQuoteCollateral = calcRealQuoteCollateral(discountedQuoteCollateral, discountedBaseDebt);
    uint256 realBaseDebt = baseDebtCoeff.mul(basePrice).mul(discountedBaseDebt);
    uint128 leverageX96 = uint128(Math.mulDiv(FP96.Q96, realQuoteCollateral, realQuoteCollateral.sub(realBaseDebt)));
    uint128 maxLeverageX96 = uint128(params.maxLeverage) << FP96.RESOLUTION;
    systemLeverage.shortX96 = leverageX96 < maxLeverageX96 ? leverageX96 : maxLeverageX96;
  }

  function updateSystemLeverages(FP96.FixedPoint memory basePrice) private {
    updateSystemLeverageLong(basePrice);
    updateSystemLeverageShort(basePrice);
  }

  /// @dev Wraps ETH into WETH if need and makes transfer from `payer`
  function wrapAndTransferFrom(address token, address payer, uint256 value) private {
    if (msg.value >= value) {
      if (token == getWETH9Address()) {
        IWETH9(token).deposit{value: value}();
        return;
      }
    }
    TransferHelper.safeTransferFrom(token, payer, address(this), value);
  }

  /// @dev Unwraps WETH to ETH and makes transfer to `recipient`
  function unwrapAndTransfer(bool unwrapWETH, address token, address recipient, uint256 value) private {
    if (unwrapWETH) {
      if (token == getWETH9Address()) {
        IWETH9(token).withdraw(value);
        TransferHelper.safeTransferETH(recipient, value);
        return;
      }
    }
    TransferHelper.safeTransfer(token, recipient, value);
  }

  /// @inheritdoc IMarginlyPoolOwnerActions
  function sweepETH() external override onlyFactoryOwner {
    if (address(this).balance > 0) {
      TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }
  }

  /// @dev Changes tech position base collateral so total calculated base balance to be equal to actual
  function syncBaseBalance() private {
    uint256 baseBalance = getBalance(baseToken);
    uint256 actualBaseCollateral = baseDebtCoeff.mul(discountedBaseDebt).add(baseBalance);
    uint256 baseCollateral = calcRealBaseCollateral(discountedBaseCollateral, discountedQuoteDebt);
    Position storage techPosition = getTechPosition();
    if (actualBaseCollateral > baseCollateral) {
      uint256 discountedBaseDelta = baseCollateralCoeff.recipMul(actualBaseCollateral.sub(baseCollateral));
      techPosition.discountedBaseAmount += discountedBaseDelta;
      discountedBaseCollateral += discountedBaseDelta;
    } else {
      uint256 discountedBaseDelta = baseCollateralCoeff.recipMul(baseCollateral.sub(actualBaseCollateral));
      techPosition.discountedBaseAmount -= discountedBaseDelta;
      discountedBaseCollateral -= discountedBaseDelta;
    }
  }

  /// @dev Changes tech position quote collateral so total calculated quote balance to be equal to actual
  function syncQuoteBalance() private {
    uint256 quoteBalance = getBalance(quoteToken);
    uint256 actualQuoteCollateral = quoteDebtCoeff.mul(discountedQuoteDebt).add(quoteBalance);
    uint256 quoteCollateral = calcRealQuoteCollateral(discountedQuoteCollateral, discountedBaseDebt);
    Position storage techPosition = getTechPosition();
    if (actualQuoteCollateral > quoteCollateral) {
      uint256 discountedQuoteDelta = quoteCollateralCoeff.recipMul(actualQuoteCollateral.sub(quoteCollateral));
      techPosition.discountedQuoteAmount += discountedQuoteDelta;
      discountedQuoteCollateral += discountedQuoteDelta;
    } else {
      uint256 discountedQuoteDelta = quoteCollateralCoeff.recipMul(quoteCollateral.sub(actualQuoteCollateral));
      techPosition.discountedQuoteAmount -= discountedQuoteDelta;
      discountedQuoteCollateral -= discountedQuoteDelta;
    }
  }

  /// @dev Used by keeper service
  function getHeapPosition(
    uint32 index,
    bool _short
  ) external view returns (bool success, MaxBinaryHeapLib.Node memory) {
    if (_short) {
      return shortHeap.getNodeByIndex(index);
    } else {
      return longHeap.getNodeByIndex(index);
    }
  }

  /// @dev Returns Uniswap SwapRouter address
  function getSwapRouter() private view returns (address) {
    return IMarginlyFactory(factory).swapRouter();
  }

  /// @dev Calculate swap price in Q96
  function getSwapPrice(uint256 quoteAmount, uint256 baseAmount) private pure returns (uint256) {
    return Math.mulDiv(quoteAmount, FP96.Q96, baseAmount);
  }

  /// @dev Returns tech position
  function getTechPosition() private view returns (Position storage) {
    return positions[IMarginlyFactory(factory).techPositionOwner()];
  }

  /// @dev Returns WETH9 address
  function getWETH9Address() private view returns (address) {
    return IMarginlyFactory(factory).WETH9();
  }

  /// @dev returns ERC20 token balance of this contract
  function getBalance(address erc20Token) private view returns (uint256) {
    return IERC20(erc20Token).balanceOf(address(this));
  }

  /// @param flag unwrapETH in case of withdraw calls or syncBalance in case of reinit call
  function execute(
    CallType call,
    uint256 amount1,
    int256 amount2,
    uint256 limitPriceX96,
    bool flag,
    address receivePositionAddress,
    uint256 swapCalldata
  ) external payable override lock {
    if (call == CallType.ReceivePosition) {
      if (amount2 < 0) revert Errors.WrongValue();
      receivePosition(receivePositionAddress, amount1, uint256(amount2));
      return;
    } else if (call == CallType.EmergencyWithdraw) {
      emergencyWithdraw(flag);
      return;
    }

    if (mode != Mode.Regular) revert Errors.EmergencyMode();

    (bool callerMarginCalled, FP96.FixedPoint memory basePrice) = reinit();
    if (callerMarginCalled) {
      updateSystemLeverages(basePrice);
      return;
    }

    Position storage position = positions[msg.sender];

    if (positionHasBadLeverage(position, basePrice)) {
      liquidate(msg.sender, position, basePrice);
      updateSystemLeverages(basePrice);
      return;
    }

    if (call == CallType.DepositBase) {
      depositBase(amount1, basePrice, position);
      if (amount2 > 0) {
        long(uint256(amount2), limitPriceX96, basePrice, position, swapCalldata);
      } else if (amount2 < 0) {
        short(uint256(-amount2), limitPriceX96, basePrice, position, swapCalldata);
      }
    } else if (call == CallType.DepositQuote) {
      depositQuote(amount1, position);
      if (amount2 > 0) {
        short(uint256(amount2), limitPriceX96, basePrice, position, swapCalldata);
      } else if (amount2 < 0) {
        long(uint256(-amount2), limitPriceX96, basePrice, position, swapCalldata);
      }
    } else if (call == CallType.WithdrawBase) {
      withdrawBase(amount1, flag, basePrice, position);
    } else if (call == CallType.WithdrawQuote) {
      withdrawQuote(amount1, flag, basePrice, position);
    } else if (call == CallType.Short) {
      short(amount1, limitPriceX96, basePrice, position, swapCalldata);
    } else if (call == CallType.Long) {
      long(amount1, limitPriceX96, basePrice, position, swapCalldata);
    } else if (call == CallType.ClosePosition) {
      closePosition(limitPriceX96, position, swapCalldata);
    } else if (call == CallType.Reinit && flag) {
      // reinit itself has already taken place
      syncBaseBalance();
      syncQuoteBalance();
      emit BalanceSync();
    }

    updateHeap(position);

    updateSystemLeverages(basePrice);
  }

  function getTimestamp() internal view virtual returns (uint256) {
    return block.timestamp;
  }
}