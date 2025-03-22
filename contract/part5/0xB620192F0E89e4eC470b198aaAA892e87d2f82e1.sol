// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Interfaces - consolidate and minimize
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IExchangeRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IExchangeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IExchangePair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface ILendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
}

//ArbitrageBot Contract 
contract ArbitrageOptimus_Betatest is ReentrancyGuard {
    using SafeMath for uint256;
    
    // ======== Storage Optimization ========
    // Token address mapping
    mapping(string => address) public tokens;
    
    // Protocols
    IExchangeFactory public uniswapFactory;
    IExchangeFactory public sushiswapFactory;
    IExchangeRouter public uniswapRouter;
    IExchangeRouter public sushiswapRouter;
    ILendingPoolAddressesProvider public lendingPoolAddressesProvider;
    
    // State variables
    address public owner;
    address public feeCollector;
    uint256 public executorRewardPercentage = 10; // 10% executor reward default (TriggerContract)
    uint256 public protocolFeePercentage = 10;    // 10% protocol fee default (for Arbi or Keepers)
    uint256 public minProfitThreshold;
    bool public paused = false;
    uint256 public flashLoanFeeBP = 9; // 0.09% flash loan fee in basis points

    // Profitable Routes
    mapping(uint => uint256) public routeProfitHistory;
    mapping(uint => uint8) public routeSuccessRate; // 0-100 scale
    uint256 private constant SUCCESS_WEIGHT = 7;
    uint256 private constant PROFIT_WEIGHT = 3;
    
    // AutoTrigger
    address public autoTriggerBot;
    bool public isAutoTriggerEnabled = true;
    
    // Constants
    uint256 private constant SLIPPAGE_TOLERANCE = 990; // 1% slippage (divide by 1000)
    uint256 private constant BASIS_POINTS = 10000; // For percentage calculations
    uint256 private constant MAX_GAS_PRICE = 50 * 1e9; // Maximum gas price (50 gwei)
    
    // Optimized route structure
    struct Route {
        address[] path;
        bool isActive;
        bool isTriangle;
        address[] routers; // Array for hop
    }
    
    Route[] public routes;
    
    event ArbitrageExecuted(address indexed executor, uint profit, uint executorReward, uint protocolFee);
    event RouteAdded(uint routeId);
    event RouteUpdated(uint routeId, bool isActive);
    event ProfitThresholdUpdated(uint newThreshold);
    event SwapExecuted(address router, address[] path, uint amountIn, uint amountOut);
    event AutoTriggerReceived(address indexed sender, uint256 amount);
    event AutoTriggerBotUpdated(address indexed newAutoTriggerBot);
    event AutoTriggerStatusUpdated(bool isEnabled);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier whenNotPaused() {
        require(!paused, "!paused");
        _;
    }
    
    modifier onlyAutoTrigger() {
        require(msg.sender == autoTriggerBot && isAutoTriggerEnabled, "!rizzed");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        feeCollector = (address(this));
        // Hardcoded protocol addresses
        uniswapFactory = IExchangeFactory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        sushiswapFactory = IExchangeFactory(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
        uniswapRouter = IExchangeRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        sushiswapRouter = IExchangeRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
        lendingPoolAddressesProvider = ILendingPoolAddressesProvider(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);
        initializeTokens();  
        // Profit threshold (0.005 ETH)
        minProfitThreshold = 5000000000000000;    
    }
    
    // Initializing tokens
    function initializeTokens() private {
        if (block.chainid == 1) { // Ethereum Mainnet
            // Core tokens
            tokens["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            tokens["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            tokens["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
            tokens["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
            
            // Additional tokens
            initializeMoreTokens();
        } else {
            revert("!network");
        }
    }
    
    // Second part of token initialization to avoid stack too deep
    function initializeMoreTokens() private {
        tokens["UNI"] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
        tokens["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokens["AAVE"] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
        tokens["SUSHI"] = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
        tokens["SNX"] = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
        tokens["MKR"] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
        tokens["COMP"] = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        tokens["FRAX"] = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        tokens["LDO"] = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
        tokens["MATIC"] = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
        tokens["SHIB"] = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
    }
    
    // Receive function - handles plain ETH transfers
    receive() external payable {
        // Flag for arbitrage but don't execute directly - prevents reentrancy
        if (!paused && msg.sender == autoTriggerBot && isAutoTriggerEnabled) {
            emit AutoTriggerReceived(msg.sender, msg.value);
            // AutoTriggerBot should call executeArbitrageFromTrigger directly
        } else {
            // For all other senders, including owner, just accept the funds silently
        }
    }
    

    // Fallback function - handles calls to non-existent functions or ETH with data
    fallback() external payable {
        // Usually empty or with minimal logic
    }
    
    // ======== Route Setup Functions ========
    
    // Setup initial token pairs to monitor - only basic A-B swaps
    function setupInitialRoutes() external onlyOwner nonReentrant {
        // Create base tokens array
        address[] memory baseTokens = new address[](4);
        baseTokens[0] = tokens["WETH"];
        baseTokens[1] = tokens["USDC"];
        baseTokens[2] = tokens["USDT"];
        baseTokens[3] = tokens["WBTC"];
        
        // Create common tokens array
        address[] memory commonTokens = new address[](15);
        commonTokens[0] = tokens["WETH"];
        commonTokens[1] = tokens["USDC"];
        commonTokens[2] = tokens["USDT"];
        commonTokens[3] = tokens["WBTC"];

        commonTokens[4] = tokens["UNI"];
        commonTokens[5] = tokens["LINK"];
        commonTokens[6] = tokens["AAVE"];
        commonTokens[7] = tokens["SUSHI"];
        commonTokens[8] = tokens["SNX"];
        commonTokens[9] = tokens["MKR"];
        commonTokens[10] = tokens["COMP"];
        commonTokens[11] = tokens["FRAX"];
        commonTokens[12] = tokens["LDO"];
        commonTokens[13] = tokens["MATIC"];
        commonTokens[14] = tokens["SHIB"];
        
        // Create routes between each token and base tokens - only direct A-B swaps
        for (uint i = 0; i < commonTokens.length; i++) {
            for (uint j = 0; j < baseTokens.length; j++) {
                if (commonTokens[i] != baseTokens[j]) {
                    // Create uni->sushi path
                    address[] memory path = new address[](2);
                    path[0] = commonTokens[i];
                    path[1] = baseTokens[j];
                    
                    address[] memory routers = new address[](1);
                    routers[0] = address(sushiswapRouter);
                    
                    routes.push(Route({
                        path: path,
                        routers: routers,
                        isActive: true,
                        isTriangle: false
                    }));
                    
                    // Create sushi->uni path
                    address[] memory routers2 = new address[](1);
                    routers2[0] = address(uniswapRouter);
                    
                    routes.push(Route({
                        path: path,
                        routers: routers2,
                        isActive: true,
                        isTriangle: false
                    }));
                }
            }
        }
    }
    
    // Setup triangle routes separately
    function setupTriangleRoutes() external onlyOwner nonReentrant {
        // Create select tokens for triangular arbitrage
        address[] memory triangleTokens = new address[](8);
        triangleTokens[0] = tokens["UNI"];
        triangleTokens[1] = tokens["LINK"];
        triangleTokens[2] = tokens["AAVE"];
        triangleTokens[3] = tokens["SUSHI"];
        triangleTokens[4] = tokens["SNX"];
        triangleTokens[5] = tokens["WBTC"];
        triangleTokens[6] = tokens["MKR"];
        triangleTokens[7] = tokens["LDO"];
        
        // WETH -> Token -> USDC -> WETH pattern
        for (uint i = 0; i < triangleTokens.length; i++) {
            if (triangleTokens[i] != tokens["USDC"]) {
                address[] memory trianglePath = new address[](4);
                trianglePath[0] = tokens["WETH"];
                trianglePath[1] = triangleTokens[i];
                trianglePath[2] = tokens["USDC"];
                trianglePath[3] = tokens["WETH"];
                
                // Try different router combinations
                // Uni -> Sushi -> Uni
                address[] memory triangleRouters1 = new address[](3);
                triangleRouters1[0] = address(uniswapRouter);
                triangleRouters1[1] = address(sushiswapRouter);
                triangleRouters1[2] = address(uniswapRouter);
                
                routes.push(Route({
                    path: trianglePath,
                    routers: triangleRouters1,
                    isActive: true,
                    isTriangle: true
                }));
                
                // Sushi -> Uni -> Sushi
                address[] memory triangleRouters2 = new address[](3);
                triangleRouters2[0] = address(sushiswapRouter);
                triangleRouters2[1] = address(uniswapRouter);
                triangleRouters2[2] = address(sushiswapRouter);
                
                routes.push(Route({
                    path: trianglePath,
                    routers: triangleRouters2,
                    isActive: true,
                    isTriangle: true
                }));
            }
        }
    }
    
    // ======== Arbitrage Execution Functions ========
    
    // Main function to check for and execute arbitrage opportunities
    function executeArbitrage() public whenNotPaused {
        // Basic gas price protection
        require(tx.gasprice <= MAX_GAS_PRICE, "!Gasprice");
    
        // Find the best arbitrage opportunity
        (uint routeId, uint profit, uint loanAmount) = findArbitrageOpportunity();
    
        // Use fixed threshold instead of dynamic
        require(profit > minProfitThreshold, "!Profitbelow");
        require(loanAmount > 0, "!loanamount");
    
        // Get the selected route
        Route memory route = routes[routeId];
        require(route.isActive, "!Routeactive");
    
        // Prepare flash loan parameters
        address asset = route.path[0];
        address[] memory assets = new address[](1);
        assets[0] = asset;
    
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanAmount;
    
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // 0 = no debt
    
        // Encode parameters for the callback
        bytes memory params = abi.encode(routeId, msg.sender, profit);
    
        // Execute the flash loan
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());
        lendingPool.flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            params,
            0 // referral code
        );
    }
    
    // Called by Aave after transferring flash loan amount
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external nonReentrant returns (bool) {
        // Validate the caller
        address lendingPoolAddress = lendingPoolAddressesProvider.getLendingPool();
        require(msg.sender == lendingPoolAddress, "!caller");
        require(initiator == address(this), "!initiator");
        
        // Handle AutoTriggerBot if it initiated the transaction
        if (initiator == autoTriggerBot && isAutoTriggerEnabled) {
            return _handleAutoTriggerExecution(assets, amounts, premiums, params);
        }
        
        return _executeArbitrageOperation(assets, amounts, premiums, params);
    }
    
    // Handle Auto Trigger Execution - simplified without gas reimbursement
    function _handleAutoTriggerExecution(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        bytes calldata params
    ) private returns (bool) {
        // Extract parameters (removed gas tracking)
        (uint routeId, address executor, uint profit) = abi.decode(params, (uint, address, uint));
    
        // Make sure executor reward goes to AutoTriggerBot
        IERC20 token = IERC20(assets[0]);
    
        // Calculate rewards
        uint256 executorReward = amounts[0] * executorRewardPercentage / 100;
        uint256 protocolFee = amounts[0] * protocolFeePercentage / 100;
    
        // Send rewards to AutoTriggerBot
        token.transfer(autoTriggerBot, executorReward);
    
        // Notify AutoTriggerBot about the fee (reset failure counter)
        (bool feeRecorded, ) = autoTriggerBot.call(
            abi.encodeWithSignature("recordExecutorFee()")
        );
    
        // Send protocol fee
        if (feeCollector == autoTriggerBot) {
            token.transfer(autoTriggerBot, protocolFee);
        } else {
            if (feeCollector != address(this)) {
                token.transfer(feeCollector, protocolFee);
            }
        }
    
        // Simply continue the cycle without gas reimbursement
        (bool cycleSuccess, ) = autoTriggerBot.call(
            abi.encodeWithSignature("continueCycle()")
        );
        
        return true;
    } 
    
    // Extracted to reduce function size and avoid stack too deep
    function _executeArbitrageOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        bytes calldata params
    ) private returns (bool) {
        // Decode parameters
        (uint routeId, address executor, uint expectedProfit) = abi.decode(params, (uint, address, uint));
        
        // Validate route
        require(routeId < routes.length, "!routeID");
        require(executor == owner || executor == autoTriggerBot, "!executor");
        require(amounts[0] > 0, "!loanamount");
        
        // Get the selected route
        Route memory route = routes[routeId];
        require(route.isActive, "!Routeactive");
        
        // Calculate the loan repayment amount
        uint256 totalDebt = amounts[0] + premiums[0];
        
        // Execute the arbitrage using a helper function
        uint256 finalBalance = _executeArbitrageSwaps(routeId, assets[0], amounts[0]);
        
        // Calculate actual profit
        require(finalBalance >= totalDebt, "!fundstorepay");
        
        uint256 actualProfit = finalBalance - totalDebt;
        require(actualProfit > minProfitThreshold, "!profitbelow");
        
        // Calculate rewards
        uint256 executorReward = actualProfit * executorRewardPercentage / 100;
        uint256 protocolFee = actualProfit * protocolFeePercentage / 100;
        uint256 remainingProfit = actualProfit - executorReward - protocolFee;
        
        // Transfer rewards
        IERC20 token = IERC20(assets[0]);
        token.transfer(executor, executorReward);
        token.transfer(feeCollector, protocolFee);
        
        // Approve lending pool to take repayment
        _safeApprove(assets[0], msg.sender, totalDebt);
        
        // Emit event
        emit ArbitrageExecuted(executor, actualProfit, executorReward, protocolFee);

        // Update route statistics
        uint8 currentRate = routeSuccessRate[routeId];
        if (currentRate == 0) currentRate = 50; // Default 50% for new routes

        // Update success rate with 90% old, 10% new weighting
        routeSuccessRate[routeId] = uint8((uint16(currentRate) * 9 + uint16(100)) / 10);

        // Update profit history
        routeProfitHistory[routeId] += actualProfit;
        
        return true;
    }

    // Helper function to execute the actual swaps
    function _executeArbitrageSwaps(uint routeId, address asset, uint256 amount) private returns (uint256) {
        Route memory route = routes[routeId];
    
        if (route.isTriangle) {
            return executeTriangleArbitrage(route, asset, amount);
        } else {
            return executeSimpleArbitrage(route, asset, amount);
        }
    }
    
    function executeSimpleArbitrage(
        Route memory route, 
        address asset, 
        uint256 amount
    ) internal returns (uint256) {
        // For simple arbitrage, we expect just one router
        require(route.routers.length > 0, "!routers");
        
        address sourceRouter = route.routers[0];
        address[] memory path = route.path;
        
        // Construct the reverse path for the second swap
        uint pathLength = path.length;
        address[] memory reversePath = new address[](pathLength);
        for (uint i = 0; i < pathLength; i++) {
            reversePath[i] = path[pathLength - 1 - i];
        }
        
        // First swap
        uint[] memory amountsOut = IExchangeRouter(sourceRouter).getAmountsOut(amount, path);
        uint256 minAmountOut = amountsOut[amountsOut.length - 1].mul(SLIPPAGE_TOLERANCE).div(1000);
        
        _safeApprove(asset, sourceRouter, amount);
        
        uint[] memory swapResult = IExchangeRouter(sourceRouter).swapExactTokensForTokens(
            amount,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300
        );
        
        uint swapResultAmount = swapResult[swapResult.length - 1];
        emit SwapExecuted(sourceRouter, path, amount, swapResultAmount);
        
        // Second swap (opposite router)
        address targetRouter = sourceRouter == address(uniswapRouter) ? 
                              address(sushiswapRouter) : 
                              address(uniswapRouter);
        
        // Get intermediate token balance
        address intermediateToken = path[pathLength - 1];
        uint256 intermediateBalance = IERC20(intermediateToken).balanceOf(address(this));
        
        uint[] memory targetAmountsOut = IExchangeRouter(targetRouter).getAmountsOut(
            intermediateBalance, 
            reversePath
        );
        
        uint256 targetMinAmountOut = targetAmountsOut[targetAmountsOut.length - 1].mul(SLIPPAGE_TOLERANCE).div(1000);
        
        _safeApprove(intermediateToken, targetRouter, intermediateBalance);
        
        uint[] memory targetSwapResult = IExchangeRouter(targetRouter).swapExactTokensForTokens(
            intermediateBalance,
            targetMinAmountOut,
            reversePath,
            address(this),
            block.timestamp + 300
        );
        
        emit SwapExecuted(targetRouter, reversePath, intermediateBalance, targetSwapResult[targetSwapResult.length - 1]);
        
        return IERC20(asset).balanceOf(address(this));
    }
    
    function executeTriangleArbitrage(
        Route memory route, 
        address asset, 
        uint256 amount
    ) internal returns (uint256) {
        require(route.isTriangle, "Not a triangle route");
        require(route.path.length >= 3, "Invalid path length for triangle");
        require(route.path[0] == route.path[route.path.length - 1], "Path must form a cycle");
        require(route.routers.length == route.path.length - 1, "Invalid router count");
        
        uint256 currentAmount = amount;
        address currentToken = asset;
        
        // Execute each hop in the triangle
        for (uint i = 0; i < route.path.length - 1; i++) {
            address[] memory currentPath = new address[](2);
            currentPath[0] = route.path[i];
            currentPath[1] = route.path[i + 1];
            
            address currentRouter = route.routers[i];
            
            // Calculate expected output
            uint[] memory expectedAmounts = IExchangeRouter(currentRouter).getAmountsOut(
                currentAmount, 
                currentPath
            );
            
            // Set minimum output with slippage tolerance
            uint256 minOutput = expectedAmounts[1].mul(SLIPPAGE_TOLERANCE).div(1000);
            
            // Approve router to spend tokens
            _safeApprove(currentToken, currentRouter, currentAmount);
            
            // Execute swap
            uint[] memory swapResult = IExchangeRouter(currentRouter).swapExactTokensForTokens(
                currentAmount,
                minOutput,
                currentPath,
                address(this),
                block.timestamp + 300
            );
            
            emit SwapExecuted(currentRouter, currentPath, currentAmount, swapResult[1]);
            
            // Update current token and amount for next hop
            currentToken = currentPath[1];
            currentAmount = swapResult[1];
        }
        
        return IERC20(asset).balanceOf(address(this));
    }
    
    // ======== Opportunity Finding Functions ========
    
    // Find the best arbitrage opportunity
    function findArbitrageOpportunity() public view returns (uint routeId, uint profit, uint loanAmount) {
        uint bestProfit = 0;
        uint bestRoute = 0;
        uint bestLoanAmount = 0;
        
        // Use fixed threshold instead of dynamic
        uint routesLength = routes.length;
        
        // Only determine priority order for active routes to save gas
        uint activeRouteCount = 0;
        uint[] memory activeRoutes = new uint[](routesLength);
        uint[] memory routeScores = new uint[](routesLength);
        
        // First pass - count active routes and calculate scores
        for (uint i = 0; i < routesLength; i++) {
            if (!routes[i].isActive) continue;
            
            activeRoutes[activeRouteCount] = i;
            routeScores[activeRouteCount] = _getRouteScore(i);
            activeRouteCount++;
        }
        
        // Sort only top 15 routes to save gas - simple insertion sort
        for (uint i = 0; i < 15 && i < activeRouteCount; i++) {
            uint maxIndex = i;
            
            for (uint j = i + 1; j < activeRouteCount; j++) {
                if (routeScores[j] > routeScores[maxIndex]) {
                    maxIndex = j;
                }
            }
            
            if (maxIndex != i) {
                // Swap routes
                uint tempRoute = activeRoutes[i];
                activeRoutes[i] = activeRoutes[maxIndex];
                activeRoutes[maxIndex] = tempRoute;
                
                // Swap scores
                uint tempScore = routeScores[i];
                routeScores[i] = routeScores[maxIndex];
                routeScores[maxIndex] = tempScore;
            }
        }
        
        // Check routes in priority order
        for (uint i = 0; i < activeRouteCount; i++) {
            uint currentRouteId = activeRoutes[i];
            
            // Early termination after checking top routes if we found something good
            if (i > 10 && bestProfit > minProfitThreshold * 3) {
                break;
            }
            
            (uint currentProfit, uint optimalAmount) = calculateArbitrageProfitForRoute(currentRouteId);
            
            if (currentProfit > bestProfit) {
                bestProfit = currentProfit;
                bestRoute = currentRouteId;
                bestLoanAmount = optimalAmount;
            }
        }
        
        return (bestRoute, bestProfit, bestLoanAmount);
    }

    // Add this helper function after findArbitrageOpportunity
    function _getRouteScore(uint routeId) internal view returns (uint256) {
        // Default score of 50 for new routes
        uint8 successRate = routeSuccessRate[routeId];
        if (successRate == 0) successRate = 50;
    
        // Profit history factor (0 or 100)
        uint256 profitFactor = routeProfitHistory[routeId] > 0 ? 100 : 0;
    
        // Weighted average: 70% success rate, 30% profit history
        return (successRate * SUCCESS_WEIGHT + profitFactor * PROFIT_WEIGHT) / (SUCCESS_WEIGHT + PROFIT_WEIGHT);
    }
    
    // Calculate profit for a specific route
    function calculateArbitrageProfitForRoute(uint routeId) public view returns (uint profit, uint optimalAmount) {
        if (routeId >= routes.length || !routes[routeId].isActive) {
            return (0, 0);
        }
        
        Route memory route = routes[routeId];
        
        if (route.isTriangle) {
            return _calculateTriangleProfit(routeId);
        }
        
        // Use standard path for simple arbitrage
        return _calculateSimpleProfit(route);
    }
    
    // Extracted to reduce function size and avoid stack too deep
    function _calculateSimpleProfit(Route memory route) private view returns (uint profit, uint optimalAmount) {
        // Use sample amount based on token
        address token = route.path[0];
        uint8 decimals = _getTokenDecimals(token);
        uint sampleAmount = 10 ** uint(decimals);
        
        if (token == tokens["WETH"]) {
            sampleAmount = 10 ** 17; // 0.1 ETH
        } else if (token == tokens["WBTC"]) {
            sampleAmount = 10 ** 6; // 0.01 WBTC
        }
        
        // Get expected output from first swap
        address sourceRouter = route.routers[0];
        uint[] memory amountsOutSource;
        
        try IExchangeRouter(sourceRouter).getAmountsOut(sampleAmount, route.path) returns (uint[] memory amounts) {
            amountsOutSource = amounts;
        } catch {
            return (0, 0);
        }
        
        // Construct reverse path
        uint pathLength = route.path.length;
        address[] memory reversePath = new address[](pathLength);
        for (uint i = 0; i < pathLength; i++) {
            reversePath[i] = route.path[pathLength - 1 - i];
        }
        
        // Get output from target DEX
        address targetRouter = sourceRouter == address(uniswapRouter) ? 
                              address(sushiswapRouter) : 
                              address(uniswapRouter);
                              
        uint[] memory amountsOutTarget;
        try IExchangeRouter(targetRouter).getAmountsOut(
            amountsOutSource[amountsOutSource.length - 1], 
            reversePath
        ) returns (uint[] memory amounts) {
            amountsOutTarget = amounts;
        } catch {
            return (0, 0);
        }
        
        // Calculate potential profit
        uint potentialOutput = amountsOutTarget[amountsOutTarget.length - 1];
        uint flashLoanFee = sampleAmount * flashLoanFeeBP / BASIS_POINTS;
        
        // Check if profitable after flash loan fee
        if (potentialOutput <= sampleAmount + flashLoanFee) {
            return (0, 0);
        }
        
        // Raw profit - now just the difference minus flash loan fee
        uint rawProfit = potentialOutput - sampleAmount - flashLoanFee;
        
        // Find optimal trade size
        uint optimalSize = _findOptimalTradeSize(
            sampleAmount, 
            potentialOutput,
            route.path[0],
            targetRouter,
            route.path,
            reversePath
        );
        
        if (optimalSize > 0) {
            // Scale profit with discount for safety
            uint scaledProfit = rawProfit * optimalSize / sampleAmount;
            scaledProfit = scaledProfit * 95 / 100; // 5% safety discount
            
            return (scaledProfit, optimalSize);
        }
        
        return (rawProfit, sampleAmount);
    }
    
    // Calculate triangle arbitrage profit
    function _calculateTriangleProfit(uint routeId) private view returns (uint profit, uint optimalAmount) {
        Route memory route = routes[routeId];
        if (!_isValidTrianglePath(route)) return (0, 0);
    
        uint sampleAmount = 10**17; // 0.1 ETH or equivalent
        uint finalAmount = _simulateTriangleArbitrage(route, sampleAmount);
    
        // Only consider flash loan fee
        uint costs = sampleAmount * flashLoanFeeBP / BASIS_POINTS;
        if (finalAmount <= sampleAmount + costs) return (0, 0);
    
        uint rawProfit = finalAmount - sampleAmount - costs;
        // Apply a safety discount and return
        return (rawProfit * 95 / 100, sampleAmount * 2);
    }

    // Helper to validate triangle path
    function _isValidTrianglePath(Route memory route) private pure returns (bool) {
        return route.isTriangle && 
           route.path.length >= 3 && 
           route.path[0] == route.path[route.path.length - 1] &&
           route.routers.length == route.path.length - 1;
    }
    
    // Find optimal trade size for triangle arbitrage
    function _findOptimalTriangleSize(Route memory route, uint sampleAmount, uint outputAmount) internal view returns (uint) {
        // Start with sample amount as optimal
        uint optimalSize = sampleAmount;
        uint maxProfit = outputAmount - sampleAmount;
        
        // Test different multiples (2x, 5x, 10x)
        uint[] memory testMultiples = new uint[](3);
        testMultiples[0] = 2;
        testMultiples[1] = 5;
        testMultiples[2] = 10;
        
        for (uint i = 0; i < testMultiples.length; i++) {
            uint testSize = sampleAmount * testMultiples[i];
            uint expectedOutput = _simulateTriangleArbitrage(route, testSize);
            
            if (expectedOutput > testSize) {
                uint profit = expectedOutput - testSize;
                
                // Apply price impact scaling (profit doesn't scale linearly)
                uint scaledProfit = profit * (95 - i * 5) / 100; // Progressive discount
                
                if (scaledProfit > maxProfit) {
                    maxProfit = scaledProfit;
                    optimalSize = testSize;
                }
            }
        }
        
        // Set an upper bound based on pool liquidity
        uint maxSafeSize = _getMaxSafeTradeSize(route.path[0], route.path[1], route.routers[0]);
        if (optimalSize > maxSafeSize) {
            optimalSize = maxSafeSize;
        }
        
        return optimalSize;
    }
    
    // Simulate triangle arbitrage
    function _simulateTriangleArbitrage(Route memory route, uint256 amount) internal view returns (uint256) {
        uint currentAmount = amount;
        
        // Execute each hop simulation with simplified slippage model
        for (uint i = 0; i < route.path.length - 1; i++) {
            address[] memory currentPath = new address[](2);
            currentPath[0] = route.path[i];
            currentPath[1] = route.path[i + 1];
            
            address currentRouter = route.routers[i];
            
            try IExchangeRouter(currentRouter).getAmountsOut(currentAmount, currentPath) returns (uint[] memory amounts) {
               
                uint slippageAdjustment = 990; // Default 1% slippage
                
                if (amount > 10**18) { // > 1 ETH equivalent
                    slippageAdjustment = 985; // 1.5% slippage for larger amounts
                }
                
                currentAmount = amounts[1] * slippageAdjustment / 1000;
            } catch {
                return 0;
            }
        }
        
        return currentAmount;
    }
    
    // Find optimal trade size
    function _findOptimalTradeSize(uint sampleAmount, uint sampleOutput, address tokenA, address targetRouter, address[] memory path, address[] memory reversePath) 
    internal view returns (uint) {
        // Start with sample amount as baseline
        uint optimalSize = sampleAmount;
        uint bestProfit = sampleOutput - sampleAmount;
        
        // Test with 2x and 5x amounts
        uint[] memory testMultiples = new uint[](2);
        testMultiples[0] = 2;
        testMultiples[1] = 5;
        
        for (uint i = 0; i < testMultiples.length; i++) {
            uint testSize = sampleAmount * testMultiples[i];
            
            // Simulate trade with larger amount
            uint expectedOutput = _simulateTrade(testSize, path, reversePath);
            
            // Calculate flash loan fee
            uint flashLoanFee = testSize * flashLoanFeeBP / BASIS_POINTS;
            
            if (expectedOutput <= testSize + flashLoanFee) {
                continue; // Not profitable at this size
            }
            
            uint profit = expectedOutput - testSize - flashLoanFee;
            
            // Apply diminishing returns model as size increases
            uint adjustedProfit = profit * (100 - i * 5) / 100;
            
            if (adjustedProfit > bestProfit) {
                bestProfit = adjustedProfit;
                optimalSize = testSize;
            }
        }
        
        // Check maximum safe size based on pool liquidity
        uint maxSafeSize = _getMaxSafeTradeSize(tokenA, path[path.length-1], address(uniswapRouter));
        if (optimalSize > maxSafeSize) {
            optimalSize = maxSafeSize;
        }
        
        return optimalSize;
    }
    
    // Simulate a complete trade
    function _simulateTrade(
        uint amount,
        address[] memory path,
        address[] memory reversePath
    ) internal view returns (uint) {
        // First swap simulation
        uint[] memory sourceAmounts;
        try IExchangeRouter(address(uniswapRouter)).getAmountsOut(amount, path) returns (uint[] memory amounts) {
            sourceAmounts = amounts;
        } catch {
            return 0;
        }
        
        // Second swap simulation
        uint[] memory targetAmounts;
        try IExchangeRouter(address(sushiswapRouter)).getAmountsOut(
            sourceAmounts[sourceAmounts.length - 1], 
            reversePath
        ) returns (uint[] memory amounts) {
            targetAmounts = amounts;
        } catch {
            return 0;
        }
        
        // Return final amount with slippage adjustment for larger amounts
        return targetAmounts[targetAmounts.length - 1] * SLIPPAGE_TOLERANCE / 1000;
    }
    
    // Get maximum safe trade size based on pool liquidity
    function _getMaxSafeTradeSize(address tokenA, address tokenB, address router) internal view returns (uint) {
        address factory = router == address(uniswapRouter) ? 
                          address(uniswapFactory) : 
                          address(sushiswapFactory);
                         
        address pair = IExchangeFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) return 0;
        
        // Get reserves from the pair
        (uint reserve0, uint reserve1, ) = IExchangePair(pair).getReserves();
        
        // Determine which reserve corresponds to tokenA
        bool isToken0 = IExchangePair(pair).token0() == tokenA;
        uint reserveA = isToken0 ? reserve0 : reserve1;
        
        // Set maximum size to a percentage of the pool's reserve
        return reserveA / 10; // 10% of pool's reserve
    }
    
    // Get token decimals
    function _getTokenDecimals(address token) internal view returns (uint8) {
        // Check common tokens first
        if (token == tokens["WETH"]) {
            return 18;
        } 
        if (token == tokens["USDC"] || token == tokens["USDT"]) {
            return 6;
        } 
        if (token == tokens["WBTC"]) {
            return 8;
        }
        
        // For other tokens, try to get decimals
        try IERC20(token).decimals() returns (uint8 dec) {
            return dec;
        } catch {
            return 18; // Default
        }
    }
    
    // Safe approve function
    function _safeApprove(address token, address spender, uint256 amount) internal {
        // First try to approve directly
        try IERC20(token).approve(spender, amount) {
            // Successfully approved
        } catch {
            // If failed, try resetting to 0 first
            try IERC20(token).approve(spender, 0) {
                // Then set to desired amount
                IERC20(token).approve(spender, amount);
            } catch {
                // If everything fails, revert
                revert("!Approval");
            }
        }
    }
    
    // ======== AutoTriggerBot Management Functions ========
    
    // Set the AutoTriggerBot address
    function setAutoTriggerBot(address _autoTriggerBot) external onlyOwner {
        require(_autoTriggerBot != address(0), "!address");
        autoTriggerBot = _autoTriggerBot;
        emit AutoTriggerBotUpdated(_autoTriggerBot);
    }
    
    // Enable or disable the AutoTriggerBot integration
    function setAutoTriggerEnabled(bool _enabled) external onlyOwner {
        isAutoTriggerEnabled = _enabled;
        emit AutoTriggerStatusUpdated(_enabled);
    }
    
    // Execute arbitrage from AutoTriggerBot - simplified without gas tracking
    function executeArbitrageFromTrigger() external onlyAutoTrigger {
        // Find the best arbitrage opportunity
        (uint routeId, uint profit, uint loanAmount) = findArbitrageOpportunity();
        
        // Check if opportunity is profitable
        bool isProfit = profit > minProfitThreshold && loanAmount > 0;
        
        if (isProfit) {
            // Get the selected route
            Route memory route = routes[routeId];
            if (route.isActive) {
                // Prepare flash loan parameters
                address asset = route.path[0];
                address[] memory assets = new address[](1);
                assets[0] = asset;
                
                uint256[] memory amounts = new uint256[](1);
                amounts[0] = loanAmount;
                
                uint256[] memory modes = new uint256[](1);
                modes[0] = 0; // 0 = no debt
                
                // Encode parameters without gas tracking
                bytes memory params = abi.encode(routeId, autoTriggerBot, profit);
                
                // Execute the flash loan
                ILendingPool lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());
                lendingPool.flashLoan(
                    address(this),
                    assets,
                    amounts,
                    modes,
                    address(this),
                    params,
                    0 // referral code
                );
                return; // Exit after execution
            }
        }
        
        // No profitable opportunity found, continue cycle
        (bool success, ) = autoTriggerBot.call(
            abi.encodeWithSignature("continueCycle()")
        );
    }
    
    // ======== Owner Management Functions ========
    // Add or update token addresses in the contract
    function addTokens(string[] calldata symbols, address[] calldata addresses) external onlyOwner {
        require(symbols.length == addresses.length, "!Arraylength");
        
        for (uint i = 0; i < symbols.length; i++) {
            require(addresses[i] != address(0), "!tokenaddress");
            tokens[symbols[i]] = addresses[i];
        }
        
        // Optional: automatically add routes for new tokens
        if (symbols.length > 0) {
            _addRoutesForNewTokens(symbols);
        }
    }
    
    // Helper function to add standard routes for new tokens
    function _addRoutesForNewTokens(string[] calldata symbols) internal {
        // Base tokens to pair with
        address[] memory baseTokens = new address[](4);
        baseTokens[0] = tokens["WETH"];
        baseTokens[1] = tokens["USDC"];
        baseTokens[2] = tokens["USDT"];
        baseTokens[3] = tokens["WBTC"];
        
        // Add basic routes for each new token
        for (uint i = 0; i < symbols.length; i++) {
            address newToken = tokens[symbols[i]];
            
            for (uint j = 0; j < baseTokens.length; j++) {
                if (newToken != baseTokens[j]) {
                    
                    // Create uni->sushi path
                    address[] memory path = new address[](2);
                    path[0] = newToken;
                    path[1] = baseTokens[j];
                    
                    address[] memory routers = new address[](1);
                    routers[0] = address(sushiswapRouter);
                    
                    routes.push(Route({
                        path: path,
                        routers: routers,
                        isActive: true,
                        isTriangle: false
                    }));
                    
                    // Create sushi->uni path
                    address[] memory routers2 = new address[](1);
                    routers2[0] = address(uniswapRouter);
                    
                    routes.push(Route({
                        path: path,
                        routers: routers2,
                        isActive: true,
                        isTriangle: false
                    }));
                }
            }
        }
    }
    
    // Add a new route to monitor
    function addRoute(
        address[] calldata path,
        address[] calldata routers,
        bool isActive,
        bool isTriangle
    ) external onlyOwner {
        require(path.length >= 2, "!pathlength");
        
        if (isTriangle) {
            require(path.length >= 3, "!min3hops");
            require(path[0] == path[path.length - 1], "!cycle");
            require(routers.length == path.length - 1, "!routercount");
        } else {
            require(routers.length > 0, "!router");
        }
        
        routes.push(Route({
            path: path,
            routers: routers,
            isActive: isActive,
            isTriangle: isTriangle
        }));
        
        emit RouteAdded(routes.length - 1);
    }
    
    // Update existing route status
    function updateRouteStatus(uint routeId, bool isActive) external onlyOwner {
        require(routeId < routes.length, "!routeID");
        routes[routeId].isActive = isActive;
        
        emit RouteUpdated(routeId, isActive);
    }
    
    // Update profit threshold
    function updateProfitThreshold(uint256 newThreshold) external onlyOwner {
        minProfitThreshold = newThreshold;
        
        emit ProfitThresholdUpdated(newThreshold);
    }
    
    // Update fee percentages
    function updateFeePercentages(uint256 executorPct, uint256 protocolPct) external onlyOwner {
        require(executorPct <= 100, "!Executor+"); // Cap at 100%
        require(protocolPct <= 100, "!Protocol+"); // Cap at 100%
        executorRewardPercentage = executorPct;
        protocolFeePercentage = protocolPct;
    }

    // Update fee collector address
    function updateFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "!address");
        feeCollector = newCollector;
    }

    // Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "!address");
        owner = newOwner;
    }
    
    // Emergency functions
    function pause() external onlyOwner {
        paused = true;
    }
    
    function unpause() external onlyOwner {
        paused = false;
    }
    
    // Recovery functions
    function recoverTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }
    
    function recoverETH() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    // Helper view functions
    function getRouteCount() external view returns (uint) {
        return routes.length;
    }
    
    function checkArbitrageOpportunity() external view returns (bool isAvailable, uint expectedProfit) {
        (uint routeId, uint profit, ) = findArbitrageOpportunity();
        return (profit > minProfitThreshold, profit);
    }
    
    // Function to manually execute arbitrage on a specific route
    function executeArbitrageOnRoute(uint routeId) external onlyOwner whenNotPaused {
        require(tx.gasprice <= MAX_GAS_PRICE, "!Gasprice");
        require(routeId < routes.length, "!routeID");
        require(routes[routeId].isActive, "!active");
        
        (uint profit, uint loanAmount) = calculateArbitrageProfitForRoute(routeId);
        
        require(profit > minProfitThreshold, "!profit");
        require(loanAmount > 0, "!loanamount");
        
        // Execute flash loan for this route
        _executeFlashLoanForRoute(routeId, loanAmount, profit);
    }
    
    // Helper function to reduce contract size
    function _executeFlashLoanForRoute(uint routeId, uint loanAmount, uint profit) private {
        Route memory route = routes[routeId];
        address asset = route.path[0];
        
        address[] memory assets = new address[](1);
        assets[0] = asset;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanAmount;
        
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // 0 = no debt
        
        bytes memory params = abi.encode(routeId, msg.sender, profit);
        
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());
        lendingPool.flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            params,
            0
        );
    }
}