// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Token_TEX is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 private _totalSupply;
    address public owner;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    mapping(address => bool) private frozenWallets;

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        _totalSupply = initialSupply * 10 ** uint256(decimals);
        owner = msg.sender;
        balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return balances[account];
    }

    function isFrozenWallet(address account) external view returns (bool) {
        return frozenWallets[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(!frozenWallets[msg.sender], "ERC20: sender is frozen");
        require(!frozenWallets[recipient], "ERC20: recipient is frozen");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(balances[msg.sender] >= amount, "ERC20: insufficient balance");

        balances[msg.sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(
        address owner_,
        address spender
    ) external view override returns (uint256) {
        return allowances[owner_][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        require(spender != address(0), "ERC20: approve to the zero address");
        require(!frozenWallets[msg.sender], "ERC20: approver is frozen");

        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(!frozenWallets[sender], "ERC20: sender is frozen");
        require(!frozenWallets[recipient], "ERC20: recipient is frozen");
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(
            allowances[sender][msg.sender] >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        require(balances[sender] >= amount, "ERC20: insufficient balance");

        balances[sender] -= amount;
        balances[recipient] += amount;
        allowances[sender][msg.sender] -= amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function burn(uint256 amount) external returns (bool) {
        require(amount > 0, "ERC20: amount must be greater than zero");
        require(balances[msg.sender] >= amount, "ERC20: insufficient balance");

        balances[msg.sender] -= amount;
        _totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
        return true;
    }

    function freezeWallet(address account) external onlyOwner {
        require(!frozenWallets[account], "ERC20: account is already frozen");
        frozenWallets[account] = true;
    }

    function unFreezeWallet(address account) external onlyOwner {
        require(frozenWallets[account], "ERC20: account is not frozen");
        frozenWallets[account] = false;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ERC20: new owner is the zero address");
        owner = newOwner;
    }

    function mint(uint256 amount) external onlyOwner returns (bool) {
        uint256 mintAmount = amount * 10 ** uint256(decimals);
        _totalSupply += mintAmount;
        balances[owner] += mintAmount;
        emit Transfer(address(0), owner, mintAmount);
        return true;
    }
}