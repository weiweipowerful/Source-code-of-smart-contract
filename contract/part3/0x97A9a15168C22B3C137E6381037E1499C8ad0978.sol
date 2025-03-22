// SPDX-License-Identifier: MIT

/**********************************************************************************************
 * ░░░░░██░███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░████░░░░░░░░░░░░░░░░░░░██░████░████░░░░░░░░░░░░░░░ *
 * ░░░░░██░░░░░███░░░░░░░░░░░░░░░░░░░░░░██░░░░░░██░░░░░░░░░░░░░░░░██░░░░░░░░░████░░░░░░░░░░░░ *
 * ░░░░░██░░░░░░░████░░░░░░░░░░░░░░░░██░░░░░░░░░░░░██░░░░░░░░░░░░░██░░░░░░░░░████░░░░░░░░░░░░ *
 * ░░░░░██░░░░░░░░░████░░░░░░░░░░░░░██░░░░░░░░░░░░░░██░░░░░░░░░░░░██░░░░░░░░░████░░░░░░░░░░░░ *
 * ░░░░░██░░░░░░░░░░░███░░░░██░░░░░█░░░░░░░░░░░░░░░░░░█░░░░██░░░░░██░████░████░░░░░░░░░░░░░░░ *
 * ░░░░░██░░░░░░░░░░░███░░░░░░░░░░░░██░░░░░░░░░░░░░░██░░░░░░░░░░░░██░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░██░░░░░░░░░████░░░░░░░░░░░░░░██░░░░░░░░░░░░██░░░░░░░░░░░░░██░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░██░░░░░░░████░░░░░░░░░░░░░░░░░░░██░░░░░░██░░░░░░░░░░░░░░░░██░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░██░░░░░███░░░░░░░░░░░░░░░░░░░░░░░░░████░░░░░░░░░░░░░░░░░░░██░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░██░███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██░░░░░░░░░░░░░░░░░░░░░░░░░ *
 **********************************************************************************************/

pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title DOP token contract
/// @notice An ERC20 token
contract DOP is ERC20, ERC20Permit, ERC20Burnable, Ownable {
    /// @notice Thrown when transfer is not enabled
    error TransferNotAllowed();

    /// @notice Thrown when there is an attempt to enable transfers more than once
    error AlreadyEnabled();

    /// A list of operational addresses which are allowed to transfer tokens while transfers are still disabled
    mapping(address => bool) public initiallyAllowedAccounts;

    /// Boolean flag indicating the current state of transfer functionality. Initially false, Can be toggled only once.
    bool public isTransferEnabled;

    /// @dev Emitted when the state of isTransferEnabled changes
    event TransfersEnabled();

    /// @dev Emitted when any account address is added in th allowed list
    event AllowListUpdated(address indexed account, bool state);

    /// @dev Constructor
    /// @param initialOwner The address of account in which tokens will be minted to
    /// @param initialAllowedList List of account addresses to allow transfer initially
    constructor(
        address initialOwner,
        address[] memory initialAllowedList
    ) ERC20("Data Ownership Protocol", "DOP") ERC20Permit("Data Ownership Protocol") Ownable(initialOwner) {
        for (uint256 i; i < initialAllowedList.length; ++i) {
            _updateAccountState(initialAllowedList[i], true);
        }

        _mint(initialOwner, 23_447_160_768 * 10 ** decimals());
    }

    /// @notice Change the state of transfer to enable for all, call only once
    function enableTransfer() external onlyOwner {
        /// revert if already enabled
        if (isTransferEnabled) {
            revert AlreadyEnabled();
        }
        isTransferEnabled = true;

        emit TransfersEnabled();
    }

    /// @dev Add an addresses to allowed list
    /// @param account The address of account of which state to be change
    /// @param state The new whitelist status of the address
    function updateAccountState(address account, bool state) external onlyOwner {
        _updateAccountState(account, state);
    }

    /// @dev Change account status to enable/disable transfer initially
    /// @param account The address of account of which state to be change
    /// @param newStatus The new whitelist status of the address
    function _updateAccountState(address account, bool newStatus) private {
        if (initiallyAllowedAccounts[account] != newStatus) {
            initiallyAllowedAccounts[account] = newStatus;

            emit AllowListUpdated({ account: account, state: newStatus });
        }
    }

    /// @dev Overridden to check if transfers are enabled
    function _update(address from, address to, uint256 value) internal override {
        if (isTransferEnabled) {
            super._update(from, to, value);
            return;
        }
        if (!initiallyAllowedAccounts[msg.sender]) {
            revert TransferNotAllowed();
        }

        super._update(from, to, value);
    }
}