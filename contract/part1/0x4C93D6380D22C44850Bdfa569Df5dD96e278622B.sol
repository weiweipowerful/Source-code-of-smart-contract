pragma solidity 0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../../interfaces/IFeeToken.sol";
import "../../common/uniswap/PoolAddress.sol";
import "../../common/uniswap/Oracle.sol";
import "../../common/uniswap/TickMath.sol";
import "../../interfaces/INonfungiblePositionManager.sol";
import "../../interfaces/IFeeTokenMinter.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 Token Minting Process State Diagram:

 stateDiagram-v2
    [*] --> PreLaunch: ORX Minter Deployment
    PreLaunch --> Launched: LaunchBlock Reached
    Launched --> TitanXDeposited: User Deposits TitanX
    Launched --> EthContributionReceived: User Contributes ETH
    TitanXDeposited --> CalculatingReturn: Calculate ORX Return
    EthContributionReceived --> EthQueuePeriod: Enter 14-day Queue
    EthQueuePeriod --> EthDripCreated: Queue Period Ends
    CalculatingReturn --> VestingCreated: Create Vesting Entry
    VestingCreated --> Vesting: Start Vesting Period
    EthDripCreated --> EthCliffPeriod: Start 21-day Cliff Period
    EthCliffPeriod --> EthVesting: Cliff Period Ends
    Vesting --> ClaimRequested: User Requests to Claim
    EthVesting --> EthDripClaimRequested: User Requests to Claim Dripped ORX
    ClaimRequested --> CalculatingClaimable: Calculate Claimable Amount
    EthDripClaimRequested --> CalculatingDrippedAmount: Calculate Dripped ORX Amount
    CalculatingClaimable --> TokensStaged: ORX Staged for 3 Days
    CalculatingDrippedAmount --> DrippedTokensMinted: Dripped ORX Minted Immediately
    TokensStaged --> TokensClaimed: User Claims ORX After 3 Days
    DrippedTokensMinted --> EthVesting: Continue Vesting
    TokensClaimed --> [*]: Vesting Complete
    EthVesting --> [*]: All ORX Vested (12 weeks total)

    Vesting --> NukeRequested: User Requests Nuke (Before 28 Days)
    NukeRequested --> Forfeited: User Confirms Nuke
    Forfeited --> [*]: All ORX Sent to Forfeit Sink

    state CalculatingReturn {
        [*] --> FixedRate: Total TitanX Deposits < Fixed Rate Threshold
        [*] --> MixedRate: Total TitanX Deposits Crosses Fixed Rate Threshold
        [*] --> CurveRate: Total TitanX Deposits > Fixed Rate Threshold
        FixedRate --> [*]: Return Fixed Rate Amount
        MixedRate --> [*]: Return Fixed Rate Amount + Curve-Based Amount
        CurveRate --> [*]: Return Curve-Based Amount
    }

    state CalculatingClaimable {
        [*] --> FullAmount: After Vesting Period
        [*] --> PartialAmount: During Vesting Period (After 28 Days)
        [*] --> ZeroAmount: Before 28 Days
        FullAmount --> [*]: Return Full Amount
        PartialAmount --> [*]: Return Partial Amount
        ZeroAmount --> [*]: Return Zero (Require Nuke Confirmation)
    }

    state CalculatingDrippedAmount {
        [*] --> DrippedFullAmount: After Vesting Period (12 weeks)
        [*] --> DrippedPartialAmount: During Vesting Period (After Cliff)
        [*] --> DrippedZeroAmount: During Cliff Period (21 days)
        DrippedFullAmount --> [*]: Return Remaining Amount
        DrippedPartialAmount --> [*]: Return Vested Amount
        DrippedZeroAmount --> [*]: Return Zero
    }
 */

/**
 * @title FeeTokenMinter
 * @dev Contract for minting/vesting FeeTokens in exchange for deposits. Also manages token buybacks and a locked LP.
 *
 *  Key features:
 *      1. Token Issuance: Hybrid initial fixed-rate with transition to curve-based model for FeeToken minting.
 *                         A small % of supply is given to Ethereum contributions.
 *      2. Deposit Vesting: 52-week vesting schedule with one-time claim and early claim forfeit system. Vesting massively tail weighted.
 *      3. ETH Contribution Vesting: 12-week vesting schedule with a 21-day cliff period for ETH contributors. Progressive linear drip release.
 *      4. Referral System: Bonus rewards for referrers. 2% additional tokens minted if referrer is present.
 *      5. Locked Liquidity: Uniswap V3 integration for liquidity and buybacks.
 *      6. Buyback Mechanism: Purchases and burns FeeTokens in either a public incentivised manner, or permissioned manner which is not incentivised.
 *      7. Incentive Programs: Supports external backstop and LP incentives vesting schedules, but reserves the right to cancel them.
 *      8. Control Functions: Functions for parameter adjustments and management within hardcoded parameter ranges.
 */
