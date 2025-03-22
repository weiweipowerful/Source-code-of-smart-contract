//SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import {
    ERC4626Upgradeable,
    IERC20,
    IERC20Metadata
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    VaultFees, Strategy, IConcreteMultiStrategyVault, Allocation
} from "../interfaces/IConcreteMultiStrategyVault.sol";
import {Errors} from "../interfaces/Errors.sol";
import {IStrategy, ReturnedRewards} from "../interfaces/IStrategy.sol";
import {IWithdrawalQueue} from "../interfaces/IWithdrawalQueue.sol";
import {IParkingLot} from "../interfaces/IParkingLot.sol";
import {MultiStrategyVaultHelper} from "../libraries/MultiStrategyVaultHelper.sol";
import {MAX_BASIS_POINTS, PRECISION, DUST, SECONDS_PER_YEAR} from "../utils/Constants.sol";
import {WithdrawalQueueHelper} from "../libraries/WithdrawalQueueHelper.sol";
import {VaultActionsHelper} from "../libraries/VaultActions.sol";
import {RewardsHelper} from "../libraries/RewardsHelper.sol";
import {StrategyHelper} from "../libraries/StrategyHelper.sol";
import {FeesHelper} from "../libraries/FeesHelper.sol";
import {TokenHelper} from "@blueprint-finance/hub-and-spokes-libraries/src/libraries/TokenHelper.sol";

/**
 * @title ConcreteMultiStrategyVault
 * @author Concrete
 * @notice An ERC4626 compliant vault that manages multiple yield generating strategies
 * @dev This vault:
 *      - Implements ERC4626 standard for tokenized vaults
 *      - Manages multiple yield strategies simultaneously
 *      - Handles fee collection and distribution
 *      - Supports emergency pausing
 *      - Provides withdrawal queueing mechanism
 */
