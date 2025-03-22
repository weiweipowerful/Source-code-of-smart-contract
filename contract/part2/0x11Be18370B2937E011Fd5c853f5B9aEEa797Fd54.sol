// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../common/Base.sol";
import "../common/StableMath.sol";
import "../Guardable.sol";
import "../interfaces/IBackstopPool.sol";
import "../interfaces/IRecoverable.sol";
import "../interfaces/ICollateralController.sol";
import "../interfaces/IPositionController.sol";
import "../incentives/BackstopPoolIncentives.sol";
import "../interfaces/IStable.sol";

/**
 * @title BackstopPool
 * @dev Contract for managing a backstop pool in a DeFi system.
 *
 * Key features:
 *   1. Deposit Management: Handles deposits of stable tokens into the backstop pool.
 *   2. Collateral Tracking: Tracks multiple types of collateral assets.
 *   3. Incentive Distribution: Manages the distribution of fee tokens as incentives.
 *   4. Position Offsetting: Allows for offsetting of positions with collateral and debt.
 *   5. Compound Interest: Implements a compound interest mechanism for deposits.
 *   6. Snapshots: Maintains snapshots of user deposits and global state for accurate reward calculations.
 */
contract BackstopPool is Base, Ownable, Guardable, IBackstopPool, IRecoverable {
    string constant public NAME = "BackstopPool";

    // External contract interfaces
    ICollateralController public collateralController;
    IPositionController public positionController;
    IStable public stableToken;
    IBackstopPoolIncentives public incentivesIssuance;

    // Total deposits in the pool
    uint256 internal totalStableDeposits;

    /**
     * @dev Struct to hold collateral totals and related data
     */
    struct CollateralTotals {
        uint256 total;
        mapping(uint128 => mapping(uint128 => uint)) epochToScaleToSum;
        uint lastCollateralError_Offset;
    }

    // Mappings for tracking rewards and collateral
    mapping(uint128 => mapping(uint128 => uint)) public epochToScaleToG;
    mapping(address => CollateralTotals) public collateralToTotals;

    /**
     * @dev Struct to represent a user's deposit
     */
    struct Deposit {
        uint initialValue;
    }

    /**
     * @dev Struct to hold snapshot data for deposits
     */
    struct Snapshots {
        mapping(address => uint) S;
        uint P;
        uint G;
        uint128 scale;
        uint128 epoch;
    }

    // Mappings for user deposits and snapshots
    mapping(address => Deposit) public deposits;
    mapping(address => Snapshots) public depositSnapshots;

    // Global state variables
    uint public P = DECIMAL_PRECISION;
    uint public constant SCALE_FACTOR = 1e9;
    uint128 public currentScale;
    uint128 public currentEpoch;

    // Error tracking for fee token and stable loss
    uint public lastFeeTokenError;
    uint public lastStableLossError_Offset;

    /**
     * @dev Sets the addresses for various components of the system
     * @param _collateralController Address of the collateral controller
     * @param _stableTokenAddress Address of the stable token
     * @param _positionController Address of the position controller
     * @param _incentivesIssuance Address of the incentives issuance contract
     */
    function setAddresses(
        address _collateralController,
        address _stableTokenAddress,
        address _positionController,
        address _incentivesIssuance
    ) external onlyOwner {
        collateralController = ICollateralController(_collateralController);
        incentivesIssuance = IBackstopPoolIncentives(_incentivesIssuance);
        stableToken = IStable(_stableTokenAddress);
        positionController = IPositionController(_positionController);
        renounceOwnership();
    }

    /**
     * @dev Gets the total amount of a specific collateral in the pool
     * @param collateral Address of the collateral token
     * @return The total amount of the specified collateral
     */
    function getCollateral(address collateral) external view override returns (uint) {
        return collateralToTotals[collateral].total;
    }

    /**
     * @dev Gets the total amount of stable token deposits in the pool
     * @return The total amount of stable token deposits
     */
    function getTotalStableDeposits() external view override returns (uint) {
        return totalStableDeposits;
    }

    /**
     * @dev Allows a user to provide funds to the backstop pool
     * @param _amount The amount of stable tokens to deposit
     */
    function provideToBP(uint _amount) external override {
        _requireNonZeroAmount(_amount);
        uint initialDeposit = deposits[msg.sender].initialValue;

        IBackstopPoolIncentives incentiveIssuanceCached = incentivesIssuance;
        _triggerFeeTokenIssuance(incentiveIssuanceCached);

        uint compoundedStableDeposit = getCompoundedStableDeposit(msg.sender);
        uint StableLoss = initialDeposit - compoundedStableDeposit;

        _payOutFeeTokenGains(incentiveIssuanceCached, msg.sender);
        _sendStableToBackstopPool(msg.sender, _amount);

        uint newDeposit = compoundedStableDeposit + _amount;
        CollateralGain[] memory depositorCollateralGains =
                        _calculateGainsAndUpdateSnapshots(msg.sender, newDeposit, false, address(0), 0, address(0), address(0));

        emit UserDepositChanged(msg.sender, newDeposit);
        emit CollateralGainsWithdrawn(msg.sender, depositorCollateralGains, StableLoss);
    }

    /**
     * @dev Allows a user to withdraw funds from the backstop pool
     * @param _amount The amount of stable tokens to withdraw
     */
    function withdrawFromBP(uint _amount) external override {
        if (_amount != 0) {
            _requireNoUnderCollateralizedPositions();
        }

        uint initialDeposit = deposits[msg.sender].initialValue;
        _requireUserHasDeposit(initialDeposit);

        IBackstopPoolIncentives incentiveIssuanceCached = incentivesIssuance;
        _triggerFeeTokenIssuance(incentiveIssuanceCached);

        uint compoundedStableDeposit = getCompoundedStableDeposit(msg.sender);
        uint StabletoWithdraw = StableMath._min(_amount, compoundedStableDeposit);
        uint StableLoss = initialDeposit - compoundedStableDeposit;

        _payOutFeeTokenGains(incentiveIssuanceCached, msg.sender);
        _sendStableToDepositor(msg.sender, StabletoWithdraw);

        uint newDeposit = compoundedStableDeposit - StabletoWithdraw;

        CollateralGain[] memory depositorCollateralGains =
                        _calculateGainsAndUpdateSnapshots(msg.sender, newDeposit, false, address(0), 0, address(0), address(0));

        emit UserDepositChanged(msg.sender, newDeposit);
        emit CollateralGainsWithdrawn(msg.sender, depositorCollateralGains, StableLoss);
    }

    /**
     * @dev Internal function to calculate gains and update snapshots
     * @param depositor Address of the depositor
     * @param newDeposit New deposit amount
     * @param withdrawingToPosition Flag indicating if withdrawing to a position
     * @param asset Address of the asset
     * @param version Version of the asset
     * @param _upperHint Upper hint for position
     * @param _lowerHint Lower hint for position
     * @return depositorCollateralGains Array of collateral gains
     */
    function _calculateGainsAndUpdateSnapshots(
        address depositor, uint newDeposit,
        bool withdrawingToPosition,
        address asset, uint8 version, address _upperHint, address _lowerHint
    ) private returns (CollateralGain[] memory depositorCollateralGains) {
        depositorCollateralGains = getDepositorCollateralGains(depositor);
        _updateDepositAndSnapshots(depositor, newDeposit);

        for (uint idx = 0; idx < depositorCollateralGains.length; idx++) {
            CollateralGain memory gain = depositorCollateralGains[idx];

            if (gain.gains == 0) {
                if (withdrawingToPosition && depositorCollateralGains[idx].asset == asset) {
                    revert("BackstopPool: caller must have non-zero Collateral Gain");
                }
                continue;
            }

            collateralToTotals[gain.asset].total -= gain.gains;
            emit BackstopPoolCollateralBalanceUpdated(gain.asset, collateralToTotals[gain.asset].total);
            emit CollateralSent(gain.asset, depositor, gain.gains);

            if (withdrawingToPosition && depositorCollateralGains[idx].asset == asset) {
                IERC20(asset).approve(address(positionController), gain.gains);
                positionController.moveCollateralGainToPosition(asset, version, gain.gains, depositor, _upperHint, _lowerHint);
            } else {
                require(IERC20(gain.asset).transfer(depositor, gain.gains), "BackstopPool: sending Collateral failed");
            }
        }
    }

    /**
     * @dev Allows a user to withdraw collateral gain to a position
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     * @param _upperHint Upper hint for position
     * @param _lowerHint Lower hint for position
     */
    function withdrawCollateralGainToPosition(address asset, uint8 version, address _upperHint, address _lowerHint) external override {
        uint initialDeposit = deposits[msg.sender].initialValue;
        _requireUserHasDeposit(initialDeposit);
        _requireUserHasPosition(asset, version, msg.sender);

        IBackstopPoolIncentives incentiveIssuanceCached = incentivesIssuance;
        _triggerFeeTokenIssuance(incentiveIssuanceCached);

        uint compoundedStableDeposit = getCompoundedStableDeposit(msg.sender);
        uint StableLoss = initialDeposit - compoundedStableDeposit;

        _payOutFeeTokenGains(incentiveIssuanceCached, msg.sender);

        CollateralGain[] memory depositorCollateralGains =
                        _calculateGainsAndUpdateSnapshots(msg.sender, compoundedStableDeposit, true, asset, version, _upperHint, _lowerHint);

        emit UserDepositChanged(msg.sender, compoundedStableDeposit);
        emit CollateralGainsWithdrawn(msg.sender, depositorCollateralGains, StableLoss);
    }

    /**
     * @dev Offsets a position with collateral and debt
     * @param collateralAsset Address of the collateral asset
     * @param version Version of the collateral
     * @param _debtToOffset Amount of debt to offset
     * @param _collToAdd Amount of collateral to add
     */
    function offset(address collateralAsset, uint8 version, uint _debtToOffset, uint _collToAdd) external override {
        _requireCallerIsPositionManager(collateralAsset, version);
        uint totalStable = totalStableDeposits;
        if (totalStable == 0 || _debtToOffset == 0) {
            return;
        }

        _triggerFeeTokenIssuance(incentivesIssuance);

        (uint CollateralGainPerUnitStaked, uint StableLossPerUnitStaked) =
                        _computeRewardsPerUnitStaked(collateralAsset, _collToAdd, _debtToOffset, totalStable);

        _updateRewardSumAndProduct(collateralAsset, CollateralGainPerUnitStaked, StableLossPerUnitStaked);
        _moveOffsetCollAndDebt(collateralController.getCollateralInstance(collateralAsset, version), _collToAdd, _debtToOffset);
    }

    /**
     * @dev Computes rewards per unit staked
     * @param collateralAsset Address of the collateral asset
     * @param _collToAdd Amount of collateral to add
     * @param _debtToOffset Amount of debt to offset
     * @param _totalStableDeposits Total stable deposits
     * @return CollateralGainPerUnitStaked Collateral gain per unit staked
     * @return stableLossPerUnitStaked Stable loss per unit staked
     */
    function _computeRewardsPerUnitStaked(
        address collateralAsset,
        uint _collToAdd,
        uint _debtToOffset,
        uint _totalStableDeposits
    ) internal returns (uint CollateralGainPerUnitStaked, uint stableLossPerUnitStaked) {
        uint CollateralNumerator = (_collToAdd * DECIMAL_PRECISION) + collateralToTotals[collateralAsset].lastCollateralError_Offset;
        assert(_debtToOffset <= _totalStableDeposits);

        if (_debtToOffset == _totalStableDeposits) {
            stableLossPerUnitStaked = DECIMAL_PRECISION;
            lastStableLossError_Offset = 0;
        } else {
            uint stableLossNumerator = (_debtToOffset * DECIMAL_PRECISION) - lastStableLossError_Offset;
            stableLossPerUnitStaked = (stableLossNumerator / _totalStableDeposits) + 1;
            lastStableLossError_Offset = (stableLossPerUnitStaked * _totalStableDeposits) - stableLossNumerator;
        }

        CollateralGainPerUnitStaked = CollateralNumerator / _totalStableDeposits;
        collateralToTotals[collateralAsset].lastCollateralError_Offset = CollateralNumerator - (CollateralGainPerUnitStaked * _totalStableDeposits);

        return (CollateralGainPerUnitStaked, stableLossPerUnitStaked);
    }

    /**
     * @dev Updates reward sum and product
     * @param collateralAsset Address of the collateral asset
     * @param _CollateralGainPerUnitStaked Collateral gain per unit staked
     * @param _stableLossPerUnitStaked Stable loss per unit staked
     */
    function _updateRewardSumAndProduct(address collateralAsset, uint _CollateralGainPerUnitStaked, uint _stableLossPerUnitStaked) internal {
        uint currentP = P;
        uint newP;

        assert(_stableLossPerUnitStaked <= DECIMAL_PRECISION);
        uint newProductFactor = uint(DECIMAL_PRECISION) - _stableLossPerUnitStaked;

        uint128 currentScaleCached = currentScale;
        uint128 currentEpochCached = currentEpoch;

        uint currentS = collateralToTotals[collateralAsset].epochToScaleToSum[currentEpochCached][currentScaleCached];
        uint marginalCollateralGain = _CollateralGainPerUnitStaked * currentP;
        uint newS = currentS + marginalCollateralGain;
        collateralToTotals[collateralAsset].epochToScaleToSum[currentEpochCached][currentScaleCached] = newS;
        emit S_Updated(collateralAsset, newS, currentEpochCached, currentScaleCached);

        if (newProductFactor == 0) {
            currentEpoch = currentEpochCached + 1;
            emit EpochUpdated(currentEpoch);
            currentScale = 0;
            emit ScaleUpdated(currentScale);
            newP = DECIMAL_PRECISION;
        } else if (((currentP * newProductFactor) / DECIMAL_PRECISION) < SCALE_FACTOR) {
            newP = ((currentP * newProductFactor) * SCALE_FACTOR) / DECIMAL_PRECISION;
            currentScale = currentScaleCached + 1;
            emit ScaleUpdated(currentScale);
        } else {
            newP = (currentP * newProductFactor) / DECIMAL_PRECISION;
        }

        assert(newP > 0);
        P = newP;

        emit P_Updated(newP);
    }

    /**
     * @dev Extracts orphaned tokens from the contract
     * @param asset Address of the token to extract
     * @param version Version of the token
     */
    function extractOrphanedTokens(address asset, uint8 version) external override onlyGuardian {
        require(asset != address(stableToken), "Naughty...");

        address[] memory collaterals = collateralController.getUniqueActiveCollateralAddresses();
        for (uint idx; idx < collaterals.length; idx++) {
            // Should not be able to extract tokens in the contract which are under normal operation.
            // Only tokens which are not claimed by users before sunset can be extracted,
            // or tokens which are accidentally sent to the contract.
            require(collaterals[idx] != asset, "Guardian can only extract non-active tokens");
        }

        IERC20 orphan = IERC20(asset);
        orphan.transfer(guardian(), orphan.balanceOf(address(this)));
    }

    /**
     * @dev Moves offset collateral and debt
     * @param collateral Collateral instance
     * @param _collToAdd Amount of collateral to add
     * @param _debtToOffset Amount of debt to offset
     */
    function _moveOffsetCollAndDebt(ICollateralController.Collateral memory collateral, uint _collToAdd, uint _debtToOffset) internal {
        IActivePool activePoolCached = collateral.activePool;
        activePoolCached.decreaseStableDebt(_debtToOffset);
        _decreaseStable(_debtToOffset);
        stableToken.burn(address(this), _debtToOffset);
        activePoolCached.sendCollateral(address(this), _collToAdd);
        collateralToTotals[address(collateral.asset)].total += _collToAdd;
        emit BackstopPoolCollateralBalanceUpdated(address(collateral.asset), collateralToTotals[address(collateral.asset)].total);
    }

    /**
     * @dev Decreases the total stable deposits
     * @param _amount Amount to decrease
     */
    function _decreaseStable(uint _amount) internal {
        uint newTotalStableDeposits = totalStableDeposits - _amount;
        totalStableDeposits = newTotalStableDeposits;
        emit BackstopPoolStableBalanceUpdated(newTotalStableDeposits);
    }

    /**
     * @dev Gets the collateral gains for a depositor
     * @param _depositor Address of the depositor
     * @return An array of CollateralGain structs
     */
    function getDepositorCollateralGains(address _depositor) public view override returns (IBackstopPool.CollateralGain[] memory) {
        uint P_Snapshot = depositSnapshots[_depositor].P;
        uint128 epochSnapshot = depositSnapshots[_depositor].epoch;
        uint128 scaleSnapshot = depositSnapshots[_depositor].scale;

        uint initialDeposit = deposits[_depositor].initialValue;
        if (initialDeposit == 0) {return new IBackstopPool.CollateralGain[](0);}

        address[] memory collaterals = collateralController.getUniqueActiveCollateralAddresses();
        IBackstopPool.CollateralGain[] memory gains = new IBackstopPool.CollateralGain[](collaterals.length);

        for (uint idx; idx < collaterals.length; idx++) {
            CollateralTotals storage c = collateralToTotals[collaterals[idx]];

            uint S_Snapshot = depositSnapshots[_depositor].S[collaterals[idx]];
            uint firstPortion = c.epochToScaleToSum[epochSnapshot][scaleSnapshot] - S_Snapshot;
            uint secondPortion = c.epochToScaleToSum[epochSnapshot][scaleSnapshot + 1] / SCALE_FACTOR;
            uint gain = ((initialDeposit * (firstPortion + secondPortion)) / P_Snapshot) / DECIMAL_PRECISION;

            gains[idx] = CollateralGain(collaterals[idx], gain);
        }

        return gains;
    }

    /**
     * @dev Gets the collateral gain for a specific depositor and asset
     * @param asset Address of the collateral asset
     * @param _depositor Address of the depositor
     * @return The amount of collateral gain
     */
    function getDepositorCollateralGain(address asset, address _depositor) external view returns (uint) {
        IBackstopPool.CollateralGain[] memory gains = getDepositorCollateralGains(_depositor);
        for (uint idx; idx < gains.length; idx++) {
            if (gains[idx].asset == asset) {
                return gains[idx].gains;
            }
        }
        return 0;
    }

    /**
     * @dev Gets the sum for a specific epoch and scale
     * @param asset Address of the collateral asset
     * @param epoch Epoch number
     * @param scale Scale number
     * @return The sum for the given epoch and scale
     */
    function getEpochToScaleToSum(address asset, uint128 epoch, uint128 scale) external override view returns (uint) {
        return collateralToTotals[asset].epochToScaleToSum[epoch][scale];
    }

    /**
     * @dev Gets the sum from the deposit snapshot for a specific user and asset
     * @param user Address of the user
     * @param asset Address of the collateral asset
     * @return The sum from the deposit snapshot
     */
    function getDepositSnapshotToAssetToSum(address user, address asset) external view returns (uint) {
        return depositSnapshots[user].S[asset];
    }

    /**
     * @dev Calculates the compounded stable deposit for a depositor
     * @param _depositor Address of the depositor
     * @return The compounded stable deposit amount
     */
    function getCompoundedStableDeposit(address _depositor) public view override returns (uint) {
        uint initialDeposit = deposits[_depositor].initialValue;
        if (initialDeposit == 0) {return 0;}

        uint snapshot_P = depositSnapshots[_depositor].P;
        uint128 scaleSnapshot = depositSnapshots[_depositor].scale;
        uint128 epochSnapshot = depositSnapshots[_depositor].epoch;

        if (epochSnapshot < currentEpoch) {return 0;}

        uint compoundedStake;
        uint128 scaleDiff = currentScale - scaleSnapshot;

        if (scaleDiff == 0) {
            compoundedStake = (initialDeposit * P) / snapshot_P;
        } else if (scaleDiff == 1) {
            compoundedStake = ((initialDeposit * P) / (snapshot_P)) / SCALE_FACTOR;
        } else {
            compoundedStake = 0;
        }

        return (compoundedStake < (initialDeposit / 1e9)) ? 0 : compoundedStake;
    }

    /**
     * @dev Sends stable tokens to the backstop pool
     * @param _address Address to send from
     * @param _amount Amount to send
     */
    function _sendStableToBackstopPool(address _address, uint _amount) internal {
        stableToken.sendToPool(_address, address(this), _amount);
        uint newTotalStableDeposits = totalStableDeposits + _amount;
        totalStableDeposits = newTotalStableDeposits;
        emit BackstopPoolStableBalanceUpdated(newTotalStableDeposits);
    }

    /**
     * @dev Sends stable tokens to a depositor
     * @param _depositor Address of the depositor
     * @param stableWithdrawal Amount to withdraw
     */
    function _sendStableToDepositor(address _depositor, uint stableWithdrawal) internal {
        if (stableWithdrawal == 0) {
            return;
        }
        stableToken.returnFromPool(address(this), _depositor, stableWithdrawal);
        _decreaseStable(stableWithdrawal);
    }

    /**
     * @dev Updates deposit and snapshots for a user
     * @param _depositor Address of the depositor
     * @param _newValue New deposit value
     */
    function _updateDepositAndSnapshots(address _depositor, uint _newValue) internal {
        deposits[_depositor].initialValue = _newValue;
        address[] memory collaterals = collateralController.getUniqueActiveCollateralAddresses();

        if (_newValue == 0) {
            delete depositSnapshots[_depositor];
            for (uint idx; idx < collaterals.length; idx++) {
                depositSnapshots[_depositor].S[collaterals[idx]] = 0;
            }
            emit DepositSnapshotUpdated(_depositor, address(0), 0, 0, 0);
            return;
        }

        uint128 currentScaleCached = currentScale;
        uint128 currentEpochCached = currentEpoch;
        uint currentG = epochToScaleToG[currentEpochCached][currentScaleCached];
        uint currentP = P;

        for (uint idx; idx < collaterals.length; idx++) {
            CollateralTotals storage c = collateralToTotals[collaterals[idx]];
            uint currentS = c.epochToScaleToSum[currentEpochCached][currentScaleCached];
            depositSnapshots[_depositor].S[collaterals[idx]] = currentS;
            emit DepositSnapshotUpdated(_depositor, collaterals[idx], currentP, currentS, currentG);
        }

        depositSnapshots[_depositor].P = currentP;
        depositSnapshots[_depositor].G = currentG;
        depositSnapshots[_depositor].scale = currentScaleCached;
        depositSnapshots[_depositor].epoch = currentEpochCached;
    }

    /**
     * @dev Triggers fee token issuance
     * @param _incentivesIssuance Address of the incentives issuance contract
     */
    function _triggerFeeTokenIssuance(IBackstopPoolIncentives _incentivesIssuance) internal {
        uint feeTokenIssuance = _incentivesIssuance.issueFeeTokens();
        _updateG(feeTokenIssuance);
    }

    /**
     * @dev Updates the G value
     * @param _feeTokenIssuance Amount of fee tokens issued
     */
    function _updateG(uint _feeTokenIssuance) internal {
        uint totalStable = totalStableDeposits; // cached to save an SLOAD
        /*
        * When total deposits is 0, G is not updated. In this case, the feeToken issued can not be obtained by later
        * depositors - it is missed out on, and remains in the balanceOf the IncentivesIssuance contract.
        */
        if (totalStable == 0 || _feeTokenIssuance == 0) {return;}

        uint feeTokenPerUnitStaked = _computeFeeTokenPerUnitStaked(_feeTokenIssuance, totalStable);
        uint marginalFeeTokenGain = feeTokenPerUnitStaked * P;
        epochToScaleToG[currentEpoch][currentScale] = epochToScaleToG[currentEpoch][currentScale] + marginalFeeTokenGain;

        emit G_Updated(epochToScaleToG[currentEpoch][currentScale], currentEpoch, currentScale);
    }

    /**
     * @dev Computes fee token per unit staked
     * @param _feeTokenIssuance Amount of fee tokens issued
     * @param _totalStableDeposits Total stable deposits
     * @return The computed fee token per unit staked
     */
    function _computeFeeTokenPerUnitStaked(uint _feeTokenIssuance, uint _totalStableDeposits) internal returns (uint) {
        /*
        * Calculate the feeToken-per-unit staked.  Division uses a "feedback" error correction, to keep the
        * cumulative error low in the running total G:
        *
        * 1) Form a numerator which compensates for the floor division error that occurred the last time this
        * function was called.
        * 2) Calculate "per-unit-staked" ratio.
        * 3) Multiply the ratio back by its denominator, to reveal the current floor division error.
        * 4) Store this error for use in the next correction when this function is called.
        * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
        */
        uint feeTokenNumerator = (_feeTokenIssuance * DECIMAL_PRECISION) + lastFeeTokenError;

        uint feeTokenPerUnitStaked = feeTokenNumerator / _totalStableDeposits;
        lastFeeTokenError = feeTokenNumerator - (feeTokenPerUnitStaked * _totalStableDeposits);

        return feeTokenPerUnitStaked;
    }

    /**
     * @dev Calculates the fee token gain for a depositor
     * @param _depositor Address of the depositor
     * @return The calculated fee token gain
     */
    function getDepositorFeeTokenGain(address _depositor) public view override returns (uint) {
        uint initialDeposit = deposits[_depositor].initialValue;
        if (initialDeposit == 0) {return 0;}
        Snapshots storage snapshots = depositSnapshots[_depositor];
        return (DECIMAL_PRECISION * (_getFeeTokenGainFromSnapshots(initialDeposit, snapshots))) / DECIMAL_PRECISION;
    }

    /**
     * @dev Gets the fee token gain from snapshots
     * @param initialStake Initial stake amount
     * @param snapshots Snapshots struct
     * @return The calculated fee token gain
     */
    function _getFeeTokenGainFromSnapshots(uint initialStake, Snapshots storage snapshots) internal view returns (uint) {
        /*
         * Grab the sum 'G' from the epoch at which the stake was made. The feeToken gain may span up to one scale change.
         * If it does, the second portion of the feeToken gain is scaled by 1e9.
         * If the gain spans no scale change, the second portion will be 0.
         */
        uint128 epochSnapshot = snapshots.epoch;
        uint128 scaleSnapshot = snapshots.scale;
        uint G_Snapshot = snapshots.G;
        uint P_Snapshot = snapshots.P;

        uint firstPortion = epochToScaleToG[epochSnapshot][scaleSnapshot] - G_Snapshot;
        uint secondPortion = epochToScaleToG[epochSnapshot][scaleSnapshot + 1] / SCALE_FACTOR;

        return ((initialStake * (firstPortion + secondPortion)) / P_Snapshot) / DECIMAL_PRECISION;
    }

    /**
     * @dev Pays out fee token gains to a depositor
     * @param _incentivesIssuance Incentives issuance contract
     * @param _depositor Address of the depositor
     */
    function _payOutFeeTokenGains(IBackstopPoolIncentives _incentivesIssuance, address _depositor) internal {
        uint depositorFeeTokenGain = getDepositorFeeTokenGain(_depositor);
        _incentivesIssuance.sendFeeTokens(_depositor, depositorFeeTokenGain);
        emit FeeTokenPaidToDepositor(_depositor, depositorFeeTokenGain);
    }

    /**
     * @dev Checks if the caller is the position manager for the given collateral and version
     * @param collateralAsset Address of the collateral asset
     * @param version Version of the collateral
     */
    function _requireCallerIsPositionManager(address collateralAsset, uint8 version) internal view {
        require(
            msg.sender == address(collateralController.getCollateralInstance(collateralAsset, version).positionManager),
            "BackstopPool: Caller is not a PositionManager"
        );
    }

    /**
     * @dev Checks if there are no under-collateralized positions
     */
    function _requireNoUnderCollateralizedPositions() internal {
        collateralController.requireNoUnderCollateralizedPositions();
    }

    /**
     * @dev Checks if a user has a deposit
     * @param _initialDeposit Initial deposit amount
     */
    function _requireUserHasDeposit(uint _initialDeposit) internal pure {
        require(_initialDeposit > 0, 'BackstopPool: User must have a non-zero deposit');
    }

    /**
     * @dev Checks if the amount is non-zero
     * @param _amount Amount to check
     */
    function _requireNonZeroAmount(uint _amount) internal pure {
        require(_amount > 0, 'BackstopPool: Amount must be non-zero');
    }

    /**
     * @dev Checks if a user has an active position for the given asset and version
     * @param asset Address of the collateral asset
     * @param version Version of the collateral
     * @param _depositor Address of the depositor
     */
    function _requireUserHasPosition(address asset, uint8 version, address _depositor) internal view {
        require(
            collateralController.getCollateralInstance(asset, version).positionManager.getPositionStatus(_depositor) == 1,
            "BackstopPool: caller must have an active position to withdraw CollateralGain to"
        );
    }
}