contract FeeTokenMinter is Ownable, IFeeTokenMinter, ReentrancyGuard {
    //==================================================================//
    //---------------------- LAUNCH PARAMETERS -------------------------//
    //==================================================================//
    /// @dev Deposit Token contribution vesting period
    uint public constant DEPOSIT_VESTING_PERIOD = 52 weeks;

    /// @dev Deposit Token contribution cliff period
    uint public constant DEPOSIT_VESTING_CLIFF_DURATION = 28 days;

    /// @dev ETH contribution vesting period
    uint public constant CONTRIBUTION_VESTING_PERIOD = 12 weeks;

    /// @dev ETH contribution cliff period
    uint public constant ETH_CONTRIBUTION_CLIFF_DURATION = 21 days;

    /// @dev Amount of time ETH will be allowed to stage during launch phase. (Rough approximation)
    uint public constant ETH_LAUNCH_PHASE_TIME = 14 days;

    //==================================================================//
    //-------------------------- CONSTANTS -----------------------------//
    //==================================================================//

    /// @dev Timestamp when the contract was deployed
    uint public immutable DEPLOYMENT_TIMESTAMP;

    /// @dev Block when the contract was deployed
    uint public immutable DEPLOYMENT_BLOCK;

    /// @dev Block number at which the contract is considered launched and deposits, eth contributions, and incentive vests can be triggered.
    uint public immutable LAUNCH_BLOCK;

    /// @dev Rough approximation of launch timestamp.
    uint public immutable LAUNCH_TIMESTAMP;

    /// @dev Approx share of fee token supply which is available at a fixed rate expressed as a percentage
    uint public constant FEE_TOKEN_AVAILABLE_AT_FIXED_DEPOSIT_RATE = 250_000_000e18;

    /// @dev Approx deposits at fixed rate. How many deposit token before we transition to curve emissions.
    uint public constant TOTAL_DEPOSITS_AT_FIXED_RATE = 1_500_000_000_000e18;

    /// @dev Initial fixed deposit rate before curve kicks in.
    /// Calculated by TOTAL_DEPOSITS_AT_FIXED_RATE / FEE_TOKEN_AVAILABLE_AT_FIXED_DEPOSIT_RATE
    uint public immutable FIXED_RATE_FOR_DEPOSIT_TOKEN;

    /// @dev Higher number implies more liquid virtual pair for x*y=k curve
    uint private constant CURVE_RATE_INCREASE_WEIGHT = 6_000_000_000_000e18;

    /// @dev Rate for ETH contributions.  Implies 369eth * 135502 == 50,000,000~ Fee Token for Eth emissions
    uint public constant ETH_RATE = 135502;

    /// @dev Fee tier for Uniswap V3 pool (1%)
    uint24 public constant POOL_FEE = 10000;

    /// @dev Minimum tick for Uniswap V3 position (full range)
    int24 public constant MIN_TICK = -887200;

    /// @dev Maximum tick for Uniswap V3 position (full range)
    int24 public constant MAX_TICK = 887200;

    /// @dev Initial LP price if token0 is occupied by the deposit token
    int24 public constant INITIAL_TICK_IF_DEPOSIT_TOKEN_IS_TOKEN0 = -120244;

    /// @dev Initial LP price if token0 is occupied by the fee token
    int24 public constant INITIAL_TICK_IF_FEE_TOKEN_IS_TOKEN0 = -INITIAL_TICK_IF_DEPOSIT_TOKEN_IS_TOKEN0;

    /// @dev Initial input to LP for Fee Token
    uint public constant INITIAL_FEE_TOKEN_LIQUIDITY_AMOUNT = 600_000e18;

    /// @dev Initial input to LP for Deposit Token
    uint public constant INITIAL_DEPOSIT_TOKEN_LIQUIDITY_AMOUNT = 100_000_000_000e18;

    /// @dev Address where forfeited tokens are sent. Ideally a multisig.
    address public immutable FORFEIT_SINK;

    /// @dev Address where ETH is sent. Ideally a multisig for slow LP management release and dev reward.
    address public immutable ETH_SINK;

    /// @dev Approximate block production time, doesn't need to be exact
    uint private constant TIME_PER_BLOCK_PRODUCTION = 12 seconds;

    //==================================================================//
    //-------------------------- INTERFACES ----------------------------//
    //==================================================================//

    /// @dev Interface for Uniswap V3 SwapRouter
    ISwapRouter public immutable router;

    /// @dev Interface for Uniswap V3 NonfungiblePositionManager
    INonfungiblePositionManager public immutable positionManager;

    /// @dev Interface for Uniswap V3 Pool
    IUniswapV3Pool public pool;

    /// @dev Interface for the deposit token
    IERC20 public immutable depositToken;

    /// @dev Interface for the FeeToken
    IFeeToken public immutable feeToken;

    //==================================================================//
    //----------------------- STATE VARIABLES --------------------------//
    //==================================================================//

    /// @dev Flag indicating if the Uniswap pool has been created
    bool public uniPoolInitialised;

    /// @dev Cooldown period between buybacks
    uint public buybackCooldownPeriod = 15 minutes;

    /// @dev Reward bips which is sent to buyback caller when buyback mode is Public
    uint public incentiveFeeBips = 300;

    /// @dev Timestamp of the last buyback/burn
    uint public lastBuyback;

    /// @dev Address for backstop incentives
    address public backstopIncentives;

    /// @dev Address for LP incentives
    address public lpIncentives;

    /// @dev Remaining ETH emissions cap
    uint public remainingCappedEthEmissions = 369 ether;

    /// @dev Available emissions for deposits
    uint public availableCurveEmissionsForDepositToken;

    /// @dev Flag indicating if the curve mechanism is active
    bool public curveActive = true;

    /// @dev Flag indicating if the backstop deposit farm is active
    bool public backstopFarmActive = true; // we assume true, even though another part of the system controls emissions

    /// @dev Flag indicating if the LP farm is active
    bool public lpFarmActive = true; // we assume true, even though another part of the system controls emissions

    /// @dev Maximum future FeeTokens from deposits
    uint public maxFutureFeeTokensFromDeposits;

    /// @dev Currently vesting FeeTokens
    uint public currentlyVestingFeeTokens;

    /// @dev Total deposited amount
    uint public totalDeposited;

    /// @dev Total staged amount waiting to unlock in the 3 day window
    uint public totalStaged;

    /// @dev Total forfeited supply
    uint public forfeitedSupply;

    /// @dev Duration in minutes for TWAP calculation
    uint32 public twapDurationMins = 15;

    /// @dev X value for curve calculations
    uint internal _x;

    /// @dev Y value for curve calculations
    uint internal _y;

    /// @dev K value for curve calculations (x * y = k)
    uint internal _k;

    /// @dev Generator for unique vest IDs
    uint public vestIdGenerator = 1;

    /// @dev Generator for unique drip IDs
    uint public dripIdGenerator = 1;

    /// @dev Cap per swap for buybacks
    uint public capPerSwap = 1_000_000_000e18;

    /// @dev Current buyback mode (Public or Private)
    BuybackMode public buybackMode = BuybackMode.Private;

    /// @dev Slippage percentage for swaps
    uint public slippagePCT = 5;

    /// @dev Total depositToken used for buy and burns
    uint public totalDepositTokenUsedForBuyAndBurns;

    /// @dev Total FeeTokens burned
    uint public totalFeeTokensBurned;

    //==================================================================//
    //--------------------------- STRUCTS ------------------------------//
    //==================================================================//

    /// @dev Structure to hold deposit vesting entry details
    struct VestingEntry {
        address owner;
        uint64 endTime;
        uint startTime;
        uint escrowAmount;
        uint vested;
        uint forfeit;
        uint deposit;
        uint duration;
        address referrer;
        bool isValid;
        uint stagedStart;
        uint stagedAmount;
    }

    /// @dev Structure to hold ETH contribution vesting entry details
    struct DripEntry {
        address contributor;
        uint contributionAmount;
        uint64 endTime;
        uint startTime;
        uint amount;
        uint vested;
        bool isValid;
    }

    /// @dev Structure to hold token information for Uniswap V3 position
    struct TokenInfo {
        uint tokenId;
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
        bool initialized;
    }

    //==================================================================//
    //-------------------------- MAPPINGS ------------------------------//
    //==================================================================//

    /// @dev Mapping of account addresses to their vesting entries
    mapping(address => mapping(uint => VestingEntry)) public vests;

    /// @dev Mapping of account addresses to their vesting FeeToken drips
    mapping(address => mapping(uint => DripEntry)) public drips;

    /// @dev Mapping of account addresses to their drip IDs
    mapping(address => uint[]) public accountDripIDs;

    /// @dev Mapping of vest IDs to their owners
    mapping(uint => address) public vestToVestOwnerIfHasReferrer;

    /// @dev Mapping of account addresses to their vesting IDs
    mapping(address => uint[]) public accountVestingIDs;

    /// @dev Mapping of referrer addresses to their total referrals
    mapping(address => uint) public totalReferrals;

    /// @dev Mapping of referrer addresses to their total referral rewards
    mapping(address => uint) public totalReferralRewards;

    /// @dev Mapping of referrer addresses to their referral vesting IDs
    mapping(address => uint[]) public referralVestingIDs;

    /// @dev Mapping of account addresses to their deposited amounts
    mapping(address => uint) public deposited;

    /// @dev Mapping of account addresses to their vesting amounts
    mapping(address => uint) public vesting;

    //==================================================================//
    //------------------------- PUBLIC VARS ----------------------------//
    //==================================================================//

    /// @dev Public variable to store token information
    TokenInfo public tokenInfo;

    //==================================================================//
    //--------------------------- ENUMS --------------------------------//
    //==================================================================//

    /// @dev Enum to represent buyback modes
    enum BuybackMode {Public, Private}

    //==================================================================//
    //--------------------------- EVENTS -------------------------------//
    //==================================================================//

    event VestStarted(address indexed beneficiary, uint value, uint duration, uint entryID, address referrer);
    event TokensStaged(address indexed beneficiary, uint value, uint availableTime);
    event EthContributed(address indexed contributor, uint256 ethAmount, uint256 feeTokenAmount, uint256 vestId);
    event DripClaimed(address indexed claimer, uint256 indexed vestId, uint256 amount);
    event Buyback(address indexed caller, uint swapInput, uint feeTokensBought, uint amountOutMinimum, uint incentiveFee, BuybackMode buybackMode, uint slippagePCT);
    event LiquidityAdded(uint initialDepositTokenSupplyInput, uint initialFeeTokenSupplyInput);
    event LPUnlocked();
    event CurveTerminated();
    event BackstopDepositFarmTerminated();
    event LPFarmTerminated();
    event Deposit(address indexed account, uint deposit, address referrer, uint mintableFeeTokens);
    event VestClaimed(address indexed account, uint vestId, uint vested, uint forfeit);
    event StagedTokensClaimed(address indexed account, uint vestId, uint amount);

    // Custom Errors
    error NotYetLaunched();
    error CurveClosed();
    error ZeroValueTransaction();
    error NoFurtherEthAllocation();
    error CannotDepositZero();
    error FailedToTransferDepositToken();
    error DepositResultsInZeroFeeTokensMinted();
    error LPNotInitialized();
    error OnlyCallableByOwnerDuringPrivateMode();
    error OnlyCallableByEOA();
    error BuybackCooldownNotRespected();
    error BuybackEmpty();
    error InvalidDripId();
    error AllTokensAlreadyDripped();
    error InvalidVestId();
    error ClaimAlreadyVested();
    error ClaimingBeforeMinimumPeriod();
    error NoTokensToClaim();
    error TokensNotYetClaimable();
    error VestDoesNotExist();

    //==================================================================//
    //------------------------- CONSTRUCTOR ----------------------------//
    //==================================================================//

    /**
     * @dev Constructor to initialize the FeeTokenMinter contract
     * @param _depositToken Address of the deposit token
     * @param _feeToken Address of the FeeToken token
     * @param _forfeitSink Address where forfeited tokens are sent
     * @param _ethSink Address where ETH contributions are sent
     * @param _swapRouter Address of the Uniswap V3 SwapRouter
     * @param _nonfungiblePositionManager Address of the Uniswap V3 NonfungiblePositionManager
     * @param _backstopIssuance Address for backstop issuance
     * @param _lpIncentives Address for LP issuance
     * @param _launchBlock Block number at which the contract is considered launched
     */
    constructor(
        address _depositToken,
        address _feeToken,
        address _forfeitSink,
        address _ethSink,
        address _swapRouter,
        address _nonfungiblePositionManager,
        address _backstopIssuance,
        address _lpIncentives,
        uint _launchBlock
    ) {
        require(_depositToken != address(0), "_depositToken is null");
        require(_feeToken != address(0), "_feeToken is null");
        require(_forfeitSink != address(0), "_forfeitSink is null");
        require(_ethSink != address(0), "_ethSink is null");
        require(_swapRouter != address(0), "_swapRouter is null");
        require(_nonfungiblePositionManager != address(0), "_nonfungiblePositionManager is null");
        require(_backstopIssuance != address(0), "_backstopIssuance is null");
        require(_lpIncentives != address(0), "_lpIncentives is null");

        DEPLOYMENT_TIMESTAMP = block.timestamp;
        DEPLOYMENT_BLOCK = block.number;

        LAUNCH_BLOCK = _launchBlock;
        LAUNCH_TIMESTAMP = ((LAUNCH_BLOCK - DEPLOYMENT_BLOCK) * TIME_PER_BLOCK_PRODUCTION) + DEPLOYMENT_TIMESTAMP;

        depositToken = IERC20(_depositToken);
        feeToken = IFeeToken(_feeToken);
        router = ISwapRouter(_swapRouter);
        positionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        FORFEIT_SINK = _forfeitSink;
        ETH_SINK = _ethSink;

        // these addresses will have ability to add token vests for incentive farms if activated elsewhere in the system
        backstopIncentives = _backstopIssuance;
        lpIncentives = _lpIncentives;

        // amount of fee token which can be emitted at a fixed Eth rate
        uint availableEmissionsForEth = remainingCappedEthEmissions * ETH_RATE;

        // amount of fee tokens which will be available in aggregate across curve emissions and fixed rate
        availableCurveEmissionsForDepositToken = feeToken.minterSupply() - availableEmissionsForEth;

        // initial fee tokens rewarded for deposit token come out at a fixed rate
        FIXED_RATE_FOR_DEPOSIT_TOKEN = TOTAL_DEPOSITS_AT_FIXED_RATE / FEE_TOKEN_AVAILABLE_AT_FIXED_DEPOSIT_RATE;

        _x = CURVE_RATE_INCREASE_WEIGHT;
        _y = availableCurveEmissionsForDepositToken;
        _k = _x * _y;
    }

    /// @dev There is no valid case for renouncing ownership
    function renounceOwnership() public override onlyOwner {
        revert();
    }

    //==================================================================//
    //-------------------------- MODIFIERS -----------------------------//
    //==================================================================//

    /// @dev Modifier to check if the curve mechanism is active
    modifier curveIsActive {
        if (!curveActive) revert CurveClosed();
        _;
    }

    /// @dev Modifier to restrict access to incentive contracts
    modifier onlyIncentives {
        require((msg.sender == backstopIncentives) || (msg.sender == lpIncentives));
        _;
    }

    /// @dev Modifier to ensure function is only callable after launch
    modifier afterLaunch {
        if (LAUNCH_BLOCK > block.number) revert NotYetLaunched();
        _;
    }

    //==================================================================//
    //----------------------- ADMIN FUNCTIONS --------------------------//
    //==================================================================//

    /**
     * @dev Sets the reward for triggering ORX buybacks when buyback mode is Public
     * @param bips New percentage reward in basis points
     */
    function setBuybackIncentiveBips(uint bips) external onlyOwner {
        require(bips >= 100 && bips <= 1000);
        incentiveFeeBips = bips;
    }

    /**
     * @dev Sets the interval for ORX buybacks
     * @param secs New interval in seconds
     */
    function setBuybackCooldownInterval(uint secs) external onlyOwner {
        require(secs >= 15 minutes && secs <= 1 days);
        buybackCooldownPeriod = secs;
    }

    /**
     * @dev Sets the duration for TWAP calculation
     * @param min New duration in minutes
     */
    function setTwapDurationMins(uint32 min) external onlyOwner {
        require(min >= 5 && min <= 60);
        twapDurationMins = min;
    }

    /**
     * @dev Sets the cap for auto swap
     * @param amount New cap amount
     */
    function setCapPerAutoSwap(uint amount) external onlyOwner {
        require(amount >= 1e18 && amount <= 500_000_000_000e18);
        capPerSwap = amount;
    }

    /**
     * @dev Sets the buyback mode
     * @param mode New buyback mode
     */
    function setBuybackMode(BuybackMode mode) external onlyOwner {
        // not doing input validation, as external call reverts if out of enum range
        buybackMode = mode;
    }

    /**
     * @dev Sets the slippage percentage
     * @param amount New slippage percentage
     */
    function setSlippage(uint amount) external onlyOwner {
        require(amount >= 1 && amount <= 50);
        slippagePCT = amount;
    }

    /**
     * @dev Terminates the curve mechanism
     */
    function terminateCurve() external onlyOwner {
        require(curveActive);
        curveActive = false;
        emit CurveTerminated();
    }

    /**
     * @dev Terminates the backstop deposit farm
     */
    function terminateBackstopDepositFarm() external onlyOwner {
        require(backstopFarmActive);
        backstopFarmActive = false;
        emit BackstopDepositFarmTerminated();
    }

    /**
     * @dev Terminates the LP farm
     */
    function terminateLPFarm() external onlyOwner {
        require(lpFarmActive);
        lpFarmActive = false;
        emit LPFarmTerminated();
    }

    /**
     * @dev Mints the initial position in the Uniswap V3 pool
     */
    function mintInitialPosition() external onlyOwner {
        require(!uniPoolInitialised);

        (address token0, address token1, uint amount0Desired, uint amount1Desired, int24 initialTick) =
                        _getPoolConfig();

        pool = IUniswapV3Pool(
            positionManager.createAndInitializePoolIfNecessary(
                token0,
                token1,
                POOL_FEE,
                TickMath.getSqrtRatioAtTick(initialTick)
            )
        );

        pool.increaseObservationCardinalityNext(100);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: POOL_FEE,
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: (amount0Desired * 90) / 100,
            amount1Min: (amount1Desired * 90) / 100,
            recipient: address(this),
            deadline: block.timestamp + 600
        });

        feeToken.mint(address(this), INITIAL_FEE_TOKEN_LIQUIDITY_AMOUNT);
        feeToken.approve(address(positionManager), INITIAL_FEE_TOKEN_LIQUIDITY_AMOUNT);
        depositToken.approve(address(positionManager), INITIAL_DEPOSIT_TOKEN_LIQUIDITY_AMOUNT);

        (uint tokenId, uint128 liquidity,,) =
                                INonfungiblePositionManager(address(positionManager)).mint(params);

        tokenInfo.tokenId = uint80(tokenId);
        tokenInfo.liquidity = uint128(liquidity);
        tokenInfo.tickLower = MIN_TICK;
        tokenInfo.tickUpper = MAX_TICK;
        uniPoolInitialised = true;
    }

    /**
     * @dev Collects fees from the Uniswap V3 position
     */
    function collectFees() external onlyOwner {
        require(uniPoolInitialised);
        address feeTokenAddress_ = address(feeToken);
        address depositTokenAddress_ = address(depositToken);

        (uint amount0, uint amount1) = _collectFees();

        uint feeTokenAmount;
        uint depositTokenAmount;

        if (feeTokenAddress_ < depositTokenAddress_) {
            feeTokenAmount = amount0;
            depositTokenAmount = amount1;
        } else {
            depositTokenAmount = amount0;
            feeTokenAmount = amount1;
        }

        totalFeeTokensBurned += feeTokenAmount;
        feeToken.burn(feeTokenAmount);
    }

    //==================================================================//
    //----------------- EXTERNAL MUTATIVE FUNCTIONS --------------------//
    //==================================================================//

    function contributeEth() external payable afterLaunch nonReentrant {
        if (msg.value == 0) revert ZeroValueTransaction();
        if (remainingCappedEthEmissions == 0) revert NoFurtherEthAllocation();

        uint contributionAmount = msg.value;
        uint refund;

        if (msg.value > remainingCappedEthEmissions) {
            contributionAmount = remainingCappedEthEmissions;
            refund = msg.value - contributionAmount;
        }

        uint feeTokenAmount = contributionAmount * ETH_RATE;
        remainingCappedEthEmissions -= contributionAmount;

        uint ethContributionId = dripIdGenerator;
        dripIdGenerator++;

        uint beginTime = (block.timestamp < (LAUNCH_TIMESTAMP + ETH_LAUNCH_PHASE_TIME)) ?
            LAUNCH_TIMESTAMP :
            block.timestamp;

        drips[msg.sender][ethContributionId] = DripEntry({
            contributor: msg.sender,
            endTime: uint64(beginTime + CONTRIBUTION_VESTING_PERIOD),
            startTime: uint64(beginTime),
            amount: feeTokenAmount,
            contributionAmount: contributionAmount,
            vested: 0,
            isValid: true
        });

        accountDripIDs[msg.sender].push(ethContributionId);
        currentlyVestingFeeTokens += feeTokenAmount;

        Address.sendValue(payable(ETH_SINK), contributionAmount);

        if (refund > 0) {
            Address.sendValue(payable(msg.sender), refund);
        }

        emit EthContributed(msg.sender, contributionAmount, feeTokenAmount, ethContributionId);
    }

    /**
     * @dev Allows users to deposit tokens and start vesting
     * @param _deposit Amount of tokens to deposit
     * @param referredBy Address of the referrer
     */
    function deposit(uint _deposit, address referredBy) external curveIsActive afterLaunch {
        if (_deposit == 0) revert CannotDepositZero();
        if (!depositToken.transferFrom(msg.sender, address(this), _deposit)) revert FailedToTransferDepositToken();

        (uint mintableFeeTokens, uint newX, uint newY) = calculateReturn(_deposit);
        if (mintableFeeTokens == 0) revert DepositResultsInZeroFeeTokensMinted();

        _y = newY;
        _x = newX;

        deposited[msg.sender] += _deposit;
        totalDeposited += _deposit;
        maxFutureFeeTokensFromDeposits += mintableFeeTokens;
        currentlyVestingFeeTokens += mintableFeeTokens;

        _appendVestingEntry(msg.sender, mintableFeeTokens, referredBy, DEPOSIT_VESTING_PERIOD, _deposit);
        emit Deposit(msg.sender, _deposit, referredBy, mintableFeeTokens);
    }

    /**
     * @dev Performs a buyback of FeeTokens
     * @return amountOut The amount of FeeTokens bought back
     */
    function buyback() external nonReentrant returns (uint amountOut) {
        if (!uniPoolInitialised) revert LPNotInitialized();
        if (buybackMode == BuybackMode.Private && msg.sender != owner()) revert OnlyCallableByOwnerDuringPrivateMode();

        if (msg.sender != tx.origin) revert OnlyCallableByEOA();
        if ((block.timestamp - lastBuyback) < buybackCooldownPeriod) revert BuybackCooldownNotRespected();

        lastBuyback = block.timestamp;

        uint amountIn = depositToken.balanceOf(address(this));
        uint buyCap = capPerSwap;
        if (amountIn > buyCap) {
            amountIn = buyCap;
        }

        uint256 incentiveFee;
        if (buybackMode == BuybackMode.Private) {
            incentiveFee = 0;
        } else {
            incentiveFee = (amountIn * incentiveFeeBips) / 10_000;
            amountIn -= incentiveFee;
            require(depositToken.transfer(msg.sender, incentiveFee), "Inc transfer error");
        }

        if (amountIn == 0) revert BuybackEmpty();

        depositToken.approve(address(router), amountIn);
        uint amountOutMinimum = calculateMinimumFeeTokenAmount(amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(depositToken),
            tokenOut: address(feeToken),
            fee: POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        amountOut = router.exactInputSingle(params);

        feeToken.burn(amountOut);

        totalDepositTokenUsedForBuyAndBurns += amountIn;
        totalFeeTokensBurned += amountOut;

        emit Buyback(msg.sender, amountIn, amountOut, amountOutMinimum, incentiveFee, buybackMode, slippagePCT);
    }

    /**
    * @dev Allows users to claim vested FeeTokens from their ETH contribution
    * @param dripId ID of the ETH contribution (drip)
    * @return dripped Amount of FeeTokens claimed
    */
    function drip(uint dripId) external returns (uint dripped) {
        DripEntry storage contribution = drips[msg.sender][dripId];

        if (!contribution.isValid) revert InvalidDripId();
        if (contribution.amount <= contribution.vested) revert AllTokensAlreadyDripped();

        uint claimableAmount = calculatePendingDrip(msg.sender, dripId);
        contribution.vested = contribution.vested + claimableAmount;
        dripped = claimableAmount;
        currentlyVestingFeeTokens -= dripped;
        if (dripped > 0) {
            feeToken.mint(msg.sender, claimableAmount);
            emit DripClaimed(msg.sender, dripId, claimableAmount);
        }
    }

    /**
     * @dev Allows users to vest their tokens
     * @param vestId ID of the vesting entry to vest
     */
    function vest(uint vestId, bool allowNuke) external {
        VestingEntry storage entry = vests[msg.sender][vestId];

        if (!entry.isValid) revert InvalidVestId();
        if (entry.escrowAmount == 0) revert ClaimAlreadyVested();

        (uint vested, uint forfeit) = _claimableVest(entry);
        if (vested == 0 && !allowNuke) revert ClaimingBeforeMinimumPeriod();

        currentlyVestingFeeTokens -= entry.escrowAmount;
        vesting[msg.sender] -= entry.escrowAmount;
        entry.escrowAmount = 0;
        entry.vested = vested;
        entry.forfeit = forfeit;

        if (forfeit != 0) {
            forfeitedSupply += forfeit;
            feeToken.mint(FORFEIT_SINK, forfeit);
        }

        if (vested != 0) {
            entry.stagedStart = block.timestamp;
            entry.stagedAmount = vested;
            totalStaged += vested;
            emit TokensStaged(msg.sender, vested, block.timestamp + 3 days);

            if (entry.referrer != address(0)) {
                uint referralBonus = (vested * 2) / 100; // 2%
                totalStaged += referralBonus;
                emit TokensStaged(entry.referrer, referralBonus, block.timestamp + 3 days);
            }
        }

        emit VestClaimed(msg.sender, vestId, vested, forfeit);
    }

    /**
     * @dev Allows users to claim their staged tokens
     * @param vestId ID of the vesting entry to claim staged tokens from
     */
    function claimStagedTokens(uint vestId) public {
        VestingEntry storage entry = vests[msg.sender][vestId];
        if (!entry.isValid) revert InvalidVestId();
        if (entry.stagedAmount == 0) revert NoTokensToClaim();
        if (block.timestamp < entry.stagedStart + 3 days) revert TokensNotYetClaimable();

        uint amount = entry.stagedAmount;
        entry.stagedAmount = 0;

        totalStaged -= amount;

        if (entry.referrer != address(0)) {
            uint referralBonus = (amount * 2) / 100; // 2%
            totalStaged -= referralBonus;
            totalReferralRewards[entry.referrer] += referralBonus;
            feeToken.mint(entry.referrer, referralBonus);
            emit StagedTokensClaimed(entry.referrer, vestId, referralBonus);
        }

        feeToken.mint(msg.sender, amount);

        emit StagedTokensClaimed(msg.sender, vestId, amount);
    }

    /**
     * @dev Appends a vesting entry for an account (only callable by incentive contracts)
     * @param account Address of the account to receive the vested tokens
     * @param quantity Amount of tokens to vest
     */
    function appendVestingEntry(address account, uint quantity) external override onlyIncentives {
        bool shouldReward =
            (msg.sender == lpIncentives && lpFarmActive) ||
            (msg.sender == backstopIncentives && backstopFarmActive);

        if (shouldReward && (block.number >= LAUNCH_BLOCK)) {
            currentlyVestingFeeTokens += quantity;
            _appendVestingEntry(account, quantity, address(0), DEPOSIT_VESTING_PERIOD, 0);
        }
    }

    //==================================================================//
    //---------------------- INTERNAL FUNCTIONS ------------------------//
    //==================================================================//

    /**
     * @dev Appends a vesting entry
     * @param account Address of the account to receive the vested tokens
     * @param quantity Amount of tokens to vest
     * @param referrer Address of the referrer
     * @param duration Duration of the vesting period
     * @param _deposit Amount of tokens deposited
     */
    function _appendVestingEntry(address account, uint quantity, address referrer, uint duration, uint _deposit) internal {
        uint vestId = vestIdGenerator;
        vestIdGenerator++;
        uint endTime = block.timestamp + duration;
        vesting[account] += quantity;

        vests[account][vestId] = VestingEntry({
            owner: account,
            endTime: uint64(endTime),
            startTime: uint64(block.timestamp),
            deposit: _deposit,
            escrowAmount: quantity,
            vested: 0,
            forfeit: 0,
            duration: duration,
            referrer: referrer,
            isValid: true,
            stagedStart: 0,
            stagedAmount: 0
        });

        if (referrer != address(0)) {
            totalReferrals[referrer]++;
            vestToVestOwnerIfHasReferrer[vestId] = account;
            referralVestingIDs[referrer].push(vestId);
        }

        accountVestingIDs[account].push(vestId);
        emit VestStarted(account, quantity, duration, vestId, referrer);
    }

    /**
     * @dev Calculates the claimable amount for a vesting entry
     * @param _entry The vesting entry to calculate for
     * @return vested The amount of tokens vested
     * @return forfeit The amount of tokens forfeited
     */
    function _claimableVest(VestingEntry memory _entry) internal view returns (uint vested, uint forfeit) {
        uint escrowAmount = _entry.escrowAmount;

        if (escrowAmount == 0) {
            return (0, 0); // Already fully claimed
        }

        uint timeElapsed = block.timestamp - _entry.startTime;
        uint halfDuration = _entry.duration / 2;

        if (block.timestamp >= _entry.endTime) {
            return (escrowAmount, 0); // Full amount claimable after end time
        } else if (timeElapsed < DEPOSIT_VESTING_CLIFF_DURATION) {
            return (0, escrowAmount); // Nothing claimable in first 28 days
        } else if (timeElapsed <= halfDuration) {
            // Slow linear increase up to 10% for the first half of the term
            uint maxFirstHalfVested = escrowAmount * 10 / 100;
            vested = maxFirstHalfVested * timeElapsed / halfDuration;
        } else {
            // Exponential increase for the second half of the term
            uint secondHalfElapsed = timeElapsed - halfDuration;
            uint secondHalfDuration = _entry.duration - halfDuration;

            // It's ok that second half initially vests slower than linear vest, because it makes up for it on tail end.
            uint exponentialFactor = ((secondHalfElapsed ** 2) * 1e18) / (secondHalfDuration ** 2);
            uint maxSecondHalfVested = escrowAmount - (escrowAmount * 10 / 100);
            vested = (escrowAmount * 10 / 100) + ((maxSecondHalfVested * exponentialFactor) / 1e18);
        }

        forfeit = escrowAmount - vested;
        return (vested, forfeit);
    }

    /**
     * @dev Gets the token configuration for pool initialization
     * @return token0 Address of token0
     * @return token1 Address of token1
     * @return amount0 Amount of token0
     * @return amount1 Amount of token1
     */
    function _getPoolConfig()
    private view returns (address token0, address token1, uint amount0, uint amount1, int24 tick) {
        address feeTokenAddress_ = address(feeToken);
        address depositTokenAddress_ = address(depositToken);

        if (feeTokenAddress_ < depositTokenAddress_) {
            token0 = feeTokenAddress_;
            amount0 = INITIAL_FEE_TOKEN_LIQUIDITY_AMOUNT;
            token1 = depositTokenAddress_;
            amount1 = INITIAL_DEPOSIT_TOKEN_LIQUIDITY_AMOUNT;
            tick = INITIAL_TICK_IF_FEE_TOKEN_IS_TOKEN0;
        } else {
            token0 = depositTokenAddress_;
            amount0 = INITIAL_DEPOSIT_TOKEN_LIQUIDITY_AMOUNT;
            token1 = feeTokenAddress_;
            amount1 = INITIAL_FEE_TOKEN_LIQUIDITY_AMOUNT;
            tick = INITIAL_TICK_IF_DEPOSIT_TOKEN_IS_TOKEN0;
        }
    }

    /**
     * @dev Collects fees from the Uniswap V3 position
     * @return amount0 Amount of token0 collected
     * @return amount1 Amount of token1 collected
     */
    function _collectFees() private returns (uint amount0, uint amount1) {
        (amount0, amount1) = positionManager.collect(INonfungiblePositionManager.CollectParams({
            tokenId: tokenInfo.tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        }));
    }

    //==================================================================//
    //----------------- PUBLIC/EXTERNAL VIEW FUNCTIONS -----------------//
    //==================================================================//

    /**
     * @dev Calculates the FeeToken return for a given ETH amount
     * @param amount Amount of ETH
     * @return The calculated FeeToken return
     */
    function calculateEthReturn(uint amount) external view returns (uint) {
        if (amount == 0) {
            return 0;
        } else if (amount >= remainingCappedEthEmissions) {
            return remainingCappedEthEmissions * ETH_RATE;
        } else {
            return amount * ETH_RATE;
        }
    }

    /**
    * @dev Calculates the amount of FeeTokens available to claim from an ETH contribution
    * @param owner Address of the ETH contributor
    * @param dripId ID of the ETH contribution (drip)
    * @return claimableAmount Amount of FeeTokens available to claim
    */
    function calculatePendingDrip(address owner, uint dripId) public view returns (uint256 claimableAmount) {
        DripEntry storage _drip = drips[owner][dripId];
        if (!_drip.isValid || _drip.amount <= _drip.vested) {
            return 0;
        }

        uint256 currentTime = block.timestamp;
        uint256 startTime = uint256(_drip.startTime);
        uint256 endTime = uint256(_drip.endTime);
        uint256 cliffDuration = ETH_CONTRIBUTION_CLIFF_DURATION;

        if (currentTime >= endTime) {
            claimableAmount = _drip.amount - _drip.vested;
        } else if (currentTime <= startTime + cliffDuration) {
            claimableAmount = 0;
        } else {
            uint256 vestingDuration = endTime - startTime - cliffDuration;
            uint256 timeVested = currentTime - startTime - cliffDuration;
            claimableAmount = ((((_drip.amount * 1e18) * timeVested) / vestingDuration) / 1e18) - _drip.vested;
        }
    }

    /**
     * @dev Calculates the return for a given token input
     * @param tokenIn Amount of tokens to input
     * @return emittableFeeTokens Amount of FeeToken that can be emitted
     * @return newX New X value after the calculation
     * @return newY New Y value after the calculation
     */
    function calculateReturn(uint tokenIn) public view returns (uint emittableFeeTokens, uint newX, uint newY) {
        if (totalDeposited >= TOTAL_DEPOSITS_AT_FIXED_RATE) {
            newX = _x + tokenIn;
            newY = _k / newX;
            emittableFeeTokens = _y - newY;
        } else if ((totalDeposited + tokenIn) <= TOTAL_DEPOSITS_AT_FIXED_RATE) {
            emittableFeeTokens = tokenIn / FIXED_RATE_FOR_DEPOSIT_TOKEN;
            // Still update the curve, because we want it to be higher than the fixed rate by the time it kicks in.
            newX = _x;
            newY = _y;
        } else {
            uint curveRatePortion = (totalDeposited + tokenIn) - TOTAL_DEPOSITS_AT_FIXED_RATE;
            uint fixedRatePortion = tokenIn - curveRatePortion;
            newX = _x + curveRatePortion;
            newY = _k / newX;
            emittableFeeTokens = _y - newY;
            emittableFeeTokens += fixedRatePortion / FIXED_RATE_FOR_DEPOSIT_TOKEN;
        }
    }

    /**
     * @dev Gets the claimable amount for a specific vesting entry
     * @param user Address of the user
     * @param vestId ID of the vesting entry
     * @return quantity Amount claimable
     * @return forfeit Amount to be forfeited
     */
    function getVestingEntryClaimable(address user, uint vestId) external view returns (uint quantity, uint forfeit) {
        VestingEntry memory entry = vests[user][vestId];
        if (!entry.isValid) revert VestDoesNotExist();
        (quantity, forfeit) = _claimableVest(entry);
    }

    /**
     * @dev Calculates the minimum FeeToken amount for a given input amount
     * @param amountIn Input amount
     * @return amountOutMinimum Minimum output amount
     */
    function calculateMinimumFeeTokenAmount(uint amountIn) public view returns (uint amountOutMinimum) {
        uint slippage_ = slippagePCT;
        uint expectedFeeTokenAmount = getFeeTokenQuoteForDepositToken(amountIn);
        amountOutMinimum = (expectedFeeTokenAmount * (100 - slippage_)) / 100;
    }

    /**
     * @dev Gets a quote for token swap
     * @param tokenIn Address of input token
     * @param tokenOut Address of output token
     * @param amountIn Amount of input token
     * @param secondsAgo Number of seconds ago for the TWAP
     * @return amountOut Quoted output amount
     */
    function getQuote(address tokenIn, address tokenOut, uint amountIn, uint32 secondsAgo) public view returns (uint amountOut) {
        address poolAddress = PoolAddress.computeAddress(
            address(positionManager.factory()),
            PoolAddress.getPoolKey(tokenIn, tokenOut, POOL_FEE)
        );

        uint32 oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(poolAddress);
        if (oldestObservation < secondsAgo) {
            secondsAgo = oldestObservation;
        }

        uint160 sqrtPriceX96;
        if (secondsAgo == 0) {
            IUniswapV3Pool uniPool = IUniswapV3Pool(poolAddress);
            (sqrtPriceX96,,,,,,) = uniPool.slot0();
        } else {
            (int24 arithmeticMeanTick,) = OracleLibrary.consult(poolAddress, secondsAgo);
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        }

        return OracleLibrary.getQuoteForSqrtRatioX96(sqrtPriceX96, amountIn, tokenIn, tokenOut);
    }

    /**
     * @dev Gets a quote for FeeToken in terms of deposit token
     * @param baseAmount Amount of deposit token
     * @return quote Quoted amount of FeeToken
     */
    function getFeeTokenQuoteForDepositToken(uint baseAmount) public view returns (uint quote) {
        return getQuote(address(depositToken), address(feeToken), baseAmount, twapDurationMins * 60);
    }

    //==================================================================//
    //-------------- EXTERNAL VIEW FUNCTIONS FOR UI --------------------//
    //==================================================================//

    /**
     * @dev Struct to represent a vesting entry with additional information
     */
    struct External_VestingEntry {
        address owner;
        uint64 endTime;
        uint startTime;
        uint escrowAmount;
        uint vested;
        uint forfeit;
        uint deposit;
        uint duration;
        address referrer;
        bool isValid;
        uint stagedStart;
        uint stagedAmount;

        uint vestId;
        uint currentVest;
        uint currentForfeit;
    }

    /**
     * @dev Struct to represent a drip entry with additional information
     */
    struct External_DripEntry {
        address contributor;
        uint64 endTime;
        uint startTime;
        uint amount;
        uint contributionAmount;
        uint vested;
        bool isValid;

        uint dripId;
        uint claimable;
    }

    /**
     * @dev Returns accountVestingId's as array for account
     * @param account The account to lookup
     * @return vestingIds array
     */
    function getAccountVestingIDs(address account) external view returns (uint[] memory) {
        return accountVestingIDs[account];
    }

    /**
     * @dev Returns referralVestingId's as array for account
     * @param account The account to lookup
     * @return referralVestingIds array
     */
    function getReferralVestingIDs(address account) external view returns (uint[] memory) {
        return referralVestingIDs[account];
    }

    /**
     * @dev Gets the total number of ETH vesting entries for an account
     * @param account Address of the account
     * @return The total number of ETH vesting entries
     */
    function getTotalEthContributions(address account) external view returns (uint) {
        return accountDripIDs[account].length;
    }

    /**
     * @dev Gets the total number of vesting entries for an account
     * @param account Address of the account
     * @return The total number of vesting entries
     */
    function getTotalVestingEntries(address account) external view returns (uint) {
        return accountVestingIDs[account].length;
    }

    /**
     * @dev Gets the total number of referral entries for an account
     * @param account Address of the account
     * @return The total number of referral entries
     */
    function getTotalReferralEntries(address account) external view returns (uint) {
        return referralVestingIDs[account].length;
    }

    /**
     * @dev Gets a paginated list of vesting entries for an account
     * @param account Address of the account
     * @param startIdx Starting index for pagination
     * @param count Number of entries to return
     * @return entries An array of External_VestingEntry structs
     */
    function getVestingEntries(address account, uint startIdx, uint count) external view returns (External_VestingEntry[] memory entries) {
        uint totalVests = accountVestingIDs[account].length;

        if (startIdx >= totalVests) {
            // Paged to the end.
            return entries;
        }

        uint endIdx = startIdx + count;
        if (endIdx > totalVests) {
            endIdx = totalVests;
        }

        entries = new External_VestingEntry[](endIdx - startIdx);

        for (uint i = startIdx; i < endIdx; i++) {
            uint vestId = accountVestingIDs[account][i];
            VestingEntry memory _vest = vests[account][vestId];
            (uint vested, uint forfeit) = _claimableVest(_vest);

            entries[i - startIdx] = External_VestingEntry({
                vestId: vestId,
                owner: _vest.owner,
                endTime: _vest.endTime,
                startTime: _vest.startTime,
                escrowAmount: _vest.escrowAmount,
                vested: _vest.vested,
                forfeit: _vest.forfeit,
                deposit: _vest.deposit,
                duration: _vest.duration,
                referrer: _vest.referrer,
                isValid: _vest.isValid,
                stagedStart: _vest.stagedStart,
                stagedAmount: _vest.stagedAmount,
                currentVest: vested,
                currentForfeit: forfeit
            });
        }
    }

    /**
    * @dev Gets a paginated list of drip entries for an account
    * @param account Address of the account
    * @param startIdx Starting index for pagination
    * @param count Number of entries to return
    * @return entries An array of External_DripEntry structs
    */
    function getDripEntries(address account, uint startIdx, uint count) external view returns (External_DripEntry[] memory entries) {
        uint totalVests = accountDripIDs[account].length;

        if (startIdx >= totalVests) {
            return entries;
        }

        uint endIdx = startIdx + count;
        if (endIdx > totalVests) {
            endIdx = totalVests;
        }

        entries = new External_DripEntry[](endIdx - startIdx);

        for (uint i = startIdx; i < endIdx; i++) {
            uint dripId = accountDripIDs[account][i];
            DripEntry memory _drip = drips[account][dripId];
            uint claimable = calculatePendingDrip(account, dripId);

            entries[i - startIdx] = External_DripEntry({
                contributor: _drip.contributor,
                endTime: _drip.endTime,
                startTime: _drip.startTime,
                amount: _drip.amount,
                contributionAmount: _drip.contributionAmount,
                vested: _drip.vested,
                isValid: _drip.isValid,
                dripId: dripId,
                claimable: claimable
            });
        }
    }

    /**
     * @dev Gets a paginated list of referral entries for an account
     * @param account Address of the account
     * @param startIdx Starting index for pagination
     * @param count Number of entries to return
     * @return entries An array of External_VestingEntry structs
     */
    function getReferralEntries(address account, uint startIdx, uint count) external view returns (External_VestingEntry[] memory entries) {
        uint totalRefs = referralVestingIDs[account].length;

        if (startIdx >= totalRefs) {
            // Paged to the end.
            return entries;
        }

        uint endIdx = startIdx + count;
        if (endIdx > totalRefs) {
            endIdx = totalRefs;
        }

        entries = new External_VestingEntry[](endIdx - startIdx);

        for (uint i = startIdx; i < endIdx; i++) {
            uint vestId = referralVestingIDs[account][i];
            VestingEntry memory _vest = vests[vestToVestOwnerIfHasReferrer[vestId]][vestId];
            (uint vested, uint forfeit) = _claimableVest(_vest);

            entries[i - startIdx] = External_VestingEntry({
                vestId: vestId,
                owner: _vest.owner,
                endTime: _vest.endTime,
                startTime: _vest.startTime,
                escrowAmount: _vest.escrowAmount,
                vested: _vest.vested,
                forfeit: _vest.forfeit,
                deposit: _vest.deposit,
                duration: _vest.duration,
                referrer: _vest.referrer,
                isValid: _vest.isValid,
                stagedStart: _vest.stagedStart,
                stagedAmount: _vest.stagedAmount,
                currentVest: vested,
                currentForfeit: forfeit
            });
        }
    }
}