// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract xcBTCToken is ERC20, ERC20Permit, AccessControl {
    // A custom role for operators. Operators can mint tokens. The operator is the ledger contract, which has strict safeguards over when tokens can be minted or burned.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // The "DEFAULT_ADMIN_ROLE" is the role is managed by a multisig.

    error RenouncingRolesIsDisabled();

    // Constructor sets the initial owner and grants the admin role to the owner
    constructor() ERC20("xcBTC", "xcBTC") ERC20Permit("xcBTC") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Override the decimals function to return the custom decimal value
    function decimals() public pure override returns (uint8) {
        return 8;
    }

    // Function to mint new tokens, restricted to operators
    function mint(address to, uint256 amount) public onlyRole(OPERATOR_ROLE) {
        _mint(to, amount);
    }

    // Function to burn tokens, restricted to operators
    function burn(uint256 amount) public onlyRole(OPERATOR_ROLE) {
        _burn(msg.sender, amount);
    }

    // Prevent addresses from removing their own roles. Admins can still remove roles from other addresses.
    function renounceRole(bytes32, address) public virtual override {
        revert RenouncingRolesIsDisabled();
    }
}