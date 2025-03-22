// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../interfaces/IWETH9.sol";
import "./lib/OracleLibrary.sol";
import "./lib/TickMath.sol";
import "./lib/constants.sol";
import "./HeliosStaxInstanceV2.sol";

/// @title Stax Staking V2 contract for Helios
contract HeliosStaxV2 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct SingleSwapOptionsV3 {
        address tokenOut;
        uint24 fee;
    }

    // -------------------------- STATE VARIABLES -------------------------- //

    /// @notice Number of total staking contract instances.
    uint256 public numInstances;
    /// @notice Current active staking contract instance.
    address payable public activeInstance;
    /// @notice Timestamp of the last distribution.
    uint256 public lastSwapTime;
    /// @notice Timestamp of the last stake.
    uint256 public lastStakeTime;
    /// @notice Timestamp of the last distribution.
    uint256 public lastDistributionTime;
    /// @notice Maximum amount per 1 swap in TitanX.
    uint256 public maxSwapAmount = 2_000_000_000 ether;
    /// @notice Minimum amount of Helios stake pool to omit cooldown restriction.
    uint256 public constant intervalOverride = 100_000_000_000 ether;
    /// @notice Minimum amount per 1 stake in Helios.
    uint256 public minStakeAmount = 100_000_000_000 ether;
    /// @notice Maximum amount per 1 distribution in ETH.
    uint256 public maxDistributionAmount = 3 ether;
    /// @notice Cooldown time between swaps in seconds.
    uint64 public swapInterval = 30 minutes;
    /// @notice Cooldown time between stakes in seconds.
    uint64 public stakeInterval = 7 days;
    /// @notice Cooldown time between distributions in seconds.
    uint64 public distributionInterval = 60 minutes;
    /// @notice Basis point incentive fee paid out for swapping.
    uint16 public swapIncentiveFeeBPS = 30;
    /// @notice Basis point incentive fee paid out for staking.
    uint16 public stakeIncentiveFeeBPS = 30;
    /// @notice Basis point incentive fee paid out for claiming.
    uint16 public claimIncentiveFeeBPS = 30;
    /// @notice Basis point incentive fee paid out for distributing.
    uint16 public distributeIncentiveFeeBPS = 30;
    /// @notice Time used for TWAP calculation
    uint32 public secondsAgo = 5 minutes;
    /// @notice Allowed deviation of the minAmountOut from historical price.
    uint32 public deviation = 500;
    /// @notice Addresses of staking contract instances.
    mapping(uint256 instanceId => address) public instances;

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
    event Stake();
    event Claim();
    event Distribution();
    event NewInstance(uint256 instanceId, address instanceAddress);

    // ------------------------------- ERRORS ------------------------------ //

    error Cooldown();
    error InsufficientBalance();
    error DuplicateDistributionToken();
    error NothingToClaim();
    error Prohibited();
    error TWAP();
    error Unauthorized();
    error ZeroAddress();
    error ZeroInput();

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

    constructor(address _owner) Ownable(_owner) {
        _deployInstance();
    }

    // --------------------------- PUBLIC FUNCTIONS ------------------------ //

    receive() external payable {}

    fallback() external payable {}

    /// @notice Swaps available TitanX to Helios for future stakes
    /// @param minAmountOut Minimum Helios amount to receive in TitanX/Helios swap.
    /// @param deadline Deadline timestamp to perform the swap.
    function swap(uint256 minAmountOut, uint256 deadline) external originCheck {
        (uint256 time, uint256 amount) = getNextSwapInfo();
        if (time > block.timestamp) revert Cooldown();
        if (amount == 0) revert InsufficientBalance();
        lastSwapTime = block.timestamp;
        uint256 incentive = _calculateIncentiveFee(amount, swapIncentiveFeeBPS);
        IERC20(TITANX).safeTransfer(msg.sender, incentive);
        _swapTitanXToHelios(amount - incentive, minAmountOut, deadline);
        emit Swap();
    }

    /// @notice Stakes all available Helios.
    function stake() external originCheck {
        (uint256 time, uint256 amount) = getNextStakeInfo();
        if (amount < intervalOverride) {
            if (time > block.timestamp) revert Cooldown();
            if (amount < minStakeAmount) revert InsufficientBalance();
        }
        lastStakeTime = block.timestamp;
        uint256 incentive = _calculateIncentiveFee(amount, stakeIncentiveFeeBPS);
        IERC20 helios = IERC20(HELIOS);
        helios.safeTransfer(msg.sender, incentive);
        helios.safeTransfer(activeInstance, amount - incentive);
        HeliosStaxInstanceV2(activeInstance).stake();
        emit Stake();
    }

    /// @notice Claims rewards for all available stakes.
    function claim() external originCheck nonReentrant {
        uint256 claimAmountTitanX;
        uint256 claimAmountEth;
        for (uint256 i = 0; i < numInstances; i++) {
            address payable instance = payable(instances[i]);
            (uint256 claimedTitanX, uint256 claimedEth) = HeliosStaxInstanceV2((instance)).claim();
            claimAmountTitanX += claimedTitanX;
            claimAmountEth += claimedEth;
        }
        if (claimAmountTitanX == 0 && claimAmountEth == 0) revert NothingToClaim();
        if (claimAmountTitanX > 0) {
            uint256 incentive = _calculateIncentiveFee(claimAmountTitanX, claimIncentiveFeeBPS);
            IERC20 titanX = IERC20(TITANX);
            titanX.safeTransfer(msg.sender, incentive);
            titanX.safeTransfer(STAX_VAULT, claimAmountTitanX - incentive);
        } else {
            uint256 incentive = _calculateIncentiveFee(claimAmountEth, claimIncentiveFeeBPS);
            Address.sendValue(payable(msg.sender), incentive);
        }
        emit Claim();
    }

    /// @notice Claims rewards from Helios Staking V2.
    /// @param instanceId ID of Helios Stax Instance to claim rewards.
    /// @param tokens Array of token addresses to claim rewards in.
    /// @param stakeIds Array of active stakeIds of the instance to claim rewards for.
    function claimV2Rewards(uint256 instanceId, address[] calldata tokens, uint256[] calldata stakeIds)
        external
        originCheck
    {
        address instance = instances[instanceId];
        if (instance == address(0)) revert ZeroAddress();
        //no incentive?
        uint256[] memory claimedRewards = HeliosStaxInstanceV2(payable(instance)).claimRewardsV2(tokens, stakeIds);
        uint256 numTokens = tokens.length;
        for (uint i = 0; i < numTokens; i++) {
            uint256 incentive = _calculateIncentiveFee(claimedRewards[i], claimIncentiveFeeBPS);
            IERC20(tokens[i]).safeTransfer(msg.sender, incentive);
        }
    }

    /// @notice Distributes accumulate ETH rewards to Stax Vault.
    /// @param minAmountOut Minimum TitanX amount to receive in ETH/TitanX swap.
    /// @param deadline Deadline timestamp to perform the swap.
    function distributeEthRewards(uint256 minAmountOut, uint256 deadline) external nonReentrant originCheck {
        (uint256 time, uint256 amount) = getNextDistributionInfo();
        if (time > block.timestamp) revert Cooldown();
        if (amount == 0) revert InsufficientBalance();
        lastDistributionTime = block.timestamp;
        uint256 incentive = _calculateIncentiveFee(amount, distributeIncentiveFeeBPS);
        _swapETHForTitanX(amount - incentive, minAmountOut, deadline);
        Address.sendValue(payable(msg.sender), incentive);
        emit Distribution();
    }

    /// @notice Distributes whitelisted tokens received from Helios Staking V2.
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

    /// @notice Creates a new staking contract instance.
    /// @dev Only available after 1000 stakes were created in the current instance.
    function deployNewInstance() external {
        if (!HeliosStaxInstanceV2(activeInstance).isAtMaxStakes()) revert Prohibited();
        _deployInstance();
    }

    // ----------------------- ADMINISTRATIVE FUNCTIONS -------------------- //

    /// @notice Sets a new maximum amount of TitanX per swap.
    /// @param limit Amount in WEI.
    function setMaxSwapAmount(uint256 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        maxSwapAmount = limit;
    }

    /// @notice Sets a new minimum amount of Helios per stake.
    /// @param limit Amount in WEI.
    function setMinStakeAmount(uint256 limit) external onlyOwner {
        minStakeAmount = limit;
    }

    /// @notice Sets a new maximum amount of ETH per distribution.
    /// @param limit Amount in WEI.
    function setMaxDistributionAmount(uint256 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        maxDistributionAmount = limit;
    }

    /// @notice Sets a new cooldown time per TitanX/Helios swap.
    /// @param limit Cooldown time in seconds.
    function setSwapInterval(uint64 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        swapInterval = limit;
    }

    /// @notice Sets a new cooldown time per staking.
    /// @param limit Cooldown time in seconds.
    function setStakeInterval(uint64 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        stakeInterval = limit;
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

    /// @notice Sets a new stake incentive fee basis points.
    /// @param bps Incentive fee in basis points (1% = 100 bps).
    function setStakeIncentiveFee(uint16 bps) external onlyOwner {
        if (bps == 0 || bps > 1000) revert Prohibited();
        stakeIncentiveFeeBPS = bps;
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

    /// @notice Sets the allowed price deviation for TWAP checks.
    /// @param limit The allowed deviation in basis points (e.g., 500 = 5%).
    function setDeviation(uint32 limit) external onlyOwner {
        if (limit == 0) revert ZeroInput();
        if (limit > BPS_BASE) revert Prohibited();
        deviation = limit;
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
    function addUniswapV2Token(address token, address target, address[] memory path, uint256 capPerSwap)
        external
        onlyOwner
    {
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
    function addUniswapV3Token(address token, address target, address tokenOut, uint24 poolFee, uint256 capPerSwap)
        external
        onlyOwner
    {
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
    function addUniswapV3MultihopToken(address token, address target, bytes memory path, uint256 capPerSwap)
        external
        onlyOwner
    {
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

    /// @notice Returns the information for the next stake.
    /// @return time The time next stake will be available.
    /// @return amount Helios available for the next stake.
    function getNextStakeInfo() public view returns (uint256 time, uint256 amount) {
        amount = IERC20(HELIOS).balanceOf(address(this));
        time = lastStakeTime + stakeInterval;
    }

    /// @notice Returns the information for the next distribution.
    /// @return time The time next distribution will be available.
    /// @return amount ETH available for the next distribution.
    function getNextDistributionInfo() public view returns (uint256 time, uint256 amount) {
        uint256 balance = address(this).balance;
        amount = balance > maxDistributionAmount ? maxDistributionAmount : balance;
        time = lastDistributionTime + distributionInterval;
    }

    /// @notice Returns total current unclaimed rewards across all instances.
    function getTotalUnclaimedRewards() external view returns (uint256 titanXRewards, uint256 ethRewards) {
        IHelios helios = IHelios(HELIOS);
        for (uint256 i = 0; i < numInstances; i++) {
            address instance = instances[i];
            titanXRewards += helios.getUserTitanXClaimableTotal(instance);
            ethRewards += helios.getUserETHClaimableTotal(instance);
        }
    }

    /// @notice Returns available matured stake.
    /// @return address Address of the instance.
    /// @return uint256 ID of the matured stake.
    function getMaturedStake() external view returns (address, uint256) {
        for (uint256 i = 0; i < numInstances; i++) {
            address payable _instance = payable(instances[i]);
            (bool mature, uint256 id) = HeliosStaxInstanceV2(_instance).stakeReachedMaturity();
            if (mature) return (_instance, id);
        }
        return (address(0), 0);
    }

    // -------------------------- INTERNAL FUNCTIONS ----------------------- //

    function _calculateIncentiveFee(uint256 amount, uint16 fee) internal pure returns (uint256) {
        return amount * fee / BPS_BASE;
    }

    function _deployInstance() internal {
        bytes memory bytecode = type(HeliosStaxInstanceV2).creationCode;
        uint256 instanceId = numInstances++;
        bytes32 salt = keccak256(abi.encodePacked(address(this), instanceId));
        address newInstance = Create2.deploy(0, salt, bytecode);
        activeInstance = payable(newInstance);
        instances[instanceId] = newInstance;
        emit NewInstance(instanceId, newInstance);
    }

    function _swapTitanXToHelios(uint256 amountIn, uint256 minAmountOut, uint256 deadline) internal {
        _twapCheck(TITANX, HELIOS, amountIn, minAmountOut);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: TITANX,
            tokenOut: HELIOS,
            fee: POOL_FEE_1PERCENT,
            recipient: address(this),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });
        IERC20(TITANX).safeIncreaseAllowance(UNISWAP_V3_ROUTER, amountIn);
        ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(params);
    }

    function _swapETHForTitanX(uint256 amountIn, uint256 minAmountOut, uint256 deadline) internal {
        IWETH9(WETH9).deposit{value: amountIn}();
        _twapCheck(WETH9, TITANX, amountIn, minAmountOut);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH9,
            tokenOut: TITANX,
            fee: POOL_FEE_1PERCENT,
            recipient: STAX_VAULT,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });
        IERC20(WETH9).safeIncreaseAllowance(UNISWAP_V3_ROUTER, amountIn);
        ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(params);
    }

    function _twapCheck(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut) internal view {
        address poolAddress = tokenIn == WETH9 ? TITANX_WETH_POOL : TITANX_HELIOS_POOL;
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
    }
}