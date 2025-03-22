/*
        [....     [... [......  [.. ..
      [..    [..       [..    [..    [..
    [..        [..     [..     [..         [..       [..
    [..        [..     [..       [..     [.   [..  [..  [..
    [..        [..     [..          [.. [..... [..[..   [..
      [..     [..      [..    [..    [..[.        [..   [..
        [....          [..      [.. ..    [....     [.. [...

    OTSea Stable Platform.

    https://otsea.io
    https://t.me/OTSeaPortal
    https://twitter.com/OTSeaERC20
*/

// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "contracts/helpers/ListHelper.sol";
import "contracts/helpers/SignatureHelper.sol";
import "contracts/helpers/WhitelistHelper.sol";
import "contracts/libraries/OTSeaErrors.sol";
import "contracts/libraries/OTSeaLibrary.sol";

/**
 * @title OTSea Over-the-Counter (OTC) Contract
 * @dev This contract facilitates the creation and execution of buy and sell orders for tokens using stable coins.
 *
 * Key definitions:
 *   - Order: An instruction given by a user to buy or sell tokens for a certain amount of stable coin.
 *   - Trade/Swap: The partial or complete execution of an order.
 *   - Input:
 *       - For buy orders: The amount of stable coin that will be used to purchase tokens.
 *       - For sell orders: The amount of tokens that will be up for sale.
 *   - Output:
 *       - For buy orders: The amount of tokens desired for the stable coin input.
 *       - For sell orders: The amount of stable coin desired for the token input.
 *
 * Transfer tax tokens:
 *   - When creating a sell order, if upon transferring tokens into the contract there are fewer tokens than expected. It
 *     is assumed the token has a transfer tax therefore, the total input and total output are reduced.
 *
 * Order features:
 *   - All-or-Nothing (AON): If enabled, an order must be filled in a single trade. If disabled, orders can be partially filled.
 *   - Whitelisting: Restricts trading to only whitelisted addresses.
 *   - Lock-up (for sell orders only): If enabled, when swapping stable coins for tokens, the tokens are locked for a duration
 *     set by the contract with the aim of reducing arbitraging. Traders can claim their tokens after the lockup
 *     period.
 *   - Hide on Frontend: Hide an order on the frontend interface.
 *
 * Platform fees:
 *   - The fee is a percentage of the stable coin traded.
 *   - The percentage charged depends on what fee type (fish or whale) the seller is. This is determined by the sellers
 *     OTSeaERC20 balance off-chain.
 *   - Initially the fish fee will be 1% and the whale fee will be 0.3%.
 *   - Fees cannot be increased, only reduced.
 *
 * EIP712 is used to sign typed data when creating a sell order or when swapping tokens for stable coins. By using a signature,
 * the contract can reliably know a user's fee type. If this were to be calculated on-chain it could be subject to
 * flash loan attacks and also would limit this contract to only be deployable on Ethereum mainnet.
 *
 * Partners:
 *   - Partners of OTSea receive a portion of the platform fee (initially 30%).
 *   - Partners have the ability to toggle on a lock-up for their project's token. If set, all swaps from stable coins to their
 *     project's token will be locked for a duration set by the contract with the aim of reducing arbitraging.
 *     Traders can claim their tokens after the lockup period ends for a specific lock-up.
 *
 * Blacklisting:
 *   - The owner of the contract has the ability to blacklist user addresses. Doing so results in the blacklisted user
 *     not being able to create new orders, trade, update the order, on top of this other other users cannot trade with
 *     orders belonging to blacklisted accounts. Blacklisted users can only cancel orders and claim their
 *     locked-up tokens.
 */
