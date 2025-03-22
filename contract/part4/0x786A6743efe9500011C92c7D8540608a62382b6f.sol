// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol";

contract AlturaBridgedToken is ERC20, ERC20Permit, AccessControlDefaultAdminRules {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor(address _defaultAdmin) ERC20("Altura", "ALU") ERC20Permit("Altura") AccessControlDefaultAdminRules(
        3 days,
        _defaultAdmin
    ) {}

    function mint(address account, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        _mint(account, amount);
    }

    function burn(uint256 amount) external onlyRole(OPERATOR_ROLE) {
        _burn(_msgSender(), amount);
    }
}