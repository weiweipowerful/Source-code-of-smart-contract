// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "stl-contracts/ERC/ERC5169.sol";

contract SLN is ERC5169, ERC20Burnable, AccessControlEnumerable {

    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint public max_supply_allowed; 

    error MaxSupplyReached();
    error OneAdminRequired();

    event MaxSupplyAllowedChanged(uint maxSupply);

    constructor() ERC20("Smart Layer Network Token","SLN") {
        _grantRole(DEFAULT_ADMIN_ROLE, 0xFB6674968c95a5F3A65373CA4EA65c76bc90d83D);
        _grantRole(MINTER_ROLE, 0xFB6674968c95a5F3A65373CA4EA65c76bc90d83D);
        _setMaxAllowed(100_000_000 * 10**18);
    }

    function _authorizeSetScripts(string[] memory) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function isMinter(address _account) public view returns (bool) {
        return hasRole(MINTER_ROLE, _account);
    }

    function owner() public view returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }

    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE){
        if (totalSupply() + _amount > max_supply_allowed){
            revert MaxSupplyReached();
        }
        _mint(_to, _amount);
    }

    function setMaxAllowed(uint max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxAllowed(max);
    }

    function _setMaxAllowed(uint max) private {
        max_supply_allowed = max;
        emit MaxSupplyAllowedChanged(max);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override (ERC5169, AccessControlEnumerable) returns (bool) {
        return ERC5169.supportsInterface(interfaceId)
        || AccessControlEnumerable.supportsInterface(interfaceId);
    }

    function _revokeRole(bytes32 role, address account) internal virtual override returns (bool) {
        if (role == DEFAULT_ADMIN_ROLE && getRoleMemberCount(DEFAULT_ADMIN_ROLE) == 1) {
            revert OneAdminRequired();
        }
        return AccessControlEnumerable._revokeRole(role, account);
    }

    function contractURI() external pure returns (string memory){
        return "https://resources.smarttokenlabs.com/contract/SLN.json";
    }
}