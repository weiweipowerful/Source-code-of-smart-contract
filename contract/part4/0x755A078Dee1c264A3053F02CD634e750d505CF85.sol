// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { IVault } from "./interfaces/IVault.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract DelayedWithdraw is Auth, ReentrancyGuard {
  using SafeERC20 for IERC20Metadata;
  using SafeERC20 for ERC20;
  using FixedPointMathLib for uint256;

  // ========================================= STRUCTS =========================================

  /**
   * @param allowWithdraws Whether or not withdrawals are allowed for this asset.
   * @param withdrawDelay The delay in seconds before a requested withdrawal can be completed.
   * @param outstandingShares The total number of shares that are currently outstanding for an asset.
   * @param withdrawFee The fee that is charged when a withdrawal is completed.
   * @param maxLoss The maximum loss that can be incurred when completing a withdrawal, evaluating the
   *                exchange rate at time of withdraw, compared to time of completion.
   * @param maxWithdrawPerUser maximum withdraw per user
   */
  struct WithdrawAsset {
    bool allowWithdraws;
    uint32 withdrawDelay;
    uint128 outstandingShares;
    uint16 withdrawFee;
    uint16 maxLoss;
    uint256 maxWithdrawPerUser;
  }

  /**
   * @param allowThirdPartyToComplete Whether or not a 3rd party can complete a withdraw on behalf of a user.
   * @param maturity The time at which the withdrawal can be completed.
   * @param shares The number of shares that are requested to be withdrawn.
   * @param assetsAtTimeOfRequest The exchange rate at the time of the request.
   */
  struct WithdrawRequest {
    bool allowThirdPartyToComplete;
    uint40 maturity;
    uint96 shares;
    uint256 assetsAtTimeOfRequest;
  }

  struct WithdrawUserRequests {
    mapping(uint256 => WithdrawRequest) requests;
    uint256[] keys;
    uint256 lastIdx;
  }

  // ========================================= CONSTANTS =========================================

  /**
   * @notice The largest withdraw fee that can be set.
   */
  uint16 internal constant MAX_WITHDRAW_FEE = 0.2e4;

  /**
   * @notice The largest max loss that can be set.
   */
  uint16 internal constant MAX_LOSS = 10_000;

  // ========================================= STATE =========================================

  /**
   * @notice The address that receives the fee when a withdrawal is completed.
   */
  address public feeAddress;

  /**
   * @notice The mapping of assets to their respective withdrawal settings.
   */
  mapping(ERC20 => WithdrawAsset) public withdrawAssets;

  /**
   * @notice The mapping of users to withdraw asset to their withdrawal requests.
   */
  mapping(address => mapping(ERC20 => WithdrawUserRequests)) internal withdrawRequests;

  /**
   * @notice Used to pause calls to `requestWithdraw`, and `completeWithdraw`.
   */
  bool public isPaused;

  //============================== ERRORS ===============================

  error DelayedWithdraw__WithdrawFeeTooHigh();
  error DelayedWithdraw__MaxLossTooLarge();
  error DelayedWithdraw__AlreadySetup();
  error DelayedWithdraw__WithdrawsNotAllowed();
  error DelayedWithdraw__WithdrawNotMatured();
  error DelayedWithdraw__NoSharesToWithdraw();
  error DelayedWithdraw__MaxLossExceeded();
  error DelayedWithdraw__transferNotAllowed();
  error DelayedWithdraw__WrongVaultStrategy();
  error DelayedWithdraw__BadAddress();
  error DelayedWithdraw__ThirdPartyCompletionNotAllowed();
  error DelayedWithdraw__WrongAsset();
  error DelayedWithdraw__Paused();
  error DelayedWithdraw__SharesIs0();
  error DelayedWithdraw__ExceedsMaxWithdrawPerUser();

  //============================== EVENTS ===============================

  event WithdrawRequested(
    address indexed account,
    ERC20 indexed asset,
    uint96 shares,
    uint40 maturity,
    bool allowThirdPartyToComplete,
    uint256 indexed withdrawalIdx
  );
  event WithdrawCancelled(address indexed account, ERC20 indexed asset, uint96 shares, uint256 indexed withdrawalIdx);
  event WithdrawCompleted(
    address indexed account,
    ERC20 indexed asset,
    uint256 shares,
    uint256 assets,
    uint256 indexed withdrawalIdx
  );
  event FeeAddressSet(address newFeeAddress);
  event SetupWithdrawalsInAsset(
    address indexed asset,
    uint64 withdrawDelay,
    uint16 withdrawFee,
    uint16 maxLoss,
    uint256 maxWithdrawPerUser
  );
  event WithdrawDelayUpdated(address indexed asset, uint256 newWithdrawDelay);
  event WithdrawFeeUpdated(address indexed asset, uint16 newWithdrawFee);
  event MaxLossUpdated(address indexed asset, uint16 newMaxLoss);
  event WithdrawalsStopped(address indexed asset);
  event ThirdPartyCompletionChanged(
    address indexed account,
    ERC20 indexed asset,
    bool allowed,
    uint256 indexed withdrawalIdx
  );
  event WithrawalCompleted(address indexed account, uint256 indexed withdrawalIdx);
  event Paused();
  event Unpaused();
  event MaxWithdrawPerUserUpdated(address indexed asset, uint256 newMaxWithdrawPerUser);

  //============================== IMMUTABLES ===============================

  /**
   * @notice The VaultV3 contract that users are withdrawing from.
   */
  IVault internal immutable lrtVault;

  constructor(address _owner, address _lrtVault, address _feeAddress) Auth(_owner, Authority(address(0))) {
    lrtVault = IVault(payable(_lrtVault));
    if (_feeAddress == address(0)) revert DelayedWithdraw__BadAddress();
    feeAddress = _feeAddress;
    emit FeeAddressSet(_feeAddress);
  }

  // ========================================= ADMIN FUNCTIONS =========================================

  /**
   * @notice Pause this contract.
   * @dev Callable by MULTISIG_ROLE.
   */
  function pause() external requiresAuth {
    isPaused = true;
    emit Paused();
  }

  /**
   * @notice Unpause this contract.
   * @dev Callable by MULTISIG_ROLE.
   */
  function unpause() external requiresAuth {
    isPaused = false;
    emit Unpaused();
  }

  /**
   * @notice Stops withdrawals for a specific asset.
   * @dev Callable by MULTISIG_ROLE.
   */
  function stopWithdrawalsInAsset(ERC20 asset) external requiresAuth {
    WithdrawAsset storage withdrawAsset = withdrawAssets[asset];
    if (!withdrawAsset.allowWithdraws) revert DelayedWithdraw__WithdrawsNotAllowed();

    withdrawAsset.allowWithdraws = false;

    emit WithdrawalsStopped(address(asset));
  }

  /**
   * @notice Sets up the withdrawal settings for a specific asset.
   * @dev Callable by OWNER_ROLE.
   */
  function setupWithdrawAsset(
    ERC20 asset,
    uint32 withdrawDelay,
    uint16 withdrawFee,
    uint16 maxLoss,
    uint256 maxWithdrawPerUser
  ) external requiresAuth {
    WithdrawAsset storage withdrawAsset = withdrawAssets[asset];

    if (withdrawFee > MAX_WITHDRAW_FEE) revert DelayedWithdraw__WithdrawFeeTooHigh();
    if (maxLoss > MAX_LOSS) revert DelayedWithdraw__MaxLossTooLarge();

    if (withdrawAsset.allowWithdraws) revert DelayedWithdraw__AlreadySetup();
    if (address(asset) != lrtVault.asset()) revert DelayedWithdraw__WrongAsset();
    withdrawAsset.allowWithdraws = true;
    withdrawAsset.withdrawDelay = withdrawDelay;
    withdrawAsset.withdrawFee = withdrawFee;
    withdrawAsset.maxLoss = maxLoss;
    withdrawAsset.maxWithdrawPerUser = maxWithdrawPerUser;

    emit SetupWithdrawalsInAsset(address(asset), withdrawDelay, withdrawFee, maxLoss, maxWithdrawPerUser);
  }

  /**
   * @notice Changes the withdraw delay for a specific asset.
   * @dev Callable by MULTISIG_ROLE.
   */
  function changeWithdrawDelay(ERC20 asset, uint32 withdrawDelay) external requiresAuth {
    WithdrawAsset storage withdrawAsset = withdrawAssets[asset];
    if (!withdrawAsset.allowWithdraws) revert DelayedWithdraw__WithdrawsNotAllowed();

    withdrawAsset.withdrawDelay = withdrawDelay;

    emit WithdrawDelayUpdated(address(asset), withdrawDelay);
  }

  /**
   * @notice Changes the withdraw fee for a specific asset.
   * @dev Callable by OWNER_ROLE.
   */
  function changeWithdrawFee(ERC20 asset, uint16 withdrawFee) external requiresAuth {
    WithdrawAsset storage withdrawAsset = withdrawAssets[asset];
    if (!withdrawAsset.allowWithdraws) revert DelayedWithdraw__WithdrawsNotAllowed();

    if (withdrawFee > MAX_WITHDRAW_FEE) revert DelayedWithdraw__WithdrawFeeTooHigh();

    withdrawAsset.withdrawFee = withdrawFee;

    emit WithdrawFeeUpdated(address(asset), withdrawFee);
  }

  /**
   * @notice Changes the max loss for a specific asset.
   * @dev Callable by OWNER_ROLE.
   * @dev Since maxLoss is a global value based off some withdraw asset, it is possible that a user
   *      creates a request, then the maxLoss is updated to some value the user is not comfortable with.
   *      In this case the user should cancel their request. However this is not always possible, so a
   *      better course of action would be if the maxLoss needs to be updated, the asset can be fully removed.
   *      Then all exisitng requests for that asset can be cancelled, and finally the maxLoss can be updated.
   */
  function changeMaxLoss(ERC20 asset, uint16 maxLoss) external requiresAuth {
    WithdrawAsset storage withdrawAsset = withdrawAssets[asset];
    if (!withdrawAsset.allowWithdraws) revert DelayedWithdraw__WithdrawsNotAllowed();

    if (maxLoss > MAX_LOSS) revert DelayedWithdraw__MaxLossTooLarge();

    withdrawAsset.maxLoss = maxLoss;

    emit MaxLossUpdated(address(asset), maxLoss);
  }

  /**
   * @notice Changes the fee address.
   * @dev Callable by STRATEGIST_MULTISIG_ROLE.
   */
  function setFeeAddress(address _feeAddress) external requiresAuth {
    if (_feeAddress == address(0)) revert DelayedWithdraw__BadAddress();
    feeAddress = _feeAddress;

    emit FeeAddressSet(_feeAddress);
  }

  /**
   * @notice Sets the maximum withdrawal amount per user for a specific asset.
   * @dev Callable by OWNER_ROLE.
   * @param asset The ERC20 token address
   * @param maxWithdraw The maximum amount a user can withdraw
   */
  function setMaxWithdrawPerUser(ERC20 asset, uint256 maxWithdraw) external requiresAuth {
    WithdrawAsset storage withdrawAsset = withdrawAssets[asset];

    withdrawAsset.maxWithdrawPerUser = maxWithdraw;

    emit MaxWithdrawPerUserUpdated(address(asset), maxWithdraw);
  }

  /**
   * @notice Cancels a user's withdrawal request.
   * @dev Callable by MULTISIG_ROLE, and STRATEGIST_MULTISIG_ROLE.
   */
  function cancelUserWithdraw(ERC20 asset, address user, uint256 withdrawalIdx) external requiresAuth {
    _cancelWithdraw(asset, user, withdrawalIdx);
  }

  /**
   * @notice Completes a user's withdrawal request.
   * @dev Admins can complete requests even if they are outside the completion window.
   * @dev Callable by MULTISIG_ROLE, and STRATEGIST_MULTISIG_ROLE.
   */
  function completeUserWithdraw(
    ERC20 asset,
    address user,
    uint256 withdrawalIdx
  ) external requiresAuth returns (uint256 assetsOut) {
    WithdrawAsset storage withdrawAsset = withdrawAssets[asset];
    WithdrawUserRequests storage userRequests = withdrawRequests[user][asset];

    WithdrawRequest storage req = userRequests.requests[withdrawalIdx];
    assetsOut = _completeWithdraw(asset, user, withdrawAsset, req, withdrawalIdx);

    _deleteWithdrawRequest(userRequests, withdrawalIdx);
  }

  // ========================================= PUBLIC FUNCTIONS =========================================

  /**
   * @notice Allows a user to set whether or not a 3rd party can complete withdraws on behalf of them.
   */
  function setAllowThirdPartyToComplete(ERC20 asset, bool allow, uint256 withdrawalIdx) external requiresAuth {
    withdrawRequests[msg.sender][asset].requests[withdrawalIdx].allowThirdPartyToComplete = allow;

    emit ThirdPartyCompletionChanged(msg.sender, asset, allow, withdrawalIdx);
  }

  /**
   * @notice Requests a withdrawal of shares for a specific asset.
   * @dev Publicly callable.
   */
  function requestWithdraw(
    ERC20 asset,
    uint96 shares,
    bool allowThirdPartyToComplete
  ) external requiresAuth nonReentrant {
    if (isPaused) revert DelayedWithdraw__Paused();
    WithdrawAsset storage withdrawAsset = withdrawAssets[asset];
    if (!withdrawAsset.allowWithdraws) revert DelayedWithdraw__WithdrawsNotAllowed();
    if (shares == 0) revert DelayedWithdraw__SharesIs0();

    WithdrawUserRequests storage userRequests = withdrawRequests[msg.sender][asset];
    if (userRequests.keys.length >= withdrawAsset.maxWithdrawPerUser) {
      revert DelayedWithdraw__ExceedsMaxWithdrawPerUser();
    }
    IERC20Metadata(lrtVault).safeTransferFrom(msg.sender, address(this), shares);

    withdrawAsset.outstandingShares += shares;

    uint256 lastIdx = userRequests.lastIdx + 1;
    userRequests.lastIdx = lastIdx;
    userRequests.keys.push(lastIdx);

    uint40 maturity = uint40(block.timestamp + withdrawAsset.withdrawDelay);

    userRequests.requests[lastIdx] = WithdrawRequest({
      allowThirdPartyToComplete: allowThirdPartyToComplete,
      maturity: maturity,
      assetsAtTimeOfRequest: lrtVault.previewRedeem(shares),
      shares: shares
    });

    emit WithdrawRequested(msg.sender, asset, shares, maturity, allowThirdPartyToComplete, lastIdx);
  }

  /**
   * @notice Cancels msg.sender's withdrawal request.
   * @dev not callable in a regular mode.
   */
  function cancelWithdraw(ERC20 asset, uint256 withdrawalIdx) external requiresAuth nonReentrant {
    _cancelWithdraw(asset, msg.sender, withdrawalIdx);
  }

  /**
   * @notice Completes a user's withdrawal request.
   * @dev Publicly callable.
   */
  function completeWithdraw(
    ERC20 asset,
    address account,
    uint256 withdrawalIdx
  ) external requiresAuth nonReentrant returns (uint256 assetsOut) {
    if (isPaused) revert DelayedWithdraw__Paused();
    WithdrawAsset storage withdrawAsset = withdrawAssets[asset];
    WithdrawUserRequests storage userRequests = withdrawRequests[account][asset];

    WithdrawRequest storage req = userRequests.requests[withdrawalIdx];

    if (msg.sender != account && !req.allowThirdPartyToComplete) {
      revert DelayedWithdraw__ThirdPartyCompletionNotAllowed();
    }
    assetsOut = _completeWithdraw(asset, account, withdrawAsset, req, withdrawalIdx);
    _deleteWithdrawRequest(userRequests, withdrawalIdx);

    emit WithrawalCompleted(account, withdrawalIdx);
  }

  /**
   * @notice Transfers any leftover balance (dust) of the specified ERC20 asset to the strategy vault.
   * @dev This function ensures that any remaining tokens in the contract are moved to the strategy.
   *      Reverts if the asset is the same as the lrtVault.
   *      Callable by MULTISIG_ROLE
   * @param asset The ERC20 asset from which dust is to be transferred.
   */
  function transferDustToStrategy(ERC20 asset) external requiresAuth {
    if (address(asset) == address(lrtVault)) revert DelayedWithdraw__transferNotAllowed();
    address[] memory default_queue = lrtVault.get_default_queue();
    if (default_queue.length != 1) revert DelayedWithdraw__WrongVaultStrategy();
    uint256 balance = asset.balanceOf(address(this));
    if (balance > 0) {
      asset.safeTransfer(default_queue[0], balance);
    }
  }

  /**
   * @notice Transfers the specified number of locked shares to the given account.
   * @dev Uses the safeTransfer function of the IERC20Metadata interface to ensure the transfer is safe.
   *      Callable by OWNER
   */
  function safeLockedShares(address account, uint256 shares, ERC20 asset) external requiresAuth {
    if (address(asset) != address(lrtVault)) revert DelayedWithdraw__transferNotAllowed();

    WithdrawAsset memory withdrawAsset = withdrawAssets[ERC20(lrtVault.asset())];
    if (withdrawAsset.outstandingShares + shares > asset.balanceOf(address(this)))
      revert DelayedWithdraw__transferNotAllowed();
    IERC20Metadata(asset).safeTransfer(account, shares);
  }

  // ========================================= VIEW FUNCTIONS =========================================

  /**
   * @notice Helper function to view the outstanding withdraw debt for a specific asset.
   */
  function viewOutstandingDebt(ERC20 asset) public view returns (uint256 debt) {
    debt = lrtVault.previewRedeem(withdrawAssets[asset].outstandingShares);
  }

  /**
   * @notice Helper function to view the outstanding withdraw debt for multiple assets.
   */
  function viewOutstandingDebts(ERC20[] calldata assets) external view returns (uint256[] memory debts) {
    debts = new uint256[](assets.length);
    for (uint256 i = 0; i < assets.length; i++) {
      debts[i] = viewOutstandingDebt(assets[i]);
    }
  }
  /// @notice Retrieves all withdraw requests for a given user and asset
  /// @param user The address of the user
  /// @param asset The ERC20 token address
  /// @return requests An array of WithdrawRequest structures
  /// @return keys An array of keys corresponding to each WithdrawRequest
  /// @return lastIdx The last index used for withdraw requests
  function getAllWithdrawRequests(
    address user,
    ERC20 asset
  ) public view returns (WithdrawRequest[] memory requests, uint256[] memory keys, uint256 lastIdx) {
    WithdrawUserRequests storage userRequests = withdrawRequests[user][asset];
    keys = userRequests.keys;
    uint256 keyCount = keys.length;

    requests = new WithdrawRequest[](keyCount);

    for (uint256 i = 0; i < keyCount; i++) {
      requests[i] = userRequests.requests[keys[i]];
    }

    lastIdx = userRequests.lastIdx;

    return (requests, keys, lastIdx);
  }

  /// @notice Retrieves a single withdraw request for a given user, asset, and withdrawal index
  /// @param user The address of the user
  /// @param asset The ERC20 token address
  /// @param withdrawalIdx The index of the withdrawal request
  /// @return A WithdrawRequest structure
  function getWithdrawRequest(
    address user,
    ERC20 asset,
    uint256 withdrawalIdx
  ) external view returns (WithdrawRequest memory) {
    return withdrawRequests[user][asset].requests[withdrawalIdx];
  }

  /// @notice Retrieves the array of keys for withdraw requests of a given user and asset
  /// @param user The address of the user
  /// @param asset The ERC20 token address
  /// @return An array of uint256 keys
  function getWithdrawRequestKeys(address user, ERC20 asset) external view returns (uint256[] memory) {
    return withdrawRequests[user][asset].keys;
  }

  /// @notice Retrieves the last index used for withdraw requests of a given user and asset
  /// @param user The address of the user
  /// @param asset The ERC20 token address
  /// @return The last index (uint256) used
  function getWithdrawRequestLastIdx(address user, ERC20 asset) external view returns (uint256) {
    return withdrawRequests[user][asset].lastIdx;
  }

  // ========================================= INTERNAL FUNCTIONS =========================================

  /**
   * @notice Internal helper function that implements shared logic for cancelling a user's withdrawal request.
   */
  function _cancelWithdraw(ERC20 asset, address account, uint256 withdrawalIdx) internal {
    WithdrawAsset storage withdrawAsset = withdrawAssets[asset];
    // We do not check if `asset` is allowed, to handle edge cases where the asset is no longer allowed.
    WithdrawUserRequests storage userRequests = withdrawRequests[account][asset];

    WithdrawRequest storage req = userRequests.requests[withdrawalIdx];

    uint96 shares = req.shares;
    if (shares == 0) revert DelayedWithdraw__NoSharesToWithdraw();
    withdrawAsset.outstandingShares -= shares;
    req.shares = 0;
    IERC20Metadata(lrtVault).safeTransfer(account, shares);
    _deleteWithdrawRequest(userRequests, withdrawalIdx);

    emit WithdrawCancelled(account, asset, shares, withdrawalIdx);
  }

  /**
   * @notice Internal helper function that implements shared logic for completing a user's withdrawal request.
   */
  function _completeWithdraw(
    ERC20 asset,
    address account,
    WithdrawAsset storage withdrawAsset,
    WithdrawRequest storage req,
    uint256 withdrawalIdx
  ) internal returns (uint256 minAssetToWithdraw) {
    if (!withdrawAsset.allowWithdraws) revert DelayedWithdraw__WithdrawsNotAllowed();

    if (block.timestamp < req.maturity) revert DelayedWithdraw__WithdrawNotMatured();
    uint256 shares = req.shares;
    if (shares == 0) revert DelayedWithdraw__NoSharesToWithdraw();

    uint256 currentAssetToWithdraw = lrtVault.previewRedeem(shares);
    minAssetToWithdraw = req.assetsAtTimeOfRequest < currentAssetToWithdraw
      ? req.assetsAtTimeOfRequest
      : currentAssetToWithdraw;
    // Safe to cast shares to a uint128 since req.shares is constrained to be less than 2^96.
    withdrawAsset.outstandingShares -= uint128(shares);

    if (withdrawAsset.withdrawFee > 0 && msg.sender != feeAddress) {
      // Handle withdraw fee.
      uint256 fee = uint256(shares).mulDivDown(withdrawAsset.withdrawFee, 1e4);
      shares -= fee;
      minAssetToWithdraw -= minAssetToWithdraw.mulDivDown(withdrawAsset.withdrawFee, 1e4);

      // Transfer fee to feeAddress.
      IERC20Metadata(lrtVault).safeTransfer(feeAddress, fee);
    }

    req.shares = 0;

    uint256 balanceBefore = asset.balanceOf(address(this));

    lrtVault.redeem(shares, address(this), address(this), withdrawAsset.maxLoss);

    uint256 balanceAfter = asset.balanceOf(address(this));

    minAssetToWithdraw = Math.min(balanceAfter - balanceBefore, minAssetToWithdraw);

    asset.safeTransfer(account, minAssetToWithdraw);

    emit WithdrawCompleted(account, asset, shares, minAssetToWithdraw, withdrawalIdx);
  }

  function _deleteWithdrawRequest(WithdrawUserRequests storage userRequests, uint256 withdrawalIdx) internal {
    // Delete the request from the mapping
    delete userRequests.requests[withdrawalIdx];

    // Remove the withdrawalIdx from the keys array
    uint256 lastIndex = userRequests.keys.length - 1;
    for (uint256 i = 0; i <= lastIndex; i++) {
      if (userRequests.keys[i] == withdrawalIdx) {
        if (i != lastIndex) {
          userRequests.keys[i] = userRequests.keys[lastIndex];
        }
        userRequests.keys.pop();
        break;
      }
    }
  }
}