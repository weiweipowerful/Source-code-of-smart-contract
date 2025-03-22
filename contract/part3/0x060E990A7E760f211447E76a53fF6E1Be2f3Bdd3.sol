// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

// Uniswap
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

// OpenZeppelins
import '@openzeppelin/contracts/access/manager/AccessManager.sol';
import '@openzeppelin/contracts/access/manager/AccessManaged.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Multicall.sol';
import '@openzeppelin/contracts/utils/math/SafeCast.sol';

// Library
import './lib/Constants.sol';
import './lib/InputTokens.sol';
import './lib/uniswap/PoolAddress.sol';
import './lib/uniswap/Oracle.sol';
import './lib/uniswap/TickMath.sol';
import './lib/uniswap/PathDecoder.sol';

// Interfaces
import './interfaces/IBurnProxy.sol';
import './interfaces/IPermit2.sol';
import './interfaces/IUniversalRouter.sol';
import './interfaces/IOutputToken.sol';
import './interfaces/IFarmKeeper.sol';

/**
 * @title UniversalBuyAndBurn
 * @notice A contract for buying and burning an output token using various ERC20 input tokens
 * @dev This contract enables a flexible buy-and-burn mechanism for tokenomics management
 *
 *  ██████╗ ██╗   ██╗██╗   ██╗     ██████╗     ██████╗ ██╗   ██╗██████╗ ███╗   ██╗
 *  ██╔══██╗██║   ██║╚██╗ ██╔╝    ██╔════╝     ██╔══██╗██║   ██║██╔══██╗████╗  ██║
 *  ██████╔╝██║   ██║ ╚████╔╝     ███████╗     ██████╔╝██║   ██║██████╔╝██╔██╗ ██║
 *  ██╔══██╗██║   ██║  ╚██╔╝      ╚════██║     ██╔══██╗██║   ██║██╔══██╗██║╚██╗██║
 *  ██████╔╝╚██████╔╝   ██║       ███████║     ██████╔╝╚██████╔╝██║  ██║██║ ╚████║
 *  ╚═════╝  ╚═════╝    ╚═╝       ╚══════╝     ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝
 *
 * Key features:
 * - Supports multiple input tokens for buying and burning a single output token
 * - Configurable parameters for each input token (e.g., cap per swap, cooldown interval, incentive fee)
 * - Direct burning of input tokens or swapping for output tokens before burning
 * - Uses Uniswap V3 for token swaps with customizable swap paths
 * - Implements a Time-Weighted Average Price (TWAP) mechanism for price quotes
 * - Includes slippage protection for swaps
 * - Provides incentives for users triggering the buy-and-burn process
 *
 * Security features:
 * - Access control using OpenZeppelin's AccessManaged
 * - Reentrancy protection
 * - Cooldown periods between buy-and-burn operations
 *
 * Restrictions:
 * - Requires a deployment of the UniSwap Universal Router
 * - Limits Swap paths to V3 pools only
 */
