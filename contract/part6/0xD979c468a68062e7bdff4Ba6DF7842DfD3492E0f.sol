// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract beoble is ERC20, ERC20Burnable, ERC20Permit {
    constructor() ERC20("beoble", "BBL") ERC20Permit("beoble") {
        _mint(_msgSender(), 1000000000*1e18); // 1,000,000,000 (1 bn)
    }
}