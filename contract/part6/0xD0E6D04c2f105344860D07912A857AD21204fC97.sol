// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract NeoTechERC20 is ERC20{
    constructor() ERC20("NEOT", "NeoTech") {
        _mint(msg.sender, 250_000_000e18);
    }
}