contract UniversalBuyAndBurn is AccessManaged, ReentrancyGuard, Multicall {
  using InputTokens for InputTokens.Map;
  using PathDecoder for PathDecoder.Hop;
  using SafeERC20 for IERC20;

  // -----------------------------------------
  // Type declarations
  // -----------------------------------------

  /**
   * @notice Function parameters to pass when enabling a new input token
   */
  struct EnableInputToken {
    address id;
    uint256 capPerSwap;
    uint256 interval;
    uint256 incentiveFee;
    IBurnProxy burnProxy;
    uint256 burnPercentage;
    uint32 priceTwa;
    uint256 slippage;
    bytes path;
    bool paused;
  }

  // -----------------------------------------
  // State variables
  // -----------------------------------------
  InputTokens.Map private _inputTokens;

  /**
   * @dev Tracks the total amount of output tokens purchased and burned.
   * This accumulates the output tokens bought and subsequently burned over time.
   */
  uint256 public totalOutputTokensBurned;

  /**
   * @dev The output token. A public burn function with a
   * function signature function burn(uint256 amount) is mandatory.
   */
  IOutputToken public outputToken;

  // -----------------------------------------
  // Events
  // -----------------------------------------
  /**
   * @notice Emitted when output tokens are bought with an input token and are subsequently burned.
   * @dev This event indicates both the purchase and burning of output tokens in a single transaction.
   * Depending on the input token settings, might also burn input tokens directly.
   * @param inputTokenAddress The input token address.
   * @param toBuy The amount of input tokens used to buy and burn the output token.
   * @param toBurn The amount of input tokens directly burned.
   * @param incentiveFee The amout of input tokens payed as incentive fee to run the function.
   * @param outputTokensBurned The amount of output tokens burned.
   * @param caller The function caller
   */
  event BuyAndBurn(
    address indexed inputTokenAddress,
    uint256 toBuy,
    uint256 toBurn,
    uint256 incentiveFee,
    uint256 outputTokensBurned,
    address caller
  );

  /**
   * @notice Emitted when a new input token is activated for the first time
   * @param inputTokenAddress the Input Token Identifier (address)
   */
  event InputTokenEnabled(address indexed inputTokenAddress, EnableInputToken params);

  /**
   * Events emitted when a input token parameter is updated
   */
  event CapPerSwapUpdated(address indexed inputTokenAddress, uint256 newCap);
  event BuyAndBurnIntervalUpdated(address indexed inputTokenAddress, uint256 newInterval);
  event IncentiveFeeUpdated(address indexed inputTokenAddress, uint256 newFee);
  event SlippageUpdated(address indexed inputTokenAddress, uint256 newSlippage);
  event PriceTwaUpdated(address indexed inputTokenAddress, uint32 newTwa);
  event BurnPercentageUpdated(address indexed inputTokenAddress, uint256 newPercentage);
  event BurnProxyUpdated(address indexed inputTokenAddress, address newProxy);
  event SwapPathUpdated(address indexed inputTokenAddress, bytes newPath);
  event PausedUpdated(address indexed inputTokenAddress, bool paused);
  event DisabledUpdated(address indexed inputTOkenAddress, bool disabled);

  // -----------------------------------------
  // Errors
  // -----------------------------------------
  error InvalidCaller();
  error CooldownPeriodActive();
  error NoInputTokenBalance();
  error InvalidInputTokenAddress();
  error InputTokenAlreadyEnabled();
  error InvalidCapPerSwap();
  error InvalidInterval();
  error InvalidIncentiveFee();
  error InvalidBurnProxy();
  error InvalidBurnPercentage();
  error InvalidPriceTwa();
  error InvalidSlippage();
  error InvalidSwapPath();
  error InputTokenPaused();

  // -----------------------------------------
  // Modifiers
  // -----------------------------------------

  // -----------------------------------------
  // Constructor
  // -----------------------------------------
  /**
   * @notice Creates a new instance of the contract.
   */
  constructor(IOutputToken outputToken_, address manager) AccessManaged(manager) {
    // store the output token interface
    outputToken = outputToken_;
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
   * @notice Buys Output tokens using an input token and then burns them.
   * @dev This function swaps an approved input token for Output tokens using the universal swap router,
   *      then burns the Output tokens.
   *      It includes security checks to prevent abuse (e.g., reentrancy, bot interactions, cooldown periods).
   *      The function also handles an incentive fee for the caller and can burn input tokens directly if specified.
   * @param inputTokenAddress The address of the input token to be used for buying Output tokens.
   * @custom:events Emits a BoughtAndBurned event after successfully buying and burning Output tokens.
   * @custom:security nonReentrant
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:error InvalidCaller Thrown if the caller is not the transaction origin (prevents contract calls).
   * @custom:error NoInputTokenBalance Thrown if there are no tokens left in the contract.
   * @custom:error CooldownPeriodActive Thrown if the function is called before the cooldown period has elapsed.
   * @custom:error InputTokenPaused Thrown if the buyAndBurn for the specified input token is paused.
   */
  function buyAndBurn(address inputTokenAddress) external nonReentrant {
    // Ensure processing a valid input token
    if (!_inputTokens.contains(inputTokenAddress)) {
      revert InvalidInputTokenAddress();
    }
    InputToken storage inputTokenInfo = _inputTokens.get(inputTokenAddress);

    // prevent contract accounts (bots) from calling this function
    // becomes obsolete with EIP-3074, there are other measures in
    // place to make MEV attacks inefficient (cap per swap, interval control)
    if (msg.sender != tx.origin) {
      revert InvalidCaller();
    }

    if (inputTokenInfo.paused) {
      revert InputTokenPaused();
    }

    // keep a minium gap of interval between each call
    // update stored timestamp
    if (block.timestamp - inputTokenInfo.lastCallTs <= inputTokenInfo.interval) {
      revert CooldownPeriodActive();
    }
    inputTokenInfo.lastCallTs = block.timestamp;

    // Get the input token amount to buy and incentive fee
    // this call will revert if there are no input tokens left in the contract
    (uint256 toBuy, uint256 toBurn, uint256 incentiveFee) = _getAmounts(inputTokenInfo);

    if (toBuy == 0 && toBurn == 0) {
      revert NoInputTokenBalance();
    }

    // Burn Input Tokens
    if (toBurn > 0) {
      // Send tokens to the burn proxy
      IERC20(inputTokenAddress).safeTransfer(address(inputTokenInfo.burnProxy), toBurn);

      // Execute burn
      inputTokenInfo.burnProxy.burn();
    }

    // Buy Output Tokens and burn them
    uint256 outputTokensBought = 0;
    if (toBuy > 0) {
      uint256 estimatedMinimumOutput = estimateMinimumOutputAmount(
        inputTokenInfo.path,
        inputTokenInfo.slippage,
        inputTokenInfo.priceTwa,
        toBuy
      );

      _approveForSwap(inputTokenAddress, toBuy);

      // Commands for the Universal Router
      bytes memory commands = abi.encodePacked(
        bytes1(0x00) // V3 swap exact input
      );

      // Inputs for the Universal Router
      bytes[] memory inputs = new bytes[](1);
      inputs[0] = abi.encode(
        address(this), // Recipient is the buy and burn contract
        toBuy,
        estimatedMinimumOutput,
        inputTokenInfo.path,
        true // Payer is the buy and burn contract
      );

      uint256 balanceBefore = outputToken.balanceOf(address(this));

      // Execute the swap
      IUniversalRouter(Constants.UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp);
      outputTokensBought = outputToken.balanceOf(address(this)) - balanceBefore;

      // Burn the tokens bought
      outputToken.burn(outputTokensBought);
    }

    if (incentiveFee > 0) {
      // Send incentive fee
      IERC20(inputTokenAddress).safeTransfer(msg.sender, incentiveFee);
    }

    // Update state
    inputTokenInfo.totalTokensUsedForBuyAndBurn += toBuy;
    inputTokenInfo.totalTokensBurned += toBurn;
    inputTokenInfo.totalIncentiveFee += incentiveFee;

    totalOutputTokensBurned += outputTokensBought;

    // Emit events
    emit BuyAndBurn(inputTokenAddress, toBuy, toBurn, incentiveFee, outputTokensBought, msg.sender);
  }

  /**
   * @notice Enables a new input token for buyAndBurn operations.
   * @dev This function can only be called by the contract owner or authorized addresses.
   *      It sets up all necessary parameters for a new input token.
   * @param params A struct containing all the parameters for the new input token.
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is zero.
   * @custom:error InputTokenAlreadyEnabled Thrown if the input token is already enabled.
   * @custom:error Various errors for invalid parameter values (see validation functions).
   * @custom:event Emits an InputTokenEnabled event with the new input token address and all its parameters.
   */
  function enableInputToken(EnableInputToken calldata params) external restricted {
    if (params.id == address(0)) revert InvalidInputTokenAddress();
    if (_inputTokens.contains(params.id)) revert InputTokenAlreadyEnabled();

    _validateCapPerSwap(params.capPerSwap);
    _validateInterval(params.interval);
    _validateIncentiveFee(params.incentiveFee);
    _validateBurnProxy(address(params.burnProxy));
    _validateBurnPercentage(params.burnPercentage);
    _validatePriceTwa(params.priceTwa);
    _validateSlippage(params.slippage);

    // Allow to enable an input token without a valid path
    // if all tokens are burned
    if (params.burnPercentage < Constants.BASIS) {
      _validatePath(PathDecoder.decode(params.path));
    }

    _inputTokens.add(
      InputToken({
        id: params.id,
        totalTokensUsedForBuyAndBurn: 0,
        totalTokensBurned: 0,
        totalIncentiveFee: 0,
        lastCallTs: 0,
        capPerSwap: params.capPerSwap,
        interval: params.interval,
        incentiveFee: params.incentiveFee,
        burnProxy: IBurnProxy(params.burnProxy),
        burnPercentage: params.burnPercentage,
        priceTwa: params.priceTwa,
        slippage: params.slippage,
        path: params.path,
        paused: params.paused,
        disabled: false
      })
    );

    emit InputTokenEnabled(params.id, params);
  }

  /**
   * @notice Sets the maximum amount of input tokens that can be used per buyAndBurn call.
   * @dev This function can only be called by the contract owner or authorized addresses.
   * @param inputTokenAddress The address of the input token for which to set the cap.
   * @param amount The maximum amount of input tokens allowed per swap, in the token's native decimals.
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:error InvalidCapPerSwap Thrown if the cap per swap is zero.
   * @custom:event Emits a CapPerSwapUpdated event with the input token address and new cap value.
   */
  function setCapPerSwap(address inputTokenAddress, uint256 amount) external restricted {
    if (!_inputTokens.contains(inputTokenAddress)) revert InvalidInputTokenAddress();
    _validateCapPerSwap(amount);
    _inputTokens.get(inputTokenAddress).capPerSwap = amount;
    emit CapPerSwapUpdated(inputTokenAddress, amount);
  }

  /**
   * @notice Sets the minimum time interval between buyAndBurn calls for a specific input token.
   * @dev This function can only be called by the contract owner or authorized addresses.
   * @param inputTokenAddress The address of the input token for which to set the interval.
   * @param secs The cooldown period in seconds between buyAndBurn calls.
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:error InvalidInterval Thrown if the interval is not between 60
   *               seconds (1 minute) and 43200 seconds (12 hours).
   * @custom:event Emits a BuyAndBurnIntervalUpdated event with the input token address and new interval value.
   */
  function setBuyAndBurnInterval(address inputTokenAddress, uint256 secs) external restricted {
    if (!_inputTokens.contains(inputTokenAddress)) revert InvalidInputTokenAddress();
    _validateInterval(secs);
    _inputTokens.get(inputTokenAddress).interval = secs;
    emit BuyAndBurnIntervalUpdated(inputTokenAddress, secs);
  }

  /**
   * @notice Sets the incentive fee percentage for buyAndBurn calls for a specific input token.
   * @dev This function can only be called by the contract owner or authorized addresses.
   * @param inputTokenAddress The address of the input token for which to set the incentive fee.
   * @param incentiveFee The incentive fee in basis points (0 = 0.0%, 1000 = 10%).
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:error InvalidIncentiveFee Thrown if the incentive fee is not between 0 (0.0%) and 1000 (10%).
   * @custom:event Emits an IncentiveFeeUpdated event with the input token address and new fee value.
   */
  function setIncentiveFee(address inputTokenAddress, uint256 incentiveFee) external restricted {
    if (!_inputTokens.contains(inputTokenAddress)) revert InvalidInputTokenAddress();
    _validateIncentiveFee(incentiveFee);
    _inputTokens.get(inputTokenAddress).incentiveFee = incentiveFee;
    emit IncentiveFeeUpdated(inputTokenAddress, incentiveFee);
  }

  /**
   * @notice Sets the slippage tolerance percentage for buyAndBurn swaps for a specific input token.
   * @dev This function can only be called by the contract owner or authorized addresses.
   * @param inputTokenAddress The address of the input token for which to set the slippage tolerance.
   * @param slippage The slippage tolerance in basis points (1 = 0.01%, 2500 = 25%).
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:error InvalidSlippage Thrown if the slippage is not between 1 (0.01%) and 2500 (25%).
   * @custom:event Emits a SlippageUpdated event with the input token address and new slippage value.
   */
  function setSlippage(address inputTokenAddress, uint256 slippage) external restricted {
    if (!_inputTokens.contains(inputTokenAddress)) revert InvalidInputTokenAddress();
    _validateSlippage(slippage);
    _inputTokens.get(inputTokenAddress).slippage = slippage;
    emit SlippageUpdated(inputTokenAddress, slippage);
  }

  /**
   * @notice Sets the Time-Weighted Average (TWA) period for price quotes used in buyAndBurn
   * swaps for a specific input token. Allows to disable TWA by setting mins to zero.
   * @dev This function can only be called by the contract owner or authorized addresses.
   * @param inputTokenAddress The address of the input token for which to set the TWA period.
   * @param mins The TWA period in minutes.
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:error InvalidPriceTwa Thrown if the TWA period is not between 0 minutes and 60 minutes (1 hour).
   * @custom:event Emits a PriceTwaUpdated event with the input token address and new TWA value.
   */
  function setPriceTwa(address inputTokenAddress, uint32 mins) external restricted {
    if (!_inputTokens.contains(inputTokenAddress)) revert InvalidInputTokenAddress();
    _validatePriceTwa(mins);
    _inputTokens.get(inputTokenAddress).priceTwa = mins;
    emit PriceTwaUpdated(inputTokenAddress, mins);
  }

  /**
   * @notice Sets the percentage of input tokens to be directly burned in buyAndBurn
   * operations for a specific input token.
   * @dev This function can only be called by the contract owner or authorized addresses.
   * @param inputTokenAddress The address of the input token for which to set the burn percentage.
   * @param burnPercentage The percentage of input tokens to be burned, expressed in basis points (0-10000).
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:error InvalidBurnPercentage Thrown if the burn percentage is greater than 10000 basis points (100%).
   * @custom:event Emits a BurnPercentageUpdated event with the input token address and new burn percentage value.
   */
  function setBurnPercentage(address inputTokenAddress, uint256 burnPercentage) external restricted {
    if (!_inputTokens.contains(inputTokenAddress)) revert InvalidInputTokenAddress();
    _validateBurnPercentage(burnPercentage);

    InputToken storage token = _inputTokens.get(inputTokenAddress);

    if (burnPercentage < Constants.BASIS) {
      // Ensure a valid path exists if burn percentage is less than 100%
      if (token.path.length < PathDecoder.V3_POP_OFFSET) {
        revert InvalidSwapPath();
      }

      _validatePath(PathDecoder.decode(token.path));
    }

    token.burnPercentage = burnPercentage;
    emit BurnPercentageUpdated(inputTokenAddress, burnPercentage);
  }

  /**
   * @notice Sets the burn proxy address for a specific input token in buyAndBurn operations.
   * @dev This function can only be called by the contract owner or authorized addresses.
   * @param inputTokenAddress The address of the input token for which to set the burn proxy.
   * @param proxy The address of the burn proxy contract.
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:error InvalidBurnProxy Thrown if the proxy address is set to the zero address.
   * @custom:event Emits a BurnProxyUpdated event with the input token address and new burn proxy address.
   */
  function setBurnProxy(address inputTokenAddress, address proxy) external restricted {
    if (!_inputTokens.contains(inputTokenAddress)) revert InvalidInputTokenAddress();
    _validateBurnProxy(proxy);
    _inputTokens.get(inputTokenAddress).burnProxy = IBurnProxy(proxy);
    emit BurnProxyUpdated(inputTokenAddress, proxy);
  }

  /**
   * @notice Sets the Uniswap swap path for a specific input token in buyAndBurn operations.
   * @dev This function can only be called by the contract owner or authorized addresses.
   * @param inputTokenAddress The address of the input token for which to set the swap path.
   * @param path The encoded swap path as a bytes array.
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:error InvalidSwapPath Thrown if the provided path is invalid (does not end with the output token).
   * @custom:event Emits a SwapPathUpdated event with the input token address and new swap path.
   */
  function setSwapPath(address inputTokenAddress, bytes calldata path) external restricted {
    if (!_inputTokens.contains(inputTokenAddress)) revert InvalidInputTokenAddress();
    _validatePath(PathDecoder.decode(path));
    _inputTokens.get(inputTokenAddress).path = path;
    emit SwapPathUpdated(inputTokenAddress, path);
  }

  /**
   * @notice Pauses or unpauses buyAndBurn for a specific input token.
   * @dev This function can only be called by the contract owner or authorized addresses.
   *      It allows for temporary suspension of buyAndBurn operations for a particular input token.
   * @param inputTokenAddress The address of the input token for which to set the pause state.
   * @param paused True to pause operations, false to unpause.
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:event Emits a PausedUpdated event with the input token address and new pause state.
   */
  function setPaused(address inputTokenAddress, bool paused) external restricted {
    if (!_inputTokens.contains(inputTokenAddress)) revert InvalidInputTokenAddress();
    _inputTokens.get(inputTokenAddress).paused = paused;
    emit PausedUpdated(inputTokenAddress, paused);
  }

  /**
   * @notice Sets the disabled state for a specific input token.
   * @dev This function can only be called by the contract owner or authorized addresses.
   *      It marks the specified input token as disabled or enabled, affecting its usability by
   *      external contracts interacting with the universal buy and burn instance. This does not
   *      directly pause buyAndBurn operations; use `setPaused` to pause them.
   * @param farmKeeper the farm keeper address to trigger updates when disabling a token
   * @param farmIds the farm to update
   * @param inputTokenAddress The address of the input token for which to set the disabled state.
   * @param disabled True to disable the token, false to enable.
   * @custom:security restricted
   * @custom:error InvalidInputTokenAddress Thrown if the input token address is not approved.
   * @custom:event DisabledUpdated Emitted with the input token address and new disabled state.
   */
  function setDisabled(
    address farmKeeper,
    address[] calldata farmIds,
    address inputTokenAddress,
    bool disabled
  ) external restricted {
    if (!_inputTokens.contains(inputTokenAddress)) revert InvalidInputTokenAddress();

    if (farmKeeper != address(0)) {
      for (uint256 idx = 0; idx < farmIds.length; idx++) {
        IFarmKeeper(farmKeeper).updateFarm(farmIds[idx], true);
      }
    }

    _inputTokens.get(inputTokenAddress).disabled = disabled;
    emit DisabledUpdated(inputTokenAddress, disabled);
  }

  /**
   * @notice Retrieves an array of all registered input tokens and their current states.
   * @dev This function provides a comprehensive view of all input tokens, including
   *      calculated values for the next buyAndBurn operation.
   * @return InputTokenView[] An array of InputTokenView structs, each containing
   *         detailed information about an input token.
   * @custom:struct InputTokenView {
   *   address id;                      // Address of the input token
   *   uint256 totalTokensUsedForBuyAndBurn;  // Total amount of tokens used to buy and burn output tokens
   *   uint256 totalTokensBurned;       // Total amount of tokens directly burned
   *   uint256 totalIncentiveFee;       // Total amount of tokens paid as incentive fees
   *   uint256 lastCallTs;              // Timestamp of the last buyAndBurn call
   *   uint256 capPerSwap;              // Maximum amount allowed per swap
   *   uint256 interval;                // Cooldown period between buyAndBurn calls
   *   uint256 incentiveFee;            // Current incentive fee percentage
   *   address burnProxy;               // Address of the burn proxy contract
   *   uint256 burnPercentage;          // Percentage of tokens to be directly burned
   *   uint32 priceTwa;                 // Time-Weighted Average period for price quotes
   *   uint256 slippage;                // Slippage tolerance for swaps
   *   bool paused;                     // Buy and burn with the given input token is paused
   *   uint256 balance;                 // Current balance of the token in this contract
   *   uint256 nextToBuy;               // Amount to be used for buying in the next operation
   *   uint256 nextToBurn;              // Amount to be directly burned in the next operation
   *   uint256 nextIncentiveFee;        // Incentive fee for the next operation
   *   uint256 nextCall;                // The UTC timestamp when buy and burn can be called next
   * }
   */
  function inputTokens() external view returns (InputTokenView[] memory) {
    InputToken[] memory tokens = _inputTokens.values();
    InputTokenView[] memory views = new InputTokenView[](tokens.length);

    for (uint256 idx = 0; idx < tokens.length; idx++) {
      views[idx] = inputToken(tokens[idx].id);
    }

    return views;
  }

  /**
   * @notice Checks if a given address is registered as an input token.
   * @dev This function provides a way to verify if an address is in the list of approved input tokens.
   * It returns true if the address is a registered input token and is not disabled. This function can be used
   * by external contracts to determine if they should interact with the universal buy and burn instance using
   * the specified input token. Note that even if the function returns false, it is still possible to send
   * funds to the buy and burn instance, but such actions may not be desired or expected.
   *
   * @param inputTokenAddress The address to check.
   * @return bool Returns true if the address is a registered and active input token (not disabled),
   * false otherwise.
   */
  function isInputToken(address inputTokenAddress) external view returns (bool) {
    if (_inputTokens.contains(inputTokenAddress)) {
      return !_inputTokens.get(inputTokenAddress).disabled;
    }

    return false;
  }

  // -----------------------------------------
  // Public functions
  // -----------------------------------------
  /**
   * @notice Retrieves the InputTokenView for a specific input token.
   * @param inputTokenAddress The address of the input token to query.
   * @return inputTokenView The InputTokenView struct containing all information about the specified input token.
   */
  function inputToken(address inputTokenAddress) public view returns (InputTokenView memory inputTokenView) {
    InputToken memory token = _inputTokens.get(inputTokenAddress);

    inputTokenView.id = token.id;
    inputTokenView.totalTokensUsedForBuyAndBurn = token.totalTokensUsedForBuyAndBurn;
    inputTokenView.totalTokensBurned = token.totalTokensBurned;
    inputTokenView.totalIncentiveFee = token.totalIncentiveFee;
    inputTokenView.lastCallTs = token.lastCallTs;
    inputTokenView.capPerSwap = token.capPerSwap;
    inputTokenView.interval = token.interval;
    inputTokenView.incentiveFee = token.incentiveFee;
    inputTokenView.burnProxy = address(token.burnProxy);
    inputTokenView.burnPercentage = token.burnPercentage;
    inputTokenView.priceTwa = token.priceTwa;
    inputTokenView.slippage = token.slippage;
    inputTokenView.paused = token.paused;
    inputTokenView.disabled = token.disabled;
    inputTokenView.path = token.path;

    inputTokenView.balance = IERC20(token.id).balanceOf(address(this));
    (uint256 toBuy, uint256 toBurn, uint256 incentiveFee) = _getAmounts(token);

    inputTokenView.nextToBuy = toBuy;
    inputTokenView.nextToBurn = toBurn;
    inputTokenView.nextIncentiveFee = incentiveFee;
    inputTokenView.nextCall = token.lastCallTs + token.interval + 1;
  }

  /**
   * @notice Get a quote for output token for a given input token amount
   * @dev Uses Time-Weighted Average Price (TWAP) and falls back to the pool price if TWAP is not available.
   * @param inputTokenAddress Address of an ERC20 token contract used as the input token
   * @param outputTokenAddress Address of an ERC20 token contract used as the output token
   * @param fee The fee tier of the pool
   * @param twap The time period in minutes for TWAP calculation (can be set to zero to fallback to pool ratio)
   * @param inputTokenAmount The amount of input token for which the output token quote is needed
   * @return quote The amount of output token
   * @dev This function computes the TWAP of output token in terms of the input token
   *      using the Uniswap V3 pools and the Oracle Library.
   * @dev Limitations: This function assumes both input and output tokens have 18 decimals.
   *      For tokens with different decimals, additional scaling would be required.
   */
  function getQuote(
    address inputTokenAddress,
    address outputTokenAddress,
    uint24 fee,
    uint256 twap,
    uint256 inputTokenAmount
  ) public view returns (uint256 quote, uint32 secondsAgo) {
    address poolAddress = PoolAddress.computeAddress(
      Constants.FACTORY,
      PoolAddress.getPoolKey(inputTokenAddress, outputTokenAddress, fee)
    );

    // Default to current price
    IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
    (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

    secondsAgo = uint32(twap * 60);
    uint32 oldestObservation = 0;

    // Load oldest observation if cardinality greather than zero
    oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(poolAddress);

    // Limit to oldest observation
    if (oldestObservation < secondsAgo) {
      secondsAgo = oldestObservation;
    }

    // If TWAP is enabled and price history exists, consult oracle
    if (secondsAgo > 0) {
      // Consult the Oracle Library for TWAP
      (int24 arithmeticMeanTick, ) = OracleLibrary.consult(poolAddress, secondsAgo);

      // Convert tick to sqrtPriceX96
      sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
    }

    return (
      OracleLibrary.getQuoteForSqrtRatioX96(sqrtPriceX96, inputTokenAmount, inputTokenAddress, outputTokenAddress),
      secondsAgo
    );
  }

  /**
   * @notice Calculate Minimum Amount Out for a swap along a path (including multiple hops)
   * @dev Calculates the minimum amount of output tokens expected along a swap path
   * @param path The encoded swap path
   * @param slippage The allowed slippage in basis points (e.g., 100 for 1%)
   * @param twap The time period in minutes for TWAP calculation
   * @param inputAmount The amount of input tokens to be swapped
   * @return amountOutMinimum The minimum amount of output tokens expected from the swap
   * @dev Limitations:
   *      1. The slippage is applied to the final output amount, not to each hop individually.
   *      2. This calculation does not account for potential price impact of the swap itself.
   */
  function estimateMinimumOutputAmount(
    bytes memory path,
    uint256 slippage,
    uint256 twap,
    uint256 inputAmount
  ) public view returns (uint256 amountOutMinimum) {
    PathDecoder.Hop[] memory hops = PathDecoder.decode(path);
    uint256 currentAmount = inputAmount;

    for (uint256 idx = 0; idx < hops.length; idx++) {
      (currentAmount, ) = getQuote(hops[idx].tokenIn, hops[idx].tokenOut, hops[idx].fee, twap, currentAmount);
    }

    // Apply slippage to the final amount
    amountOutMinimum = (currentAmount * (Constants.BASIS - slippage)) / Constants.BASIS;
  }

  // -----------------------------------------
  // Internal functions
  // -----------------------------------------

  // -----------------------------------------
  // Private functions
  // -----------------------------------------
  function _getAmounts(
    InputToken memory inputTokenInfo
  ) private view returns (uint256 toBuy, uint256 toBurn, uint256 incentiveFee) {
    IERC20 token = IERC20(inputTokenInfo.id);

    // Core Token Balance of this contract
    uint256 inputAmount = token.balanceOf(address(this));
    uint256 capPerSwap = inputTokenInfo.capPerSwap;
    if (inputAmount > capPerSwap) {
      inputAmount = capPerSwap;
    }

    if (inputAmount == 0) {
      return (0, 0, 0);
    }

    incentiveFee = (inputAmount * inputTokenInfo.incentiveFee) / Constants.BASIS;
    inputAmount -= incentiveFee;

    if (inputTokenInfo.burnPercentage == Constants.BASIS) {
      // Burn 100% of the input tokens
      return (0, inputAmount, incentiveFee);
    } else if (inputTokenInfo.burnPercentage == 0) {
      // Burn 0% of the input tokens
      return (inputAmount, 0, incentiveFee);
    }

    // Calculate amounts
    toBurn = (inputAmount * inputTokenInfo.burnPercentage) / Constants.BASIS;
    toBuy = inputAmount - toBurn;

    return (toBuy, toBurn, incentiveFee);
  }

  function _approveForSwap(address token, uint256 amount) private {
    // Approve transfer via permit2
    IERC20(token).safeIncreaseAllowance(Constants.PERMIT2, amount);

    // Give universal router access to tokens via permit2
    // If the inputted expiration is 0, the allowance only lasts the duration of the block.
    IPermit2(Constants.PERMIT2).approve(token, Constants.UNIVERSAL_ROUTER, SafeCast.toUint160(amount), 0);
  }

  function _validatePath(PathDecoder.Hop[] memory hops) private view {
    if (hops[hops.length - 1].tokenOut != address(outputToken)) {
      revert InvalidSwapPath();
    }
  }

  function _validateCapPerSwap(uint256 amount) private pure {
    if (amount == 0) revert InvalidCapPerSwap();
  }

  function _validateInterval(uint256 secs) private pure {
    if (secs < 60 || secs > 43200) revert InvalidInterval();
  }

  function _validateIncentiveFee(uint256 fee) private pure {
    if (fee > 1000) revert InvalidIncentiveFee();
  }

  function _validateBurnProxy(address proxy) private pure {
    if (proxy == address(0)) revert InvalidBurnProxy();
  }

  function _validateBurnPercentage(uint256 percentage) private pure {
    if (percentage > Constants.BASIS) revert InvalidBurnPercentage();
  }

  function _validatePriceTwa(uint32 mins) private pure {
    if (mins > 60) revert InvalidPriceTwa();
  }

  function _validateSlippage(uint256 slippage) private pure {
    if (slippage < 1 || slippage > 2500) revert InvalidSlippage();
  }
}