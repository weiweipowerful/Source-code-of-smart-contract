// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.26;

import "@openzeppelin/[email protected]/token/ERC20/ERC20.sol";
import "@openzeppelin/[email protected]/access/Ownable.sol";

contract PIZZA is ERC20, Ownable {
    constructor(address initialOwner)
        ERC20("PIZZA", "PIZZA")
        Ownable(initialOwner)
    {
        _mint(msg.sender, 10000000000 * 10 ** decimals());
    }
}