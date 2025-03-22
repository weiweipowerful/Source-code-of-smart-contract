// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OlaToken is ERC20 {
    constructor() ERC20("Ola", "OLA") {
        _mint(msg.sender, 2_100_000_000 * 10**18);
    }
}