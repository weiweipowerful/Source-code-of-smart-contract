// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LFERC20 is ERC20 {    
    constructor(address receiver) ERC20("LF", "LF") {
        _mint(receiver, 10_000_000_000 * 10 ** 18);
    }
}