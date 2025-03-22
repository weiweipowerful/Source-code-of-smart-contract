// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract FlashLoanArbitrage is ReentrancyGuard {
    address public owner;
    address public addressesProvider;  // ✅ Store Aave PoolAddressesProvider

    constructor(address _addressesProvider) {  // ✅ Accept provider address
        owner = msg.sender;
        addressesProvider = _addressesProvider;
    }

    function executeOperation(
        address asset,             
        uint256 amount,            
        address initiator,         
        address[] calldata route,  
        bytes calldata params      
    ) external nonReentrant returns (bool) {
        require(msg.sender == owner, "Not authorized");

        IERC20(asset).approve(route[0], amount);

        IUniswapV2Router(route[0]).swapExactTokensForTokens(
            amount,
            0,
            route,
            initiator,
            block.timestamp + 300
        );

        return true;
    }
}