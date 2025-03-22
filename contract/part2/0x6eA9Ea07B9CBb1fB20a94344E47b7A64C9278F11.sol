// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/[email protected]/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/[email protected]/token/ERC20/extensions/ERC20Burnable.sol";

contract RLLL is ERC20, ERC20Burnable {
    constructor(address recipient) ERC20("RLLL", "RLLL") {
        _mint(recipient, 1000000000 * 10 ** decimals());
    }
}