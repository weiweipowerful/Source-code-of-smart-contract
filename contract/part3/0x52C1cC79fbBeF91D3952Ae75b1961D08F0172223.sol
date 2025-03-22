// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

// OpenZeppelin
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/access/manager/AccessManaged.sol';
import '@openzeppelin/contracts/utils/Multicall.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

// Libary
import './lib/Constants.sol';
import './lib/Farms.sol';
import './lib/uniswap/PoolAddress.sol';
import './lib/uniswap/LiquidityAmounts.sol';
import './lib/uniswap/PositionValue.sol';

// Interfaces
import './interfaces/IIncentiveToken.sol';
import './interfaces/IFarmKeeper.sol';

// Other Contracts
import './UniversalBuyAndBurn.sol';

/**
 * @title FarmKeeper: A Uniswap V3 Farming Protocol
 * @notice Manages liquidity farms for Uniswap V3 pools with integrated buy-and-burn mechanism
 * @dev Inspired by MasterChef, adapted for Uniswap V3 and Universal Buy And Burn
 *
 *  ███████╗ █████╗ ██████╗ ███╗   ███╗██╗  ██╗███████╗███████╗██████╗ ███████╗██████╗
 *  ██╔════╝██╔══██╗██╔══██╗████╗ ████║██║ ██╔╝██╔════╝██╔════╝██╔══██╗██╔════╝██╔══██╗
 *  █████╗  ███████║██████╔╝██╔████╔██║█████╔╝ █████╗  █████╗  ██████╔╝█████╗  ██████╔╝
 *  ██╔══╝  ██╔══██║██╔══██╗██║╚██╔╝██║██╔═██╗ ██╔══╝  ██╔══╝  ██╔═══╝ ██╔══╝  ██╔══██╗
 *  ██║     ██║  ██║██║  ██║██║ ╚═╝ ██║██║  ██╗███████╗███████╗██║     ███████╗██║  ██║
 *  ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝
 *
 *
 * Key Features:
 * 1. Uniswap V3 Compatibility: Manages farms for Uniswap V3 liquidity positions
 * 2. Flexible Reward System: Distributes incentive tokens as rewards based on liquidity provision
 * 3. Fee Collection: Collects and distributes fees from Uniswap V3 positions
 * 4. Buy-and-Burn Integration: Automatically sends collected fees to a buy-and-burn mechanism
 * 5. Protocol Fee: Allows for collection of protocol fees on each farm
 *
 * How it works:
 * - Users deposit liquidity into farms, receiving a share of the farm's total liquidity
 * - The contract manages a single Uniswap V3 position for each farm
 * - Rewards (incentive tokens) are minted and distributed based on users' liquidity share and time
 * - Fees collected from Uniswap V3 positions are:
 *   a) Sent to the buy-and-burn contract for designated input tokens
 *   b) Distributed to users for non-input tokens
 * - Users can withdraw their liquidity and claim rewards at any time
 *
 * Security features:
 * - Access control using OpenZeppelin's AccessManaged
 * - Reentrancy protection through function ordering and ReentrancyGuard
 * - Slippage protection for liquidity operations
 */
