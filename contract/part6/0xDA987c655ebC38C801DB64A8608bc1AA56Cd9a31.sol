// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { ERC20 } from "@oz/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@oz/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Burnable } from "@oz/token/ERC20/extensions/ERC20Burnable.sol";
import { AccessControlEnumerable } from "@oz/access/extensions/AccessControlEnumerable.sol";

contract Token is ERC20, ERC20Permit, ERC20Burnable, AccessControlEnumerable {
    /// @notice Minter role bytes, equals keccak256("MINTER_ROLE");
    bytes32 public constant MINTER_ROLE = 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6;
    /// @notice Hardcapped maximum supply of the token. Cannot be changed after deployment.
    uint256 public immutable MAX_SUPPLY;

    error MaxSupplyExceeded();

    modifier whenSupplyLeft(uint256 amount) {
        if (totalSupply() + amount > MAX_SUPPLY) revert MaxSupplyExceeded();
        _;
    }

    /// @notice Constructs the token with the given name, symbol, admin and max supply.
    /// @param name_ The name of the token.
    /// @param symbol_ The symbol of the token.
    /// @param admin The admin of the token that will be able to set additional roles.
    /// @param maxSupply The maximum supply of the token.
    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        uint256 maxSupply
    )
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        MAX_SUPPLY = maxSupply;
    }

    /// @notice Mints the given amount of tokens to the given address.
    /// @dev Allowed only to the address having a minter role.
    /// @param to The address to mint the tokens to.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenSupplyLeft(amount) {
        _mint(to, amount);
    }
}