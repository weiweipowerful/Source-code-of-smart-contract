// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title WorldMobileToken
/// @dev This contract implements the WorldMobileToken, an ERC20 token with additional features.
contract WorldMobileToken is ERC20Capped, ERC20Permit, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @notice Creates a new WorldMobileToken contract.
    constructor()
    ERC20("WorldMobileToken", "WMTX")
        // we can tweak this to change the initial owner (instead of the contract deployer account)
    ERC20Permit("WorldMobileToken")
    ERC20Capped(2_000_000_000 * 10 ** decimals())
    {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender()); // Grant the contract deployer the default admin role
        _grantRole(MINTER_ROLE, _msgSender()); // Grant the contract deployer the minter role
        _grantRole(BURNER_ROLE, _msgSender()); // Grant the contract deployer the burner role
    }

    /// @notice Returns the number of decimals used to get its user representation.
    /// @return The number of decimals used to get its user representation.
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    /// @notice Mints tokens and assigns them to `to`, increasing the total supply.
    /// @param to The account to mint the tokens to.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _mint(address account, uint256 amount) internal override(ERC20, ERC20Capped) {
        super._mint(account, amount);
    }

    /// @notice Destroys `value` tokens from the caller.
    /// @param value The amount of tokens to burn.
    function burn(uint256 value) public onlyRole(BURNER_ROLE) {
        _burn(_msgSender(), value);
    }

    /// @notice Destroys `value` tokens from `account`, deducting from the caller's allowance.
    /// @param account The account to burn the tokens from.
    /// @param value The amount of tokens to burn.
    function burnFrom(address account, uint256 value) public onlyRole(BURNER_ROLE) {
        _spendAllowance(account, _msgSender(), value);
        _burn(account, value);
    }
}