contract ConcreteMultiStrategyVault is
    ERC4626Upgradeable,
    Errors,
    ReentrancyGuard,
    PausableUpgradeable,
    OwnableUpgradeable,
    IConcreteMultiStrategyVault
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public firstDeposit = 0;
    /// @dev Public variable storing the address of the protectStrategy contract.
    address public protectStrategy;

    /// @dev Internal variable to store the number of decimals the vault's shares will have.
    uint8 private _decimals;
    /// @notice The offset applied to decimals to prevent inflation attacks.
    /// @dev Public constant representing the offset applied to the vault's share decimals.
    uint8 public constant decimalOffset = 9;
    /// @notice The highest value of share price recorded, used for performance fee calculation.
    /// @dev Public variable to store the high water mark for performance fee calculation.
    uint256 public highWaterMark;
    /// @notice The maximum amount of assets that can be deposited into the vault.
    /// @dev Public variable to store the deposit limit of the vault.
    uint256 public depositLimit;
    /// @notice The timestamp at which the fees were last updated.
    /// @dev Public variable to store the last update time of the fees.
    uint256 public feesUpdatedAt;
    /// @notice The recipient address for any fees collected by the vault.
    /// @dev Public variable to store the address of the fee recipient.
    address public feeRecipient;
    /// @notice Indicates if the vault is in idle mode, where deposits are not passed to strategies.
    /// @dev Public boolean indicating if the vault is idle.
    bool public vaultIdle;

    /// @notice Indicates if the vault withdrawals are paused
    /// @dev Public boolean indicating if the vault withdrawals are paused
    bool public withdrawalsPaused;

    /// @notice The array of strategies that the vault can interact with.
    /// @dev Public array storing the strategies associated with the vault.
    Strategy[] internal strategies;
    /// @notice The fee structure of the vault.
    /// @dev Public variable storing the fees associated with the vault.
    VaultFees private fees;

    IWithdrawalQueue public withdrawalQueue;

    IParkingLot public parkingLot;
    uint256 public minQueueRequest;

    //Rewards Management
    // Array to store reward addresses
    address[] private rewardAddresses;

    // Mapping to get the index of each reward address
    mapping(address => uint256) public rewardIndex;

    // Mapping to store the reward index for each user and reward address
    mapping(address => mapping(address => uint256)) public userRewardIndex;

    // Mapping to store the total rewards claimed by user for each reward address
    mapping(address => mapping(address => uint256)) public totalRewardsClaimed;

    event Initialized(address indexed vaultName, address indexed underlyingAsset);

    event RequestedFunds(address indexed protectStrategy, uint256 amount);

    event RewardsHarvested();

    event MinimunQueueRequestUpdated(uint256 _oldMinQueueRequest, uint256 _newMinQueueRequest);
    /// @notice Modifier to restrict access to only the designated protection strategy account.
    /// @dev Reverts the transaction if the sender is not the protection strategy account.

    modifier onlyProtect() {
        if (protectStrategy != _msgSender()) {
            revert ProtectUnauthorizedAccount(_msgSender());
        }
        _;
    }

    ///@notice Modifier that allows protocol to take fees
    modifier takeFees() {
        if (!paused()) {
            uint256 totalFee = accruedProtocolFee() + accruedPerformanceFee();
            uint256 shareValue = convertToAssets(1e18);
            uint256 _totalAssets = totalAssets();

            if (shareValue > highWaterMark) highWaterMark = shareValue;

            if (totalFee > 0 && _totalAssets > 0) {
                uint256 supply = totalSupply();
                uint256 feeInShare =
                    supply == 0 ? totalFee : totalFee.mulDiv(supply, _totalAssets - totalFee, Math.Rounding.Floor);
                _mint(feeRecipient, feeInShare);
                feesUpdatedAt = block.timestamp;
            }
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the vault with its core parameters
     * @dev Sets up the vault's initial state including strategies, fees, and limits
     * @param baseAsset_ The underlying asset token address
     * @param shareName_ The name for the vault's share token
     * @param shareSymbol_ The symbol for the vault's share token
     * @param strategies_ Array of initial strategies
     * @param feeRecipient_ Address to receive collected fees
     * @param fees_ Initial fee structure
     * @param depositLimit_ Maximum deposit amount allowed
     * @param owner_ Address of the vault owner
     */
    // slither didn't detect the nonReentrant modifier
    // slither-disable-next-line reentrancy-no-eth,reentrancy-benign,calls-loop,costly-loop
    function initialize(
        IERC20 baseAsset_,
        string memory shareName_,
        string memory shareSymbol_,
        Strategy[] memory strategies_,
        address feeRecipient_,
        VaultFees memory fees_,
        uint256 depositLimit_,
        address owner_
    ) external initializer nonReentrant {
        __Pausable_init();
        __ERC4626_init(baseAsset_);
        __ERC20_init(shareName_, shareSymbol_);
        __Ownable_init(owner_);

        if (address(baseAsset_) == address(0)) revert InvalidAssetAddress();

        (protectStrategy, _decimals) = MultiStrategyVaultHelper.validateVaultParameters(
            baseAsset_, decimalOffset, strategies_, protectStrategy, strategies, fees_, fees
        );
        if (feeRecipient_ == address(0)) {
            revert InvalidFeeRecipient();
        }
        feeRecipient = feeRecipient_;

        highWaterMark = 1e9; // Set the initial high water mark for performance fee calculation.
        depositLimit = depositLimit_;

        // By default, the vault is not idle. It can be set to idle mode using toggleVaultIdle(true).
        vaultIdle = false;
        withdrawalsPaused = false;

        emit Initialized(address(this), address(baseAsset_));
    }

    /**
     * @notice Returns the decimals of the vault's shares.
     * @dev Overrides the decimals function in inherited contracts to return the custom vault decimals.
     * @return The decimals of the vault's shares.
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Toggles the withdrawals paused state
     * @dev Can only be called by the owner. Emits a `WithdrawalPausedToggled` event.
     * @param withdrawalsPaused_ The new state of the withdrawals paused state
     */
    function toggleWithdrawalsPaused(bool withdrawalsPaused_) public onlyOwner {
        withdrawalsPaused = withdrawalsPaused_;
        emit WithdrawalPausedToggled(withdrawalsPaused, withdrawalsPaused_);
    }

    /**
     * @notice Pauses all deposit and withdrawal functions.
     * @dev Can only be called by the owner. Emits a `Paused` event.
     */
    function pause() public takeFees onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the vault, allowing deposit and withdrawal functions.
     * @dev Can only be called by the owner. Emits an `Unpaused` event.
     */
    function unpause() public takeFees onlyOwner {
        _unpause();
        feesUpdatedAt = block.timestamp;
    }

    // ========== PUBLIC ENTRY DEPOSIT/WITHDRAW =============
    /**
     * @notice Allows a user to deposit assets into the vault in exchange for shares.
     * @dev This function is a wrapper that calls the main deposit function with the sender's address as the receiver.
     * @param assets_ The amount of assets to deposit.
     * @return The number of shares minted for the deposited assets.
     */
    function deposit(uint256 assets_) external returns (uint256) {
        return deposit(assets_, msg.sender);
    }

    /**
     * @notice Deposits assets into the vault on behalf of a receiver, in exchange for shares.
     * @dev Calculates the deposit fee, mints shares to the fee recipient and the receiver, then transfers the assets from the sender.
     *      If the vault is not idle, it also allocates the assets into the strategies according to their allocation.
     * @param assets_ The amount of assets to deposit.
     * @param receiver_ The address for which the shares will be minted.
     * @return shares The number of shares minted for the deposited assets.
     */
    // We're not using the timestamp for comparisions
    // slither-disable-next-line timestamp
    function deposit(uint256 assets_, address receiver_)
        public
        override
        nonReentrant
        whenNotPaused
        takeFees
        returns (uint256 shares)
    {
        _validateAndUpdateDepositTimestamps(receiver_);

        if (totalAssets() + assets_ > depositLimit) {
            revert MaxError();
        }

        // Calculate shares based on whether sender is fee recipient
        if (msg.sender == feeRecipient) {
            shares = _convertToShares(assets_, Math.Rounding.Floor);
        } else {
            // Calculate the fee in shares
            uint256 feeShares = _convertToShares(
                assets_.mulDiv(uint256(fees.depositFee), MAX_BASIS_POINTS, Math.Rounding.Ceil), Math.Rounding.Ceil
            );

            // Calculate the net shares to mint for the deposited assets
            shares = _convertToShares(assets_, Math.Rounding.Floor) - feeShares;

            // Mint fee shares to fee recipient
            if (feeShares > 0) _mint(feeRecipient, feeShares);
        }

        if (shares <= DUST) revert ZeroAmount();

        _mint(receiver_, shares);
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets_);

        // Handle strategy allocation if vault is not idle
        if (!vaultIdle) {
            StrategyHelper.depositIntoStrategies(strategies, assets_, address(this), true);
        }
        emit Deposit(msg.sender, receiver_, assets_, shares);
    }

    /**
     * @notice Allows a user to mint shares in exchange for assets.
     * @dev This function is a wrapper that calls the main mint function with the sender's address as the receiver.
     * @param shares_ The number of shares to mint.
     * @return The amount of assets deposited in exchange for the minted shares.
     */
    function mint(uint256 shares_) external returns (uint256) {
        return mint(shares_, msg.sender);
    }

    /**
     * @notice Mints shares on behalf of a receiver, in exchange for assets.
     * @dev Calculates the deposit fee in shares, mints shares to the fee recipient and the receiver, then transfers the assets from the sender.
     *      If the vault is not idle, it also allocates the assets into the strategies according to their allocation.
     * @param shares_ The number of shares to mint.
     * @param receiver_ The address for which the shares will be minted.
     * @return assets The amount of assets deposited in exchange for the minted shares.
     */
    // We're not using the timestamp for comparisions
    // slither-disable-next-line timestamp
    function mint(uint256 shares_, address receiver_)
        public
        override
        nonReentrant
        whenNotPaused
        takeFees
        returns (uint256 assets)
    {
        _validateAndUpdateDepositTimestamps(receiver_);

        if (shares_ <= DUST) revert ZeroAmount();

        // Calculate the deposit fee in shares
        uint256 depositFee = uint256(fees.depositFee);
        uint256 feeShares =
            shares_.mulDiv(MAX_BASIS_POINTS, MAX_BASIS_POINTS - depositFee, Math.Rounding.Ceil) - shares_;

        // Calculate the total assets required for the minted shares, including fees
        assets = _convertToAssets(shares_ + feeShares, Math.Rounding.Ceil);

        if (totalAssets() + assets > depositLimit) revert MaxError();

        if (assets > maxMint(receiver_)) revert MaxError();

        // Mint shares to fee recipient and receiver
        if (feeShares > 0) _mint(feeRecipient, feeShares);
        _mint(receiver_, shares_);

        // Transfer the assets from the sender to the vault
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        // If the vault is not idle, allocate the assets into strategies
        if (!vaultIdle) {
            StrategyHelper.depositIntoStrategies(strategies, assets, address(this), true);
        }
        emit Deposit(msg.sender, receiver_, assets, shares_);
    }

    /**
     * @notice Redeems shares for the caller and sends the assets to the caller.
     * @dev This is a convenience function that calls the main redeem function with the caller as both receiver and owner.
     * @param shares_ The number of shares to redeem.
     * @return assets The amount of assets returned in exchange for the redeemed shares.
     */
    function redeem(uint256 shares_) external returns (uint256) {
        return redeem(shares_, msg.sender, msg.sender);
    }

    /**
     * @notice Redeems shares on behalf of an owner and sends the assets to a receiver.
     * @dev Redeems the specified amount of shares from the owner's balance, deducts the withdrawal fee in shares, burns the shares, and sends the assets to the receiver.
     *      If the caller is not the owner, it requires approval.
     * @param shares_ The number of shares to redeem.
     * @param receiver_ The address to receive the assets.
     * @param owner_ The owner of the shares being redeemed.
     * @return assets The amount of assets returned in exchange for the redeemed shares.
     */
    function redeem(uint256 shares_, address receiver_, address owner_)
        public
        override
        nonReentrant
        whenNotPaused
        takeFees
        returns (uint256 assets)
    {
        VaultActionsHelper.validateRedeemParams(receiver_, shares_, maxRedeem(owner_));

        uint256 feeShares = msg.sender != feeRecipient
            ? shares_.mulDiv(uint256(fees.withdrawalFee), MAX_BASIS_POINTS, Math.Rounding.Ceil)
            : 0;

        assets = _convertToAssets(shares_ - feeShares, Math.Rounding.Floor);

        _withdraw(assets, receiver_, owner_, shares_, feeShares);
    }

    /**
     * @notice Withdraws a specified amount of assets for the caller.
     * @dev This is a convenience function that calls the main withdraw function with the caller as both receiver and owner.
     * @param assets_ The amount of assets to withdraw.
     * @return shares The number of shares burned in exchange for the withdrawn assets.
     */
    function withdraw(uint256 assets_) external returns (uint256) {
        return withdraw(assets_, msg.sender, msg.sender);
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        // Get the raw max withdrawal amount
        uint256 rawMaxWithdraw = _convertToAssets(balanceOf(owner), Math.Rounding.Floor);

        // Calculate pending fees
        uint256 pendingFees = accruedProtocolFee();

        // Return max withdraw minus pending fees
        return rawMaxWithdraw.mulDiv(MAX_BASIS_POINTS - fees.withdrawalFee, MAX_BASIS_POINTS, Math.Rounding.Floor)
            - pendingFees;
    }

    /**
     * @notice Withdraws a specified amount of assets on behalf of an owner and sends them to a receiver.
     * @dev Calculates the number of shares equivalent to the assets requested, deducts the withdrawal fee in shares, burns the shares, and sends the assets to the receiver.
     *      If the caller is not the owner, it requires approval.
     * @param assets_ The amount of assets to withdraw.
     * @param receiver_ The address to receive the withdrawn assets.
     * @param owner_ The owner of the shares equivalent to the assets being withdrawn.
     * @return shares The number of shares burned in exchange for the withdrawn assets.
     */
    // We're not using the timestamp for comparisions
    // slither-disable-next-line timestamp
    function withdraw(uint256 assets_, address receiver_, address owner_)
        public
        override
        nonReentrant
        whenNotPaused
        takeFees
        returns (uint256 shares)
    {
        if (receiver_ == address(0)) revert InvalidRecipient();
        if (assets_ > maxWithdraw(owner_)) revert MaxError();
        shares = _convertToShares(assets_, Math.Rounding.Ceil);
        if (shares <= DUST) revert ZeroAmount();

        // If msg.sender is the withdrawal queue, go straght to the actual withdrawal
        uint256 withdrawalFee = uint256(fees.withdrawalFee);
        uint256 feeShares = msg.sender != feeRecipient
            ? shares.mulDiv(MAX_BASIS_POINTS, MAX_BASIS_POINTS - withdrawalFee, Math.Rounding.Ceil) - shares
            : 0;
        shares += feeShares;

        _withdraw(assets_, receiver_, owner_, shares, feeShares);
    }

    /**
     * @notice Consumes allowance, burn shares, mint fees and transfer assets to receiver
     * @dev internal function for redeem and withdraw
     * @param assets_ The amount of assets to withdraw.
     * @param receiver_ The address to receive the withdrawn assets.
     * @param owner_ The owner of the shares equivalent to the assets being withdrawn.
     * @param shares The address to receive the withdrawn assets.
     * @param feeShares The owner of the shares equivalent to the assets being withdrawn.
     */
    // We're not using the timestamp for comparisions
    // slither-disable-next-line timestamp
    function _withdraw(uint256 assets_, address receiver_, address owner_, uint256 shares, uint256 feeShares) private {
        if (withdrawalsPaused) revert WithdrawalsPaused();
        if (msg.sender != owner_) {
            _approve(owner_, msg.sender, allowance(owner_, msg.sender) - shares);
        }
        _burn(owner_, shares);
        if (feeShares > 0) _mint(feeRecipient, feeShares);
        uint256 availableAssetsForWithdrawal = getAvailableAssetsForWithdrawal();
        WithdrawalQueueHelper.processWithdrawal(
            assets_,
            receiver_,
            availableAssetsForWithdrawal,
            asset(),
            address(withdrawalQueue),
            minQueueRequest,
            strategies,
            parkingLot
        );
        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);
    }

    /**
     * @notice Prepares and executes the withdrawal process for a specific withdrawal request.
     * @dev Calls the prepareWithdrawal function to obtain withdrawal details such as recipient address, withdrawal amount, and updated available assets.
     * @dev Compares the original available assets with the updated available assets to determine if funds need to be withdrawn from the strategy.
     * @dev If the available assets have changed, calls the _withdrawStrategyFunds function to withdraw funds from the strategy and transfer them to the recipient.
     * @param _requestId The identifier of the withdrawal request.
     * @param avaliableAssets The amount of available assets for withdrawal.
     * @return The new available assets after processing the withdrawal.
     */
    //we control the external call
    //slither-disable-next-line calls-loop,naming-convention
    function claimWithdrawal(uint256 _requestId, uint256 avaliableAssets) private returns (uint256) {
        return WithdrawalQueueHelper.claimWithdrawal(
            _requestId, avaliableAssets, withdrawalQueue, asset(), strategies, parkingLot
        );
    }

    function getRewardTokens() public view returns (address[] memory) {
        return rewardAddresses;
    }

    function getAvailableAssetsForWithdrawal() public view returns (uint256) {
        return WithdrawalQueueHelper.getAvailableAssetsForWithdrawal(asset(), strategies);
    }

    /**
     * @notice Updates the user rewards to the current reward index.
     * @dev Calculates the rewards to be transferred to the user based on the difference between the current and previous reward indexes.
     * @param userAddress The address of the user to update rewards for.
     */
    //slither-disable-next-line unused-return,calls-loop,reentrancy-no-eth
    function getUserRewards(address userAddress) external view returns (ReturnedRewards[] memory) {
        return RewardsHelper.getUserRewards(
            balanceOf(userAddress), userAddress, rewardAddresses, rewardIndex, userRewardIndex
        );
    }

    // function to return all the rewards claimed by a user for all the reward tokens in the vault
    function getTotalRewardsClaimed(address userAddress) external view returns (ReturnedRewards[] memory) {
        return RewardsHelper.getTotalRewardsClaimed(rewardAddresses, totalRewardsClaimed, userAddress);
    }

    // ================= ACCOUNTING =====================
    /**
     * @notice Calculates the total assets under management in the vault, including those allocated to strategies.
     * @dev Sums the balance of the vault's asset held directly and the assets managed by each strategy.
     * @return total The total assets under management in the vault.
     */
    function totalAssets() public view override returns (uint256 total) {
        total = VaultActionsHelper.getTotalAssets(IERC20(asset()).balanceOf(address(this)), strategies, withdrawalQueue);
    }

    /**
     * @notice Provides a preview of the number of shares that would be minted for a given deposit amount, after fees.
     * @dev Calculates the deposit fee and subtracts it from the deposit amount to determine the net amount for share conversion.
     * @param assets_ The amount of assets to be deposited.
     * @return The number of shares that would be minted for the given deposit amount.
     */
    function previewDeposit(uint256 assets_) public view override returns (uint256) {
        // Calculate gross shares first
        uint256 grossShares = _convertToShares(assets_, Math.Rounding.Floor);

        // Calculate fee shares using same formula and rounding as deposit
        uint256 feeShares = msg.sender != feeRecipient
            ? _convertToShares(
                assets_.mulDiv(uint256(fees.depositFee), MAX_BASIS_POINTS, Math.Rounding.Ceil), Math.Rounding.Ceil
            )
            : 0;

        // Return net shares
        return grossShares - feeShares;
    }

    /**
     * @notice Provides a preview of the amount of assets required to mint a specific number of shares, after accounting for deposit fees.
     * @dev Adds the deposit fee to the share amount to determine the gross amount for asset conversion.
     * @param shares_ The number of shares to be minted.
     * @return The amount of assets required to mint the specified number of shares.
     */
    function previewMint(uint256 shares_) public view override returns (uint256) {
        uint256 grossShares = shares_.mulDiv(MAX_BASIS_POINTS, MAX_BASIS_POINTS - fees.depositFee, Math.Rounding.Floor);
        return _convertToAssets(grossShares, Math.Rounding.Floor);
    }

    /**
     * @notice Provides a preview of the number of shares that would be burned for a given withdrawal amount, after fees.
     * @dev Calculates the withdrawal fee and adds it to the share amount to determine the gross shares for asset conversion.
     * @param assets_ The amount of assets to be withdrawn.
     * @return shares The number of shares that would be burned for the given withdrawal amount.
     */
    function previewWithdraw(uint256 assets_) public view override returns (uint256 shares) {
        shares = _convertToShares(assets_, Math.Rounding.Ceil);
        shares = msg.sender != feeRecipient
            ? shares.mulDiv(MAX_BASIS_POINTS, MAX_BASIS_POINTS - fees.withdrawalFee, Math.Rounding.Floor)
            : shares;
    }

    /**
     * @notice Provides a preview of the amount of assets that would be redeemed for a specific number of shares, after withdrawal fees.
     * @dev Subtracts the withdrawal fee from the share amount to determine the net shares for asset conversion.
     * @param shares_ The number of shares to be redeemed.
     * @return The amount of assets that would be redeemed for the specified number of shares.
     */
    function previewRedeem(uint256 shares_) public view override returns (uint256) {
        if (msg.sender == feeRecipient) {
            // Fee recipient gets exact conversion
            return _convertToAssets(shares_, Math.Rounding.Floor);
        }

        uint256 feeShares = shares_.mulDiv(uint256(fees.withdrawalFee), MAX_BASIS_POINTS, Math.Rounding.Ceil);
        return _convertToAssets(shares_ - feeShares, Math.Rounding.Floor);
    }

    /**
     * @notice Calculates the maximum amount of assets that can be minted, considering the deposit limit and current total assets.
     * @dev Returns zero if the vault is paused or if the total assets are equal to or exceed the deposit limit.
     * @return The maximum amount of assets that can be minted.
     */
    //We're not using the timestamp for comparisions
    //slither-disable-next-line timestamp
    function maxMint(address) public view override returns (uint256) {
        return (paused() || totalAssets() >= depositLimit) ? 0 : depositLimit - totalAssets();
    }

    /**
     * @notice Converts an amount of assets to the equivalent amount of shares, considering the current share price and applying the specified rounding.
     * @dev Utilizes the total supply and total assets to calculate the share price for conversion.
     * @param assets The amount of assets to convert to shares.
     * @param rounding The rounding direction to use for the conversion.
     * @return shares The equivalent amount of shares for the given assets.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256 shares) {
        shares = assets.mulDiv(totalSupply() + 10 ** decimalOffset, totalAssets() + 1, rounding);
    }

    /**
     * @notice Converts an amount of shares to the equivalent amount of assets, considering the current share price and applying the specified rounding.
     * @dev Utilizes the total assets and total supply to calculate the asset price for conversion.
     * @param shares The amount of shares to convert to assets.
     * @param rounding The rounding direction to use for the conversion.
     * @return The equivalent amount of assets for the given shares.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** decimalOffset, rounding);
    }

    // ============ FEE ACCOUNTING =====================
    /**
     * @notice Calculates the accrued protocol fee based on the current protocol fee rate and time elapsed.
     * @dev The protocol fee is calculated as a percentage of the total assets, prorated over time since the last fee update.
     * @return The accrued protocol fee in asset units.
     */
    function accruedProtocolFee() public view whenNotPaused returns (uint256) {
        // Only calculate if a protocol fee is set
        return FeesHelper.accruedProtocolFee(fees.protocolFee, totalAssets(), feesUpdatedAt);
    }

    /**
     * @notice Calculates the accrued performance fee based on the vault's performance relative to the high water mark.
     * @dev The performance fee is calculated as a percentage of the profit (asset value increase) since the last high water mark update.
     * @return fee The accrued performance fee in asset units.
     */
    // We're not using the timestamp for comparisions
    // slither-disable-next-line timestamp
    function accruedPerformanceFee() public view returns (uint256) {
        // Calculate the share value in assets
        uint256 shareValue = convertToAssets(1e18);
        // Only calculate if a performance fee is set and the share value exceeds the high water mark
        return FeesHelper.accruedPerformanceFee(
            fees.performanceFee, totalAssets(), shareValue, highWaterMark, asset(), fees
        );
    }

    /**
     * @notice Retrieves the current fee structure of the vault.
     * @dev Returns the vault's fees including deposit, withdrawal, protocol, and performance fees.
     * @return A `VaultFees` struct containing the current fee rates.
     */
    function getVaultFees() public view returns (VaultFees memory) {
        return fees;
    }

    // ============== FEE LOGIC ===================

    /**
     * @notice Placeholder function for taking portfolio and protocol fees.
     * @dev This function is intended to be overridden with actual fee-taking logic.
     */
    function takePortfolioAndProtocolFees() external nonReentrant takeFees onlyOwner {
        // Intentionally left blank for override
    }

    /**
     * @notice Updates the vault's fee structure.
     * @dev Can only be called by the vault owner. Emits an event upon successful update.
     * @param newFees_ The new fee structure to apply to the vault.
     */
    function setVaultFees(VaultFees calldata newFees_) external takeFees onlyOwner {
        fees = newFees_; // Update the fee structure
        feesUpdatedAt = block.timestamp; // Record the time of the fee update
    }

    /**
     * @notice Sets a new fee recipient address for the vault.
     * @dev Can only be called by the vault owner. Reverts if the new recipient address is the zero address.
     * @param newRecipient_ The address of the new fee recipient.
     */
    function setFeeRecipient(address newRecipient_) external onlyOwner {
        // Validate the new recipient address
        if (newRecipient_ == address(0)) revert InvalidFeeRecipient();

        // Emit an event for the fee recipient update
        emit FeeRecipientUpdated(feeRecipient, newRecipient_);

        feeRecipient = newRecipient_; // Update the fee recipient
    }

    /**
     * @notice Sets a minimum amount required to queue a withdrawal request.
     * @param minQueueRequest_ The address of the new fee recipient.
     */
    function setMinimunQueueRequest(uint256 minQueueRequest_) external onlyOwner {
        emit MinimunQueueRequestUpdated(minQueueRequest, minQueueRequest_);
        minQueueRequest = minQueueRequest_;
    }

    /**
     * @notice Sets a new fee recipient address for the vault.
     * @dev Can only be called by the vault owner. Reverts if the new recipient address is the zero address.
     * @param withdrawalQueue_ The address of the new withdrawlQueue.
     */
    function setWithdrawalQueue(address withdrawalQueue_) external onlyOwner {
        withdrawalQueue = WithdrawalQueueHelper.setWithdrawalQueue(address(withdrawalQueue), withdrawalQueue_);
    }

    /**
     * @notice Sets a new parking lot address for the vault.
     * @dev Can only be called by the vault owner. Reverts if the new parking lot address is the zero address.
     * @param parkingLot_ The address of the new parking lot.
     */
    function setParkingLot(address parkingLot_) external onlyOwner {
        // Validate the new recipient address
        if (parkingLot_ == address(0)) revert InvalidParkingLot();

        // create a success
        // Emit an event for the fee recipient update
        address token = asset();
        address currentParkingLot = address(parkingLot);
        if (currentParkingLot != address(0)) TokenHelper.attemptForceApprove(token, currentParkingLot, 0, true);
        bool successfulApproval = TokenHelper.attemptForceApprove(token, parkingLot_, type(uint256).max, false);
        emit ParkingLotUpdated(currentParkingLot, parkingLot_, successfulApproval);

        parkingLot = IParkingLot(parkingLot_); // Update the fee recipient
    }
    // ============= STRATEGIES ===================
    /**
     * @notice Retrieves the current strategies employed by the vault.
     * @dev Returns an array of `Strategy` structs representing each strategy.
     * @return An array of `Strategy` structs.
     */

    function getStrategies() external view returns (Strategy[] memory) {
        return strategies;
    }

    /**
     * @notice Toggles the vault's idle state.
     * @dev Can only be called by the vault owner. Emits a `ToggleVaultIdle` event with the previous and new state.
     */
    function toggleVaultIdle() external onlyOwner {
        emit ToggleVaultIdle(vaultIdle, !vaultIdle);
        vaultIdle = !vaultIdle;
    }

    /**
     * @notice Adds a new strategy or replaces an existing one.
     * @dev Can only be called by the vault owner. Validates the total allocation does not exceed 100%.
     *      Emits a `StrategyAdded` or/and `StrategyRemoved` event.
     * @param index_ The index at which to add or replace the strategy. If replacing, this is the index of the existing strategy.
     * @param replace_ A boolean indicating whether to replace an existing strategy.
     * @param newStrategy_ The new strategy to add or replace the existing one with.
     */
    // slither didn't detect the nonReentrant modifier
    // slither-disable-next-line reentrancy-no-eth
    function addStrategy(uint256 index_, bool replace_, Strategy calldata newStrategy_)
        external
        nonReentrant
        onlyOwner
        takeFees
    {
        IStrategy newStrategy;
        IStrategy removedStrategy;
        (protectStrategy, newStrategy, removedStrategy) = StrategyHelper.addOrReplaceStrategy(
            strategies, newStrategy_, replace_, index_, protectStrategy, IERC20(asset())
        );
        if (address(removedStrategy) != address(0)) {
            emit StrategyRemoved(address(removedStrategy));
        }
        emit StrategyAdded(address(newStrategy));
    }

    /**
     * @notice Adds a new strategy or replaces an existing one.
     * @dev Can only be called by the vault owner. Validates that the index to be removed exists.
     *      Emits a `StrategyRemoved` event.
     * @param index_ The index of the strategy to be removed.
     */
    // slither didn't detect the nonReentrant modifier
    // slither-disable-next-line reentrancy-no-eth
    function removeStrategy(uint256 index_) public nonReentrant onlyOwner takeFees {
        uint256 len = strategies.length;
        if (index_ >= len) revert InvalidIndex(index_);

        IStrategy stratToBeRemoved = strategies[index_].strategy;
        protectStrategy = StrategyHelper.removeStrategy(stratToBeRemoved, protectStrategy, IERC20(asset()));
        emit StrategyRemoved(address(stratToBeRemoved));

        strategies[index_] = strategies[len - 1];
        strategies.pop();
    }

    /// @notice Emergency function to force remove a strategy when it's unable to withdraw funds
    /// @dev Should only be used when a strategy is permanently compromised or frozen
    /// @param index_ The index of the strategy to remove
    /// @param forceEject_ If true, bypasses the locked assets check
    function emergencyRemoveStrategy(uint256 index_, bool forceEject_) external onlyOwner {
        StrategyHelper.emergencyRemoveStrategy(strategies, asset(), index_, forceEject_, protectStrategy);
    }

    /**
     * @notice ERC20 _update function override.
     */
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) updateUserRewardsToCurrent(from);
        if (to != address(0)) updateUserRewardsToCurrent(to);
        super._update(from, to, value);
    }

    /**
     * @notice Changes strategies allocations.
     * @dev Can only be called by the vault owner. Validates the total allocation does not exceed 100% and the length corresponds with the strategies array.
     *      Emits a `StrategyAllocationsChanged`
     * @param allocations_ The array with the new allocations.
     * @param redistribute A boolean indicating whether to redistributes allocations.
     */
    function changeAllocations(Allocation[] calldata allocations_, bool redistribute)
        external
        nonReentrant
        onlyOwner
        takeFees
    {
        StrategyHelper.changeAllocations(strategies, allocations_, redistribute, asset());
    }

    /**
     * @notice Pushes funds from the vault into all strategies based on their allocation.
     * @dev Can only be called by the vault owner. Reverts if the vault is idle.
     */
    function pushFundsToStrategies() public onlyOwner {
        if (vaultIdle) revert VaultIsIdle();

        // Call the library function to distribute assets
        StrategyHelper.distributeAssetsToStrategies(strategies, IERC20(asset()).balanceOf(address(this)));
    }

    /**
     * @notice Pulls funds back from all strategies into the vault.
     * @dev Can only be called by the vault owner.
     */
    // We are aware that we aren't using the return value
    // We control both the length of the array and the external call
    //slither-disable-next-line unused-return,calls-loop
    function pullFundsFromStrategies() public onlyOwner {
        StrategyHelper.pullFundsFromStrategies(strategies);
    }

    /**
     * @notice Pulls funds back from a single strategy into the vault.
     * @dev Can only be called by the vault owner.
     * @param index_ The index of the strategy from which to pull funds.
     */

    // We are aware that we aren't using the return value
    // We control both the length of the array and the external call
    //slither-disable-next-line unused-return,calls-loop
    function pullFundsFromSingleStrategy(uint256 index_) public onlyOwner {
        StrategyHelper.pullFundsFromSingleStrategy(strategies, index_);
    }

    /**
     * @notice Pushes funds from the vault into a single strategy based on its allocation.
     * @dev Can only be called by the vault owner. Reverts if the vault is idle.
     * @param index_ The index of the strategy into which to push funds.
     */
    function pushFundsIntoSingleStrategy(uint256 index_) external onlyOwner {
        StrategyHelper.pushFundsIntoSingleStrategyNoAmount(
            strategies, IERC20(asset()).balanceOf(address(this)), index_, vaultIdle
        );
    }

    /**
     * @notice Pushes the amount sent from the vault into a single strategy.
     * @dev Can only be called by the vault owner. Reverts if the vault is idle.
     * @param index_ The index of the strategy into which to push funds.
     * @param amount The index of the strategy into which to push funds.
     */
    function pushFundsIntoSingleStrategy(uint256 index_, uint256 amount) external onlyOwner {
        StrategyHelper.pushFundsIntoSingleStrategy(
            strategies, vaultIdle, IERC20(asset()).balanceOf(address(this)), index_, amount
        );
    }

    /**
     * @notice Sets a new deposit limit for the vault.
     * @dev Can only be called by the vault owner. Emits a `DepositLimitSet` event with the new limit.
     * @param newLimit_ The new deposit limit to set.
     */
    function setDepositLimit(uint256 newLimit_) external onlyOwner {
        depositLimit = newLimit_;
        emit DepositLimitSet(newLimit_);
    }

    /**
     * @notice Harvest rewards on every strategy.
     * @dev Calculates de reward index for each reward found.
     */
    //we control the external call
    //slither-disable-next-line unused-return,calls-loop,reentrancy-no-eth
    function harvestRewards(bytes calldata encodedData) external nonReentrant onlyOwner {
        uint256[] memory indices;
        bytes[] memory data;
        if (encodedData.length != 0) {
            (indices, data) = abi.decode(encodedData, (uint256[], bytes[]));
        }
        uint256 totalSupply = totalSupply();
        bytes memory rewardsData;
        uint256 lenIndices = indices.length;
        uint256 lenStrategies = strategies.length;
        uint256 lenRewards;
        for (uint256 i; i < lenStrategies;) {
            //We control both the length of the array and the external call
            //slither-disable-next-line unused-return,calls-loop
            for (uint256 k = 0; k < lenIndices;) {
                if (indices[k] == i) {
                    rewardsData = data[k];
                    break;
                }
                rewardsData = "";

                unchecked {
                    k++;
                }
            }
            ReturnedRewards[] memory returnedRewards = strategies[i].strategy.harvestRewards(rewardsData);
            lenRewards = returnedRewards.length;
            for (uint256 j; j < lenRewards;) {
                uint256 amount = returnedRewards[j].rewardAmount;
                address rewardToken = returnedRewards[j].rewardAddress;
                if (amount != 0) {
                    if (rewardIndex[rewardToken] == 0) {
                        rewardAddresses.push(rewardToken);
                    }
                    if (totalSupply > 0) {
                        rewardIndex[rewardToken] += amount.mulDiv(PRECISION, totalSupply, Math.Rounding.Floor);
                    }
                }
                unchecked {
                    j++;
                }
            }
            unchecked {
                i++;
            }
        }
        emit RewardsHarvested();
    }

    /**
     * @notice Updates the user rewards to the current reward index.
     * @dev Calculates the rewards to be transferred to the user based on the difference between the current and previous reward indexes.
     * @param userAddress The address of the user to update rewards for.
     */
    //slither-disable-next-line unused-return,calls-loop,reentrancy-no-eth
    function updateUserRewardsToCurrent(address userAddress) private {
        RewardsHelper.updateUserRewardsToCurrent(
            balanceOf(userAddress), userAddress, rewardAddresses, rewardIndex, userRewardIndex, totalRewardsClaimed
        );
    }

    /**
     * @notice Claims multiple withdrawal requests starting from the lasFinalizedRequestId.
     * @dev This function allows the contract owner to claim multiple withdrawal requests in batches.
     * @param maxRequests The maximum number of withdrawal requests to be processed in this batch.
     */
    function batchClaimWithdrawal(uint256 maxRequests) external onlyOwner nonReentrant {
        if (address(withdrawalQueue) == address(0)) revert QueueNotSet();
        uint256 availableAssets = getAvailableAssetsForWithdrawal();
        WithdrawalQueueHelper.batchClaim(withdrawalQueue, maxRequests, availableAssets, asset(), strategies, parkingLot);
    }

    function claimRewards() external {
        updateUserRewardsToCurrent(msg.sender);
    }

    /**
     * @notice Requests funds from available assets.
     * @dev This function allows the protect strategy to request funds from available assets, withdraws from other strategies if necessary,
     * and deposits the requested funds into the protect strategy.
     * @param amount The amount of funds to request.
     */
    //we control the external call, only callable by the protect strategy
    //slither-disable-next-line calls-loop,,reentrancy-events
    function requestFunds(uint256 amount) external onlyProtect {
        uint256 acumulated = MultiStrategyVaultHelper.withdrawAssets(asset(), amount, protectStrategy, strategies);
        WithdrawalQueueHelper.requestFunds(amount, acumulated, protectStrategy);
    }

    // Helper function ////////////////////////

    function _validateAndUpdateDepositTimestamps(address receiver_) private {
        if (receiver_ == address(0)) revert InvalidRecipient();
        if (totalSupply() == 0) feesUpdatedAt = block.timestamp;

        if (firstDeposit == 0) {
            firstDeposit = block.timestamp;
        }
    }
}