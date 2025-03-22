// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IOrxStaking.sol";
import "./lib/OracleLibrary.sol";
import "./lib/TickMath.sol";
import "./lib/constants.sol";

/// @title Stax Staking contract for Ouroboros
contract OrxStax is Ownable2Step {
    using SafeERC20 for IERC20;

    struct SingleSwapOptionsV3 {
        address tokenOut;
        uint24 fee;
    }

    // -------------------------- STATE VARIABLES -------------------------- //

    IOrxStaking constant OrxStaking = IOrxStaking(ORX_STAKING);

    /// @notice Stax Vault address that stores and distributes all rewards.
    address public immutable STAX_VAULT;

    /// @notice Timestamp of the last swap and stake.
    uint256 public lastSwapTime;
    /// @notice Timestamp of the last distribution.
    uint256 public lastDistributionTime;
    /// @notice Maximum amount per 1 swap in TitanX.
    uint256 public maxSwapAmount = 2_000_000_000 ether;
    /// @notice Maximum amount per 1 distribution in USDx.
    uint256 public maxDistributionAmount = 5_000 ether;
    /// @notice Cooldown time between swaps in seconds.
    uint64 public swapInterval = 1 hours;
    /// @notice Cooldown time between distributions in seconds.
    uint64 public distributionInterval = 1 hours;
    /// @notice Basis point incentive fee paid out for swapping and staking.
    uint16 public swapIncentiveFeeBPS = 60;
    /// @notice Basis point incentive fee paid out for claiming.
    uint16 public claimIncentiveFeeBPS = 30;
    /// @notice Basis point incentive fee paid out for distributing.
    uint16 public distributeIncentiveFeeBPS = 30;
    /// @notice Time used for TWAP calculation
    uint32 public secondsAgo = 5 minutes;
    /// @notice Allowed deviation of the minAmountOut from historical price during TitanX/ORX swaps.
    uint32 public orxDeviation = 1000;

    /// @notice Users who are whitelisted to perform token distributions.
    mapping(address => bool) public whitelistedUsers;
    /// @notice Tokens whitelisted to be distributed.
    mapping(address => bool) public distributionTokens;
    /// @notice Type of a token distribution. 0 - disabled; 1 - transfer; 2 - Uniswap v2; 3 - Uniswap v3.
    mapping(address => uint8) public distributionTypes;
    /// @notice Maximum amount of tokens to be distributed in a single call involving swaps.
    mapping(address => uint256) public distributionCaps;
    /// @notice Times of last distributions per token involving swaps.
    mapping(address => uint256) public tokenDistributionTimes;
    /// @notice Receiving address of the token distribution.
    mapping(address => address) public distributionTargets;
    /// @notice Does token utilize multihop swaps in distribution.
    mapping(address => bool) public isMultihopSwap;
    /// @notice Hashed path for a distribution of a token utilizing Uniswap V3 multihop path.
    mapping(address => bytes) public multihopSwapOptionsV3;
    /// @notice Output token info for Uniswap V3 single swap.
    mapping(address => SingleSwapOptionsV3) public swapOptionsV3;
    /// @notice Path of a swap for Uniswap V2 protocol.
    mapping(address => address[]) public swapOptionsV2;

    // ------------------------------- EVENTS ------------------------------ //

    event Swap();
    event Claim();
    event Distribution();

    // ------------------------------- ERRORS ------------------------------ //

    error Cooldown();
    error InsufficientBalance();
    error UnclaimedRewards();
    error NothingToClaim();
    error Prohibited();
    error TWAP();
    error Unauthorized();
    error ZeroAddress();
    error ZeroInput();
    error DuplicateDistributionToken();

    // ------------------------------ MODIFIERS ---------------------------- //

    modifier originCheck() {
        if (address(msg.sender).code.length != 0 || msg.sender != tx.origin) revert Unauthorized();
        _;
    }

    modifier onlyWhitelist() {
        if (!whitelistedUsers[msg.sender]) revert Unauthorized();
        _;
    }

    // ----------------------------- CONSTRUCTOR --------------------------- //

    constructor(address _owner, address _staxVault) Ownable(_owner) {
        if (_staxVault == address(0)) revert ZeroAddress();
        STAX_VAULT = _staxVault;
    }

    // --------------------------- PUBLIC FUNCTIONS ------------------------ //

    /// @notice Swaps available TitanX to ORX for future stakes
    /// @param minAmountOut Minimum ORX amount to receive in TitanX/ORX swap.
    /// @param deadline Deadline timestamp to perform the swap.
    function swapAndStake(uint256 minAmountOut, uint256 deadline) external originCheck {
        (uint256 time, uint256 amount) = getNextSwapInfo();
        if (time > block.timestamp) revert Cooldown();
        if (amount == 0) revert InsufficientBalance();
        lastSwapTime = block.timestamp;
        uint256 incentive = _calculateIncentiveFee(amount, swapIncentiveFeeBPS);
        IERC20(TITANX).safeTransfer(msg.sender, incentive);
        uint256 orxAmount = _swapTitanXToOrx(amount - incentive, minAmountOut, deadline);
        OrxStaking.stake(orxAmount);
        emit Swap();
    }

    /// @notice Claims rewards for all available stakes.
    function claim() external originCheck {
        uint256 claimAmount = OrxStaking.getPendingStableGain(address(this));
        if (claimAmount == 0) revert NothingToClaim();
        OrxStaking.unstake(0);
        uint256 incentive = _calculateIncentiveFee(claimAmount, claimIncentiveFeeBPS);
        IERC20 usdx = IERC20(USDX);
        usdx.safeTransfer(msg.sender, incentive);
        emit Claim();
    }

    /// @notice Distributes accumulated rewards to Stax Vault.
    /// @param minAmountOut Minimum TitanX amount to receive in USDx/TitanX swap.
    /// @param deadline Deadline timestamp to perform the swap.
    function distributeUsdx(uint256 minAmountOut, uint256 deadline) external onlyWhitelist {
        (uint256 time, uint256 amount) = getNextDistributionInfo();
        if (time > block.timestamp) revert Cooldown();
        if (amount == 0) revert InsufficientBalance();
        lastDistributionTime = block.timestamp;
        uint256 incentive = _calculateIncentiveFee(amount, distributeIncentiveFeeBPS);
        _swapUsdxToTitanX(amount - incentive, minAmountOut, deadline);
        IERC20(USDX).safeTransfer(msg.sender, incentive);
        emit Distribution();
    }

    /// @notice Distributes whitelisted tokens received as collateral rewards.
    /// @param token Address of a token to distribute.
    /// @param minAmountOut Minimum amount of tokens to receive from swap.
    /// @param deadline Deadline timestamp to perform the swap.
    function distributeToken(address token, uint256 minAmountOut, uint256 deadline) external {
        if (!distributionTokens[token]) revert Prohibited();

        uint8 distributionType = distributionTypes[token];
        if (distributionType == 1) return _transferToken(token);
        if (tokenDistributionTimes[token] + distributionInterval > block.timestamp) revert Cooldown();
        if (distributionType == 2) return _handleV2Swap(token, minAmountOut, deadline);
        if (distributionType == 3) return _handleV3Swap(token, minAmountOut, deadline);
        revert ZeroInput();
    }

    // ----------------------- ADMINISTRATIVE FUNCTIONS -------------------- //

    /// @notice Sets a new maximum amount of TitanX per swap.
    /// @param limit Amount in WEI.
    function setMaxSwapAmount(uint256 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        maxSwapAmount = limit;
    }

    /// @notice Sets a new maximum amount of USDx per distribution.
    /// @param limit Amount in WEI.
    function setMaxDistributionAmount(uint256 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        maxDistributionAmount = limit;
    }

    /// @notice Sets a new cooldown time per TitanX/Orx swap.
    /// @param limit Cooldown time in seconds.
    function setSwapInterval(uint64 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        swapInterval = limit;
    }

    /// @notice Sets a new cooldown time per distribution.
    /// @param limit Cooldown time in seconds.
    function setDistributionInterval(uint64 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        distributionInterval = limit;
    }

    /// @notice Sets a new swap incentive fee basis points.
    /// @param bps Incentive fee in basis points (1% = 100 bps).
    function setSwapIncentiveFee(uint16 bps) external onlyOwner {
        if (bps == 0 || bps > 1000) revert Prohibited();
        swapIncentiveFeeBPS = bps;
    }

    /// @notice Sets a new claim incentive fee basis points.
    /// @param bps Incentive fee in basis points (1% = 100 bps).
    function setClaimIncentiveFee(uint16 bps) external onlyOwner {
        if (bps == 0 || bps > 1000) revert Prohibited();
        claimIncentiveFeeBPS = bps;
    }

    /// @notice Sets a new distribute incentive fee basis points.
    /// @param bps Incentive fee in basis points (1% = 100 bps).
    function setDistributeIncentiveFee(uint16 bps) external onlyOwner {
        if (bps == 0 || bps > 1000) revert Prohibited();
        distributeIncentiveFeeBPS = bps;
    }

    /// @notice Sets the number of seconds to look back for TWAP price calculations.
    /// @param limit The number of seconds to use for TWAP price lookback.
    function setSecondsAgo(uint32 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        secondsAgo = limit;
    }

    /// @notice Sets the allowed price deviation for TWAP checks during TitanX/ORX swaps.
    /// @param limit The allowed deviation in basis points (e.g., 500 = 5%).
    function setOrxDeviation(uint32 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        if (limit > BPS_BASE) revert Prohibited();
        orxDeviation = limit;
    }

    /// @notice Adds a distribution token that requires a simple transfer.
    /// @param token Address of the token to be enabled.
    /// @param target Address of where to transfer the token.
    function addTransferToken(address token, address target) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (distributionTokens[token]) revert DuplicateDistributionToken();
        distributionTokens[token] = true;
        distributionTypes[token] = 1;
        distributionTargets[token] = target;
    }

    /// @notice Adds a distribution token that requires a Uniswap V2 swap.
    /// @param token Address of the token to be enabled.
    /// @param target Address of where to transfer swapped tokens.
    /// @param path Array of addresses from input token to output token. (Supports Multihop)
    /// @param capPerSwap Maximum amount of tokens to be distributed in a single call.
    function addUniswapV2Token(address token, address target, address[] memory path, uint256 capPerSwap) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (distributionTokens[token]) revert DuplicateDistributionToken();
        distributionTokens[token] = true;
        distributionTypes[token] = 2;
        distributionTargets[token] = target;
        swapOptionsV2[token] = path;
        distributionCaps[token] = capPerSwap;
    }

    /// @notice Adds a distribution token that requires a Uniswap V3 Single swap.
    /// @param token Address of the token to be enabled.
    /// @param target Address of where to transfer swapped tokens.
    /// @param tokenOut Address of the output token.
    /// @param poolFee Fee of the V3 pool between input and output tokens.
    /// @param capPerSwap Maximum amount of tokens to be distributed in a single call.
    function addUniswapV3Token(address token, address target, address tokenOut, uint24 poolFee, uint256 capPerSwap) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (distributionTokens[token]) revert DuplicateDistributionToken();
        distributionTokens[token] = true;
        distributionTypes[token] = 3;
        isMultihopSwap[token] = false;
        distributionTargets[token] = target;
        swapOptionsV3[token] = SingleSwapOptionsV3(tokenOut, poolFee);
        distributionCaps[token] = capPerSwap;
    }

    /// @notice Adds a distribution token that requires a Uniswap V3 Multihop swap.
    /// @param token Address of the token to be enabled.
    /// @param target Address of where to transfer swapped tokens.
    /// @param path Hashed path for the swap.
    /// @param capPerSwap Maximum amount of tokens to be distributed in a single call.
    function addUniswapV3MultihopToken(address token, address target, bytes memory path, uint256 capPerSwap) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (distributionTokens[token]) revert DuplicateDistributionToken();
        distributionTokens[token] = true;
        distributionTypes[token] = 3;
        isMultihopSwap[token] = true;
        distributionTargets[token] = target;
        multihopSwapOptionsV3[token] = path;
        distributionCaps[token] = capPerSwap;
    }

    /// @notice Removes a distribution token from whitelisted tokens.
    /// @param token Address of the token to be disabled.
    function disableDistributionToken(address token) external onlyOwner {
        if (!distributionTokens[token]) revert Prohibited();
        delete distributionTokens[token];
        delete distributionTypes[token];
        delete distributionTargets[token];
        delete distributionCaps[token];
        delete swapOptionsV2[token];
        delete swapOptionsV3[token];
        delete multihopSwapOptionsV3[token];
        delete isMultihopSwap[token];
    }

    /// @notice Sets the whitelist status for provided addresses for UniswapV2 token swaps.
    /// @param accounts List of wallets which status will be changed.
    /// @param isAllowed Status to be set.
    function setDistrbutionWhitelist(address[] calldata accounts, bool isAllowed) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelistedUsers[accounts[i]] = isAllowed;
        }
    }

    /// @notice Sets a new maximum amount of token per distribution.
    /// @param token Address of the token to edit.
    /// @param limit Amount in WEI.
    function setDistrbutionTokenCapPerSwap(address token, uint256 limit) external onlyOwner {
        if (!distributionTokens[token]) revert Prohibited();
        if (limit == 0) revert ZeroInput();
        distributionCaps[token] = limit;
    }

    // ---------------------------- VIEW FUNCTIONS ------------------------- //

    /// @notice Returns the information for the next swap.
    /// @return time The time next swap will be available.
    /// @return amount TitanX available for the next swap.
    function getNextSwapInfo() public view returns (uint256 time, uint256 amount) {
        uint256 balance = IERC20(TITANX).balanceOf(address(this));
        amount = balance > maxSwapAmount ? maxSwapAmount : balance;
        time = lastSwapTime + swapInterval;
    }

    /// @notice Returns the information for the next distribution.
    /// @return time The time next distribution will be available.
    /// @return amount USDx available for the next distribution.
    function getNextDistributionInfo() public view returns (uint256 time, uint256 amount) {
        uint256 balance = IERC20(USDX).balanceOf(address(this));
        amount = balance > maxDistributionAmount ? maxDistributionAmount : balance;
        time = lastDistributionTime + distributionInterval;
    }

    // -------------------------- INTERNAL FUNCTIONS ----------------------- //

    function _calculateIncentiveFee(uint256 amount, uint16 fee) internal pure returns (uint256) {
        return amount * fee / BPS_BASE;
    }

    function _swapTitanXToOrx(uint256 amountIn, uint256 minAmountOut, uint256 deadline) internal returns (uint256) {
        _twapCheck(TITANX, ORX, amountIn, minAmountOut, ORX_TITANX_POOL, orxDeviation);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: TITANX,
            tokenOut: ORX,
            fee: POOL_FEE_1PERCENT,
            recipient: address(this),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });
        IERC20(TITANX).safeIncreaseAllowance(UNISWAP_V3_ROUTER, amountIn);
        return ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(params);
    }

    function _swapUsdxToTitanX(uint256 amountIn, uint256 minAmountOut, uint256 deadline) internal {
        bytes memory path = abi.encodePacked(USDX, USDX_USDC_POOL_FEE, USDC, USDC_WETH_POOL_FEE, WETH9, POOL_FEE_1PERCENT, TITANX);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: STAX_VAULT,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });
        IERC20(USDX).safeIncreaseAllowance(UNISWAP_V3_ROUTER, amountIn);
        ISwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
    }

    function _twapCheck(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address poolAddress, uint32 deviation) internal view {
        uint32 _secondsAgo = secondsAgo;
        uint32 oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(poolAddress);
        if (oldestObservation < _secondsAgo) {
            _secondsAgo = oldestObservation;
        }

        (int24 arithmeticMeanTick,) = OracleLibrary.consult(poolAddress, _secondsAgo);
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        uint256 twapAmountOut =
            OracleLibrary.getQuoteForSqrtRatioX96(sqrtPriceX96, amountIn, tokenIn, tokenOut);
        uint256 lowerBound = (twapAmountOut * (BPS_BASE - deviation)) / BPS_BASE;
        if (minAmountOut < lowerBound) revert TWAP();
    }

    function _transferToken(address _token) internal {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) revert InsufficientBalance();
        uint256 incentive = _calculateIncentiveFee(balance, distributeIncentiveFeeBPS);
        balance -= incentive;
        token.safeTransfer(distributionTargets[_token], balance);
        token.safeTransfer(msg.sender, incentive);
        emit Distribution();
    }

    function _handleV2Swap(address _token, uint256 minAmountOut, uint256 deadline) internal onlyWhitelist {
        tokenDistributionTimes[_token] = block.timestamp;
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        uint256 capPerSwap = distributionCaps[_token];
        uint256 amountIn = balance > capPerSwap ? capPerSwap : balance;
        if (amountIn == 0) revert InsufficientBalance();
        uint256 incentive = _calculateIncentiveFee(amountIn, distributeIncentiveFeeBPS);
        amountIn -= incentive;
        token.safeIncreaseAllowance(UNISWAP_V2_ROUTER, amountIn);
        address[] memory path = swapOptionsV2[_token];
        IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn, minAmountOut, path, distributionTargets[_token], deadline
        );
        token.safeTransfer(msg.sender, incentive);
        emit Distribution();
    }

    function _handleV3Swap(address _token, uint256 minAmountOut, uint256 deadline) internal onlyWhitelist {
        tokenDistributionTimes[_token] = block.timestamp;
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        uint256 capPerSwap = distributionCaps[_token];
        uint256 amountIn = balance > capPerSwap ? capPerSwap : balance;
        if (amountIn == 0) revert InsufficientBalance();
        uint256 incentive = _calculateIncentiveFee(amountIn, distributeIncentiveFeeBPS);
        amountIn -= incentive;
        address target = distributionTargets[_token];
        token.safeIncreaseAllowance(UNISWAP_V3_ROUTER, amountIn);
        if (isMultihopSwap[_token]) {
            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: multihopSwapOptionsV3[_token],
                recipient: target,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut
            });
            ISwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
        } else {
            SingleSwapOptionsV3 memory options = swapOptionsV3[_token];
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: _token,
                tokenOut: options.tokenOut,
                fee: options.fee,
                recipient: target,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            });
            ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(params);
        }
        token.safeTransfer(msg.sender, incentive);
        emit Distribution();
    }
}