//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IKYCRegistry} from "./interfaces/IKYCRegistry.sol";

/// @title KYC Registry Contract
/// @notice Manages KYC (Know Your Customer) approvals and providers
/// @dev Implements role-based access control for KYC management
contract KYCRegistry is AccessControl, IKYCRegistry {
  /// @notice Role identifier for KYC providers
  bytes32 public constant KYC_PROVIDER_ROLE = keccak256("KYC_PROVIDER_ROLE");
  /// @notice Role identifier for KYC administrators
  bytes32 public constant KYC_ADMIN_ROLE = keccak256("KYC_ADMIN_ROLE");

  /// @notice Mapping to track KYC approval status for each address
  mapping(address => bool) private _kycApproved;

  /// @notice Initializes the contract with the deployer as the default admin and KYC admin
  /// @dev Sets up role hierarchy where KYC_ADMIN_ROLE manages KYC_PROVIDER_ROLE
  constructor(address initialAdmin_, address kycAdmin_) {
    _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin_);
    _grantRole(KYC_ADMIN_ROLE, kycAdmin_);

    _setRoleAdmin(KYC_PROVIDER_ROLE, KYC_ADMIN_ROLE);
  }

  /// @notice Emitted when a user's KYC status is approved
  /// @param user Address of the approved user
  event KYCApproved(address indexed user);

  /// @notice Emitted when a user's KYC status is revoked
  /// @param user Address of the user whose KYC was revoked
  event KYCRevoked(address indexed user);

  /// @notice Emitted when a new KYC provider is added
  /// @param provider Address of the new KYC provider
  event KYCProviderAdded(address indexed provider);

  /// @notice Emitted when a KYC provider is removed
  /// @param provider Address of the removed KYC provider
  event KYCProviderRemoved(address indexed provider);

  /// @notice Adds a new KYC provider
  /// @dev Only callable by addresses with KYC_ADMIN_ROLE
  /// @param provider Address of the new KYC provider
  /// @custom:throws InvalidAddress if provider address is zero
  function addKYCProvider(address provider) external onlyRole(KYC_ADMIN_ROLE) {
    if (provider == address(0)) revert InvalidAddress();
    grantRole(KYC_PROVIDER_ROLE, provider);
    emit KYCProviderAdded(provider);
  }

  /// @notice Removes a KYC provider
  /// @dev Only callable by addresses with KYC_ADMIN_ROLE
  /// @param provider Address of the KYC provider to remove
  /// @custom:throws InvalidAddress if provider address is zero
  function removeKYCProvider(
    address provider
  ) external onlyRole(KYC_ADMIN_ROLE) {
    if (provider == address(0)) revert InvalidAddress();
    revokeRole(KYC_PROVIDER_ROLE, provider);
    emit KYCProviderRemoved(provider);
  }

  /// @notice Approves KYC status for a user
  /// @dev Only callable by addresses with KYC_PROVIDER_ROLE
  /// @param user Address of the user to approve
  /// @custom:throws InvalidAddress if user address is zero
  /// @custom:throws AlreadyApproved if user is already KYC approved
  function approveKYC(address user) external onlyRole(KYC_PROVIDER_ROLE) {
    if (user == address(0)) revert InvalidAddress();
    if (_kycApproved[user]) revert AlreadyApproved();
    _kycApproved[user] = true;
    emit KYCApproved(user);
  }

  /// @notice Revokes KYC status for a user
  /// @dev Only callable by addresses with KYC_PROVIDER_ROLE
  /// @param user Address of the user to revoke KYC from
  /// @custom:throws InvalidAddress if user address is zero
  /// @custom:throws NotApproved if user is not KYC approved
  function revokeKYC(address user) external onlyRole(KYC_PROVIDER_ROLE) {
    if (user == address(0)) revert InvalidAddress();
    if (!_kycApproved[user]) revert NotApproved();
    _kycApproved[user] = false;
    emit KYCRevoked(user);
  }

  /// @notice Checks if a user is KYC approved
  /// @param user Address of the user to check
  /// @return bool True if user is KYC approved, false otherwise
  function isKYCApproved(address user) external view returns (bool) {
    return _kycApproved[user];
  }

  /// @notice Checks if an address has KYC provider role
  /// @param provider Address to check
  /// @return bool True if address is a KYC provider, false otherwise
  function isKYCProvider(address provider) external view returns (bool) {
    return hasRole(KYC_PROVIDER_ROLE, provider);
  }

  /// @notice Thrown when an invalid (zero) address is provided
  error InvalidAddress();
  /// @notice Thrown when attempting to approve KYC for an already approved user
  error AlreadyApproved();
  /// @notice Thrown when attempting to revoke KYC from a non-approved user
  error NotApproved();
}