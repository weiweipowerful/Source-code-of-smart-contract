// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./UniswapTaxTokenV5.sol";

/**
 * website: https://replygai.com
 * twitter: https://x.com/0xReplyGai
 */

/**
 * @title ReplyGai Token
 * @dev ERC20 token with 3% tax that inherits from UniswapTaxTokenV5
 */
contract ReplyGai is UniswapTaxTokenV5 {
    // Constants
    uint256 private constant TAX_RATE = 50; // 3% tax (represented as 30/1000)
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000; // 1 billion tokens

    /**
     * @dev Constructor for ReplyGai token
     * @param initialOwner The address that will be set as the owner and tax wallet
     * @param uniswapRouter The address of the Uniswap V2 Router to use
     */
    constructor(address initialOwner, address uniswapRouter) UniswapTaxTokenV5(
        initialOwner, // initialOwner instead of msg.sender
        uniswapRouter,
        TAX_RATE,
        TOTAL_SUPPLY,
        "REPLY GAI",
        "REPLY"
    ) {
        // Additional initialization can be done here if needed
    }
}