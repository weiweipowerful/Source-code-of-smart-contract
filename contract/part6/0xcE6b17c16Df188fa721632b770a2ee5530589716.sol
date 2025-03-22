// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(address _tokenHolder) ERC20("ETFSwap", "ETFS") {
        _mint(_tokenHolder, 1000000000 ether);
    }
}