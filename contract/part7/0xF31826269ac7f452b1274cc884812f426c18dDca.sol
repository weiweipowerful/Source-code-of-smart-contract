// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MILK Coin (MILK)
 * @notice MILK is an ERC20 token deployed on Ethereum mainnet. It has a 
 * maximum supply of 9,860,000,000 tokens, which is identical to OX (Open
 * Exchange Token). All of the supply is being minted directly to the
 * treasury multisig address
 * (eth:0x4B214e2a2a9716bfF0C20EbDA912B13c7a184E23) upon deployment.
 */

contract MILKCoin is ERC20 {
    uint256 public constant SUPPLY = 9860000000;
    constructor(address multisig) ERC20("MILK Coin", "MILK") {
        _mint(multisig, SUPPLY * (10 ** uint256(decimals())));
    }
}