// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Cashna is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ReentrancyGuard {
    // Blacklist mapping
    mapping(address => bool) private _blacklist;

    // Events
    event Blacklisted(address indexed account);
    event RemovedFromBlacklist(address indexed account);

    constructor(address initialOwner)
        ERC20("Cashna", "CASHNA")
        Ownable(initialOwner)
        ReentrancyGuard() // Initialize ReentrancyGuard
    {
        _mint(msg.sender, 40000000000 * 10 ** decimals());
    }

    // Pause functionality
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // Minting functionality
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // Add an address to the blacklist
    function addToBlacklist(address account) external onlyOwner {
        _blacklist[account] = true;
        emit Blacklisted(account);
    }

    // Remove an address from the blacklist
    function removeFromBlacklist(address account) external onlyOwner {
        _blacklist[account] = false;
        emit RemovedFromBlacklist(account);
    }

    // Override transfer to enforce blacklist
    function transfer(address to, uint256 amount) public override nonReentrant returns (bool) {
        require(!_blacklist[msg.sender], "Sender is blacklisted");
        require(!_blacklist[to], "Recipient is blacklisted");

        return super.transfer(to, amount);
    }

    // Override transferFrom to enforce blacklist
    function transferFrom(address from, address to, uint256 amount) public override nonReentrant returns (bool) {
        require(!_blacklist[from], "Sender is blacklisted");
        require(!_blacklist[to], "Recipient is blacklisted");

        return super.transferFrom(from, to, amount);
    }

    // Override _update to resolve conflicts
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}