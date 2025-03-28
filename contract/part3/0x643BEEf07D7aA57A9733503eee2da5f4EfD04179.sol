/**
 *Submitted for verification at Etherscan.io on 2024-06-17
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LGCYX {
    string public name = "LGCYX";
    string public symbol = "LGCYX";
    uint8 public decimals = 18;
    uint256 public totalSupply = 100000000000 * 10 ** uint256(decimals);
    
    address public owner;
    bool public paused = false;
    
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    mapping(address => bool) private blacklisted;
    address[] private blacklistedAccounts;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);
    event Blacklisted(address account);
    event Unblacklisted(address account);
    event Burn(address indexed burner, uint256 value);
    
    modifier onlyOwner() {
        require(owner == msg.sender, "Caller is not the owner");
        _;
    }
    
    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }
    
    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "Account is blacklisted");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    function transfer(address recipient, uint256 amount) public notPaused notBlacklisted(msg.sender) notBlacklisted(recipient) returns (bool) {
        require(recipient != address(0), "Transfer to the zero address");
        require(balances[msg.sender] >= amount, "Transfer amount exceeds balance");

        balances[msg.sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public notPaused notBlacklisted(msg.sender) notBlacklisted(spender) returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public notPaused notBlacklisted(sender) notBlacklisted(recipient) returns (bool) {
        require(recipient != address(0), "Transfer to the zero address");
        require(balances[sender] >= amount, "Transfer amount exceeds balance");
        require(allowances[sender][msg.sender] >= amount, "Transfer amount exceeds allowance");

        balances[sender] -= amount;
        balances[recipient] += amount;
        allowances[sender][msg.sender] -= amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function allowance(address tokenOwner, address spender) public view returns (uint256) {
        return allowances[tokenOwner][spender];
    }

    function burn(uint256 amount) public notPaused notBlacklisted(msg.sender) {
        require(balances[msg.sender] >= amount, "Burn amount exceeds balance");

        balances[msg.sender] -= amount;
        totalSupply -= amount;
        emit Burn(msg.sender, amount);
    }

    function pause() public onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function blacklist(address account) public onlyOwner {
        require(!blacklisted[account], "Account is already blacklisted");
        blacklisted[account] = true;
        blacklistedAccounts.push(account);
        emit Blacklisted(account);
    }

    function unblacklist(address account) public onlyOwner {
        require(blacklisted[account], "Account is not blacklisted");
        blacklisted[account] = false;

        for (uint i = 0; i < blacklistedAccounts.length; i++) {
            if (blacklistedAccounts[i] == account) {
                blacklistedAccounts[i] = blacklistedAccounts[blacklistedAccounts.length - 1];
                blacklistedAccounts.pop();
                break;
            }
        }

        emit Unblacklisted(account);
    }

    function isBlacklisted(address account) public view returns (bool) {
        return blacklisted[account];
    }

    function getBlacklistedAccounts() public view returns (address[] memory) {
        return blacklistedAccounts;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}