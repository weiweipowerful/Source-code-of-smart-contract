// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/[email protected]/token/ERC20/ERC20.sol";
import "@openzeppelin/[email protected]/token/ERC20/extensions/ERC20Burnable.sol";

contract EarnToken is ERC20, ERC20Burnable {
    constructor()
        ERC20("Earn Network", "EARN")
    {
        _mint(msg.sender, 10000000000 * 10 ** decimals());
    }
}