// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

/**
 * @title NektarToken
 * @notice Implementation of the Nektar Token with transfer restrictions and whitelist functionality
 * @dev Extends ERC20 and OwnableRoles to provide a token with time-based transfer restrictions and whitelisting
 */
contract NektarToken is ERC20, OwnableRoles {
    /**
     * @notice The role for addresses that are allowed to transfer tokens before the timelock expires
     * @dev Uses the first available role from OwnableRoles
     */
    uint256 internal constant _TRANSFER_ROLE = _ROLE_0;

    /**
     * @notice The timestamp after which all transfers are allowed
     * @dev Set during contract deployment and cannot be changed afterwards
     */
    bool public isTransferable;

    /**
     * @notice Error thrown when a transfer is attempted before the timelock expires by a non-whitelisted address
     */
    error TransferNotAllowed();

    /**
     * @notice Error thrown when an invalid address is provided
     */
    error InvalidAddress();

    /**
     * @notice Error thrown when transferability is already enabled
     */
    error TransferabilityAlreadyEnabled();

    /**
     * @notice Event emitted when transferability is enabled
     */
    event TransferabilityEnabled();

    /**
     * @notice Initializes the NektarToken contract
     * @dev Sets up the token with initial supply, transfer timelock, and whitelist
     * @param _transferWhitelist Array of addresses initially whitelisted for transfers
     * @param _owner The address to receive the initial token supply, allowed to make the distribution and enable transferability
     */
    constructor(
        address[] memory _transferWhitelist,
        address _owner
    ) ERC20("Nektar Token", "NET", 18) {
        _mint(_owner, 1_000_000_000 ether);

        _initializeOwner(_owner);

        for (uint256 i; i < _transferWhitelist.length; i++) {
            _grantRoles(_transferWhitelist[i], _TRANSFER_ROLE);
        }
    }

    /**
     * @notice Transfers tokens to a specified address
     * @dev Overrides ERC20 transfer function to include transfer restrictions
     * @param to The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     * @return bool Returns true if the transfer was successful
     */
    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        _onlyTransferable();
        return super.transfer(to, amount);
    }

    /**
     * @notice Transfers tokens from one address to another
     * @dev Overrides ERC20 transferFrom function to include transfer restrictions
     * @param from The address to transfer tokens from
     * @param to The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     * @return bool Returns true if the transfer was successful
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        _onlyTransferable();
        return super.transferFrom(from, to, amount);
    }

    /**
     * @notice Grants the specified address the ability to transfer tokens before the timelock expires
     * @param _address The address to grant the transfer role
     */
    function grantTransferRole(address _address) external onlyOwner {
        if (_address == address(0)) {
            revert InvalidAddress();
        }

        _grantRoles(_address, _TRANSFER_ROLE);
    }

    /**
     * @notice Enables token transferability for all holders
     * @dev Can only be called by the contract owner. Once enabled, cannot be disabled.
     * @dev Reverts with TransferabilityAlreadyEnabled if transferability is already enabled
     * @custom:emits TransferabilityEnabled when transferability is successfully enabled
     */
    function enableTransferability() external onlyOwner {
        if (isTransferable) {
            revert TransferabilityAlreadyEnabled();
        }

        isTransferable = true;

        emit TransferabilityEnabled();
    }

    /**
     * @notice Checks if the caller is allowed to transfer tokens
     * @dev Reverts if the transfer is not allowed based on timelock and whitelist status
     */
    function _onlyTransferable() internal view {
        if (isTransferable) {
            return;
        }

        if (msg.sender == owner()) return;

        if (hasAnyRole(msg.sender, _TRANSFER_ROLE)) {
            return;
        }

        revert TransferNotAllowed();
    }
}