// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface IBridge {
    function deposit(uint256 amount, address receiver, address token) external returns(uint256);
    function depositUnderlying(uint256 amount, address receiver) external returns(uint256);
    function underlying() external view returns (address);
}

contract Deposit is Ownable {
    IERC20 public immutable token;
    IBridge public bridge;  // Remove immutable to allow bridge updates

    event DepositReceived(address indexed from, uint256 amount);
    event BridgeUpdated(address indexed oldBridge, address indexed newBridge);

    constructor(address _token, address _bridge) Ownable(msg.sender) {
        token = IERC20(_token);
        bridge = IBridge(_bridge);
        // Approve bridge to spend our tokens
        token.approve(_bridge, type(uint256).max);
    }

    // Add function to update bridge address
    function updateBridge(address newBridge) external onlyOwner {
        require(newBridge != address(0), "Invalid bridge address");
        address oldBridge = address(bridge);
        
        // Remove approval from old bridge
        token.approve(oldBridge, 0);
        
        // Update bridge
        bridge = IBridge(newBridge);
        
        // Approve new bridge
        token.approve(newBridge, type(uint256).max);
        
        emit BridgeUpdated(oldBridge, newBridge);
    }

    // This will be called by our backend when it detects a deposit
    function forwardDeposit(address user, uint256 amount) external onlyOwner {
        require(token.balanceOf(address(this)) >= amount, "Insufficient balance");

        // Use deposit function instead of depositUnderlying
        bridge.deposit(amount, user, address(token));
        
        emit DepositReceived(user, amount);
    }

    // Add forwardDepositUnderlying for cases where we want to use that specifically
    function forwardDepositUnderlying(address user, uint256 amount) external onlyOwner {
        require(token.balanceOf(address(this)) >= amount, "Insufficient balance");
        require(address(token) == bridge.underlying(), "Token must be underlying");

        bridge.depositUnderlying(amount, user);
        
        emit DepositReceived(user, amount);
    }
}