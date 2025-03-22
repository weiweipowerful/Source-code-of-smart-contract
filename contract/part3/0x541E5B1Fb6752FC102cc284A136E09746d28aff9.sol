// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract JMC is ERC20 {
    uint256 private constant ETH_TO_JMC_RATE = 500500 * 1e18; // 1 ETH ≈ 500,500 JMC

    event Minted(address indexed user, uint256 ethReceived, uint256 jmcMinted);

    constructor() payable ERC20("Jamu Meta Coin", "JMC") {}

    receive() external payable {
        require(msg.value != 0, "Must send ETH to mint JMC");

        uint256 jmcAmount = (msg.value * ETH_TO_JMC_RATE) / 1e18;
        require(jmcAmount != 0, "Mint amount too low");

        _mint(msg.sender, jmcAmount);
        emit Minted(msg.sender, msg.value, jmcAmount);
    }
}