contract FarmKeeper is IFarmKeeper, AccessManaged, Multicall, ReentrancyGuard {
  using Farms for Farms.Map;
  using SafeERC20 for IERC20;

  // -----------------------------------------
  // Type declarations
  // -----------------------------------------
  struct AddFarmParams {
    address tokenA;
    address tokenB;
    uint24 fee;
    uint56 allocPoints;
    uint256 protocolFee;
    uint32 priceTwa;
    uint256 slippage;
  }

  // -----------------------------------------
  // State variables
  // -----------------------------------------
  /** @notice The farms managed by this contract */
  Farms.Map private _farms;

  /** @notice Accumulated protocol fees for each token */
  mapping(address token => uint256 amount) public protocolFees;

  /** @notice Indicates if the contract has been successfully initialized */
  bool public initialized;

  /** @notice The start time of all farms */
  uint256 public startTime;

  /** @notice The IncentiveToken contract */
  IIncentiveToken public incentiveToken;

  /** @notice The TINC buy and burn contract */
  UniversalBuyAndBurn public buyAndBurn;

  /** @notice Total allocation points across all farms */
  uint256 public totalAllocPoints;
  // -----------------------------------------
  // Events
  // -----------------------------------------
  event FarmEnabled(address indexed id, AddFarmParams params);
  event FeeDistributed(address indexed id, address indexed user, address indexed token, uint256 amount);
  event IncentiveTokenDistributed(address indexed id, address indexed user, uint256 amount);
  event Deposit(
    address indexed id,
    address indexed user,
    uint128 liquidity,
    uint256 amountToken0,
    uint256 amountToken1
  );
  event Withdraw(
    address indexed id,
    address indexed user,
    uint256 liquidity,
    uint256 amountToken0,
    uint256 amountToken1
  );
  event ProtocolFeesCollected(address indexed token, uint256 amount);

  event SlippageUpdated(address indexed id, uint256 newSlippage);
  event PriceTwaUpdated(address indexed id, uint32 newTwa);
  event ProtocolFeeUpdated(address indexed id, uint256 newFee);
  event AllocationUpdated(address indexed id, uint256 allocPoints);

  // -----------------------------------------
  // Errors
  // -----------------------------------------
  error InvalidLiquidityAmount();
  error InvalidPriceTwa();
  error InvalidSlippage();
  error InvalidFee();
  error InvalidAllocPoints();
  error InvalidTokenId();
  error InvalidFarmId();
  error AlreadyInitialized();
  error InvalidIncentiveToken();
  error DuplicatedFarm();
  error TotalAllocationCannotBeZero();

  // -----------------------------------------
  // Modifiers
  // -----------------------------------------

  // -----------------------------------------
  // Constructor
  // -----------------------------------------
  /**
   * @notice Creates a new instance of the contract
   * @param incentiveTokenAddress The address of the Incentive Token contract
   * @param universalBuyAndBurnAddress The address of the Universal Buy And Burn contract
   * @param manager The address of the Access Manager contract
   */
  constructor(
    address incentiveTokenAddress,
    address universalBuyAndBurnAddress,
    address manager
  ) AccessManaged(manager) {
    incentiveToken = IIncentiveToken(incentiveTokenAddress);
    buyAndBurn = UniversalBuyAndBurn(universalBuyAndBurnAddress);
  }

  // -----------------------------------------
  // Receive function
  // -----------------------------------------

  // -----------------------------------------
  // Fallback function
  // -----------------------------------------

  // -----------------------------------------
  // External functions
  // -----------------------------------------
  /**
   * @notice Initializes the FarmKeeper contract
   * @dev Can only be called once and must be called by the contract manager after ownership of
   * the incentive token has been successfully transfered to the farm keeper.
   */
  function initialize() external restricted {
    if (initialized) revert AlreadyInitialized();
    if (incentiveToken.owner() != address(this)) revert InvalidIncentiveToken();
    initialized = true;

    uint256 currentTimestamp = block.timestamp;
    uint256 secondsUntilMidnight = 86400 - (currentTimestamp % 86400);

    // Farming begins at midnight UTC
    startTime = currentTimestamp + secondsUntilMidnight;
  }

  /**
   * @notice Allows a user to deposit liquidity into a farm
   * Setting liquidity to zero allows to pull fees and incentive tokens
   * without modifying the liquidity position by the user.
   * @param id The ID of the farm to deposit into
   * @param liquidity The amount of liquidity to deposit
   * @param deadline The Unix timestamp by which the transaction must be confirmed.
   * If the transaction is pending in the mempool beyond this time, it will revert,
   * preventing any further interaction with the Uniswap LP position.
   */
  function deposit(address id, uint128 liquidity, uint256 deadline) external nonReentrant {
    if (!_farms.contains(id)) revert InvalidFarmId();

    Farm storage farm = _farms.get(id);
    User storage user = _farms.user(id, msg.sender);

    // Update farm and collect fees
    _updateFarm(farm, true);

    // Distribute pending rewards and fees
    uint256 pendingIncentiveTokens = Math.mulDiv(
      user.liquidity,
      farm.accIncentiveTokenPerShare,
      Constants.SCALE_FACTOR_1E12
    ) - user.rewardCheckpoint;
    uint256 pendingFeeToken0 = Math.mulDiv(user.liquidity, farm.accFeePerShareForToken0, Constants.SCALE_FACTOR_1E18) -
      user.feeCheckpointToken0;
    uint256 pendingFeeToken1 = Math.mulDiv(user.liquidity, farm.accFeePerShareForToken1, Constants.SCALE_FACTOR_1E18) -
      user.feeCheckpointToken1;

    uint128 addedLiquidity = 0;
    uint256 amountToken0 = 0;
    uint256 amountToken1 = 0;

    // Allow to call this function without modifying liquidity
    // to pull rewards only
    if (liquidity > 0) {
      if (farm.lp.tokenId == 0) {
        // Create LP position and refund caller
        (addedLiquidity, amountToken0, amountToken1) = _createLiquidityPosition(farm, liquidity, deadline);
      } else {
        // Add liquidity to existing position
        (addedLiquidity, amountToken0, amountToken1) = _addLiquidity(farm, liquidity, deadline);
      }
    }

    // Update state
    user.liquidity += addedLiquidity;
    user.rewardCheckpoint = Math.mulDiv(user.liquidity, farm.accIncentiveTokenPerShare, Constants.SCALE_FACTOR_1E12);
    user.feeCheckpointToken0 = Math.mulDiv(user.liquidity, farm.accFeePerShareForToken0, Constants.SCALE_FACTOR_1E18);
    user.feeCheckpointToken1 = Math.mulDiv(user.liquidity, farm.accFeePerShareForToken1, Constants.SCALE_FACTOR_1E18);

    // Payout pending tokens
    if (pendingIncentiveTokens > 0) {
      incentiveToken.mint(msg.sender, pendingIncentiveTokens);
      emit IncentiveTokenDistributed(id, msg.sender, pendingIncentiveTokens);
    }
    if (pendingFeeToken0 > 0) {
      _safeTransferToken(farm.poolKey.token0, msg.sender, pendingFeeToken0);
      emit FeeDistributed(id, msg.sender, farm.poolKey.token0, pendingFeeToken0);
    }
    if (pendingFeeToken1 > 0) {
      _safeTransferToken(farm.poolKey.token1, msg.sender, pendingFeeToken1);
      emit FeeDistributed(id, msg.sender, farm.poolKey.token1, pendingFeeToken1);
    }

    emit Deposit(id, msg.sender, liquidity, amountToken0, amountToken1);
  }

  /**
   * @notice Allows a user to withdraw liquidity from a farm
   * To harvest incentive tokens and fees, call `deposit` with liquidity amount of 0.
   * @param id The ID of the farm to withdraw from
   * @param liquidity The amount of liquidity to withdraw
   * @param deadline The Unix timestamp by which the transaction must be confirmed.
   * If the transaction is pending in the mempool beyond this time, it will revert,
   * preventing any further interaction with the Uniswap LP position.
   */
  function withdraw(address id, uint128 liquidity, uint256 deadline) external nonReentrant {
    if (!_farms.contains(id)) revert InvalidFarmId();

    Farm storage farm = _farms.get(id);
    User storage user = _farms.user(id, msg.sender);

    if (user.liquidity < liquidity || liquidity == 0) {
      revert InvalidLiquidityAmount();
    }

    // Update farms and collect fees
    _updateFarm(farm, true);

    // Calculate pending rewards and fees
    uint256 pendingIncentiveTokens = Math.mulDiv(
      user.liquidity,
      farm.accIncentiveTokenPerShare,
      Constants.SCALE_FACTOR_1E12
    ) - user.rewardCheckpoint;
    uint256 pendingFeeToken0 = Math.mulDiv(user.liquidity, farm.accFeePerShareForToken0, Constants.SCALE_FACTOR_1E18) -
      user.feeCheckpointToken0;
    uint256 pendingFeeToken1 = Math.mulDiv(user.liquidity, farm.accFeePerShareForToken1, Constants.SCALE_FACTOR_1E18) -
      user.feeCheckpointToken1;

    // Update state
    user.liquidity -= liquidity;
    user.rewardCheckpoint = Math.mulDiv(user.liquidity, farm.accIncentiveTokenPerShare, Constants.SCALE_FACTOR_1E12);
    user.feeCheckpointToken0 = Math.mulDiv(user.liquidity, farm.accFeePerShareForToken0, Constants.SCALE_FACTOR_1E18);
    user.feeCheckpointToken1 = Math.mulDiv(user.liquidity, farm.accFeePerShareForToken1, Constants.SCALE_FACTOR_1E18);

    // Decrease liquidity
    (uint256 amountToken0, uint256 amountToken1) = _decreaseLiquidity(farm, liquidity, msg.sender, deadline);

    // Payout pending tokens
    if (pendingIncentiveTokens > 0) {
      // Mint Incentive Tokens to user
      incentiveToken.mint(msg.sender, pendingIncentiveTokens);
      emit IncentiveTokenDistributed(id, msg.sender, pendingIncentiveTokens);
    }
    if (pendingFeeToken0 > 0) {
      _safeTransferToken(farm.poolKey.token0, msg.sender, pendingFeeToken0);
      emit FeeDistributed(id, msg.sender, farm.poolKey.token0, pendingFeeToken0);
    }
    if (pendingFeeToken1 > 0) {
      _safeTransferToken(farm.poolKey.token1, msg.sender, pendingFeeToken1);
      emit FeeDistributed(id, msg.sender, farm.poolKey.token1, pendingFeeToken1);
    }

    emit Withdraw(id, msg.sender, liquidity, amountToken0, amountToken1);
  }

  /**
   * @notice Updates a specific farm and collect fees
   * @param id The ID of the farm to update
   * @param collectFees collect trading fees accumulated by the liquidity provided
   */
  function updateFarm(address id, bool collectFees) external nonReentrant {
    if (!_farms.contains(id)) revert InvalidFarmId();

    Farm storage farm = _farms.get(id);
    _updateFarm(farm, collectFees);
  }

  /**
   * @notice Enables a new farm
   * @param params The parameters for the new farm
   */
  function enableFarm(AddFarmParams calldata params) external restricted {
    PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(params.tokenA, params.tokenB, params.fee);

    // Compute pool address to check for duplicates
    address id = PoolAddress.computeAddress(Constants.FACTORY, poolKey);

    // Check for duplicates
    if (_farms.contains(id)) revert DuplicatedFarm();

    _validateAllocPoints(params.allocPoints);
    _validatePriceTwa(params.priceTwa);
    _validateSlippage(params.slippage);
    _validateProtocolFee(params.protocolFee);

    // Ensure valid allocations points when enabling a farm
    if (totalAllocPoints + params.allocPoints <= 0) revert InvalidAllocPoints();

    // Update all farms but do not collect fees as only
    // the incentive token allocations are affected by enabling a new farm
    massUpdateFarms(false);

    // Append new farm
    _farms.add(
      Farm({
        id: id,
        poolKey: poolKey,
        lp: LP({tokenId: 0, liquidity: 0}),
        allocPoints: params.allocPoints,
        lastRewardTime: block.timestamp > startTime ? block.timestamp : startTime,
        accIncentiveTokenPerShare: 0,
        accFeePerShareForToken0: 0,
        accFeePerShareForToken1: 0,
        protocolFee: params.protocolFee,
        priceTwa: params.priceTwa,
        slippage: params.slippage
      })
    );

    totalAllocPoints += params.allocPoints;
    emit FarmEnabled(id, params);
  }

  /**
   * @notice Sets the slippage percentage for buy and burn minimum received amount
   * @param id The ID of the farm to update
   * @param slippage The new slippage value (from 0% to 15%)
   */
  function setSlippage(address id, uint256 slippage) external restricted {
    if (!_farms.contains(id)) revert InvalidFarmId();

    _validateSlippage(slippage);
    _farms.get(id).slippage = slippage;
    emit SlippageUpdated(id, slippage);
  }

  /**
   * @notice Sets the TWA value used for requesting quotes
   * @param id The ID of the farm to update
   * @param mins TWA in minutes
   */
  function setPriceTwa(address id, uint32 mins) external restricted {
    if (!_farms.contains(id)) revert InvalidFarmId();

    _validatePriceTwa(mins);
    _farms.get(id).priceTwa = mins;
    emit PriceTwaUpdated(id, mins);
  }

  /**
   * @notice Sets the protocol fee for a farm
   * @param id The ID of the farm to update
   * @param fee The new protocol fee
   */
  function setProtocolFee(address id, uint256 fee) external restricted {
    if (!_farms.contains(id)) revert InvalidFarmId();

    _validateProtocolFee(fee);
    Farm storage farm = _farms.get(id);

    // collect fees and distribute with the old protocol fee
    // before the new setting takes effect
    _updateFarm(farm, true);
    farm.protocolFee = fee;

    emit ProtocolFeeUpdated(id, fee);
  }

  /**
   * @notice Collect accumulated protocol fees for a specific token
   * @param token The address of the token to withdraw fees for
   */
  function collectProtocolFee(address token) external restricted {
    uint256 protocolFee = protocolFees[token];
    protocolFees[token] = 0;

    if (protocolFee > 0) {
      IERC20(token).safeTransfer(msg.sender, protocolFee);
    }

    emit ProtocolFeesCollected(token, protocolFee);
  }

  /**
   * @notice Updates the allocation points for a given farm
   * @param id The ID of the farm to update
   * @param allocPoints The new allocation points
   */
  function setAllocation(address id, uint256 allocPoints) external restricted {
    if (!_farms.contains(id)) revert InvalidFarmId();

    _validateAllocPoints(allocPoints);
    Farm storage farm = _farms.get(id);

    // Update all farms but do not collect fees as only
    // the INC token distribution is affected by modifying allocations
    massUpdateFarms(false);

    if (farm.allocPoints > allocPoints) {
      if (totalAllocPoints - (farm.allocPoints - allocPoints) <= 0) revert TotalAllocationCannotBeZero();
    }

    totalAllocPoints = totalAllocPoints - farm.allocPoints + allocPoints;
    farm.allocPoints = allocPoints;

    emit AllocationUpdated(id, allocPoints);
  }

  /**
   * @notice Retrieves all farms
   * @return An array of all Farms
   */
  function farmViews() external view returns (FarmView[] memory) {
    Farm[] memory farms = _farms.values();
    FarmView[] memory views = new FarmView[](farms.length);

    for (uint256 idx = 0; idx < farms.length; idx++) {
      views[idx] = farmView(farms[idx].id);
    }

    return views;
  }

  /**
   * @notice Retrieves a user view for a specific farm
   * @param id The ID of the farm
   * @param userId The address of the user
   * @return A UserView struct with the user's farm information
   */
  function userView(address id, address userId) external view returns (UserView memory) {
    if (!_farms.contains(id)) revert InvalidFarmId();

    Farm storage farm = _farms.get(id);
    User storage user = _farms.user(id, userId);

    if (user.liquidity == 0) {
      return
        UserView({
          token0: farm.poolKey.token0,
          token1: farm.poolKey.token1,
          liquidity: user.liquidity,
          balanceToken0: 0,
          balanceToken1: 0,
          pendingFeeToken0: 0,
          pendingFeeToken1: 0,
          pendingIncentiveTokens: 0
        });
    }

    (
      uint256 accIncentiveTokenPerShare,
      uint256 accFeePerShareForToken0,
      uint256 accFeePerShareForToken1
    ) = _getSharesAtBlockTimestamp(farm);

    (uint160 slotPrice, ) = _getTwaPrice(farm.id, 0);
    (uint256 balanceToken0, uint256 balanceToken1) = LiquidityAmounts.getAmountsForLiquidity(
      slotPrice,
      TickMath.getSqrtRatioAtTick(Constants.MIN_TICK),
      TickMath.getSqrtRatioAtTick(Constants.MAX_TICK),
      user.liquidity
    );

    return
      UserView({
        token0: farm.poolKey.token0,
        token1: farm.poolKey.token1,
        liquidity: user.liquidity,
        balanceToken0: balanceToken0,
        balanceToken1: balanceToken1,
        pendingFeeToken0: Math.mulDiv(user.liquidity, accFeePerShareForToken0, Constants.SCALE_FACTOR_1E18) -
          user.feeCheckpointToken0,
        pendingFeeToken1: Math.mulDiv(user.liquidity, accFeePerShareForToken1, Constants.SCALE_FACTOR_1E18) -
          user.feeCheckpointToken1,
        pendingIncentiveTokens: Math.mulDiv(user.liquidity, accIncentiveTokenPerShare, Constants.SCALE_FACTOR_1E12) -
          user.rewardCheckpoint
      });
  }

  /**
   * @notice Calculates the token amounts required for a given liquidity amount
   * @param id The unique identifier of the farm
   * @param liquidity The amount of liquidity to provide
   * @return token0 The address of the first token in the pair
   * @return token1 The address of the second token in the pair
   * @return amount0 The desired amount of token0
   * @return amount1 The desired amount of token1
   */
  function getAmountsForLiquidity(
    address id,
    uint128 liquidity
  ) external view returns (address token0, address token1, uint256 amount0, uint256 amount1) {
    if (!_farms.contains(id)) revert InvalidFarmId();

    Farm storage farm = _farms.get(id);
    (uint160 slotPrice, ) = _getTwaPrice(farm.id, 0);

    // Calculate amounts based on current slot price
    (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
      slotPrice,
      TickMath.getSqrtRatioAtTick(Constants.MIN_TICK),
      TickMath.getSqrtRatioAtTick(Constants.MAX_TICK),
      liquidity
    );

    token0 = farm.poolKey.token0;
    token1 = farm.poolKey.token1;
  }

  /**
   * @notice Calculates the liquidity and token amounts for a given token amount
   * @param id The unique identifier of the farm
   * @param token The address of the token to provide
   * @param amount The amount of the token to provide
   * @return token0 The address of the first token in the pair
   * @return token1 The address of the second token in the pair
   * @return liquidity The calculated liquidity amount
   * @return amount0 The amount of token0 required
   * @return amount1 The amount of token1 required
   */
  function getLiquidityForAmount(
    address id,
    address token,
    uint256 amount
  ) external view returns (address token0, address token1, uint128 liquidity, uint256 amount0, uint256 amount1) {
    if (!_farms.contains(id)) revert InvalidFarmId();

    Farm storage farm = _farms.get(id);
    token0 = farm.poolKey.token0;
    token1 = farm.poolKey.token1;

    // Get prices
    (uint160 slotPrice, ) = _getTwaPrice(farm.id, 0);
    uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(Constants.MIN_TICK);
    uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(Constants.MAX_TICK);

    if (token == token0) {
      liquidity = LiquidityAmounts.getLiquidityForAmount0(slotPrice, sqrtRatioBX96, amount);
    } else if (token == token1) {
      liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, slotPrice, amount);
    } else {
      revert InvalidTokenId();
    }

    // Calculate amounts based on the slot price
    (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
      slotPrice,
      TickMath.getSqrtRatioAtTick(Constants.MIN_TICK),
      TickMath.getSqrtRatioAtTick(Constants.MAX_TICK),
      liquidity
    );
  }

  /**
   * @notice Computes the unique identifier for a Uniswap V3 pool
   * @param tokenA The address of the first token in the pair
   * @param tokenB The address of the second token in the pair
   * @param fee The fee tier of the pool
   * @return The computed address of the Uniswap V3 pool
   */
  function getFarmId(address tokenA, address tokenB, uint24 fee) external pure returns (address) {
    PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(tokenA, tokenB, fee);
    return PoolAddress.computeAddress(Constants.FACTORY, poolKey);
  }

  // -----------------------------------------
  // Public functions
  // -----------------------------------------
  /**
   * @notice Retrieves detailed information about a specific farm
   * @param id The unique identifier of the farm
   * @return A FarmView struct containing comprehensive farm details
   */
  function farmView(address id) public view returns (FarmView memory) {
    if (!_farms.contains(id)) revert InvalidFarmId();

    Farm storage farm = _farms.get(id);

    (uint160 slotPrice, ) = _getTwaPrice(farm.id, 0);
    (uint256 balanceToken0, uint256 balanceToken1) = LiquidityAmounts.getAmountsForLiquidity(
      slotPrice,
      TickMath.getSqrtRatioAtTick(Constants.MIN_TICK),
      TickMath.getSqrtRatioAtTick(Constants.MAX_TICK),
      farm.lp.liquidity
    );

    (
      uint256 accIncentiveTokenPerShare,
      uint256 accFeePerShareForToken0,
      uint256 accFeePerShareForToken1
    ) = _getSharesAtBlockTimestamp(farm);

    return
      FarmView({
        id: farm.id,
        poolKey: farm.poolKey,
        lp: farm.lp,
        allocPoints: farm.allocPoints,
        lastRewardTime: farm.lastRewardTime,
        // @dev: accumulated share values have been updated to the current block time and **do not**
        // reflect the values captured at last reward time
        accIncentiveTokenPerShare: accIncentiveTokenPerShare,
        accFeePerShareForToken0: accFeePerShareForToken0,
        accFeePerShareForToken1: accFeePerShareForToken1,
        protocolFee: farm.protocolFee,
        priceTwa: farm.priceTwa,
        slippage: farm.slippage,
        balanceToken0: balanceToken0,
        balanceToken1: balanceToken1
      });
  }

  /**
   * @notice Updates reward variables for all farms
   * @dev This function can be gas-intensive, use cautiously
   * @param collectFees optionally, collect fees on every farm
   */
  function massUpdateFarms(bool collectFees) public nonReentrant {
    uint256 length = _farms.length();

    // Iterate all farms and update them
    for (uint256 idx = 0; idx < length; idx++) {
      Farm storage farm = _farms.at(idx);
      _updateFarm(farm, collectFees);
    }
  }

  // -----------------------------------------
  // Internal functions
  // -----------------------------------------

  // -----------------------------------------
  // Private functions
  // -----------------------------------------
  function _updateFarm(Farm storage farm, bool collectFees) private {
    // Total liquidity
    uint256 liquidity = farm.lp.liquidity;

    // Collect fees if needed, possible even if incentive token are not issued yet
    if (collectFees) {
      _collectFees(farm);
    }

    // Do nothing if farm is up to date or issueing incentive tokens has not yet started yet
    if (block.timestamp <= farm.lastRewardTime || block.timestamp < startTime) {
      return;
    }

    // No updates on incentive tokens if liquidity is zero or this farm does not have any allocation
    if (liquidity == 0 || farm.allocPoints == 0) {
      farm.lastRewardTime = block.timestamp;
      return;
    }

    // Mint incentive tokens
    uint256 timeMultiplier = _getTimeMultiplier(farm.lastRewardTime, block.timestamp);

    uint256 incentiveTokenReward = Math.mulDiv(
      timeMultiplier * Constants.INCENTIVE_TOKEN_PER_SECOND,
      farm.allocPoints,
      totalAllocPoints
    );

    // Scale shares by scaling factor and liquidity
    farm.accIncentiveTokenPerShare += Math.mulDiv(incentiveTokenReward, Constants.SCALE_FACTOR_1E12, liquidity);
    farm.lastRewardTime = block.timestamp;
  }

  function _collectFees(Farm storage farm) private {
    // Cache State Variables
    uint256 liquidity = farm.lp.liquidity;
    uint256 tokenId = farm.lp.tokenId;
    INonfungiblePositionManager manager = INonfungiblePositionManager(Constants.NON_FUNGIBLE_POSITION_MANAGER);

    // Do nothing if shared LP position has not been minted yet or there is no liquidity
    // and hence no fees will be collected
    if (tokenId <= 0 || liquidity == 0) return;

    // Collect the maximum amount possible of both tokens
    INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
      tokenId,
      address(this),
      type(uint128).max,
      type(uint128).max
    );
    (uint256 amount0, uint256 amount1) = manager.collect(params);

    // Identify tokens which are accepted as input for buy and burn
    bool isInputToken0 = buyAndBurn.isInputToken(farm.poolKey.token0);
    bool isInputToken1 = buyAndBurn.isInputToken(farm.poolKey.token1);

    // Handle token0
    if (isInputToken0) {
      uint256 protocolFee = 0;

      if (farm.protocolFee > 0) {
        protocolFee = Math.mulDiv(amount0, farm.protocolFee, Constants.BASIS);
        protocolFees[farm.poolKey.token0] += protocolFee;
      }

      // Send core tokens to the buy and burn contract
      _safeTransferToken(farm.poolKey.token0, address(buyAndBurn), amount0 - protocolFee);
    } else {
      farm.accFeePerShareForToken0 += Math.mulDiv(amount0, Constants.SCALE_FACTOR_1E18, liquidity);
    }

    // Handle token1
    if (isInputToken1) {
      uint256 protocolFee = 0;

      if (farm.protocolFee > 0) {
        protocolFee = Math.mulDiv(amount1, farm.protocolFee, Constants.BASIS);
        protocolFees[farm.poolKey.token1] += protocolFee;
      }

      // Send core tokens to the buy and burn contract
      _safeTransferToken(farm.poolKey.token1, address(buyAndBurn), amount1 - protocolFee);
    } else {
      farm.accFeePerShareForToken1 += Math.mulDiv(amount1, Constants.SCALE_FACTOR_1E18, liquidity);
    }
  }

  function _createLiquidityPosition(
    Farm storage farm,
    uint128 liquidity,
    uint256 deadline
  ) private returns (uint128, uint256, uint256) {
    (
      uint256 desiredAmount0,
      uint256 desiredAmount1,
      uint256 minAmount0,
      uint256 minAmount1
    ) = _getDesiredAmountsForLiquidity(farm, liquidity);

    // Transfer tokens to the Farm Keeper
    IERC20(farm.poolKey.token0).safeTransferFrom(msg.sender, address(this), desiredAmount0);
    IERC20(farm.poolKey.token1).safeTransferFrom(msg.sender, address(this), desiredAmount1);

    IERC20(farm.poolKey.token0).safeIncreaseAllowance(Constants.NON_FUNGIBLE_POSITION_MANAGER, desiredAmount0);
    IERC20(farm.poolKey.token1).safeIncreaseAllowance(Constants.NON_FUNGIBLE_POSITION_MANAGER, desiredAmount1);

    // Mint the shared liquidity position
    INonfungiblePositionManager manager = INonfungiblePositionManager(Constants.NON_FUNGIBLE_POSITION_MANAGER);

    INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
      token0: farm.poolKey.token0,
      token1: farm.poolKey.token1,
      fee: farm.poolKey.fee,
      tickLower: Constants.MIN_TICK,
      tickUpper: Constants.MAX_TICK,
      amount0Desired: desiredAmount0,
      amount1Desired: desiredAmount1,
      amount0Min: minAmount0,
      amount1Min: minAmount1,
      recipient: address(this),
      deadline: deadline
    });

    (uint256 tokenId, uint128 mintedLiquidity, uint256 usedAmount0, uint256 usedAmount1) = manager.mint(mintParams);

    // Refund unused tokens
    uint256 unusedAmount0 = desiredAmount0 - usedAmount0;
    uint256 unusedAmount1 = desiredAmount1 - usedAmount1;

    if (unusedAmount0 > 0) {
      _safeTransferToken(farm.poolKey.token0, msg.sender, unusedAmount0);
    }

    if (unusedAmount1 > 0) {
      _safeTransferToken(farm.poolKey.token1, msg.sender, unusedAmount1);
    }

    // Update state
    farm.lp.tokenId = tokenId;
    farm.lp.liquidity += mintedLiquidity;

    return (mintedLiquidity, usedAmount0, usedAmount1);
  }

  function _addLiquidity(
    Farm storage farm,
    uint128 liquidity,
    uint256 deadline
  ) private returns (uint128, uint256, uint256) {
    (
      uint256 desiredAmount0,
      uint256 desiredAmount1,
      uint256 minAmount0,
      uint256 minAmount1
    ) = _getDesiredAmountsForLiquidity(farm, liquidity);

    // Transfer tokens to the Farm Keeper
    IERC20(farm.poolKey.token0).safeTransferFrom(msg.sender, address(this), desiredAmount0);
    IERC20(farm.poolKey.token1).safeTransferFrom(msg.sender, address(this), desiredAmount1);

    IERC20(farm.poolKey.token0).safeIncreaseAllowance(Constants.NON_FUNGIBLE_POSITION_MANAGER, desiredAmount0);
    IERC20(farm.poolKey.token1).safeIncreaseAllowance(Constants.NON_FUNGIBLE_POSITION_MANAGER, desiredAmount1);

    INonfungiblePositionManager manager = INonfungiblePositionManager(Constants.NON_FUNGIBLE_POSITION_MANAGER);

    (uint128 addedLiquidity, uint256 usedAmount0, uint256 usedAmount1) = manager.increaseLiquidity(
      INonfungiblePositionManager.IncreaseLiquidityParams({
        tokenId: farm.lp.tokenId,
        amount0Desired: desiredAmount0,
        amount1Desired: desiredAmount1,
        amount0Min: minAmount0,
        amount1Min: minAmount1,
        deadline: deadline
      })
    );

    // Refund unused tokens
    uint256 unusedAmount0 = desiredAmount0 - usedAmount0;
    uint256 unusedAmount1 = desiredAmount1 - usedAmount1;

    if (unusedAmount0 > 0) {
      _safeTransferToken(farm.poolKey.token0, msg.sender, unusedAmount0);
    }

    if (unusedAmount1 > 0) {
      _safeTransferToken(farm.poolKey.token1, msg.sender, unusedAmount1);
    }
    // Update state
    farm.lp.liquidity += addedLiquidity;

    // Track liquidity added by each individual user
    return (addedLiquidity, usedAmount0, usedAmount1);
  }

  function _decreaseLiquidity(
    Farm storage farm,
    uint128 liquidity,
    address to,
    uint256 deadline
  ) private returns (uint256 amount0, uint256 amount1) {
    INonfungiblePositionManager manager = INonfungiblePositionManager(Constants.NON_FUNGIBLE_POSITION_MANAGER);
    (, , uint256 minAmount0, uint256 minAmount1) = _getDesiredAmountsForLiquidity(farm, liquidity);

    (amount0, amount1) = manager.decreaseLiquidity(
      INonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: farm.lp.tokenId,
        liquidity: liquidity,
        amount0Min: minAmount0,
        amount1Min: minAmount1,
        deadline: deadline
      })
    );

    // Directly transfer tokens to caller
    INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
      farm.lp.tokenId,
      to,
      uint128(amount0),
      uint128(amount1)
    );
    manager.collect(params);
    farm.lp.liquidity -= liquidity;
  }

  function _safeTransferToken(address token, address to, uint256 amount) private {
    uint256 balanace = IERC20(token).balanceOf(address(this));

    if (amount > 0) {
      // In case if rounding error causes farm keeper to not have enough tokens.
      if (amount > balanace) {
        IERC20(token).safeTransfer(to, balanace);
      } else {
        IERC20(token).safeTransfer(to, amount);
      }
    }
  }

  function _getTimeMultiplier(uint256 from, uint256 to) private view returns (uint256) {
    from = from > startTime ? from : startTime;
    if (to < startTime) {
      return 0;
    }
    return to - from;
  }

  function _getTwaPrice(address id, uint32 priceTwa) private view returns (uint160 slotPrice, uint160 twaPrice) {
    // Default to current price
    IUniswapV3Pool pool = IUniswapV3Pool(id);
    (slotPrice, , , , , , ) = pool.slot0();

    // Default TWA price to slot
    twaPrice = slotPrice;

    uint32 secondsAgo = uint32(priceTwa * 60);
    uint32 oldestObservation = 0;

    // Load oldest observation if cardinality greater than zero
    oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(id);

    // Limit to oldest observation (fallback)
    if (oldestObservation < secondsAgo) {
      secondsAgo = oldestObservation;
    }

    // If TWAP is enabled and price history exists, consult oracle
    if (secondsAgo > 0) {
      // Consult the Oracle Library for TWAP
      (int24 arithmeticMeanTick, ) = OracleLibrary.consult(id, secondsAgo);

      // Convert tick to sqrtPriceX96
      twaPrice = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
    }
  }

  function _getDesiredAmountsForLiquidity(
    Farm storage farm,
    uint128 liquidity
  ) private view returns (uint256 desiredAmount0, uint256 desiredAmount1, uint256 minAmount0, uint256 minAmount1) {
    (uint160 slotPrice, uint160 twaPrice) = _getTwaPrice(farm.id, farm.priceTwa);
    // Calculate desired amounts based on current slot price
    (desiredAmount0, desiredAmount1) = LiquidityAmounts.getAmountsForLiquidity(
      slotPrice,
      TickMath.getSqrtRatioAtTick(Constants.MIN_TICK),
      TickMath.getSqrtRatioAtTick(Constants.MAX_TICK),
      liquidity
    );

    // Calculate minimal amounts based on TWA price for slippage protection
    (minAmount0, minAmount1) = LiquidityAmounts.getAmountsForLiquidity(
      twaPrice,
      TickMath.getSqrtRatioAtTick(Constants.MIN_TICK),
      TickMath.getSqrtRatioAtTick(Constants.MAX_TICK),
      liquidity
    );

    // Apply slippage
    minAmount0 = (minAmount0 * (Constants.BASIS - farm.slippage)) / Constants.BASIS;
    minAmount1 = (minAmount1 * (Constants.BASIS - farm.slippage)) / Constants.BASIS;
  }

  function _getSharesAtBlockTimestamp(
    Farm storage farm
  )
    private
    view
    returns (uint256 accIncentiveTokenPerShare, uint256 accFeePerShareForToken0, uint256 accFeePerShareForToken1)
  {
    accIncentiveTokenPerShare = farm.accIncentiveTokenPerShare;
    accFeePerShareForToken0 = farm.accFeePerShareForToken0;
    accFeePerShareForToken1 = farm.accFeePerShareForToken1;

    // Do not perform any updates if liquidity is zero
    if (farm.lp.liquidity <= 0) {
      return (accIncentiveTokenPerShare, accFeePerShareForToken0, accFeePerShareForToken1);
    }

    if (block.timestamp > farm.lastRewardTime) {
      uint256 timeMultiplier = _getTimeMultiplier(farm.lastRewardTime, block.timestamp);

      uint256 incentiveTokenReward = Math.mulDiv(
        timeMultiplier * Constants.INCENTIVE_TOKEN_PER_SECOND,
        farm.allocPoints,
        totalAllocPoints
      );

      accIncentiveTokenPerShare += Math.mulDiv(incentiveTokenReward, Constants.SCALE_FACTOR_1E12, farm.lp.liquidity);
    }

    // Try update fees if LP token exists
    if (farm.lp.tokenId > 0) {
      (uint256 pendingFeeAmount0, uint256 pendingFeeAmount1) = PositionValue.fees(
        INonfungiblePositionManager(Constants.NON_FUNGIBLE_POSITION_MANAGER),
        farm.lp.tokenId
      );

      bool isInputToken0 = buyAndBurn.isInputToken(farm.poolKey.token0);
      bool isInputToken1 = buyAndBurn.isInputToken(farm.poolKey.token1);

      if (!isInputToken0 && pendingFeeAmount0 > 0) {
        accFeePerShareForToken0 += Math.mulDiv(pendingFeeAmount0, Constants.SCALE_FACTOR_1E18, farm.lp.liquidity);
      }

      if (!isInputToken1 && pendingFeeAmount1 > 0) {
        accFeePerShareForToken1 += Math.mulDiv(pendingFeeAmount1, Constants.SCALE_FACTOR_1E18, farm.lp.liquidity);
      }
    }
  }

  function _validatePriceTwa(uint32 mins) private pure {
    if (mins < 5 || mins > 60) revert InvalidPriceTwa();
  }

  function _validateSlippage(uint256 slippage) private pure {
    if (slippage < 1 || slippage > 2500) revert InvalidSlippage();
  }

  function _validateProtocolFee(uint256 fee) private pure {
    if (fee > 2500) revert InvalidFee();
  }

  function _validateAllocPoints(uint256 allocPoints) private pure {
    if (allocPoints > Constants.MAX_ALLOCATION_POINTS) revert InvalidAllocPoints();
  }
}