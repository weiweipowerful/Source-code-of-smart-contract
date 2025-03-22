//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract TapToken is ERC20Upgradeable, ERC20BurnableUpgradeable, AccessControlUpgradeable {
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    uint8 private _decimals;

    function initialize(string memory name_, string memory symbol_, uint8 decimals_) initializer public {
        _grantRole(BRIDGE_ROLE, msg.sender);
        __ERC20_init(name_, symbol_);
        _decimals = decimals_;
    }

    function mint(address account, uint256 value) public {
        require(hasRole(BRIDGE_ROLE, _msgSender()), "TS001");
        _mint(account, value);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}