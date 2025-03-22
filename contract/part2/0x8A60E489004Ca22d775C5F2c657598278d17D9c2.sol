// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

contract USDa is OFT, AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    mapping(address => bool) public isBlackListed;

    event AddedBlackList(address _addr);
    event RemovedBlackList(address _addr);

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) {
        _grantRole(DEFAULT_ADMIN_ROLE, _delegate);
        _grantRole(ADMIN_ROLE, _delegate);
        _setRoleAdmin(MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MINT_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BURN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSE_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    function addBlackList(address _addr) public onlyRole(MANAGER_ROLE) {
        isBlackListed[_addr] = true;
        emit AddedBlackList(_addr);
    }

    function removeBlackList(address _addr) public onlyRole(MANAGER_ROLE) {
        isBlackListed[_addr] = false;
        emit RemovedBlackList(_addr);
    }

    function pause() external onlyRole(PAUSE_ROLE) {
        Pausable._pause();
    }

    function unpause() external onlyRole(PAUSE_ROLE) {
        Pausable._unpause();
    }

    function mint(address _user, uint256 _amount) public onlyRole(MINT_ROLE) {
        _mint(_user, _amount);
    }

    function burn(address _user, uint256 _amount) public onlyRole(BURN_ROLE) {
        _burn(_user, _amount);
    }

    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        require(!isBlackListed[from] && !isBlackListed[to], "isBlackListed");
        super._update(from, to, value);
    }
}