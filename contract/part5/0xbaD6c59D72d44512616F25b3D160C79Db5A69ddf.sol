// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";


contract VATAN is ERC20, AccessControl, ERC20Permit, ERC20Burnable, ERC20Pausable {
    uint8 private immutable _customDecimals;
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    constructor(address initialOwner)
        ERC20("Vatan", "VATAN")
        ERC20Permit("Vatan")
    {
        require(initialOwner != address(0), "Invalid owner address");
        _customDecimals = 18;
        _mint(initialOwner, 500_000_000 * 10 ** _customDecimals);
        emit TokensMinted(initialOwner, 500_000_000 * 10 ** _customDecimals);

        _grantRole(ADMIN_ROLE, initialOwner);
    }

    function transferOwnership(address newOwner) external onlyRole(ADMIN_ROLE) {
        require(newOwner != address(0), "New owner cannot be zero address");
        grantRole(ADMIN_ROLE, newOwner);
        revokeRole(ADMIN_ROLE, msg.sender);
        emit OwnershipTransferred(msg.sender, newOwner);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function burn(uint256 value) public override whenNotPaused {
        _burn(_msgSender(), value);
        emit TokensBurned(_msgSender(), value);
    }

    function burnFrom(address account, uint256 value) public override whenNotPaused {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= value, "Burn exceeds allowance");
        _approve(account, _msgSender(), currentAllowance - value);
        _burn(account, value);
        emit TokensBurned(account, value);
    }

    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }

    // ---------- EVENTS ----------
    event TokensBurned(address indexed account, uint256 amount);
    event TokensMinted(address indexed recipient, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}