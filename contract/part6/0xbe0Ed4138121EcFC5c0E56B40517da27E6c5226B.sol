// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;

import {
    ERC20,
    ERC20Permit
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AethirToken
 * @dev This contract is an implementation of the ERC20 token standard with additional features.
 * The admin multisig wallet can manage addresses from the whitelist, update the maximum allowed token amount for a whitelisted address.
 * The contract also includes a mint function that can be called by the admin multisig wallet to mint tokens to the contract itself.
 */
contract AethirToken is ERC20Permit, Ownable {
    // Events that the contract emits when changes are made
    event WhitelistedAdded(address account, uint256 maxAmount);
    event WhitelistedRemoved(address account);
    event WhitelistedMaxAmountUpdated(address account, uint256 newMaxAmount);
    event WhitelistedAddressUpdated(address account, address newAddress);

    // Constant that defines the maximum supply of tokens
    uint256 public constant MAX_SUPPLY = 42_000_000_000 * 10 ** 18;

    // Mappings that keep track of the allowed and transferred amounts for each address
    mapping(address => uint256) public allowedAmount;
    mapping(address => uint256) public transferredAmount;

    // Variable that keeps track of the remain amount of tokens that have been whitelisted
    uint256 public remainWhitelisted;

    // Variable that keeps track of the amount of tokens that have been transferred out
    uint256 public totalTransferred;

    /**
     * @dev Contract constructor.
     *
     * This constructor sets the name and symbol of the token using the ERC20
     * constructor, and sets the name of the permit using the ERC20Permit
     * constructor. It also transfers the ownership of the contract to the
     * provided admin multisig wallet.
     *
     * @param _adminMultisigWallet The address of the admin multisig wallet that will own the contract.
     */
    constructor(
        address _adminMultisigWallet
    ) ERC20("Cethir Token", "CTH") ERC20Permit("CTH") {
        transferOwnership(_adminMultisigWallet);
    }

    /**
     * @dev Mints a specified amount of tokens and store inside the token contract.
     *
     * This function can only be called by the admin multisig wallet. It mints
     * a specified amount of tokens and assigns them to the contract itself,
     * increasing the total supply.
     *
     * Requirements:
     *
     * - The total supply of tokens after the minting operation must not exceed the maximum supply.
     *
     * @param amount The amount of tokens to mint.
     */
    function mint(uint256 amount) public onlyOwner {
        require(
            totalSupply() + amount <= MAX_SUPPLY,
            "Cannot mint more than max supply"
        );
        _mint(address(this), amount);
    }

    /**
     * @dev Transfers tokens to a whitelisted address.
     *
     * This function can only be called by the admin multisig wallet. It transfers
     * a specified amount of tokens to a given address, provided that the address
     * is whitelisted and the amount does not exceed the maximum allowed amount
     * for that address.
     *
     * Requirements:
     *
     * - `to` must be a whitelisted address.
     * - The sum of `amount` and the previously transferred amount to `to` must not exceed the maximum allowed amount for `to`.
     *
     * @param to The address to transfer tokens to.
     * @param amount The amount of tokens to transfer.
     */
    function transferToWhitelisted(
        address to,
        uint256 amount
    ) public onlyOwner {
        require(
            transferredAmount[to] + amount <= allowedAmount[to],
            "Cannot transfer more than max allowed amount"
        );
        transferredAmount[to] += amount;
        totalTransferred += amount;
        remainWhitelisted -= amount;
        SafeERC20.safeTransfer(this, to, amount);
    }

    /**
     * @dev Adds an address to the whitelist and sets its maximum allowed token amount.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must not already be whitelisted.
     * - `maxAmount` must be greater than 0.
     *
     * Emits an {WhitelistedAdded} event.
     *
     * @param account The address to add to the whitelist.
     * @param maxAmount The maximum amount of tokens that the address is allowed to hold.
     */
    function addWhitelisted(
        address account,
        uint256 maxAmount
    ) public onlyOwner {
        require(account != address(0), "Account is the zero address");
        require(account != address(this), "Account is the token address");
        require(allowedAmount[account] == 0, "Account was whitelisted");
        require(maxAmount > 0, "Max amount must be greater than 0");
        require(
            remainWhitelisted + totalTransferred + maxAmount <= MAX_SUPPLY,
            "Cannot whitelist more than max supply"
        );
        emit WhitelistedAdded(account, maxAmount);
        remainWhitelisted += maxAmount;
        allowedAmount[account] = maxAmount;
    }

    /**
     * @dev Removes an address from the whitelist.
     *
     * This function can only be called by the admin multisig wallet. It removes
     * a given address from the whitelist by setting its maximum allowed token
     * amount to 0.
     *
     * Requirements:
     *
     * - `account` must be a whitelisted address.
     *
     * Emits a {WhitelistedRemoved} event.
     *
     * @param account The address to remove from the whitelist.
     */
    function removeWhitelisted(address account) public onlyOwner {
        require(allowedAmount[account] > 0, "Account is not whitelisted");
        emit WhitelistedRemoved(account);
        remainWhitelisted -=
            allowedAmount[account] -
            transferredAmount[account];
        allowedAmount[account] = 0;
        transferredAmount[account] = 0;
    }

    /**
     * @dev Updates the maximum allowed token amount for a whitelisted address.
     *
     * This function can only be called by the admin multisig wallet. It updates
     * the maximum allowed token amount for a given address, provided that the address
     * is whitelisted and the new maximum amount is greater than 0.
     *
     * Requirements:
     *
     * - `account` must be a whitelisted address.
     * - `newMaxAmount` must be greater than 0.
     *
     * Emits an {WhitelistedMaxAmountUpdated} event.
     *
     * @param account The address to update the maximum allowed token amount for.
     * @param newMaxAmount The new maximum amount of tokens that the address is allowed to hold.
     */
    function updateWhitelistedMaxAmount(
        address account,
        uint256 newMaxAmount
    ) public onlyOwner {
        require(allowedAmount[account] > 0, "Account is not whitelisted");
        require(newMaxAmount > 0, "Max amount must be greater than 0");
        require(
            newMaxAmount >= transferredAmount[account],
            "Max amount must not less than transferred amount"
        );
        require(
            remainWhitelisted + totalTransferred + newMaxAmount <=
                MAX_SUPPLY + allowedAmount[account],
            "Cannot whitelist more than max supply"
        );
        emit WhitelistedMaxAmountUpdated(account, newMaxAmount);
        remainWhitelisted =
            remainWhitelisted +
            newMaxAmount -
            allowedAmount[account];
        allowedAmount[account] = newMaxAmount;
    }

    /**
     * @dev Updates the whitelisted address.
     *
     * This function can only be called by the admin multisig wallet. It updates
     * the whitelisted address to a new address, provided that the original address
     * is whitelisted, and the new address is not already whitelisted.
     *
     * The function also transfers the allowed and transferred amounts from the
     * original address to the new address, and resets the allowed and transferred
     * amounts for the original address to 0.
     *
     * Requirements:
     *
     * - `account` must be a whitelisted address.
     * - `newAddress` cannot be the zero address.
     * - `newAddress` must not already be whitelisted.
     *
     * Emits an {WhitelistedAddressUpdated} event.
     *
     * @param account The original address to update.
     * @param newAddress The new address to update to.
     */
    function updateWhitelistedAddress(
        address account,
        address newAddress
    ) public onlyOwner {
        require(newAddress != address(0), "New address is the zero address");
        require(allowedAmount[account] > 0, "Account is not whitelisted");
        require(allowedAmount[newAddress] == 0, "New address was whitelisted");
        emit WhitelistedAddressUpdated(account, newAddress);
        allowedAmount[newAddress] = allowedAmount[account];
        transferredAmount[newAddress] = transferredAmount[account];
        allowedAmount[account] = 0;
        transferredAmount[account] = 0;
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._afterTokenTransfer(from, to, amount);
        // Allow any wallet addresses to transfer token back to the contract
        // If the wallet address is whitelisted, the transfered amount will be updated
        if (to == address(this) && from != address(0)) {
            totalTransferred -= amount;
            if (transferredAmount[from] >= amount) {
                transferredAmount[from] -= amount;
            } else {
                transferredAmount[from] = 0;
            }
        }
    }
}