// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

// UniSwap
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

// OpenZeppelin
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

// lib
import "./lib/Constants.sol";
import "./lib/interfaces/IDragonX.sol";
import "./lib/interfaces/ITitanX.sol";
import "./lib/interfaces/INonfungiblePositionManager.sol";

/*
 * @title The BabyDragonX Contract
 * @author The DragonX and BabyDragon devs
 */
contract BabyDragonX is ERC20, Ownable2Step {
    // -----------------------------------------
    // Type declarations
    // -----------------------------------------
    /**
     * @dev Indicates if a contract was initialized
     */
    enum Initialized {
        No,
        Yes
    }

    /**
     * @dev Indicates if minting was closed
     */
    enum MintingFinalized {
        No,
        Yes
    }

    /**
     * @dev Represents the information about a Uniswap V3 liquidity pool position token.
     * This struct is used to store details of the position token, specifically for a single full range position.
     */
    struct LpTokenInfo {
        uint80 tokenId; // The ID of the position token in the Uniswap V3 pool.
        uint128 liquidity; // The amount of liquidity provided in the position.
        int24 tickLower; // The lower end of the price range for the position.
        int24 tickUpper; // The upper end of the price range for the position.
    }

    // -----------------------------------------
    // State variables
    // -----------------------------------------
    /**
     * @dev Begin of the mint phase
     */
    uint256 public mintPhaseBegin;

    /**
     * @dev The end of the mint phase
     */
    uint256 public mintPhaseEnd;

    /**
     * @dev The address of the main LP for DragonX / BabyDragon
     */
    address public poolAddress;

    /**
     * @notice true if the address is a LP Pool
     */
    mapping(address => bool) public pools;

    /**
     * @dev Indicates if BabyDragon contract was initialized
     */
    Initialized public initialized;

    /**
     * @dev Indicates if the mint phase was finalized
     */
    MintingFinalized public mintingFinalized;

    /**
     * @dev Total DragonX send to BabyDragonX buy and burn
     */
    uint256 public totalDragonSentToBabyDragonBuyAndBurn;

    /**
     * @dev Total BabyDragon burned through LP fees
     */
    uint256 public totalBabyDragonBurned;

    /**
     * @dev Interacting with LP pools is disabled while minting
     */
    bool public tradingEnabled;

    /**
     * @dev Stores the position token information, specifically for a single full range position in the Uniswap V3 pool.
     */
    LpTokenInfo public lpTokenInfo;

    /**
     * @dev The BabyDragonX buy and burn address (smart contract executing buy and burns)
     */
    address public babyDragonBuyAndBurnAddress;

    // -----------------------------------------
    // Events
    // -----------------------------------------
    /**
     * @notice Emitted when fees are collected in both DragonX and BabyDragon tokens.
     * @dev This event is triggered when a fee collection transaction is completed.
     * @param dragon The amount of DragonX collected as fees.
     * @param babyDragon The amount of BabyDragon tokens collected as fees.
     * @param caller The address of the user or contract that initiated the fee collection.
     */
    event CollectedFees(
        uint256 indexed dragon,
        uint256 indexed babyDragon,
        address indexed caller
    );

    // -----------------------------------------
    // Errors
    // -----------------------------------------

    // -----------------------------------------
    // Modifiers
    // -----------------------------------------

    // -----------------------------------------
    // Constructor
    // -----------------------------------------
    constructor(
        address babyDragonBuyAndBurnAddress_
    ) ERC20("Baby DragonX", "BDX") Ownable(msg.sender) {
        require(babyDragonBuyAndBurnAddress_ != address(0), "invalid address");
        // set other states
        initialized = Initialized.No;
        mintingFinalized = MintingFinalized.No;
        tradingEnabled = false;
        babyDragonBuyAndBurnAddress = babyDragonBuyAndBurnAddress_;
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
     * Mint BabyDragonX Tokens
     * @dev Mints BabyDragonX tokens in exchange for TitanX tokens based on a dynamic minting ratio.
     * This function allows users to contribute TitanX tokens during the mint phase of
     * DragonX and receive BabyDragonX tokens in return.
     * The mint ratio adjusts according to the timestamp. It also allocates a
     * portion of TitanX tokens for team allocation,
     * expenses, and DragonX genesis share before minting.
     *
     * Requirements:
     * - The contract must be initialized.
     * - The minting phase must have started and not yet ended.
     *
     * Emits a {Transfer} event from the zero address to the `msg.sender` indicating the minting of BabyDragonX tokens.
     *
     * @param titanAmount The amount of TitanX tokens the user wishes to contribute for minting BabyDragonX tokens.
     * The function calculates the allocation for different purposes, mints DragonX tokens with a portion of TitanX,
     * and finally mints BabyDragonX tokens based on the calculated ratio.
     */
    function mint(uint256 titanAmount) external {
        IDragonX dragonX = IDragonX(DRAGONX_ADDRESS);
        ITitanX titanX = ITitanX(TITANX_ADDRESS);

        require(initialized == Initialized.Yes, "not initialized");
        require(titanAmount > 0, "invalid amount");

        // Align the mint-ratio with DragonX
        // This function will revert if minting has ended or not started yet
        uint256 ratio = getMintRatio();

        // 7% Baby Dragon Team Allocation
        uint256 teamAllocation = (titanAmount * 700) / BASIS;
        titanX.transferFrom(
            msg.sender,
            BABY_DRAGON_TEAM_ADDRESS,
            teamAllocation
        );

        // 5% Baby Dragon Expenses
        uint256 expenses = (titanAmount * 500) / BASIS;
        titanX.transferFrom(msg.sender, BABY_DRAGON_EXPENSES_ADDRESS, expenses);

        // Send 1% of TitanX to DragonX genesis
        uint256 dragonGenesisShare = (titanAmount * 100) / BASIS;
        titanX.transferFrom(
            msg.sender,
            DRAGONX_GENESIS_ADDRESS,
            dragonGenesisShare
        );

        // Mint DragonX with 87% of TitanX (accumulate in this contract)
        uint256 titanToMintDragon = titanAmount -
            teamAllocation -
            expenses -
            dragonGenesisShare;
        titanX.transferFrom(msg.sender, address(this), titanToMintDragon);
        titanX.approve(DRAGONX_ADDRESS, titanToMintDragon);
        dragonX.mint(titanToMintDragon);

        // Mint BabyDragon
        uint256 babyDragonToMint = (titanAmount * ratio) / BASIS;
        _mint(msg.sender, babyDragonToMint);
    }

    /**
     * Collects fees accrued from liquidity provision in DragonX and BabyDragon tokens.
     * @dev This function handles the collection and burning of fees generated by liquidity pools.
     * It determines the amounts of DragonX and BabyDragon tokens collected as fees,
     * burns the collected BabyDragon tokens, and sends the collected DragonX tokens to the
     * BabyDragon buy and burn address.
     *
     * Emits a {CollectedFees} event indicating the amounts of tokens collected and burned, and the caller's address.
     */
    function collectFees() external {
        require(initialized == Initialized.Yes, "not initialized");

        // Cache state variables
        address dragonAddress = DRAGONX_ADDRESS;
        address babyDragonAddress = address(this);

        (uint256 amount0, uint256 amount1) = _collectFees();

        uint256 dragon;
        uint256 babyDragon;

        if (dragonAddress < babyDragonAddress) {
            dragon = amount0;
            babyDragon = amount1;
        } else {
            babyDragon = amount0;
            dragon = amount1;
        }

        // Burn BabyDragon
        totalBabyDragonBurned += babyDragon;
        _burn(address(this), babyDragon);

        // Burn DragonX
        IDragonX dragonX = IDragonX(dragonAddress);
        totalDragonSentToBabyDragonBuyAndBurn += dragon;
        dragonX.transfer(babyDragonBuyAndBurnAddress, dragon);

        emit CollectedFees(dragon, babyDragon, msg.sender);
    }

    /**
     * @notice Allows users to burn their BabyDragonX tokens, reducing the total supply.
     * @dev Burns a specific amount of BabyDragonX tokens from the caller's balance.
     * Updates the `totalBabyDragonBurned` state to reflect the burned tokens.
     *
     * @param amount The amount of BabyDragonX tokens to burn from the caller's balance.
     *
     * Requirements:
     * - The caller must have at least `amount` tokens in their balance.
     */
    function burn(uint256 amount) external {
        require(amount > 0, "invalid amount");
        totalBabyDragonBurned += amount;
        _burn(msg.sender, amount);
    }

    /**
     * Finalizes the minting phase, allocates tokens for liquidity, grants, and rewards, and enables trading.
     * @dev This function can only be called once by the contract owner after
     * the minting phase has ended.
     * It performs token allocations to various addresses and pools, mints additional
     * BabyDragonX tokens for grants and rewards, adds liquidity to the UniSwap pool,
     * and enables trading by updating the contract state.
     *
     * Requirements:
     * - The minting phase has ended.
     * - The function must not have been previously called.
     * - Can only be called by the contract owner.
     */
    function finalizeMint() external onlyOwner {
        require(block.timestamp > mintPhaseEnd, "minting still open");
        require(
            mintingFinalized == MintingFinalized.No,
            "minting already finalized"
        );

        IDragonX dragonX = IDragonX(DRAGONX_ADDRESS);
        uint256 dragonBalance = dragonX.balanceOf(address(this));

        // Allocate 50% to liquidity pool
        uint256 liquidityTopUp = (dragonBalance * 5000) / BASIS;

        // Allocate 3% to BabyDragonX Genesis
        uint256 genesisShare = (dragonBalance * 300) / BASIS;
        dragonX.transfer(BABY_DRAGON_TEAM_ADDRESS, genesisShare);

        // Allocate 47% to BabyDragonX buy and burn
        uint256 dragonForBabyDragonBurnShare = dragonBalance -
            liquidityTopUp -
            genesisShare;
        dragonX.transfer(
            babyDragonBuyAndBurnAddress,
            dragonForBabyDragonBurnShare
        );
        totalDragonSentToBabyDragonBuyAndBurn += dragonForBabyDragonBurnShare;

        // Mint additional 4% for grants
        uint256 totalBabyDragonMinted = totalSupply();
        _mint(BABY_DRAGON_GRANT_ADDRESS, (totalBabyDragonMinted * 400) / BASIS);

        // Mint additional 10% for future rewards
        _mint(
            BABY_DRAGON_FUTURE_REWARDS_ADDRESS,
            (totalBabyDragonMinted * 1000) / BASIS
        );

        // Prepare LP
        uint256 amount0Desired = liquidityTopUp;
        uint256 amount1Desired = liquidityTopUp;

        // mint BabyDragon for LP
        _mint(address(this), liquidityTopUp);

        // Approve the Uniswap non-fungible position manager to spend DragonX.
        dragonX.approve(UNI_NONFUNGIBLEPOSITIONMANAGER, liquidityTopUp);

        // Approve the UniSwap non-fungible position manager to spend BabyDragon.
        _approve(address(this), UNI_NONFUNGIBLEPOSITIONMANAGER, liquidityTopUp);

        // Top Up Liquidity
        (uint128 liquidity, , ) = _addLiquidity(amount0Desired, amount1Desired);
        lpTokenInfo.liquidity = liquidity;

        // Burn remaining DragonX
        if (dragonX.balanceOf(address(this)) > 0) {
            dragonX.burn();
        }

        // Burn remaining BabyDragon
        uint256 remainingBabyDragon = balanceOf(address(this));
        if (remainingBabyDragon > 0) {
            totalBabyDragonBurned += remainingBabyDragon;
            _burn(address(this), remainingBabyDragon);
        }

        // enable trading
        tradingEnabled = true;

        // Update state
        mintingFinalized = MintingFinalized.Yes;
    }

    /**
     * @notice Initializes the contract by setting up initial liquidity in the Uniswap pool and enabling minting.
     * @dev This function sets the initial liquidity parameters for the BabyDragonX and
     * DragonX tokens in the Uniswap pool. It mints initial liquidity tokens to this contract,
     * approves the Uniswap non-fungible position manager to spend the tokens,
     * and creates the initial liquidity pool if it doesn't exist already.
     * It also sets the minting phase's beginning and end times. This function can only be
     * called once by the contract owner.
     *
     * @param initialLiquidityAmount The amount of DragonX tokens to be added as initial liquidity to the Uniswap pool.
     * The function automatically calculates and mints the amount of BabyDragonX tokens for the initial liquidity,
     * assuming an initial price ratio of 1 DragonX to 1 BabyDragonX.
     *
     * Requirements:
     * - The contract must not have been initialized before.
     * - Only the contract owner can call this function.
     */
    function initialize(uint256 initialLiquidityAmount) external onlyOwner {
        require(initialized == Initialized.No, "already initialized");
        IDragonX dragonX = IDragonX(DRAGONX_ADDRESS);

        // Mint initial liquidity
        _mint(address(this), initialLiquidityAmount);

        // Setup initial liquidity pool
        // Transfer the specified amount of DragonX tokens from the caller to this contract.
        dragonX.transferFrom(msg.sender, address(this), initialLiquidityAmount);

        // Approve the Uniswap non-fungible position manager to spend DragonX.
        dragonX.approve(UNI_NONFUNGIBLEPOSITIONMANAGER, initialLiquidityAmount);

        // Approve the UniSwap non-fungible position manager to spend BabyDragon.
        _approve(
            address(this),
            UNI_NONFUNGIBLEPOSITIONMANAGER,
            initialLiquidityAmount
        );

        // Create the initial liquidity pool in Uniswap V3.
        _createPool(initialLiquidityAmount);

        // Mint the initial position in the pool.
        _mintInitialPosition(initialLiquidityAmount);

        // Align mint phase begin to midnight UTC
        uint256 currentTimestamp = block.timestamp;
        uint256 secondsUntilMidnight = 86400 - (currentTimestamp % 86400);

        // The mint phase begins at midnight
        mintPhaseBegin = currentTimestamp + secondsUntilMidnight;

        // Minting will be open for 14 days
        mintPhaseEnd = mintPhaseBegin + 14 days;

        // Update states
        initialized = Initialized.Yes;
    }

    /**
     * @notice Registers or deregisters an address as a liquidity pool.
     * @dev Allows the contract owner to mark an address as a recognized liquidity pool
     * or remove it from the list of recognized pools. This function is critical for managing
     * which pools are considered for trading and can help in disabling trading in the minting phase.
     *
     * @param poolAddress_ The address of the liquidity pool to be registered or deregistered.
     * @param isPool A boolean indicating whether the address should be considered a
     * liquidity pool (true) or not (false).
     *
     * Requirements:
     * - Only the contract owner can call this function.
     * - This function has no effect once minting is finalized and trading is enabled.
     */
    function setPool(address poolAddress_, bool isPool) external onlyOwner {
        require(poolAddress_ != address(0), "invalid address");
        pools[poolAddress_] = isPool;
    }

    /**
     * @notice Sets the BabyDragon buy and burn address to a new address.
     * @dev Allows the contract owner to update the address where DragonX tokens are
     * sent for buying and burning BabyDragonX tokens.
     * This can be used to change the destination address for the DragonX tokens
     * collected as fees and used for burning.
     *
     * @param babyDragonBuyAndBurnAddress_ The new address for buying and burning BabyDragonX tokens.
     *
     * Requirements:
     * - Only the contract owner can call this function.
     * - The new address must not be the zero address.
     */
    function setBabyDragonBuyAndBurnAddress(
        address babyDragonBuyAndBurnAddress_
    ) external onlyOwner {
        require(babyDragonBuyAndBurnAddress_ != address(0), "invalid address");
        babyDragonBuyAndBurnAddress = babyDragonBuyAndBurnAddress_;
    }

    // -----------------------------------------
    // Public functions
    // -----------------------------------------
    /**
     * @notice Calculates the current mint ratio for BabyDragonX tokens based on the current
     * phase of the minting period.
     * @dev Returns a mint ratio that determines how many BabyDragonX tokens can be minted per unit of TitanX.
     * The mint ratio changes depending on which week of the minting phase the function is called.
     *
     * The mint ratio starts at 1 for the first week and adjusts to 0.95 for the second week.
     * This function ensures that the ratio is only accessible during the minting phase to enforce the minting schedule.
     *
     * Requirements:
     * - The current timestamp must be within the minting phase period, between `mintPhaseBegin` and `mintPhaseEnd`.
     *
     * @return ratio The current mint ratio
     */
    function getMintRatio() public view returns (uint256 ratio) {
        require(initialized == Initialized.Yes, "not yet initialized");
        require(block.timestamp >= mintPhaseBegin, "minting not started");
        require(block.timestamp <= mintPhaseEnd, "minting has ended");

        if (block.timestamp < mintPhaseBegin + 7 days) {
            // week 1
            ratio = 10_000;
        } else {
            // week 2
            ratio = 9_500;
        }
    }

    // -----------------------------------------
    // Internal functions
    // -----------------------------------------
    /**
     * @dev Overrides the ERC20 `_update` function to enforce trading restrictions.
     * This internal function is called during every transfer operation to check if trading is enabled
     * and whether the sender or recipient is a recognized liquidity pool address.
     * It ensures that trading through LP pools is only possible when explicitly enabled.
     *
     * @param from The address sending the tokens.
     * @param to The address receiving the tokens.
     * @param value The amount of tokens being transferred.
     *
     * Requirements:
     * - Trading must be enabled if either `from` or `to` is a recognized liquidity pool address.
     * - Always allow the contract itself to interact with the LP pool.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // Allow the contract itself to always interact without checking if trading is enabled
        if (from != address(this) && to != address(this)) {
            require(
                (!pools[from] && !pools[to]) || tradingEnabled,
                "trading was not enabled yet"
            );
        }

        super._update(from, to, value);
    }

    // -----------------------------------------
    // Private functions
    // -----------------------------------------
    /**
     * @notice Sorts tokens in ascending order, as required by Uniswap for identifying a pair.
     * @dev This function arranges the token addresses in ascending order and assigns
     * liquidity in a ratio of 1:1
     * @param initialLiquidityAmount The amount of liquidity to assign to each token.
     * @return token0 The token address that is numerically smaller.
     * @return token1 The token address that is numerically larger.
     * @return amount0 The liquidity amount for `token0`.
     * @return amount1 The liquidity amount for `token1`.
     */
    function _getTokenConfig(
        uint256 initialLiquidityAmount
    )
        private
        view
        returns (
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1
        )
    {
        // Cache state variables
        address dragonAddress = DRAGONX_ADDRESS;
        address babyDragonAddress = address(this);

        amount0 = initialLiquidityAmount;
        amount1 = initialLiquidityAmount;

        if (dragonAddress < babyDragonAddress) {
            token0 = dragonAddress;
            token1 = babyDragonAddress;
        } else {
            token0 = babyDragonAddress;
            token1 = dragonAddress;
        }
    }

    /**
     * @notice Creates a liquidity pool with a preset square root price ratio.
     * @dev This function initializes a Uniswap V3 pool with the specified initial liquidity amount.
     * @param initialLiquidityAmount The amount of liquidity to use for initializing the pool.
     */
    function _createPool(uint256 initialLiquidityAmount) private {
        (address token0, address token1, , ) = _getTokenConfig(
            initialLiquidityAmount
        );
        INonfungiblePositionManager manager = INonfungiblePositionManager(
            UNI_NONFUNGIBLEPOSITIONMANAGER
        );

        poolAddress = manager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            FEE_TIER,
            INITIAL_SQRT_PRICE_DRAGONX_BABYDRAGONX
        );

        // Increase cardinality for observations enabling TWAP
        IUniswapV3Pool(poolAddress).increaseObservationCardinalityNext(100);

        // Update state
        pools[poolAddress] = true;
    }

    /**
     * @notice Mints a full range liquidity provider (LP) token in the Uniswap V3 pool.
     * @dev This function mints an LP token with the full price range in the Uniswap V3 pool.
     * @param initialLiquidityAmount The amount of liquidity to be used for minting the position.
     */
    function _mintInitialPosition(uint256 initialLiquidityAmount) private {
        INonfungiblePositionManager manager = INonfungiblePositionManager(
            UNI_NONFUNGIBLEPOSITIONMANAGER
        );

        (
            address token0,
            address token1,
            uint256 amount0Desired,
            uint256 amount1Desired
        ) = _getTokenConfig(initialLiquidityAmount);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE_TIER,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: (amount0Desired * 90) / 100,
                amount1Min: (amount1Desired * 90) / 100,
                recipient: address(this),
                deadline: block.timestamp
            });

        (uint256 tokenId, uint256 liquidity, , ) = manager.mint(params);

        lpTokenInfo.tokenId = uint80(tokenId);
        lpTokenInfo.liquidity = uint128(liquidity);
        lpTokenInfo.tickLower = MIN_TICK;
        lpTokenInfo.tickUpper = MAX_TICK;
    }

    /**
     * @notice Collects liquidity pool fees from the Uniswap V3 pool.
     * @dev This function calls the Uniswap V3 `collect` function to retrieve LP fees.
     * @return amount0 The amount of `token0` collected as fees.
     * @return amount1 The amount of `token1` collected as fees.
     */
    function _collectFees() private returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager manager = INonfungiblePositionManager(
            UNI_NONFUNGIBLEPOSITIONMANAGER
        );

        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams(
                lpTokenInfo.tokenId,
                address(this),
                type(uint128).max,
                type(uint128).max
            );

        (amount0, amount1) = manager.collect(params);
    }

    /**
     * @dev Adds liquidity to the Uniswap V3 pool for the BabyDragonX and DragonX tokens.
     * Attempts to add the desired amounts of token0 and token1 to the liquidity pool, with a
     * 10% minimum slippage tolerance.
     *
     * @param amount0Desired The desired amount of token0 to be added to the pool.
     * @param amount1Desired The desired amount of token1 to be added to the pool.
     * @return liquidity The amount of liquidity tokens received for the added liquidity.
     * @return amount0 The actual amount of token0 added to the pool.
     * @return amount1 The actual amount of token1 added to the pool.
     */
    function _addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired
    ) private returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager manager = INonfungiblePositionManager(
            UNI_NONFUNGIBLEPOSITIONMANAGER
        );

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: lpTokenInfo.tokenId,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        (liquidity, amount0, amount1) = manager.increaseLiquidity(params);
    }
}