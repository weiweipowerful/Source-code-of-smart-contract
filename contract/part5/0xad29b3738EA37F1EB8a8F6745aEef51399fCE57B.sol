// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../common/Base.sol";
import "../common/StableMath.sol";
import "../interfaces/ICollateralController.sol";
import "../Guardable.sol";
import "../interfaces/IFeeTokenStaking.sol";
import "../interfaces/IPositionController.sol";
import "../interfaces/IStable.sol";

/**
 * @title PositionController
 * @dev Contract for managing positions, including opening, adjusting, and closing positions.
 *
 * Key features:
 *      1. Position Management: Allows users to open, adjust, and close positions with various collateral types.
 *      2. Collateral Handling: Manages different types of collateral, including deposit and withdrawal.
 *      3. Debt Management: Handles borrowing and repayment of stable tokens.
 *      4. Liquidation and Recovery: Implements recovery mode and handles liquidations.
 *      5. Fee Management: Calculates and applies borrowing fees.
 *      6. Escrow Mechanism: Implements an escrow system for newly minted stable tokens.
 *      7. Referral System: Supports a referral system for position creation.
 *      8. Safety Checks: Implements various safety checks to maintain system stability.
 */
contract PositionController is Base, Ownable, Guardable, IPositionController {
    using SafeERC20 for IERC20Metadata;

    // Address of the backstop pool
    address public backstopPoolAddress;
    // Interface for the stable token
    IStable public stableToken;
    // Interface for fee token staking
    IFeeTokenStaking public feeTokenStaking;
    // Address of the fee token staking contract
    address public feeTokenStakingAddress;
    // Interface for collateral controller
    ICollateralController public collateralController;

    // Mapping to store loan origination escrow for each asset, version, and user
    mapping(address => mapping(uint8 => mapping(address => LoanOriginationEscrow))) public assetToVersionToUserToEscrow;

    /**
     * @dev Struct to represent a loan origination escrow
     */
    struct LoanOriginationEscrow {
        address owner;
        address asset;
        uint8 version;
        uint startTimestamp;
        uint stables;
        uint quotePrice;

        // only set on external reads.  Do not use for contract operations.
        uint loanCooldownPeriod;
    }

    /**
    * @notice Distributes clawback rewards to fee token stakers
    * @param amount Amount of stable tokens to distribute
    */
    function distributeClawbackRewards(uint amount) external onlyGuardian {
        require(amount > 0, "Cannot distribute zero amount");
        require(stableToken.balanceOf(address(this)) >= amount, "Insufficient Balance");
        feeTokenStaking.increaseF_STABLE(amount);
        stableToken.transfer(feeTokenStakingAddress, amount);
    }

    /**
     * @dev Reclaims clawback rewards to multisig
     * @param amount Amount of rewards to reclaim
     * Can only be called by the guardian
     */
    function reclaimClawbackRewards(uint amount) external onlyGuardian {
        require(amount > 0, "Cannot reclaim zero amount");
        require(stableToken.balanceOf(address(this)) >= amount, "Insufficient Balance");
        stableToken.transfer(0x54FDAcea0af4026306A665E9dAB635Ef5fF2963f, amount);
    }

    /**
     * @dev Allows users to claim their escrowed stables
     * @param originator Address of the originator
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     */
    function claimEscrow(address originator, address asset, uint8 version) external {
        ICollateralController.Collateral memory c = collateralController.getCollateralInstance(asset, version);
        LoanOriginationEscrow storage escrow = assetToVersionToUserToEscrow[asset][version][originator];
        require(escrow.startTimestamp != 0, "No active escrow for this asset and version");

        (uint requiredEscrowDuration, uint claimGracePeriod) = collateralController.getLoanCooldownRequirement(asset, version);
        uint cooldownExpiry = escrow.startTimestamp + requiredEscrowDuration;

        uint currentPrice = c.priceFeed.fetchLowestPrice(false, false);
        uint gracePeriodExpiry = cooldownExpiry + claimGracePeriod;
        bool wasLiquidated = c.positionManager.getPositionStatus(escrow.owner) == 3;

        if ((block.timestamp < gracePeriodExpiry) && !wasLiquidated) {
            require(msg.sender == escrow.owner, "Only originator can unlock during grace period");
        }

        bool isRecoveryMode = collateralController.checkRecoveryMode(asset, version, currentPrice);
        uint ICR = c.positionManager.getCurrentICR(escrow.owner, currentPrice);

        uint thresholdRatio = isRecoveryMode ?
            collateralController.getCCR(asset, version)
            :
            collateralController.getMCR(asset, version);

        if ((ICR < thresholdRatio) || wasLiquidated) {
            stableToken.mint(address(this), escrow.stables);
        } else {
            require(block.timestamp >= cooldownExpiry, "Escrow claiming cooldown not met");
            stableToken.mint(escrow.owner, escrow.stables);
        }

        delete assetToVersionToUserToEscrow[asset][version][originator];
    }

    /**
     * @dev Retrieves the escrow information for a given account
     * @param account Address of the account
     * @param asset Asset which may have a pending escrow
     * @param version Corresponding asset version
     * @return LoanOriginationEscrow struct containing escrow details
     */
    function getEscrow(address account, address asset, uint8 version) external view returns (LoanOriginationEscrow memory) {
        LoanOriginationEscrow memory loe = assetToVersionToUserToEscrow[asset][version][account];
        (loe.loanCooldownPeriod,) = collateralController.getLoanCooldownRequirement(loe.asset, loe.version);
        return loe;
    }

    /**
     * @dev Struct to hold local variables for adjusting a position
     * Used to avoid stack too deep errors
     */
    struct LocalVariables_adjustPosition {
        uint price;
        uint collChange;
        uint netDebtChange;
        bool isCollIncrease;
        uint debt;
        uint coll;
        uint oldICR;
        uint newICR;
        uint newTCR;
        uint stableFee;
        uint newDebt;
        uint newColl;
        uint stake;
        uint suggestedAdditiveFeePCT;
        uint utilizationPCT;
        uint loadIncrease;
        bool isRecoveryMode;
    }

    /**
     * @dev Struct to hold local variables for opening a position
     * Used to avoid stack too deep errors
     */
    struct LocalVariables_openPosition {
        uint price;
        uint stableFee;
        uint netDebt;
        uint compositeDebt;
        uint ICR;
        uint NICR;
        uint stake;
        uint arrayIndex;
        uint suggestedFeePCT;
        uint utilizationPCT;
        uint loadIncrease;
        bool isRecoveryMode;
        uint requiredEscrowDuration;
    }

    /**
     * @dev Enum to represent different position operations
     */
    enum PositionOperation {
        openPosition,
        closePosition,
        adjustPosition
    }

    /**
     * @dev Sets the addresses for various components of the system
     * @param _collateralController Address of the collateral controller
     * @param _backstopPoolAddress Address of the backstop pool
     * @param _gasPoolAddress Address of the gas pool
     * @param _stableTokenAddress Address of the stable token
     * @param _feeTokenStakingAddress Address of the fee token staking contract
     * Can only be called by the owner
     */
    function setAddresses(
        address _collateralController,
        address _backstopPoolAddress,
        address _gasPoolAddress,
        address _stableTokenAddress,
        address _feeTokenStakingAddress
    ) external override onlyOwner {
        assert(MIN_NET_DEBT > 0);

        backstopPoolAddress = _backstopPoolAddress;
        gasPoolAddress = _gasPoolAddress;
        stableToken = IStable(_stableTokenAddress);
        feeTokenStakingAddress = _feeTokenStakingAddress;
        feeTokenStaking = IFeeTokenStaking(_feeTokenStakingAddress);
        collateralController = ICollateralController(_collateralController);
        renounceOwnership();
    }

    /**
     * @dev Opens a new position
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     * @param suppliedCollateral Amount of collateral supplied
     * @param _maxFeePercentage Maximum fee percentage allowed
     * @param _stableAmount Amount of stable tokens to borrow
     * @param _upperHint Upper hint for position insertion
     * @param _lowerHint Lower hint for position insertion
     */
    function openPosition(
        address asset, uint8 version, uint suppliedCollateral, uint _maxFeePercentage,
        uint _stableAmount, address _upperHint, address _lowerHint
    ) external override {
        ICollateralController.Collateral memory collateral = collateralController.getCollateralInstance(asset, version);
        LocalVariables_openPosition memory vars;

        collateralController.requireIsActive(asset, version);
        _requireNotSunsetting(address(collateral.asset), collateral.version);

        (vars.utilizationPCT, vars.loadIncrease) = collateralController.regenerateAndConsumeLoanPoints(asset, version, _stableAmount);
        (vars.price, vars.suggestedFeePCT) = collateral.priceFeed.fetchLowestPriceWithFeeSuggestion(
            vars.loadIncrease,
            vars.utilizationPCT,
            true, // Test health of liquidity before issuing more debt
            true  // Test market stability. We want to be extremely conservative with new debt creation, so this check includes SPOT price if spotConsideration is 'true' in the price feed.
        );

        vars.isRecoveryMode = collateralController.checkRecoveryMode(address(collateral.asset), collateral.version, vars.price);
        _requireValidMaxFeePercentage(_maxFeePercentage, vars.isRecoveryMode, asset, version, vars.suggestedFeePCT);
        _requirePositionIsNotActive(collateral.positionManager, msg.sender);

        vars.netDebt = _stableAmount;

        if (!vars.isRecoveryMode) {
            vars.stableFee = _triggerBorrowingFee(
                collateral.positionManager,
                stableToken,
                _stableAmount,
                _maxFeePercentage,
                vars.suggestedFeePCT
            );
            vars.netDebt = vars.netDebt + vars.stableFee;
        }

        _requireAtLeastMinNetDebt(vars.netDebt);

        // ICR is based on the composite debt, i.e. the requested stable amount + stable borrowing fee + stable gas comp.
        vars.compositeDebt = vars.netDebt + GAS_COMPENSATION;
        assert(vars.compositeDebt > 0);

        vars.ICR = StableMath._computeCR(suppliedCollateral, vars.compositeDebt, vars.price, collateral.asset.decimals());
        vars.NICR = StableMath._computeNominalCR(suppliedCollateral, vars.compositeDebt, collateral.asset.decimals());

        if (vars.isRecoveryMode) {
            _requireICRisAboveCCR(vars.ICR, asset, version);
        } else {
            _requireICRisAboveMCR(vars.ICR, asset, version);
            uint newTCR = _getNewTCRFromPositionChange(collateral, suppliedCollateral, true, vars.compositeDebt, true, vars.price);  // bools: coll increase, debt increase
            _requireNewTCRisAboveCCR(newTCR, asset, version);
        }

        _requireDoesNotExceedCap(collateral, vars.compositeDebt);

        collateral.positionManager.setPositionStatus(msg.sender, 1);
        collateral.positionManager.increasePositionColl(msg.sender, suppliedCollateral);
        collateral.positionManager.increasePositionDebt(msg.sender, vars.compositeDebt);

        collateral.positionManager.updatePositionRewardSnapshots(msg.sender);
        vars.stake = collateral.positionManager.updateStakeAndTotalStakes(msg.sender);

        collateral.sortedPositions.insert(msg.sender, vars.NICR, _upperHint, _lowerHint);
        vars.arrayIndex = collateral.positionManager.addPositionOwnerToArray(msg.sender);
        emit PositionCreated(asset, version, msg.sender, vars.arrayIndex);

        // Move the collateral to the Active Pool, and mint the stableAmount to the borrower
        _activePoolAddColl(collateral, suppliedCollateral);
        (vars.requiredEscrowDuration,) = collateralController.getLoanCooldownRequirement(asset, version);
        _withdrawStable(collateral.activePool, stableToken, msg.sender, _stableAmount, vars.netDebt, vars.requiredEscrowDuration != 0, asset, version, vars.price);
        // Move the stable gas compensation to the Gas Pool
        _withdrawStable(collateral.activePool, stableToken, gasPoolAddress, GAS_COMPENSATION, GAS_COMPENSATION, false, asset, version, vars.price);

        emit PositionUpdated(asset, version, msg.sender, vars.compositeDebt, suppliedCollateral, vars.stake, uint8(PositionOperation.openPosition));
        emit StableBorrowingFeePaid(asset, version, msg.sender, vars.stableFee);
    }

    /**
     * @dev Adds collateral to an existing position
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     * @param _collAddition Amount of collateral to add
     * @param _upperHint Upper hint for position insertion
     * @param _lowerHint Lower hint for position insertion
     */
    function addColl(address asset, uint8 version, uint _collAddition, address _upperHint, address _lowerHint) external override {
        _requireNotSunsetting(asset, version);
        _adjustPosition(AdjustPositionParams(asset, version, _collAddition, msg.sender, 0, 0, false, _upperHint, _lowerHint, 0));
    }

    /**
     * @dev Moves collateral gain to a position (only callable by Backstop Pool)
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     * @param _collAddition Amount of collateral to add
     * @param _borrower Address of the borrower
     * @param _upperHint Upper hint for position insertion
     * @param _lowerHint Lower hint for position insertion
     */
    function moveCollateralGainToPosition(address asset, uint8 version, uint _collAddition, address _borrower, address _upperHint, address _lowerHint) external override {
        _requireCallerIsBackstopPool();
        _requireNotSunsetting(asset, version);
        _adjustPosition(AdjustPositionParams(asset, version, _collAddition, _borrower, 0, 0, false, _upperHint, _lowerHint, 0));
    }

    /**
     * @dev Withdraws collateral from an existing position
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     * @param _collWithdrawal Amount of collateral to withdraw
     * @param _upperHint Upper hint for position insertion
     * @param _lowerHint Lower hint for position insertion
     */
    function withdrawColl(address asset, uint8 version, uint _collWithdrawal, address _upperHint, address _lowerHint) external override {
        _adjustPosition(AdjustPositionParams(asset, version, 0, msg.sender, _collWithdrawal, 0, false, _upperHint, _lowerHint, 0));
    }

    /**
     * @dev Withdraws stable tokens from a position
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     * @param _maxFeePercentage Maximum fee percentage allowed
     * @param _stableAmount Amount of stable tokens to withdraw
     * @param _upperHint Upper hint for position insertion
     * @param _lowerHint Lower hint for position insertion
     */
    function withdrawStable(address asset, uint8 version, uint _maxFeePercentage, uint _stableAmount, address _upperHint, address _lowerHint) external override {
        _requireNotSunsetting(asset, version);
        _adjustPosition(AdjustPositionParams(asset, version, 0, msg.sender, 0, _stableAmount, true, _upperHint, _lowerHint, _maxFeePercentage));
    }

    /**
     * @dev Repays stable tokens to a position
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     * @param _stableAmount Amount of stable tokens to repay
     * @param _upperHint Upper hint for position insertion
     * @param _lowerHint Lower hint for position insertion
     */
    function repayStable(address asset, uint8 version, uint _stableAmount, address _upperHint, address _lowerHint) external override {
        _adjustPosition(AdjustPositionParams(asset, version, 0, msg.sender, 0, _stableAmount, false, _upperHint, _lowerHint, 0));
    }

    /**
     * @dev Adjusts an existing position
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     * @param _collAddition Amount of collateral to add
     * @param _maxFeePercentage Maximum fee percentage allowed
     * @param _collWithdrawal Amount of collateral to withdraw
     * @param _stableChange Amount of stable tokens to change
     * @param _isDebtIncrease Whether the debt is increasing
     * @param _upperHint Upper hint for position insertion
     * @param _lowerHint Lower hint for position insertion
     */
    function adjustPosition(address asset, uint8 version, uint _collAddition, uint _maxFeePercentage, uint _collWithdrawal,
        uint _stableChange, bool _isDebtIncrease, address _upperHint, address _lowerHint) external override {
        if (_collAddition > 0 || (_stableChange > 0 && _isDebtIncrease)) {_requireNotSunsetting(asset, version);}
        _adjustPosition(AdjustPositionParams(asset, version, _collAddition, msg.sender, _collWithdrawal, _stableChange, _isDebtIncrease, _upperHint, _lowerHint, _maxFeePercentage));
    }

    /**
     * @dev Struct to hold parameters for position adjustment
     */
    struct AdjustPositionParams {
        address asset;
        uint8 version;
        uint _collAddition;
        address _borrower;
        uint _collWithdrawal;
        uint _stableChange;
        bool _isDebtIncrease;
        address _upperHint;
        address _lowerHint;
        uint _maxFeePercentage;
    }

    /**
     * @dev Internal function to adjust a position
     * @param params AdjustPositionParams struct containing adjustment parameters
     */
    function _adjustPosition(AdjustPositionParams memory params) internal {
        ICollateralController.Collateral memory collateral = collateralController.getCollateralInstance(params.asset, params.version);
        LocalVariables_adjustPosition memory vars;

        (vars.utilizationPCT, vars.loadIncrease) = params._isDebtIncrease ?
            collateralController.regenerateAndConsumeLoanPoints(params.asset, params.version, params._stableChange) :
            collateralController.regenerateAndConsumeLoanPoints(params.asset, params.version, 0);

        (vars.price, vars.suggestedAdditiveFeePCT) = collateral.priceFeed.fetchLowestPriceWithFeeSuggestion(
            vars.loadIncrease,
            vars.utilizationPCT,
            params._isDebtIncrease, // Test health of liquidity before issuing more debt
            params._isDebtIncrease  // Test market stability. We want to be extremely conservative with new debt creation, so this check includes SPOT price if spotConsideration is 'true' in the price feed.
        );

        vars.isRecoveryMode = collateralController.checkRecoveryMode(address(collateral.asset), collateral.version, vars.price);

        if (params._isDebtIncrease) {
            _requireValidMaxFeePercentage(params._maxFeePercentage, vars.isRecoveryMode, params.asset, params.version, vars.suggestedAdditiveFeePCT);
            _requireNonZeroDebtChange(params._stableChange);
        }
        _requireSingularCollChange(params._collWithdrawal, params._collAddition);
        _requireNonZeroAdjustment(params._collWithdrawal, params._stableChange, params._collAddition);
        _requirePositionIsActive(collateral.positionManager, params._borrower);

        assert(msg.sender == params._borrower || (msg.sender == backstopPoolAddress && params._collAddition > 0 && params._stableChange == 0));

        collateral.positionManager.applyPendingRewards(params._borrower);

        // Get the collChange based on whether or not Collateral was sent in the transaction
        (vars.collChange, vars.isCollIncrease) = _getCollChange(params._collAddition, params._collWithdrawal);

        vars.netDebtChange = params._stableChange;

        // If the adjustment incorporates a debt increase and system is in Normal Mode, then trigger a borrowing fee
        if (params._isDebtIncrease && !vars.isRecoveryMode) {
            vars.stableFee = _triggerBorrowingFee(
                collateral.positionManager,
                stableToken,
                params._stableChange,
                params._maxFeePercentage,
                vars.suggestedAdditiveFeePCT
            );
            vars.netDebtChange = vars.netDebtChange + vars.stableFee; // The raw debt change includes the fee
        }

        vars.debt = collateral.positionManager.getPositionDebt(params._borrower);
        vars.coll = collateral.positionManager.getPositionColl(params._borrower);

        // Get the Position's old ICR before the adjustment, and what its new ICR will be after the adjustment
        vars.oldICR = StableMath._computeCR(vars.coll, vars.debt, vars.price, collateral.asset.decimals());
        vars.newICR = _getNewICRFromPositionChange(vars.coll, vars.debt, vars.collChange, vars.isCollIncrease,
            vars.netDebtChange, params._isDebtIncrease, vars.price, collateral.asset.decimals());

        assert(params._collWithdrawal <= vars.coll);

        // Check the adjustment satisfies all conditions for the current system mode
        _requireValidAdjustmentInCurrentMode(collateral, vars.isRecoveryMode, params._collWithdrawal, params._isDebtIncrease, vars);

        if (params._isDebtIncrease) {
            _requireDoesNotExceedCap(collateral, vars.netDebtChange);
        }

        // When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough stable
        if (!params._isDebtIncrease && params._stableChange > 0) {
            _requireAtLeastMinNetDebt((vars.debt - GAS_COMPENSATION) - vars.netDebtChange);
            _requireValidStableRepayment(vars.debt, vars.netDebtChange);
            _requireSufficientStableBalance(stableToken, params._borrower, vars.netDebtChange);
        }

        (vars.newColl, vars.newDebt) = _updatePositionFromAdjustment(
            collateral.positionManager, params._borrower, vars.collChange, vars.isCollIncrease, vars.netDebtChange, params._isDebtIncrease
        );

        vars.stake = collateral.positionManager.updateStakeAndTotalStakes(params._borrower);

        // Re-insert Position in to the sorted list
        uint newNICR = _getNewNominalICRFromPositionChange(
            vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, params._isDebtIncrease, collateral.asset.decimals()
        );

        collateral.sortedPositions.reInsert(params._borrower, newNICR, params._upperHint, params._lowerHint);

        emit PositionUpdated(params.asset, params.version, params._borrower, vars.newDebt, vars.newColl, vars.stake, uint8(PositionOperation.adjustPosition));
        emit StableBorrowingFeePaid(params.asset, params.version, params._borrower, vars.stableFee);

        // Use the unmodified _stableChange here, as we don't send the fee to the user
        _moveTokensAndCollateralFromAdjustment(collateral, stableToken, msg.sender, vars, params);
    }

    /**
     * @dev Closes an existing position
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     */
    function closePosition(address asset, uint8 version) external override {
        require(
            assetToVersionToUserToEscrow[asset][version][msg.sender].startTimestamp == 0,
            "Claim your escrowed stables before closing position"
        );

        ICollateralController.Collateral memory collateral = collateralController.getCollateralInstance(asset, version);

        _requirePositionIsActive(collateral.positionManager, msg.sender);

        uint price = collateral.priceFeed.fetchLowestPrice(false, false);
        require(!collateralController.checkRecoveryMode(asset, collateral.version, price), "PositionController: Operation not permitted during Recovery Mode");

        collateral.positionManager.applyPendingRewards(msg.sender);

        uint coll = collateral.positionManager.getPositionColl(msg.sender);
        uint debt = collateral.positionManager.getPositionDebt(msg.sender);

        _requireSufficientStableBalance(stableToken, msg.sender, debt - GAS_COMPENSATION);

        uint newTCR = _getNewTCRFromPositionChange(collateral, coll, false, debt, false, price);
        _requireNewTCRisAboveCCR(newTCR, asset, version);

        collateral.positionManager.removeStake(msg.sender);
        collateral.positionManager.closePosition(msg.sender);

        emit PositionUpdated(asset, version, msg.sender, 0, 0, 0, uint8(PositionOperation.closePosition));

        // Burn the repaid stable from the user's balance and the gas compensation from the Gas Pool
        _repayStables(collateral.activePool, stableToken, msg.sender, debt - GAS_COMPENSATION);
        _repayStables(collateral.activePool, stableToken, gasPoolAddress, GAS_COMPENSATION);

        // Send the collateral back to the user
        collateral.activePool.sendCollateral(msg.sender, coll);
    }

    /**
     * @dev Allows users to claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     */
    function claimCollateral(address asset, uint8 version) external override {
        // send Collateral from CollSurplus Pool to owner
        collateralController.getCollateralInstance(asset, version).collateralSurplusPool.claimColl(msg.sender);
    }

    // --- Helper functions ---

    // ... (previous code remains unchanged)

    /**
     * @dev Triggers the borrowing fee calculation and distribution
     * @param _positionManager The position manager contract
     * @param _stableToken The stable token contract
     * @param _stableAmount The amount of stable tokens being borrowed
     * @param _maxFeePercentage The maximum fee percentage allowed by the user
     * @param suggestedAdditiveFeePCT The suggested additive fee percentage
     * @return The calculated stable fee
     */
    function _triggerBorrowingFee(
        IPositionManager _positionManager,
        IStable _stableToken,
        uint _stableAmount,
        uint _maxFeePercentage,
        uint suggestedAdditiveFeePCT
    ) internal returns (uint) {
        _positionManager.decayBaseRateFromBorrowing(); // decay the baseRate state variable
        uint stableFee = _positionManager.getBorrowingFee(_stableAmount, suggestedAdditiveFeePCT);
        _requireUserAcceptsFee(stableFee, _stableAmount, _maxFeePercentage);

        // Send fee to feetoken staking contract
        feeTokenStaking.increaseF_STABLE(stableFee);
        _stableToken.mint(feeTokenStakingAddress, stableFee);

        return stableFee;
    }

    /**
     * @dev Calculates the USD value of the collateral
     * @param _coll The amount of collateral
     * @param _price The price of the collateral
     * @return The USD value of the collateral
     */
    function _getUSDValue(uint _coll, uint _price) internal pure returns (uint) {
        uint usdValue = (_price * _coll) / DECIMAL_PRECISION;
        return usdValue;
    }

    /**
     * @dev Determines the collateral change amount and direction
     * @param _collReceived The amount of collateral received
     * @param _requestedCollWithdrawal The amount of collateral requested for withdrawal
     * @return collChange The amount of collateral change
     * @return isCollIncrease True if collateral is increasing, false if decreasing
     */
    function _getCollChange(
        uint _collReceived,
        uint _requestedCollWithdrawal
    )
    internal
    pure
    returns (uint collChange, bool isCollIncrease)
    {
        if (_collReceived != 0) {
            collChange = _collReceived;
            isCollIncrease = true;
        } else {
            collChange = _requestedCollWithdrawal;
        }
    }

    /**
     * @dev Updates a position's collateral and debt based on the adjustment
     * @param _positionManager The position manager contract
     * @param _borrower The address of the borrower
     * @param _collChange The amount of collateral change
     * @param _isCollIncrease True if collateral is increasing, false if decreasing
     * @param _debtChange The amount of debt change
     * @param _isDebtIncrease True if debt is increasing, false if decreasing
     * @return newColl The new collateral amount
     * @return newDebt The new debt amount
     */
    function _updatePositionFromAdjustment
    (
        IPositionManager _positionManager,
        address _borrower,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
    internal
    returns (uint, uint)
    {
        uint newColl = (_isCollIncrease) ? _positionManager.increasePositionColl(_borrower, _collChange)
            : _positionManager.decreasePositionColl(_borrower, _collChange);
        uint newDebt = (_isDebtIncrease) ? _positionManager.increasePositionDebt(_borrower, _debtChange)
            : _positionManager.decreasePositionDebt(_borrower, _debtChange);

        return (newColl, newDebt);
    }

    /**
     * @dev Moves tokens and collateral based on the position adjustment
     * @param collateral The collateral struct
     * @param _stableToken The stable token contract
     * @param _borrower The address of the borrower
     * @param vars The local variables for position adjustment
     * @param params The parameters for position adjustment
     */
    function _moveTokensAndCollateralFromAdjustment
    (
        ICollateralController.Collateral memory collateral,
        IStable _stableToken,
        address _borrower,
        LocalVariables_adjustPosition memory vars,
        AdjustPositionParams memory params
    )
    internal
    {
        if (params._isDebtIncrease) {
            (uint requiredEscrowDuration,) = collateralController.getLoanCooldownRequirement(address(collateral.asset), collateral.version);
            bool shouldEscrow = requiredEscrowDuration != 0;
            _withdrawStable(collateral.activePool, _stableToken, _borrower, params._stableChange, vars.netDebtChange, shouldEscrow, address(collateral.asset), collateral.version, vars.price);
        } else {
            _repayStables(collateral.activePool, _stableToken, _borrower, params._stableChange);
        }

        if (vars.isCollIncrease) {
            _activePoolAddColl(collateral, vars.collChange);
        } else {
            collateral.activePool.sendCollateral(_borrower, vars.collChange);
        }
    }

    /**
     * @dev Adds collateral to the Active Pool
     * @param collateral The collateral struct
     * @param _amount The amount of collateral to add
     */
    function _activePoolAddColl(ICollateralController.Collateral memory collateral, uint _amount) internal {
        collateral.asset.safeTransferFrom(msg.sender, address(collateral.activePool), _amount);
        collateral.activePool.receiveCollateral(address(collateral.asset), _amount);
    }

    /**
     * @dev Withdraws stable tokens and updates the active debt
     * @param _activePool The active pool contract
     * @param _stableToken The stable token contract
     * @param _account The account to receive the stable tokens
     * @param _stableAmount The amount of stable tokens to withdraw
     * @param _netDebtIncrease The net increase in debt
     * @param shouldEscrow Whether the withdrawn amount should be escrowed
     * @param asset The address of the collateral asset
     * @param version The version of the collateral
     * @param quotePrice The current price quote
     */
    function _withdrawStable(
        IActivePool _activePool,
        IStable _stableToken,
        address _account,
        uint _stableAmount,
        uint _netDebtIncrease,
        bool shouldEscrow,
        address asset,
        uint8 version,
        uint quotePrice
    ) internal {
        _activePool.increaseStableDebt(_netDebtIncrease);
        if (shouldEscrow) {
            require(
                assetToVersionToUserToEscrow[asset][version][_account].startTimestamp == 0,
                "Claim your escrowed stables before creating more debt"
            );

            LoanOriginationEscrow memory loe =
                            LoanOriginationEscrow(_account, asset, version, block.timestamp, _stableAmount, quotePrice, 0);

            assetToVersionToUserToEscrow[asset][version][_account] = loe;
        } else {
            _stableToken.mint(_account, _stableAmount);
        }
    }

    /**
     * @dev Repays stable tokens and decreases the active debt
     * @param _activePool The active pool contract
     * @param _stableToken The stable token contract
     * @param _account The account repaying the stable tokens
     * @param _stables The amount of stable tokens to repay
     */
    function _repayStables(IActivePool _activePool, IStable _stableToken, address _account, uint _stables) internal {
        _activePool.decreaseStableDebt(_stables);
        _stableToken.burn(_account, _stables);
    }

    /**
     * @dev Ensures that only one type of collateral change (withdrawal or addition) is performed
     * @param _collWithdrawal The amount of collateral withdrawal
     * @param _collAddition The amount of collateral addition
     */
    function _requireSingularCollChange(uint _collWithdrawal, uint _collAddition) internal pure {
        require(_collAddition == 0 || _collWithdrawal == 0, "PositionController: Cannot withdraw and add coll");
    }

    /**
     * @dev Ensures that at least one type of adjustment (collateral or debt) is being made
     * @param _collWithdrawal The amount of collateral withdrawal
     * @param _stableChange The amount of stable token change
     * @param _collAddition The amount of collateral addition
     */
    function _requireNonZeroAdjustment(uint _collWithdrawal, uint _stableChange, uint _collAddition) internal pure {
        require(
            _collAddition != 0 || _collWithdrawal != 0 || _stableChange != 0,
            "PositionController: There must be either a collateral change or a debt change"
        );
    }

    /**
     * @dev Ensures that the position is active
     * @param _positionManager The position manager contract
     * @param _borrower The address of the borrower
     */
    function _requirePositionIsActive(IPositionManager _positionManager, address _borrower) internal view {
        uint status = _positionManager.getPositionStatus(_borrower);
        require(status == 1, "PositionController: Position does not exist or is closed");
    }

    /**
     * @dev Ensures that the position is not active
     * @param _positionManager The position manager contract
     * @param _borrower The address of the borrower
     */
    function _requirePositionIsNotActive(IPositionManager _positionManager, address _borrower) internal view {
        uint status = _positionManager.getPositionStatus(_borrower);
        require(status != 1, "PositionController: Position is active");
    }

    /**
     * @dev Ensures that the debt change is non-zero
     * @param _stableChange The amount of stable token change
     */
    function _requireNonZeroDebtChange(uint _stableChange) internal pure {
        require(_stableChange > 0, "PositionController: Debt increase requires non-zero debtChange");
    }

    /**
     * @dev Ensures that no collateral withdrawal is performed in Recovery Mode
     * @param _collWithdrawal The amount of collateral withdrawal
     */
    function _requireNoCollWithdrawal(uint _collWithdrawal) internal pure {
        require(_collWithdrawal == 0, "PositionController: Collateral withdrawal not permitted Recovery Mode");
    }

    /**
     * @dev Validates the position adjustment based on the current mode (Normal or Recovery)
     * @param collateral The collateral struct
     * @param _isRecoveryMode Whether the system is in Recovery Mode
     * @param _collWithdrawal The amount of collateral withdrawal
     * @param _isDebtIncrease Whether the debt is increasing
     * @param _vars The local variables for position adjustment
     */
    function _requireValidAdjustmentInCurrentMode(
        ICollateralController.Collateral memory collateral,
        bool _isRecoveryMode,
        uint _collWithdrawal,
        bool _isDebtIncrease,
        LocalVariables_adjustPosition memory _vars
    )
    internal
    view
    {
        /*
        *In Recovery Mode, only allow:
        *
        * - Pure collateral top-up
        * - Pure debt repayment
        * - Collateral top-up with debt repayment
        * - A debt increase combined with a collateral top-up which makes the ICR >= 150% and improves the ICR (and by extension improves the TCR).
        *
        * In Normal Mode, ensure:
        *
        * - The new ICR is above MCR
        * - The adjustment won't pull the TCR below CCR
        */
        if (_isRecoveryMode) {
            _requireNoCollWithdrawal(_collWithdrawal);
            if (_isDebtIncrease) {
                _requireICRisAboveCCR(_vars.newICR, address(collateral.asset), collateral.version);
                _requireNewICRisAboveOldICR(_vars.newICR, _vars.oldICR);
            }
        } else { // if Normal Mode
            _requireICRisAboveMCR(_vars.newICR, address(collateral.asset), collateral.version);
            _vars.newTCR = _getNewTCRFromPositionChange(collateral, _vars.collChange, _vars.isCollIncrease, _vars.netDebtChange, _isDebtIncrease, _vars.price);
            _requireNewTCRisAboveCCR(_vars.newTCR, address(collateral.asset), collateral.version);
        }
    }

    /**
     * @dev Ensures that the new ICR is above the Minimum Collateralization Ratio (MCR)
     * @param _newICR The new Individual Collateralization Ratio
     * @param asset The address of the collateral asset
     * @param version The version of the collateral
     */
    function _requireICRisAboveMCR(uint _newICR, address asset, uint8 version) internal view {
        require(
            _newICR >= collateralController.getMCR(asset, version),
            "PositionController: An operation that would result in ICR < MCR is not permitted"
        );
    }

    /**
     * @dev Ensures that the new ICR is above the Critical Collateralization Ratio (CCR)
     * @param _newICR The new Individual Collateralization Ratio
     * @param asset The address of the collateral asset
     * @param version The version of the collateral
     */
    function _requireICRisAboveCCR(uint _newICR, address asset, uint8 version) internal view {
        require(
            _newICR >= collateralController.getCCR(asset, version),
            "PositionController: Operation must leave position with ICR >= CCR"
        );
    }

    /**
     * @dev Ensures that the new ICR is above the old ICR in Recovery Mode
     * @param _newICR The new Individual Collateralization Ratio
     * @param _oldICR The old Individual Collateralization Ratio
     */
    function _requireNewICRisAboveOldICR(uint _newICR, uint _oldICR) internal pure {
        require(_newICR >= _oldICR, "PositionController: Cannot decrease your Position's ICR in Recovery Mode");
    }

    /**
     * @dev Ensures that the new TCR is above the Critical Collateralization Ratio (CCR)
     * @param _newTCR The new Total Collateralization Ratio
     * @param asset The address of the collateral asset
     * @param version The version of the collateral
     */
    function _requireNewTCRisAboveCCR(uint _newTCR, address asset, uint8 version) internal view {
        require(
            _newTCR >= collateralController.getCCR(asset, version),
            "PositionController: An operation that would result in TCR < CCR is not permitted"
        );
    }

    /**
     * @dev Ensures that the net debt is at least the minimum allowed
     * @param _netDebt The net debt amount
     */
    function _requireAtLeastMinNetDebt(uint _netDebt) internal pure {
        require(_netDebt >= MIN_NET_DEBT, "PositionController: Position's net debt must be greater than minimum");
    }

    /**
     * @dev Validates that the stable repayment amount is valid
     * @param _currentDebt The current debt of the position
     * @param _debtRepayment The amount of debt to be repaid
     */
    function _requireValidStableRepayment(uint _currentDebt, uint _debtRepayment) internal pure {
        require(_debtRepayment <= (_currentDebt - GAS_COMPENSATION), "PositionController: Amount repaid must not be larger than the Position's debt");
    }

    /**
     * @dev Ensures that the caller is the Backstop Pool
     */
    function _requireCallerIsBackstopPool() internal view {
        require(msg.sender == backstopPoolAddress, "PositionController: Caller is not Backstop Pool");
    }

    /**
     * @dev Checks if the borrower has sufficient stable balance for repayment
     * @param _stableToken The stable token contract
     * @param _borrower The address of the borrower
     * @param _debtRepayment The amount of debt to be repaid
     */
    function _requireSufficientStableBalance(IStable _stableToken, address _borrower, uint _debtRepayment) internal view {
        require(_stableToken.balanceOf(_borrower) >= _debtRepayment, "PositionController: Caller doesn't have enough stable to make repayment");
    }

    /**
     * @dev Validates the maximum fee percentage based on the current mode and suggested fee
     * @param _maxFeePercentage The maximum fee percentage specified by the user
     * @param _isRecoveryMode Whether the system is in Recovery Mode
     * @param asset The address of the collateral asset
     * @param version The version of the collateral
     * @param suggestedFeePCT The suggested fee percentage
     */
    function _requireValidMaxFeePercentage(uint _maxFeePercentage, bool _isRecoveryMode, address asset, uint8 version, uint suggestedFeePCT) internal view {
        uint minBorrowingFeePct = collateralController.getMinBorrowingFeePct(asset, version);

        if (_isRecoveryMode) {
            require(_maxFeePercentage <= DECIMAL_PRECISION, "Max fee percentage must less than or equal to 100%");
        } else {
            uint floor = StableMath._max(DYNAMIC_BORROWING_FEE_FLOOR, minBorrowingFeePct) + suggestedFeePCT;
            bool effectiveFeeAccepted = _maxFeePercentage >= floor && _maxFeePercentage <= DECIMAL_PRECISION;
            require(effectiveFeeAccepted, "Max fee percentage must be between 0.5% and 100%");
        }
    }

    /**
     * @dev Computes the new nominal ICR (Individual Collateralization Ratio) after a position change
     * @param _coll Current collateral amount
     * @param _debt Current debt amount
     * @param _collChange Amount of collateral change
     * @param _isCollIncrease True if collateral is increasing, false if decreasing
     * @param _debtChange Amount of debt change
     * @param _isDebtIncrease True if debt is increasing, false if decreasing
     * @param decimals Decimals of the collateral asset
     * @return The new nominal ICR
     */
    function _getNewNominalICRFromPositionChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint8 decimals
    )
    pure
    internal
    returns (uint)
    {
        (uint newColl, uint newDebt) = _getNewPositionAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);
        return StableMath._computeNominalCR(newColl, newDebt, decimals);
    }

    /**
     * @dev Computes the new ICR (Individual Collateralization Ratio) after a position change
     * @param _coll Current collateral amount
     * @param _debt Current debt amount
     * @param _collChange Amount of collateral change
     * @param _isCollIncrease True if collateral is increasing, false if decreasing
     * @param _debtChange Amount of debt change
     * @param _isDebtIncrease True if debt is increasing, false if decreasing
     * @param _price Current price of the collateral
     * @param _collateralDecimals Decimals of the collateral asset
     * @return The new ICR
     */
    function _getNewICRFromPositionChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price,
        uint8 _collateralDecimals
    )
    pure
    internal
    returns (uint)
    {
        (uint newColl, uint newDebt) = _getNewPositionAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);
        return StableMath._computeCR(newColl, newDebt, _price, _collateralDecimals);
    }

    /**
     * @dev Calculates new collateral and debt amounts after a position change
     * @param _coll Current collateral amount
     * @param _debt Current debt amount
     * @param _collChange Amount of collateral change
     * @param _isCollIncrease True if collateral is increasing, false if decreasing
     * @param _debtChange Amount of debt change
     * @param _isDebtIncrease True if debt is increasing, false if decreasing
     * @return New collateral amount and new debt amount
     */
    function _getNewPositionAmounts(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
    internal
    pure
    returns (uint, uint)
    {
        uint newColl = _coll;
        uint newDebt = _debt;

        newColl = _isCollIncrease ? _coll + _collChange : _coll - _collChange;
        newDebt = _isDebtIncrease ? _debt + _debtChange : _debt - _debtChange;

        return (newColl, newDebt);
    }

    /**
     * @dev Calculates the new TCR (Total Collateralization Ratio) after a position change
     * @param collateral Struct containing collateral information
     * @param _collChange Amount of collateral change
     * @param _isCollIncrease True if collateral is increasing, false if decreasing
     * @param _debtChange Amount of debt change
     * @param _isDebtIncrease True if debt is increasing, false if decreasing
     * @param _price Current price of the collateral
     * @return The new TCR
     */
    function _getNewTCRFromPositionChange
    (
        ICollateralController.Collateral memory collateral,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    )
    internal
    view
    returns (uint)
    {
        uint totalColl = collateralController.getAssetColl(address(collateral.asset), collateral.version);
        uint totalDebt = collateralController.getAssetDebt(address(collateral.asset), collateral.version);

        totalColl = _isCollIncrease ? totalColl + _collChange : totalColl - _collChange;
        totalDebt = _isDebtIncrease ? totalDebt + _debtChange : totalDebt - _debtChange;

        uint newTCR = StableMath._computeCR(totalColl, totalDebt, _price, collateral.asset.decimals());
        return newTCR;
    }

    /**
     * @dev Ensures that the new debt does not exceed the debt cap for the collateral
     * @param collateral Struct containing collateral information
     * @param _debtChange Amount of debt change
     */
    function _requireDoesNotExceedCap(ICollateralController.Collateral memory collateral, uint _debtChange) internal view {
        uint totalDebt = collateralController.getAssetDebt(address(collateral.asset), collateral.version);
        require(
            totalDebt + _debtChange <= collateralController.getDebtCap(address(collateral.asset), collateral.version),
            "PositionController: Debt would exceed current debt cap"
        );
    }

    /**
     * @dev Ensures that the collateral is not in the process of being decommissioned
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     */
    function _requireNotSunsetting(address asset, uint8 version) internal view {
        require(!collateralController.isDecommissioned(asset, version), "PositionController: Collateral is sunsetting");
    }

    /**
     * @dev Calculates the composite debt (user debt + gas compensation)
     * @param _debt User debt amount
     * @return Composite debt amount
     */
    function getCompositeDebt(uint _debt) external view override returns (uint) {
        return _debt + GAS_COMPENSATION;
    }
}