// SPDX-License-Identifier: MIT
/**
 *
 * HealthSci.AI
 * Website: https://healthsci.ai
 * X:https://twitter.com/HealthSci_AI
 * Medium: https://healthsci.medium.com/
 * Telegram: https://t.me/healthsci 
 * 
*/
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.25;

import "@openzeppelin/[email protected]/token/ERC20/ERC20.sol";
import "@openzeppelin/[email protected]/access/Ownable.sol";

contract HealthSciAI is ERC20, Ownable {
    constructor(address initialOwner)
        ERC20("HealthSci.AI", "HSAI")
        Ownable(initialOwner)
    {
        _mint(msg.sender, 100000000 * 10 ** decimals());
    }
}