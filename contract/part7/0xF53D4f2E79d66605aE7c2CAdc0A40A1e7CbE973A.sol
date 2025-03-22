// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IUniswapV3Factory.sol";
import "../interfaces/IShogun.sol";
import "../interfaces/IX28.sol";
import "./openzeppelin/security/ReentrancyGuard.sol";
import "./openzeppelin/token/ERC721/IERC165.sol";

import "../libs/Constant.sol";
import "../libs/UniswapV2Library.sol";
import "../libs/CallbackValidation.sol";
import "../libs/OracleLibrary.sol";

contract BuyAndBurnShogun is ReentrancyGuard {
    /** @dev Shogun genesis timestamp */
    uint256 private s_shogunGenesisTs;

    /** @dev Shogun contract address */
    address private s_shogunAddress;

    /** @dev owner address */
    address private s_ownerAddress;

    /** @dev Shogun TitanX uniswapv2 pool address */
    address private s_poolAddress;

    //TitanX to X28
    /** @dev TitanX to X28 */
    uint256 private s_totalTitanXBuy;

    /** @dev X28 bought via TitanX > X28 burned */
    uint256 private s_totalX28Burned;

    /** @dev X28 to Shogun */
    uint256 private s_totalX28Buy;

    //burn stats
    /** @dev tracks Shogun burned through buyandburn */
    uint256 private s_totalShogunBurn;

    //config variables
    //TitanX
    /** @dev tracks current per swap cap TitanX */
    uint256 private s_capPerSwapTitanX;

    /** @dev tracks timestamp of the last TitanX buy X28 was called */
    uint256 private s_lastCallTsBuynBurnTitanX;

    /** @dev TitanX slippage */
    uint256 private s_slippageBuynBurnTitanX;

    /** @dev TitanX incentive fee dividend amount */
    uint256 private s_TitanXIncentiveDividend;

    /** @dev current TitanX swap cap per interval */
    uint256 private s_currentCapPerIntervalTitanX;

    //X28
    /** @dev tracks current per swap cap X28 */
    uint256 private s_capPerSwapX28;

    /** @dev tracks timestamp of the last X28 buy Shogun and burn was called */
    uint256 private s_lastCallTsBuynBurnX28;

    /** @dev X28 slippage */
    uint256 private s_slippageBuynBurnX28;

    /** @dev X28 incentive fee dividend amount */
    uint256 private s_X28IncentiveDividend;

    /** @dev current X28 swap cap per interval */
    uint256 private s_currentCapPerIntervalX28;

    /** @dev uniswapv3 oracle price seconds ago */
    uint32 private s_twapSecondsAgo;

    /** @dev max cap for missed interval accumulation */
    uint256 private s_maxIntervalAccumulation;

    //event
    event BoughtX28(uint256 indexed titanx, uint256 indexed x28, address indexed caller);
    event BoughtAndBurned(uint256 indexed x28, uint256 indexed Shogun, address indexed caller);

    constructor() {
        s_ownerAddress = msg.sender;

        s_capPerSwapTitanX = 1e5 ether;
        s_slippageBuynBurnTitanX = MIN_SLIPPAGE_TITANX;
        s_TitanXIncentiveDividend = 5000;

        s_capPerSwapX28 = 1e5 ether;
        s_slippageBuynBurnX28 = MIN_SLIPPAGE_X28;
        s_X28IncentiveDividend = 5000;

        s_twapSecondsAgo = 300;
        s_maxIntervalAccumulation = 3;
    }

    /** @notice remove owner */
    function renounceOwnership() public {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        s_ownerAddress = address(0);
    }

    /** @notice set new owner address. Only callable by owner address.
     * @param ownerAddress new owner address
     */
    function setOwnerAddress(address ownerAddress) external {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        require(ownerAddress != address(0), "InvalidAddress");
        s_ownerAddress = ownerAddress;
    }

    /** @notice set Shogun address. One-time setter. Only callable by owner address.
     * @param shogunAddress Shogun contract address
     */
    function setShogunContractAddress(address shogunAddress) external {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        require(s_shogunAddress == address(0), "CannotResetAddress");
        require(shogunAddress != address(0), "InvalidAddress");
        s_shogunAddress = shogunAddress;
        uint256 genesisTs = IShogun(shogunAddress).genesisTs();
        s_shogunGenesisTs = genesisTs;
        s_lastCallTsBuynBurnTitanX = genesisTs;
        s_lastCallTsBuynBurnX28 = genesisTs;
        _createPool();
        _createInitialLiquidity();
    }

    /**
     * @notice set TitanX cap amount per buynburn call. Only callable by owner address.
     * @param amount amount in 18 decimals
     */
    function setCapPerSwapTitanX(uint256 amount) external {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        s_capPerSwapTitanX = amount;
    }

    /**
     * @notice set buy and burn slippage % minimum received amount. Only callable by owner address.
     * @param amount amount from 5 - 15
     */
    function setTitanXSlippage(uint256 amount) external {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        require(amount >= MIN_SLIPPAGE_TITANX && amount <= MAX_SLIPPAGE_TITANX, "5-15_Only");
        s_slippageBuynBurnTitanX = amount;
    }

    /** @notice set TitanX incentive fee percentage callable by owner only
     * amount is in 10000 scaling factor, which means 0.33 is 0.33 * 10000 = 3300
     * @param amount amount between 1 - 10000
     */
    function setTitanXIncentiveFeeDividend(uint256 amount) external {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        require(amount != 0 && amount <= 10000, "InvalidAmount");
        s_TitanXIncentiveDividend = amount;
    }

    /**
     * @notice set X28 cap amount per buynburn call. Only callable by owner address.
     * @param amount amount in 18 decimals
     */
    function setCapPerSwapX28(uint256 amount) external {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        s_capPerSwapX28 = amount;
    }

    /**
     * @notice set buy and burn slippage % minimum received amount. Only callable by owner address.
     * @param amount amount from 5 - 15
     */
    function setX28Slippage(uint256 amount) external {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        require(amount >= MIN_SLIPPAGE_X28 && amount <= MAX_SLIPPAGE_X28, "5-15_Only");
        s_slippageBuynBurnX28 = amount;
    }

    /** @notice set X28 incentive fee percentage callable by owner only
     * amount is in 10000 scaling factor, which means 0.33 is 0.33 * 10000 = 3300
     * @param amount amount between 1 - 10000
     */
    function setX28IncentiveFeeDividend(uint256 amount) external {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        require(amount != 0 && amount <= 10000, "InvalidAmount");
        s_X28IncentiveDividend = amount;
    }

    /**
     * @notice set twap seconds ago. Only callable by owner address.
     * @param secs amount in seconds
     */
    function setTwapSecondsAgo(uint32 secs) external {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        require(secs >= MIN_TWAP_SECONDS && secs <= MAX_TWAP_SECONDS, "5min-12h_Only");
        s_twapSecondsAgo = secs;
    }

    /**
     * @notice set max for missed interval accumulation. Only callable by owner address.
     * @param max number
     */
    function setMaxIntervalAccumulations(uint256 max) external {
        require(msg.sender == s_ownerAddress, "InvalidCaller");
        require(max != 0, "CannotZero");
        s_maxIntervalAccumulation = max;
    }

    /** @notice burn all Shogun in BuyAndBurn address */
    function burnShogun() public {
        IShogun(s_shogunAddress).burnCAShogun(address(this));
    }

    /** @notice daily update only callable by Shogun contract
     * this will sync daily update with Shogun
     * reset & calculate daily B&B funds + swap cap per interval
     */
    function dailyUpdate() external {
        require(msg.sender == s_shogunAddress, "InvalidCaller");

        //Initial phase of 28 days to use 28% of balance
        //Phase 2 is from day 29 onwards to use 8% of balance
        uint256 percent = ((block.timestamp - s_shogunGenesisTs) / 1 days) + 1 <= 28
            ? INITIAL_PHASE_BNB_FUNDS_PERCENT
            : PHASE_2_BNB_FUNDS_PERCENT;
        _updateTitanXCap(percent);
        _updateX28Cap(percent);
    }

    /** @notice buy and burn Shogun from uniswap pool */
    function buyX28() public nonReentrant {
        require(msg.sender == tx.origin, "InvalidCaller");
        uint256 balance = IERC20(TITANX).balanceOf(address(this));
        require(balance != 0, "NoAvailableFunds");
        require(block.timestamp - s_lastCallTsBuynBurnTitanX > INTERVAL_SECONDS, "IntervalWait");
        _titanXBuyX28(balance);
    }

    /** @notice buy and burn Shogun from uniswap pool */
    function buynBurn() public nonReentrant {
        require(msg.sender == tx.origin, "InvalidCaller");
        uint256 balance = IERC20(X28).balanceOf(address(this));
        require(balance != 0, "NoAvailableFunds");
        require(block.timestamp - s_lastCallTsBuynBurnX28 > INTERVAL_SECONDS, "IntervalWait");
        _x28BuyShogun(balance);
    }

    /** @notice Used by uniswapV3. Modified from uniswapV3 swap callback function to complete the swap */
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported

        IUniswapV3Pool pool = CallbackValidation.verifyCallback(
            UNISWAPV3FACTORY,
            TITANX,
            X28,
            POOLFEE1PERCENT
        );
        require(address(pool) == X28_TITANX_POOL, "WrongPool");

        uint256 swapAmount = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        s_totalTitanXBuy += swapAmount;
        IERC20(TITANX).transfer(msg.sender, swapAmount);
    }

    // ==================== Private Functions =======================================
    /** @dev reset interval count + calculate daily B&B funds with swap cap per interval */
    function _updateTitanXCap(uint256 percent) private {
        uint256 balance = IERC20(TITANX).balanceOf(address(this));
        if (balance == 0) {
            s_currentCapPerIntervalTitanX = 0;
            return;
        }
        s_currentCapPerIntervalTitanX = (balance * percent) / PERCENT_BPS / MAX_INTERVALS;
    }

    /** @dev reset interval count + calculate daily B&B funds with swap cap per interval */
    function _updateX28Cap(uint256 percent) private {
        uint256 balance = IERC20(X28).balanceOf(address(this));
        if (balance == 0) {
            s_currentCapPerIntervalX28 = 0;
            return;
        }
        s_currentCapPerIntervalX28 = (balance * percent) / PERCENT_BPS / MAX_INTERVALS;
    }

    /** @dev create pool */
    function _createPool() private {
        require(s_poolAddress == address(0), "PoolHasCreated");
        s_poolAddress = IUniswapV2Factory(UNISWAPV2FACTORY).createPair(s_shogunAddress, X28);
        require(
            s_poolAddress == IUniswapV2Factory(UNISWAPV2FACTORY).getPair(s_shogunAddress, X28),
            "CreatePairFailed"
        );
    }

    /** @dev create initial liquidity */
    function _createInitialLiquidity() private {
        IShogun(s_shogunAddress).mintLPTokens();
        _mintPosition();
    }

    /** @dev mint full range LP token */
    function _mintPosition() private {
        IERC20(X28).transfer(s_poolAddress, INITIAL_LP_X28);
        IERC20(s_shogunAddress).transfer(s_poolAddress, INITIAL_LP_SHOGUN);
        IUniswapV2Pair(s_poolAddress).mint(address(this));
    }

    /** @dev check against swap cap and use the amount to swap X28.
     * reward TitanX as incentive fee to caller.
     */
    function _titanXBuyX28(uint256 balance) private {
        uint256 amount = getNextIntervalSwapAmountTitanX();
        require(amount != 0, "SwapAmountIsZero");

        amount = amount > balance ? balance : amount;
        s_lastCallTsBuynBurnTitanX = block.timestamp;

        uint256 incentiveFee = (amount * s_TitanXIncentiveDividend) / INCENTIVE_FEE_PERCENT_BASE;
        amount -= incentiveFee;

        _swapTitanXForX28(amount);
        IERC20(TITANX).transfer(msg.sender, incentiveFee);
    }

    /** @dev call uniswap swap function to swap TitanX for X28, then burn all X28
     * @param amountTitanX TitanX amount
     */
    function _swapTitanXForX28(uint256 amountTitanX) private {
        //calculate minimum amount for slippage protection
        uint256 minTokenAmount = ((amountTitanX * 1 ether * (100 - s_slippageBuynBurnTitanX)) /
            getTwapX28TitanX()) / 100;

        (int256 amount0, int256 amount1) = IUniswapV3Pool(X28_TITANX_POOL).swap(
            address(this),
            TITANX < X28,
            int256(amountTitanX),
            TITANX < X28 ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
            ""
        );
        uint256 x28Amount = TITANX < X28
            ? uint256(amount1 >= 0 ? amount1 : -amount1)
            : uint256(amount0 >= 0 ? amount0 : -amount0);
        //slippage protection check
        require(x28Amount >= minTokenAmount, "TooLittleReceived");

        //burn X28
        uint256 burnAmount = (x28Amount * BURN_PERCENT) / PERCENT_BPS;
        IX28(X28).transfer(X28_BNB, burnAmount);
        IX28(X28).burnCAX28(X28_BNB);
        s_totalX28Burned += burnAmount;

        //transfer LP amount to LP address
        IX28(X28).transfer(
            IShogun(s_shogunAddress).getLPAddress(),
            (x28Amount * LP_PERCENT) / PERCENT_BPS
        );

        //transfer genesis amount to genesis address
        IX28(X28).transfer(
            IShogun(s_shogunAddress).getGenesisAddress(),
            (x28Amount * GENESIS_PERCENT) / PERCENT_BPS
        );

        emit BoughtX28(amountTitanX, x28Amount, msg.sender);
    }

    /** @dev check against swap cap and use the amount to swap Shogun.
     * reward X28 as incentive fee to caller.
     */
    function _x28BuyShogun(uint256 balance) private {
        uint256 amount = getNextIntervalSwapAmountX28();
        require(amount != 0, "SwapAmountIsZero");

        amount = amount > balance ? balance : amount;
        s_lastCallTsBuynBurnX28 = block.timestamp;

        uint256 incentiveFee = (amount * s_X28IncentiveDividend) / INCENTIVE_FEE_PERCENT_BASE;
        amount -= incentiveFee;

        _swapX28ForShogun(amount);
        IERC20(X28).transfer(msg.sender, incentiveFee);
    }

    /** @dev call uniswap swap function to swap X28 for Shogun, then burn Shogun
     * @param amount amount
     */
    function _swapX28ForShogun(uint256 amount) private {
        //calculate minimum amount for slippage protection
        uint256 minTokenAmount = ((amount * 1 ether * (100 - s_slippageBuynBurnX28)) /
            getCurrentShogunX28Price()) / 100;

        address[] memory path = new address[](2);
        path[0] = X28;
        path[1] = s_shogunAddress;

        uint256[] memory amounts = UniswapV2Library.getAmountsOut(s_poolAddress, amount, path);
        require(amounts[1] >= minTokenAmount, "TooLittleReceived");
        IERC20(X28).transfer(s_poolAddress, amount);
        uint256 amountShogun = _swap(s_poolAddress, amounts, path);

        s_totalShogunBurn += (amountShogun * SHOGUN_BURN_PERCENT) / PERCENT_BPS;
        s_totalX28Buy += amount;
        burnShogun();

        emit BoughtAndBurned(amount, amountShogun, msg.sender);
    }

    /** @dev swap tokens
     * @param pairAddress pair address
     * @param amounts amounts in and out
     * @param path token addresses
     */
    function _swap(
        address pairAddress,
        uint256[] memory amounts,
        address[] memory path
    ) private returns (uint256) {
        (address token0, ) = UniswapV2Library.sortTokens(path[0], path[1]);
        uint256 amountOut = amounts[1];
        (uint256 amount0Out, uint256 amount1Out) = path[0] == token0
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));
        IUniswapV2Pair(pairAddress).swap(amount0Out, amount1Out, address(this), new bytes(0));
        return amount0Out == uint256(0) ? amount1Out : amount0Out;
    }

    //views
    function getGenesisTs() public view returns (uint256) {
        return s_shogunGenesisTs;
    }

    /** @notice supported interface check
     * @param interfaceId interfaceId
     * return bool true/false
     */
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == IERC165.supportsInterface.selector ||
            interfaceId == type(IShogun).interfaceId;
    }

    /** @notice get Shogun TitanX pool address
     * @return address Shogun TitanX pool address
     */
    function getPoolAddress() public view returns (address) {
        return s_poolAddress;
    }

    /** @notice get buy and burn funds
     * @return amount TitanX amount
     */
    function getTitanXBuyAndBurnFunds() public view returns (uint256) {
        return IERC20(TITANX).balanceOf(address(this));
    }

    /** @notice get buy and burn funds
     * @return amount TitanX amount
     */
    function getX28BuyAndBurnFunds() public view returns (uint256) {
        return IERC20(X28).balanceOf(address(this));
    }

    /** @notice get total TitanX amount used to buy X28
     * @return total TitanX amount
     */
    function getTotalTitanXBuy() public view returns (uint256) {
        return s_totalTitanXBuy;
    }

    /** @notice get total X28 burned via TitanX > X28
     * @return total TitanX amount
     */
    function getTotalX28Burned() public view returns (uint256) {
        return s_totalX28Burned;
    }

    /** @notice get total X28 amount used to buy and burn Shogun
     * @return total X28 amount
     */
    function getTotalX28Buy() public view returns (uint256) {
        return s_totalX28Buy;
    }

    /** @notice get total Shogun amount burned
     * @return amount total Shogun amount
     */
    function getTotalShogunBurn() public view returns (uint256) {
        return s_totalShogunBurn;
    }

    /** @notice get X28/TitanX twap
     * @return amount
     */
    function getTwapX28TitanX() public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(X28_TITANX_POOL, s_twapSecondsAgo);
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(meanTick);
        uint256 numerator1 = sqrtPriceX96 * sqrtPriceX96;
        uint256 numerator2 = 1 ether;
        uint256 price = FullMath.mulDiv(numerator1, numerator2, 1 << 192);
        price = TITANX < X28 ? (1 ether * 1 ether) / price : price;
        return price;
    }

    /** @notice get current price of the Shogun/X28 pair
     * @return price
     */
    function getCurrentShogunX28Price() public view returns (uint256) {
        (uint256 Res0, uint256 Res1) = UniswapV2Library.getReserves(
            s_poolAddress,
            X28,
            s_shogunAddress
        );
        return (Res0 * 1 ether) / Res1;
    }

    /** @notice get Shogun address
     * @return ShogunAddress Shogun address
     */
    function getShogunAddress() public view returns (address) {
        return s_shogunAddress;
    }

    /** @notice get cap amount per buy and burn
     * @return cap amount
     */
    function getTitanXBuyAndBurnCap() public view returns (uint256) {
        return s_capPerSwapTitanX;
    }

    /** @notice get buynburn slippage
     * @return slippage
     */
    function getSlippageBuynBurnTitanX() public view returns (uint256) {
        return s_slippageBuynBurnTitanX;
    }

    /** @notice get the buy and burn last called timestamp
     * return ts timestamp in seconds
     */
    function getLastCalledTsBuynBurnTitanX() public view returns (uint256) {
        return s_lastCallTsBuynBurnTitanX;
    }

    /** @notice get current TitanX incentive fee dividend
     * @return amount
     */
    function getTitanXIncentiveDividend() public view returns (uint256) {
        return s_TitanXIncentiveDividend;
    }

    /** @notice get cap amount per buy and burn
     * @return cap amount
     */
    function getX28BuyAndBurnCap() public view returns (uint256) {
        return s_capPerSwapX28;
    }

    /** @notice get buynburn slippage
     * @return slippage
     */
    function getSlippageBuynBurnX28() public view returns (uint256) {
        return s_slippageBuynBurnX28;
    }

    /** @notice get the buy and burn last called timestamp
     * return ts timestamp in seconds
     */
    function getLastCalledTsBuynBurnX28() public view returns (uint256) {
        return s_lastCallTsBuynBurnX28;
    }

    /** @notice get current X28 incentive fee dividend
     * @return amount
     */
    function getX28IncentiveDividend() public view returns (uint256) {
        return s_X28IncentiveDividend;
    }

    /** @notice get the buynburn interval between each call in seconds
     * @return seconds
     */
    function getBuynBurnInterval() public pure returns (uint256) {
        return INTERVAL_SECONDS;
    }

    /** @notice get current max cap for missed interval accumulation
     * @return max
     */
    function getCurrentMaxIntervalAccumulation() public view returns (uint256) {
        return s_maxIntervalAccumulation;
    }

    /** @notice get today's max B&B funds TitanX > X28
     * @return amount
     */
    function getTodayMaxBuyFundsTitanX() public view returns (uint256) {
        return getCurrentCapPerIntervalTitanX() * MAX_INTERVALS;
    }

    /** @notice get today's max B&B funds X28 > Shogun
     * @return amount
     */
    function getTodayMaxBuyFundsX28() public view returns (uint256) {
        return getCurrentCapPerIntervalX28() * MAX_INTERVALS;
    }

    /** @notice get today's TitanX swap cap per interval
     * @return amount
     */
    function getCurrentCapPerIntervalTitanX() public view returns (uint256) {
        uint256 currentCap = s_currentCapPerIntervalTitanX;
        uint256 swapCapLimit = s_capPerSwapTitanX;
        currentCap = currentCap > swapCapLimit ? swapCapLimit : currentCap;
        return currentCap;
    }

    /** @notice get today's X28 swap cap per interval
     * @return amount
     */
    function getCurrentCapPerIntervalX28() public view returns (uint256) {
        uint256 currentCap = s_currentCapPerIntervalX28;
        uint256 swapCapLimit = s_capPerSwapX28;
        currentCap = currentCap > swapCapLimit ? swapCapLimit : currentCap;
        return currentCap;
    }

    /** @notice get missed intervals based on last called timestamp, up to 3 intervals */
    function getMissedIntervals(uint256 lastCallTs) public view returns (uint256) {
        uint256 missedIntervals = (block.timestamp - lastCallTs) / INTERVAL_SECONDS;
        uint256 maxAccumulation = s_maxIntervalAccumulation;
        missedIntervals = missedIntervals > maxAccumulation ? maxAccumulation : missedIntervals;
        missedIntervals = missedIntervals == 0 ? 1 : missedIntervals;
        return missedIntervals;
    }

    /** @notice get next interval swap amount up to 3 missed intervals
     * @return amount
     */
    function getNextIntervalSwapAmountTitanX() public view returns (uint256) {
        return getCurrentCapPerIntervalTitanX() * getMissedIntervals(s_lastCallTsBuynBurnTitanX);
    }

    /** @notice get next interval swap amount up to 3 missed intervals
     * @return amount
     */
    function getNextIntervalSwapAmountX28() public view returns (uint256) {
        return getCurrentCapPerIntervalX28() * getMissedIntervals(s_lastCallTsBuynBurnX28);
    }
}