contract OTSeaStable is
    ListHelper,
    Ownable,
    Pausable,
    ReentrancyGuard,
    SignatureHelper,
    WhitelistHelper
{
    using SafeERC20 for IERC20;

    struct NewOrder {
        IERC20 stablecoin;
        IERC20 token;
        bool isAON;
        /**
         * @dev withLockUp is a boolean only applicable to sell orders. If true, when swapping stablecoins for the order's tokens,
         * the amount the user should receive will instead be locked up for the duration set by _lockupPeriod.
         * After the lockup period has passed, the user is then able to claim their tokens.
         */
        bool withLockUp;
        bool isHidden;
        uint256 totalInput;
        uint256 totalOutput;
    }

    struct Order {
        address creator;
        OrderType orderType;
        State state;
        OTSeaLibrary.FeeType feeType;
        bool isAON;
        bool isHidden;
        bool withLockUp;
        IERC20 stablecoin;
        IERC20 token;
        uint256 totalInput;
        uint256 inputTransacted;
        uint256 totalOutput;
        uint256 outputTransacted;
    }

    struct FeeDetailsSignature {
        bytes signature;
        uint256 expiresAt;
        OTSeaLibrary.FeeType feeType;
    }

    /**
     * @dev the Trade struct represents a trade a user wants to perform.
     * - If a user wants to swap stablecoins for tokens, it is a buy trade that interacts with sell orders (BuyTrade struct is used).
     * - If a user wants to swap tokens for stablecoins, it is a sell trade that interacts with buy orders (Trade struct is used).
     */
    struct Trade {
        /// @dev valid orders will always have an orderID greater than 0 and less than or equal to the total orders.
        uint72 orderID;
        /**
         * @dev Definition of amountToSwap:
         * Buy trade:
         *  - amount of stablecoins to swap for tokens.
         * Sell trade:
         *  - amount of tokens to swap for stablecoins.
         */
        uint256 amountToSwap;
        /**
         * @dev "totalOutput" is used to calculate the amount to receive from a trade.
         * - Trade.totalOutput must exactly match Order.totalOutput.
         * - Any discrepancy between these values causes the TX to revert.
         * - This strict equality check prevents the manipulation of order outputs (e.g., front-running) by the order creators.
         */
        uint256 totalOutput;
    }

    /**
     * @dev The partner struct refers to partners of OTSea. account is set to an address owned by the project for the
     * purpose of:
     * - Receiving the referral fees
     * - Being able to manually enforce lock-ups on orders that exchange the project's token
     */
    struct Partner {
        address account;
        bool isLockUpOverrideEnabled;
    }

    struct LockUp {
        address token;
        uint88 unlockAt;
        uint256 amount;
        uint256 withdrawn;
    }

    struct ClaimLockUp {
        uint256 index;
        uint256 amount;
    }

    enum State {
        Open,
        Fulfilled,
        Cancelled
    }

    enum OrderType {
        Buy,
        Sell
    }

    /// @dev Partner referral fees can be set to be between 10-50% (to 2 d.p.) of the platform revenue
    uint16 private constant MIN_PARTNER_FEE = 1000;
    uint16 private constant MAX_PARTNER_FEE = 5000;
    uint8 private constant MAX_TRADES_UPPER_LIMIT = 100;
    uint8 private constant MAX_CANCELLATIONS = 100;
    uint8 private constant MIN_LOCKUP_TIME = 1 minutes;
    uint16 private constant MAX_LOCKUP_TIME = 1 hours;
    bytes32 private constant FEE_DETAILS_SIGNATURE_TYPE =
        keccak256("FeeDetails(address account,uint256 expiresAt,uint8 feeType)");
    address private _revenueDistributor;
    uint72 private _totalOrders;
    /// @dev _fishFee = 1% of the stablecoins traded
    uint8 private _fishFee = 100;
    /// @dev _whaleFee = 0.3% of the stablecoins traded
    uint8 private _whaleFee = 30;
    uint8 private _maxTrades = 10;
    uint16 private _partnerFee = 3000;
    uint16 private _lockupPeriod = 5 minutes;
    mapping(uint72 => Order) private _orders;
    /// @dev token => partner
    mapping(address => Partner) private _partners;
    /// @dev user address => lock-up list
    mapping(address => LockUp[]) private _lockUps;
    mapping(address => bool) private _blacklist;
    /// @dev stablecoin => available
    mapping(address => bool) private _stablecoins;

    /// @dev errors
    error UnlockDateNotReached(uint256 index);
    error LockUpNotAllowed();
    error OrderBlacklisted();
    error InvalidTradeOrderType();
    error OrderNotFound(uint72 orderID);

    /// @dev events
    event FeesUpdated(uint8 fishFee, uint8 whaleFee, uint16 partnerFee);
    event MaxTradesUpdated(uint8 maxSwaps);
    event PartnerUpdated(address indexed token, Partner partner);
    event LockUpOverrideUpdated(address indexed account, address indexed token, bool enforced);
    event LockupPeriodUpdated(uint16 time);
    event BlacklistUpdated(address indexed account, bool operation);
    event BuyOrderCreated(
        uint72 indexed orderID,
        address indexed creator,
        NewOrder newOrder,
        uint8 stableDecimals,
        uint8 decimals
    );
    event SellOrderCreated(
        uint72 indexed orderID,
        address indexed creator,
        NewOrder newOrder,
        uint256 actualTotalInput,
        uint256 actualTotalOutput,
        OTSeaLibrary.FeeType feeType,
        uint8 stableDecimals,
        uint8 decimals
    );
    event SwappedStableForTokens(
        address indexed account,
        address indexed stablecoin,
        address indexed token,
        Trade[] trades,
        uint256 swapped,
        uint256 received,
        uint256 claimable
    );
    event SwappedTokensForStable(
        address indexed account,
        address indexed stablecoin,
        address indexed token,
        Trade[] trades,
        uint256 swapped,
        uint256 received,
        OTSeaLibrary.FeeType feeType
    );
    event Traded(
        uint72 indexed orderID,
        address indexed account,
        uint256 swapped,
        uint256 received
    );
    event LockUpsClaimed(address indexed account, address indexed receiver, ClaimLockUp[] claims);
    event OrderPriceUpdated(uint72 indexed orderID, uint256 newTotalOutput);
    event OrderLockUpUpdated(uint72 indexed orderID, bool enforced);
    event CancelledOrders(uint72[] orderIDs);
    event RevenueTransferred(address stablecoin, uint256 amount);
    event PartnerFeePaid(
        address indexed token,
        address stablecoin,
        address indexed partner,
        uint256 amount
    );
    event SetStablecoin(
        address indexed stablecoin,
        bool enabled
    );

    /// @param _orderID Order ID
    modifier onlyOrderCreator(uint72 _orderID) {
        _checkCallerIsOrderCreator(_orderID);
        _;
    }

    modifier whenNotBlacklisted() {
        _checkCallerIsNotBlacklisted();
        _;
    }

    /// @param _stablecoin Stablecoin address
    modifier availableStablecoin(IERC20 _stablecoin) {
        _checkIsAvailableStablecoin(address(_stablecoin));
        _;
    }

    /**
     * @param _multiSigAdmin Multi-sig admin
     * @param revenueDistributor_ Revenue distributor contract
     * @param _signer Signer address
     * @param stablecoins_ Stablecoin addresses
     */
    constructor(
        address _multiSigAdmin,
        address revenueDistributor_,
        address _signer,
        address[] memory stablecoins_
    ) Ownable(_multiSigAdmin) SignatureHelper("OTSea", "v1.0.0", _signer) {
        if (address(revenueDistributor_) == address(0)) revert OTSeaErrors.InvalidAddress();
        _revenueDistributor = revenueDistributor_;

        uint256 length = stablecoins_.length;
        for (uint256 i = 0; i < length; i++) {
            if (stablecoins_[i] == address(0)) revert OTSeaErrors.InvalidAddress();
            _stablecoins[stablecoins_[i]] = true;

            emit SetStablecoin(stablecoins_[i], true);
        }
    }

    /// @notice Update the Revenue Distributor
    function setRevenueDistributor(address revenueDistributor_) external onlyOwner {
        if (address(_revenueDistributor) == address(0)) revert OTSeaErrors.InvalidAddress();
        _revenueDistributor = revenueDistributor_;
    }

    /// @notice Pause the contract
    function pauseContract() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpauseContract() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Set/reset stable coins
     * @param _stablecoin Stablecoin address
     * @param _isEnable Available flag
     */
    function setStablecoin(address _stablecoin, bool _isEnable) external onlyOwner {
        if (_stablecoin == address(0)) revert OTSeaErrors.InvalidAddress();
        if (_stablecoins[_stablecoin] == _isEnable) revert OTSeaErrors.Unchanged();
        _stablecoins[_stablecoin] = _isEnable;

        emit SetStablecoin(_stablecoin, _isEnable);
    }

    /**
     * @notice Set the fish and whale fees
     * @param _newFishFee Fish fee
     * @param _newWhaleFee Whale fee
     * @param _newPartnerFee Partner fee relative to the revenue
     */
    function setFees(
        uint8 _newFishFee,
        uint8 _newWhaleFee,
        uint16 _newPartnerFee
    ) external onlyOwner {
        if (
            _fishFee < _newFishFee ||
            _whaleFee < _newWhaleFee ||
            _newFishFee < _newWhaleFee ||
            _newPartnerFee < MIN_PARTNER_FEE ||
            MAX_PARTNER_FEE < _newPartnerFee
        ) revert OTSeaErrors.InvalidFee();
        _fishFee = _newFishFee;
        _whaleFee = _newWhaleFee;
        _partnerFee = _newPartnerFee;
        emit FeesUpdated(_newFishFee, _newWhaleFee, _newPartnerFee);
    }

    /**
     * @notice Set the maximum number of trades that can occur in a single TX
     * @param maxTrades_ Max trades
     */
    function setMaxTrades(uint8 maxTrades_) external onlyOwner {
        if (maxTrades_ == 0 || MAX_TRADES_UPPER_LIMIT < maxTrades_)
            revert OTSeaErrors.InvalidAmount();
        _maxTrades = maxTrades_;
        emit MaxTradesUpdated(maxTrades_);
    }

    /**
     * @notice Add, remove or update a partner's details
     * @param _token Token address
     * @param _partner Partner details
     */
    function updatePartner(address _token, Partner calldata _partner) external onlyOwner {
        if (_token == address(0)) revert OTSeaErrors.InvalidAddress();
        if (
            _partners[_token].account == _partner.account &&
            _partners[_token].isLockUpOverrideEnabled == _partner.isLockUpOverrideEnabled
        ) revert OTSeaErrors.Unchanged();
        if (_partner.account == address(0) && _partner.isLockUpOverrideEnabled)
            revert OTSeaErrors.NotAvailable();
        _partners[_token] = Partner(_partner.account, _partner.isLockUpOverrideEnabled);
        emit PartnerUpdated(_token, _partner);
    }

    /**
     * @notice Add/remove a lock-up override for a token, only the partner and the owner can make this change
     * @param _token Token address
     * @param _enforce enable (true) or disable (false)
     * @dev If token lock-up override is enabled, when swapping stablecoins for tokens, the tokens will be held in the contract
     * for the trader to claim after the _lockupPeriod has passed. If disabled, it will fallback to the Order.withLockUp
     * boolean when swapping stablecoins for tokens.
     */
    function updateLockUpOverride(address _token, bool _enforce) external {
        Partner storage partner = _partners[_token];
        /// @dev no need to check if _token is the zero address because partner.account would equal the zero address
        if (partner.account == address(0)) revert OTSeaErrors.NotAvailable();
        if (partner.account != _msgSender() && owner() != _msgSender())
            revert OTSeaErrors.Unauthorized();
        if (partner.isLockUpOverrideEnabled == _enforce) revert OTSeaErrors.Unchanged();
        partner.isLockUpOverrideEnabled = _enforce;
        emit LockUpOverrideUpdated(_token, _msgSender(), _enforce);
    }

    /**
     * @notice Set the lockup period for orders using a lock-up or for tokens that have enforced a lock-up override
     * @param _time Time (in seconds)
     */
    function setLockupPeriod(uint16 _time) external onlyOwner {
        if (_time < MIN_LOCKUP_TIME || MAX_LOCKUP_TIME < _time) revert OTSeaErrors.InvalidAmount();
        _lockupPeriod = _time;
        emit LockupPeriodUpdated(_time);
    }

    /**
     * @notice Add/remove an account from the blacklist
     * @param _account Account
     * @param _operation add (true) or remove (false) "account" to/from the blacklist
     * @dev Blacklisting an account prevents them from creating orders, trading, updating an order,
     * and other users interacting with their orders. Blacklisted users can only cancel orders and claim
     * their locked-up tokens.
     */
    function blacklistAccount(address _account, bool _operation) external onlyOwner {
        if (_account == address(0)) revert OTSeaErrors.InvalidAddress();
        if (_blacklist[_account] == _operation) revert OTSeaErrors.Unchanged();
        _blacklist[_account] = _operation;
        emit BlacklistUpdated(_account, _operation);
    }

    /**
     * @notice Initiate the creation of a buy order
     * @param _newOrder Core new order details
     * @param _whitelist List of exclusive users allowed to trade the order (optional)
     * @dev no need for nonReentrant modifier because no external calls are made
     */
    function createBuyOrder(
        NewOrder calldata _newOrder,
        address[] calldata _whitelist
    )
        external
        nonReentrant
        whenNotPaused
        whenNotBlacklisted
        availableStablecoin(_newOrder.stablecoin)
    {
        if (address(_newOrder.token) == address(0)) revert OTSeaErrors.InvalidAddress();
        uint72 orderID = _createBuyOrder(_newOrder);
        if (_whitelist.length != 0) {
            _initializeWhitelist(orderID, _whitelist);
        }
    }

    /**
     * @notice Initiate the creation of a sell order
     * @param _newOrder Core new order details
     * @param _whitelist List of exclusive users allowed to trade the order (optional)
     * @param _feeDetailsSignature Fee details signature (optional)
     */
    function createSellOrder(
        NewOrder calldata _newOrder,
        address[] calldata _whitelist,
        FeeDetailsSignature calldata _feeDetailsSignature
    )
        external
        nonReentrant
        whenNotPaused
        whenNotBlacklisted
        availableStablecoin(_newOrder.stablecoin)
    {
        if (address(_newOrder.token) == address(0)) revert OTSeaErrors.InvalidAddress();
        /// @dev retrieve the fee type to be stored against the order
        OTSeaLibrary.FeeType feeType = _retrieveFeeDetails(_feeDetailsSignature);
        uint72 orderID = _createSellOrder(_newOrder, feeType);
        if (_whitelist.length != 0) {
            _initializeWhitelist(orderID, _whitelist);
        }
    }

    /**
     * @notice Swap stablecoins for tokens (interacts with sell orders)
     * @param _token Token address
     * @param _token Token address
     * @param _trades Trades
     * @param _newOrder Core new order details
     * @param _allowLockUps Allow trades to have lock-ups (true), disallow trades to have lock-ups (false)
     * @param _expectedLockupPeriod The current lockupPeriod defined by _lockupPeriod
     * @dev _allowLockups act as a safety measure to ensure the user is comfortable with some or all trades resulting
     * in tokens being locked. _expectedLockupPeriod should match the current _lockupPeriod, this is in case the owner
     * changes the _lockupPeriod.
     */
    function swapStableForTokens(
        IERC20 _stablecoin,
        IERC20 _token,
        Trade[] calldata _trades,
        NewOrder calldata _newOrder,
        bool _allowLockUps,
        uint16 _expectedLockupPeriod
    ) external nonReentrant whenNotPaused whenNotBlacklisted availableStablecoin(_stablecoin) {
        if (_allowLockUps && _expectedLockupPeriod != _lockupPeriod)
            revert OTSeaErrors.ExpectationMismatch();
        (
            uint256 totalAmountToSwap,
            uint256 totalAmountToReceive,
            uint256 totalAmountToClaim,
            uint256 totalRevenue
        ) = _executeBuy(_stablecoin, _token, _trades, _allowLockUps);
        if (_newOrder.token == _token && _newOrder.stablecoin == _stablecoin) {
            /// @dev _newOrder.totalInput (stablecoins) is left in the contract for users to sell tokens for
            _createBuyOrder(_newOrder);
        }

        _transferRevenue(_stablecoin, _msgSender(), totalRevenue, address(_token));
        /// @dev a swap results in tokens either being locked, directly transferred to the user, or both
        if (totalAmountToClaim != 0) {
            /// @dev lock-up the (totalAmountToClaim) tokens for the user to claim after the lockup period has passed
            _lockUps[_msgSender()].push(
                LockUp(
                    address(_token),
                    uint88(block.timestamp + _lockupPeriod),
                    totalAmountToClaim,
                    0
                )
            );
        }
        if (totalAmountToReceive != 0) {
            /// @dev transfer the purchased tokens to the caller
            _token.safeTransfer(_msgSender(), totalAmountToReceive);
        }
        emit SwappedStableForTokens(
            _msgSender(),
            address(_stablecoin),
            address(_token),
            _trades,
            totalAmountToSwap,
            totalAmountToReceive,
            totalAmountToClaim
        );
    }

    /**
     * @notice Swap tokens for stablcoins (interacts with buy orders)
     * @param _token Token address
     * @param _trades Trades
     * @param _newOrder Core new order details
     * @param _feeDetailsSignature Signature containing data about msg.sender's fee type
     */
    function swapTokensForStable(
        IERC20 _stablecoin,
        IERC20 _token,
        Trade[] calldata _trades,
        NewOrder calldata _newOrder,
        FeeDetailsSignature calldata _feeDetailsSignature
    ) external nonReentrant whenNotPaused whenNotBlacklisted availableStablecoin(_stablecoin) {
        OTSeaLibrary.FeeType feeType = _retrieveFeeDetails(_feeDetailsSignature);
        (uint256 totalAmountToSwap, uint256 totalAmountToReceive) = _executeSell(
            _stablecoin,
            _token,
            _trades
        );
        if (_newOrder.token == _token && _newOrder.stablecoin == _stablecoin) {
            /// @dev create a sell order.
            _createSellOrder(_newOrder, feeType);
        }
        /// @dev transfer out stablecoins.
        uint256 revenue = _handleStablePayment(
            _stablecoin,
            address(this),
            _msgSender(),
            totalAmountToReceive,
            feeType
        );
        _transferRevenue(_stablecoin, address(this), revenue, address(_token));
        emit SwappedTokensForStable(
            _msgSender(),
            address(_stablecoin),
            address(_token),
            _trades,
            totalAmountToSwap,
            totalAmountToReceive,
            feeType
        );
    }

    /**
     * @notice Claim multiple lock-ups (supports lock-ups with different tokens)
     * @param _receiver Address to receive tokens
     * @param _claims A list of claims
     * @dev The purpose of the _receiver is in case the transfer were to fail (e.g. max wallet reached). ClaimLockUp
     * includes an amount, this is essential because a token may have a max tx limit in place wish could result
     * in a transfer failing. Therefore the user simply needs to claim in small chunks.
     * Blacklisted users can claim their lock-ups.
     */
    function claimLockUps(address _receiver, ClaimLockUp[] calldata _claims) external {
        uint256 total = _lockUps[_msgSender()].length;
        if (total == 0) revert OTSeaErrors.NotAvailable();
        uint256 length = _claims.length;
        _validateListLength(length);
        for (uint256 i; i < length; ) {
            ClaimLockUp calldata _claim = _claims[i];
            if (total <= _claim.index) revert OTSeaErrors.InvalidIndex(i);
            LockUp memory lockUp = _lockUps[_msgSender()][_claim.index];
            if (block.timestamp < lockUp.unlockAt) revert UnlockDateNotReached(i);
            uint256 remaining = lockUp.amount - lockUp.withdrawn;
            if (_claim.amount == 0 || remaining < _claim.amount)
                revert OTSeaErrors.InvalidAmountAtIndex(i);
            _lockUps[_msgSender()][_claim.index].withdrawn += _claim.amount;
            IERC20(lockUp.token).safeTransfer(_receiver, _claim.amount);
            unchecked {
                i++;
            }
        }
        emit LockUpsClaimed(_msgSender(), _receiver, _claims);
    }

    /**
     * @notice Claim multiple lock-ups (supports only lock-ups with the same tokens)
     * @param _token Token address
     * @param _receiver Address to receive tokens
     * @param _claims A list of claims
     * @dev use this function if claiming lock-ups for the same token as it is more gas efficient. The purpose of
     * the _receiver is in case the transfer were to fail (e.g. max wallet reached). ClaimLockUp
     * includes an amount, this is essential because a token may have a max tx limit in place wish could result
     * in a transfer failing. Therefore the user simply needs to claim in small chunks over multiple txs.
     * Blacklisted users can claim their lock-ups.
     */
    function claimLockUpByToken(
        IERC20 _token,
        address _receiver,
        ClaimLockUp[] calldata _claims
    ) external {
        if (address(_token) == address(0)) revert OTSeaErrors.InvalidAddress();
        uint256 total = _lockUps[_msgSender()].length;
        if (total == 0) revert OTSeaErrors.NotAvailable();
        uint256 length = _claims.length;
        _validateListLength(length);
        uint256 totalToClaim;
        for (uint256 i; i < length; ) {
            ClaimLockUp calldata _claim = _claims[i];
            if (total <= _claim.index) revert OTSeaErrors.InvalidIndex(i);
            LockUp memory lockUp = _lockUps[_msgSender()][_claim.index];
            if (lockUp.token != address(_token)) revert OTSeaErrors.InvalidAddressAtIndex(i);
            if (block.timestamp < lockUp.unlockAt) revert UnlockDateNotReached(i);
            uint256 remaining = lockUp.amount - lockUp.withdrawn;
            if (_claim.amount == 0 || remaining < _claim.amount)
                revert OTSeaErrors.InvalidAmountAtIndex(i);
            _lockUps[_msgSender()][_claim.index].withdrawn += _claim.amount;
            totalToClaim += _claim.amount;
            unchecked {
                i++;
            }
        }
        _token.safeTransfer(_receiver, totalToClaim);
        emit LockUpsClaimed(_msgSender(), _receiver, _claims);
    }

    /**
     * @notice Update the price of an order
     * @param _orderID Order ID
     * @param _expectedRemainingInput Expected remaining input
     * @param _newRemainingOutput New output value for the remaining input
     */
    function updatePrice(
        uint72 _orderID,
        uint256 _expectedRemainingInput,
        uint256 _newRemainingOutput
    ) external onlyOrderCreator(_orderID) whenNotPaused whenNotBlacklisted {
        Order storage order = _orders[_orderID];
        if (order.state != State.Open) revert OTSeaErrors.NotAvailable();
        if (_newRemainingOutput == 0) revert OTSeaErrors.InvalidAmount();
        if (order.totalInput - order.inputTransacted != _expectedRemainingInput)
            revert OTSeaErrors.ExpectationMismatch();
        uint256 newTotalOutput = order.outputTransacted + _newRemainingOutput;
        order.totalOutput = newTotalOutput;
        emit OrderPriceUpdated(_orderID, newTotalOutput);
    }

    /**
     * @notice Update an order's whitelist
     * @param _orderID Order ID
     * @param _updates Whitelist updates
     */
    function updateWhitelist(
        uint72 _orderID,
        WhitelistUpdate[] calldata _updates
    ) external override onlyOrderCreator(_orderID) whenNotPaused whenNotBlacklisted {
        if (_orders[_orderID].state != State.Open) revert OTSeaErrors.NotAvailable();
        _updateWhitelist(_orderID, _updates);
    }

    /**
     * @notice Update a sell order to enforce or remove a lock-up when traded with
     * @param _orderID Order ID
     * @param _enforce enable (true) or disable (false)
     */
    function updateOrderLockUp(
        uint72 _orderID,
        bool _enforce
    ) external onlyOrderCreator(_orderID) whenNotPaused whenNotBlacklisted {
        Order storage order = _orders[_orderID];
        if (order.state != State.Open || order.orderType == OrderType.Buy)
            revert OTSeaErrors.NotAvailable();
        if (order.withLockUp == _enforce) revert OTSeaErrors.Unchanged();
        order.withLockUp = _enforce;
        emit OrderLockUpUpdated(_orderID, _enforce);
    }

    /**
     * @notice Cancel multiple orders (supports orders with different tokens)
     * @param _orderIDs A list of order IDs to cancel
     * @dev Blacklisted users can cancel orders
     */
    function cancelOrders(uint72[] calldata _orderIDs) external nonReentrant {
        uint256 total = _orderIDs.length;
        if (total == 0 || MAX_CANCELLATIONS < total) revert OTSeaErrors.InvalidArrayLength();

        uint256 i;
        for (i; i < total; ) {
            Order storage order = _orders[_orderIDs[i]];
            if (order.creator != _msgSender()) revert OTSeaErrors.Unauthorized();
            if (order.state != State.Open) revert OTSeaErrors.NotAvailable();
            order.state = State.Cancelled;
            uint256 outstanding = order.totalInput - order.inputTransacted;
            if (order.orderType == OrderType.Buy) {
                /// @dev transfer unsold stablecoins.
                order.stablecoin.safeTransfer(order.creator, outstanding);
            } else {
                /// @dev transfer unsold tokens.
                order.token.safeTransfer(order.creator, outstanding);
            }
            unchecked {
                i++;
            }
        }

        emit CancelledOrders(_orderIDs);
    }

    /**
     * @notice Cancel multiple orders (supports only orders with the same tokens)
     * @param _token Token address
     * @param _orderIDs A list of order IDs to cancel
     * @dev use this function if cancelling orders with the same token as it is more gas efficient.
     * Blacklisted users can cancel orders
     */
    function cancelTokenOrders(IERC20 _token, uint72[] calldata _orderIDs) external nonReentrant {
        uint256 total = _orderIDs.length;
        if (total == 0 || MAX_CANCELLATIONS < total) revert OTSeaErrors.InvalidArrayLength();

        uint256 totalTokensOwed;
        uint256 i;
        for (i; i < total; ) {
            Order storage order = _orders[_orderIDs[i]];
            if (order.creator != _msgSender()) revert OTSeaErrors.Unauthorized();
            if (order.state != State.Open || order.token != _token)
                revert OTSeaErrors.NotAvailable();
            order.state = State.Cancelled;
            uint256 outstanding = order.totalInput - order.inputTransacted;
            if (order.orderType == OrderType.Buy) {
                /// @dev transfer unsold stablecoins.
                order.stablecoin.safeTransfer(order.creator, outstanding);
            } else {
                /// @dev transfer unsold tokens.
                totalTokensOwed += outstanding;
            }
            unchecked {
                i++;
            }
        }

        if (totalTokensOwed != 0) {
            _token.safeTransfer(_msgSender(), totalTokensOwed);
        }
        emit CancelledOrders(_orderIDs);
    }

    /**
     * @notice Get the total number of orders
     * @return uint72 Total orders
     */
    function getTotalOrders() external view returns (uint72) {
        return _totalOrders;
    }

    /**
     * @notice Get an order by ID
     * @param _orderID Order ID
     * @return order Order details
     */
    function getOrder(uint72 _orderID) external view returns (Order memory order) {
        _checkIDExists(_orderID);
        return _orders[_orderID];
    }

    /**
     * @notice Get a list of orders in a sequence from an order ID to another order ID
     * @param _start Start order ID
     * @param _end End order ID
     * @return orders A list of orders starting and _start and ending at _end
     */
    function getOrdersInSequence(
        uint256 _start,
        uint256 _end
    )
        external
        view
        onlyValidSequence(_start, _end, _totalOrders, DISALLOW_ZERO)
        returns (Order[] memory orders)
    {
        orders = new Order[](_end - _start + 1);
        uint256 index;
        uint256 orderId = _start;
        for (orderId; orderId <= _end; ) {
            orders[index++] = _orders[uint72(orderId)];
            unchecked {
                orderId++;
            }
        }
        return orders;
    }

    /**
     * @notice Get a list of orders by a list of order IDs
     * @param _orderIDs Order IDs
     * @return orders A list of orders with each index corresponding to _orderIDs
     */
    function getOrdersByIDs(
        uint72[] calldata _orderIDs
    ) external view returns (Order[] memory orders) {
        uint256 length = _orderIDs.length;
        _validateListLength(length);
        orders = new Order[](length);
        uint256 i;
        for (i; i < length; ) {
            _checkIDExists(_orderIDs[i]);
            orders[i] = _orders[_orderIDs[i]];
            unchecked {
                i++;
            }
        }
        return orders;
    }

    /**
     * @notice Get the lockup period
     * @return uint16 Lockup period
     */
    function getLockupPeriod() public view returns (uint16) {
        return _lockupPeriod;
    }

    /**
     * @notice Get the total lock-ups for a user
     * @param _account Account
     * @return uint256 Total lock-ups for _account
     */
    function getTotalLockUps(address _account) public view returns (uint256) {
        if (_account == address(0)) revert OTSeaErrors.InvalidAddress();
        return _lockUps[_account].length;
    }

    /**
     * @notice Get lock-ups for a user
     * @param _account Account
     * @param _indexes Indexes
     * @return lockUps Lock-up list
     */
    function getLockUps(
        address _account,
        uint256[] calldata _indexes
    ) external view returns (LockUp[] memory lockUps) {
        uint256 total = getTotalLockUps(_account);
        uint256 length = _indexes.length;
        _validateListLength(length);
        lockUps = new LockUp[](length);
        uint256 i;
        for (i; i < length; ) {
            if (total <= _indexes[i]) revert OTSeaErrors.InvalidIndex(i);
            lockUps[i] = _lockUps[_account][_indexes[i]];
            unchecked {
                i++;
            }
        }
        return lockUps;
    }

    /**
     * @notice Get fee percents
     * @return fishFee Fish fee percent
     * @return whaleFee Whale fee percent
     * @return partnerFee Partner fee percent
     */
    function getFees() external view returns (uint8 fishFee, uint8 whaleFee, uint16 partnerFee) {
        return (_fishFee, _whaleFee, _partnerFee);
    }

    /**
     * @notice Get the maximum number of trades that can be executed in a single TX
     * @return uint8 Maximum number of trades
     */
    function getMaxTrades() external view returns (uint8) {
        return _maxTrades;
    }

    /**
     * @notice Get partner details for a token
     * @param _token Token address
     * @return Partner Partner details
     */
    function getPartner(address _token) external view returns (Partner memory) {
        if (_token == address(0)) revert OTSeaErrors.InvalidAddress();
        return _partners[_token];
    }

    /**
     * @notice Check if an account is blacklisted
     * @param _account Account
     * @return bool true if blacklisted, false if not
     */
    function isAccountBlacklisted(address _account) external view returns (bool) {
        if (_account == address(0)) revert OTSeaErrors.InvalidAddress();
        return _blacklist[_account];
    }

    /**
     * @notice Check if an order is blacklisted
     * @param _orderID Order ID
     * @return bool true if blacklisted, false if not
     */
    function isOrderBlacklisted(uint72 _orderID) external view returns (bool) {
        _checkIDExists(_orderID);
        return _blacklist[_orders[_orderID].creator];
    }

    /**
     * @notice Check if an stablecoin is available
     * @param _stablecoin Stablecoin address
     * @return bool true if it is available, false if not
     */
    function isAvailableStablecoin(address _stablecoin) external view returns (bool) {
        if (_stablecoin == address(0)) revert OTSeaErrors.InvalidAddress();
        return _stablecoins[_stablecoin];
    }

    /**
     * @param _newOrder Core new order details
     * @return orderID Order ID
     */
    function _createBuyOrder(NewOrder calldata _newOrder) private returns (uint72 orderID) {
        /// @dev lock-ups can only be used on sell orders
        if (_newOrder.withLockUp) revert LockUpNotAllowed();
        if (_newOrder.totalInput == 0 || _newOrder.totalOutput == 0)
            revert OTSeaErrors.InvalidAmount();
        orderID = ++_totalOrders;
        uint256 totalInput = _transferInTokens(_newOrder.stablecoin, _newOrder.totalInput);

        /// @dev stablecoin transfer fee should be 0
        if (totalInput != _newOrder.totalInput) {
            revert OTSeaErrors.NotAvailable();
        }

        _orders[orderID] = Order({
            creator: _msgSender(),
            orderType: OrderType.Buy,
            state: State.Open,
            /// @dev feeType is set to the default FeeType (fish) because it is ignored for buy orders
            feeType: OTSeaLibrary.FeeType.Fish,
            isAON: _newOrder.isAON,
            isHidden: _newOrder.isHidden,
            withLockUp: false,
            stablecoin: _newOrder.stablecoin,
            token: _newOrder.token,
            totalInput: totalInput,
            inputTransacted: 0,
            totalOutput: _newOrder.totalOutput,
            outputTransacted: 0
        });
        emit BuyOrderCreated(
            orderID,
            _msgSender(),
            _newOrder,
            IERC20Metadata(address(_newOrder.stablecoin)).decimals(),
            IERC20Metadata(address(_newOrder.token)).decimals()
        );
    }

    /**
     * @param _newOrder Core new order details
     * @param _feeType Fee type
     * @return orderID Order ID
     */
    function _createSellOrder(
        NewOrder calldata _newOrder,
        OTSeaLibrary.FeeType _feeType
    ) private returns (uint72 orderID) {
        if (_newOrder.totalInput == 0 || _newOrder.totalOutput == 0)
            revert OTSeaErrors.InvalidAmount();
        orderID = ++_totalOrders;
        uint256 totalInput = _transferInTokens(_newOrder.token, _newOrder.totalInput);
        /// @dev if the tokens transferred does not match the amount, then the total stablecoins should be adjusted to account for taxes.
        uint256 totalOutput = totalInput == _newOrder.totalInput
            ? _newOrder.totalOutput
            : (_newOrder.totalOutput * totalInput) / _newOrder.totalInput;
        _orders[orderID] = Order({
            creator: _msgSender(),
            orderType: OrderType.Sell,
            state: State.Open,
            feeType: _feeType,
            isAON: _newOrder.isAON,
            isHidden: _newOrder.isHidden,
            withLockUp: _newOrder.withLockUp,
            stablecoin: _newOrder.stablecoin,
            token: _newOrder.token,
            totalInput: totalInput,
            inputTransacted: 0,
            totalOutput: totalOutput,
            outputTransacted: 0
        });
        emit SellOrderCreated(
            orderID,
            _msgSender(),
            _newOrder,
            totalInput,
            totalOutput,
            _feeType,
            IERC20Metadata(address(_newOrder.stablecoin)).decimals(),
            IERC20Metadata(address(_newOrder.token)).decimals()
        );
    }

    /**
     * @param _stablecoin Stablecoin to buy
     * @param _token Token to buy
     * @param _trades Trades to execute
     * @param _allowLockUps Allow trades to have lock-ups (true), disallow trades to have lock-ups (false)
     * @return totalAmountToSwap Total stablecoins to swap
     * @return totalAmountToReceive Total tokens to receive
     * @return totalAmountToClaim Total tokens to claim after the _lockupPeriod
     * @return totalRevenue Total revenue
     */
    function _executeBuy(
        IERC20 _stablecoin,
        IERC20 _token,
        Trade[] calldata _trades,
        bool _allowLockUps
    )
        private
        returns (
            uint256 totalAmountToSwap,
            uint256 totalAmountToReceive,
            uint256 totalAmountToClaim,
            uint256 totalRevenue
        )
    {
        uint256 total = _trades.length;
        if (total == 0 || _maxTrades < total) revert OTSeaErrors.InvalidArrayLength();
        bool isLockUpOverrideEnabled = _partners[address(_token)].isLockUpOverrideEnabled;
        if (isLockUpOverrideEnabled && !_allowLockUps) revert OTSeaErrors.ExpectationMismatch();
        uint256 i;
        for (i; i < total; ) {
            Trade calldata trade = _trades[i];
            Order storage order = _orders[trade.orderID];
            if (_blacklist[order.creator]) revert OrderBlacklisted();
            /// @dev orders should only be sell orders (which means there is no need to check if the order ID exists).
            if (order.orderType == OrderType.Buy) revert InvalidTradeOrderType();
            uint256 amountToReceive = _executeTrade(_stablecoin, _token, trade);
            totalRevenue += _handleStablePayment(
                _stablecoin,
                _msgSender(),
                order.creator,
                trade.amountToSwap,
                order.feeType
            );

            /// @dev total tokens to send to msg.sender.
            totalAmountToSwap += trade.amountToSwap;
            if (isLockUpOverrideEnabled || order.withLockUp) {
                if (!_allowLockUps) revert OTSeaErrors.ExpectationMismatch();
                totalAmountToClaim += amountToReceive;
            } else {
                totalAmountToReceive += amountToReceive;
            }
            unchecked {
                i++;
            }
        }
        return (totalAmountToSwap, totalAmountToReceive, totalAmountToClaim, totalRevenue);
    }

    /**
     * @param _stablecoin Stablecoin to sell
     * @param _token Token to sell
     * @param _trades Trades to execute
     * @return totalAmountToSwap Total tokens to swap
     * @return totalAmountToReceive Total stablecoins to receive
     */
    function _executeSell(
        IERC20 _stablecoin,
        IERC20 _token,
        Trade[] calldata _trades
    ) private returns (uint256 totalAmountToSwap, uint256 totalAmountToReceive) {
        uint256 total = _trades.length;
        if (total == 0 || _maxTrades < total) revert OTSeaErrors.InvalidArrayLength();
        uint256 i;
        for (i; i < total; ) {
            Trade calldata trade = _trades[i];
            _checkIDExists(trade.orderID);
            Order storage order = _orders[trade.orderID];
            if (_blacklist[order.creator]) revert OrderBlacklisted();
            /// @dev orders should only be buy orders.
            if (order.orderType == OrderType.Sell) revert InvalidTradeOrderType();
            uint256 amountToReceive = _executeTrade(_stablecoin, _token, trade);
            _token.safeTransferFrom(_msgSender(), order.creator, trade.amountToSwap);
            /// @dev total stablecoins swapped.
            totalAmountToSwap += trade.amountToSwap;
            /// @dev total tokens to send to msg.sender.
            totalAmountToReceive += amountToReceive;
            unchecked {
                i++;
            }
        }
        return (totalAmountToSwap, totalAmountToReceive);
    }

    /**
     * @param _stablecoin Stablecoin to trade
     * @param _token Token to trade
     * @param _trade Trade to execute
     * @return amountToReceive Amount to receive
     * @dev a generic function used both when buying and selling
     */
    function _executeTrade(
        IERC20 _stablecoin,
        IERC20 _token,
        Trade calldata _trade
    ) private returns (uint256 amountToReceive) {
        Order storage order = _orders[_trade.orderID];
        if (order.state != State.Open || order.token != _token || order.stablecoin != _stablecoin)
            revert OTSeaErrors.NotAvailable();
        if (
            _getTotalWhitelisted(_trade.orderID) != 0 &&
            !_checkIsWhitelisted(_msgSender(), _trade.orderID)
        ) revert OTSeaErrors.Unauthorized();
        if (_trade.amountToSwap == 0) revert OTSeaErrors.InvalidAmount();
        /// @dev owner of order can change price therefore we much check the trade totalOutput matches the on-chain value
        if (order.totalOutput != _trade.totalOutput) revert OTSeaErrors.ExpectationMismatch();
        uint256 remainingInput = order.totalInput - order.inputTransacted;
        uint256 remainingOutput = order.totalOutput - order.outputTransacted;
        if (
            order.isAON
                ? _trade.amountToSwap != remainingOutput
                : remainingOutput < _trade.amountToSwap
        ) revert OTSeaErrors.InvalidPurchase();
        if (_trade.amountToSwap == remainingOutput) {
            amountToReceive = remainingInput;
            order.state = State.Fulfilled;
        } else {
            amountToReceive = (remainingInput * _trade.amountToSwap) / remainingOutput;
        }
        order.inputTransacted += amountToReceive;
        order.outputTransacted += _trade.amountToSwap;
        emit Traded(_trade.orderID, _msgSender(), _trade.amountToSwap, amountToReceive);
    }

    /**
     * @param _stablecoin Stablecoin IERC20
     * @param _from Account to send stablecoins from
     * @param _to Account to send stablecoins to
     * @param _amount Amount of stablecoins to send to _account
     * @param _feeType Fee type of _account
     * @return revenue Amount of stablecoins revenue
     * @dev a function to calculate the revenue and transfer the remaining stablecoins to an account
     */
    function _handleStablePayment(
        IERC20 _stablecoin,
        address _from,
        address _to,
        uint256 _amount,
        OTSeaLibrary.FeeType _feeType
    ) private returns (uint256 revenue) {
        revenue =
            (_amount * (_feeType == OTSeaLibrary.FeeType.Fish ? _fishFee : _whaleFee)) /
            OTSeaLibrary.PERCENT_DENOMINATOR;

        _safeTransferERC20(_stablecoin, _from, _to, _amount - revenue);
    }

    /**
     * @param _stablecoin Stablecoin IERC20
     * @param _from Account to send revenue from
     * @param _revenue Revenue
     * @param _token Token
     * @dev Pays partner fee (stablecoins) and transfers the remaining revenue to the revenue distributor
     */
    function _transferRevenue(IERC20 _stablecoin, address _from, uint256 _revenue, address _token) private {
        address partner = _partners[_token].account;
        if (partner != address(0)) {
            uint256 fee = (_revenue * _partnerFee) / OTSeaLibrary.PERCENT_DENOMINATOR;
            _revenue -= fee;
             _safeTransferERC20(_stablecoin, _from, partner, fee);
            emit PartnerFeePaid(_token, address(_stablecoin), partner, fee);
        }

        _safeTransferERC20(_stablecoin, _from, _revenueDistributor, _revenue);
        emit RevenueTransferred(address(_stablecoin), _revenue);
    }

    /// @param _orderID Order ID
    function _checkIDExists(uint72 _orderID) internal view override {
        if (_orderID == 0 || _totalOrders < _orderID) revert OrderNotFound(_orderID);
    }

    /**
     * @param _feeDetailsSignature Fee details signature
     * @return feeType Fee type
     * @dev verifies the signature (if present) and returns the fee type
     */
    function _retrieveFeeDetails(
        FeeDetailsSignature calldata _feeDetailsSignature
    ) private view returns (OTSeaLibrary.FeeType feeType) {
        /// @dev if no signature is present then the user is a fish
        if (_feeDetailsSignature.signature.length == 0) {
            return feeType;
        }
        /// @dev reconstruct data that was signed off-chain
        bytes memory data = abi.encode(
            FEE_DETAILS_SIGNATURE_TYPE,
            _msgSender(),
            _feeDetailsSignature.expiresAt,
            _feeDetailsSignature.feeType
        );
        /// @dev check the signature was signed by the signer
        _checkSignature(data, _feeDetailsSignature.signature, _feeDetailsSignature.expiresAt);
        return _feeDetailsSignature.feeType;
    }

    /// @param _orderID Order ID
    function _checkCallerIsOrderCreator(uint72 _orderID) private view {
        /**
         * @dev it is more efficient calling _checkIDExists(_orderID) here than in the modifier because using it
         * in a modifier would duplicate the same code across all functions where it is used.
         */
        _checkIDExists(_orderID);
        if (_orders[_orderID].creator != _msgSender()) revert OTSeaErrors.Unauthorized();
    }

    function _checkCallerIsNotBlacklisted() private view {
        if (_blacklist[_msgSender()]) revert OTSeaErrors.Unauthorized();
    }

    /// @param _stablecoin Stablecoin address
    function _checkIsAvailableStablecoin(address _stablecoin) private view {
        if (!_stablecoins[_stablecoin]) revert OTSeaErrors.NotAvailable();
    }

    /**
     * @param _token Token to transfer into the contract from msg.sender
     * @param _amount Amount of _token to transfer
     * @return uint256 Actual amount transferred into the contract
     * @dev This function exists due to _token potentially having taxes
     */
    function _transferInTokens(IERC20 _token, uint256 _amount) internal returns (uint256) {
        uint256 balanceBefore = _token.balanceOf(address(this));
        _token.safeTransferFrom(_msgSender(), address(this), _amount);
        return _token.balanceOf(address(this)) - balanceBefore;
    }

    /**
     * @param _token Token to transfer
     * @param _from Account to send stablecoins from
     * @param _to Account to send stablecoins to
     * @param _amount Amount of _token to transfer
     * @dev This function transfer ERC20
     */
    function _safeTransferERC20(IERC20 _token, address _from, address _to, uint256 _amount) private {
        if (_from == address(this)) {
            _token.safeTransfer(_to, _amount);
        } else {
            _token.safeTransferFrom(_from, _to, _amount);
        }
    }
}