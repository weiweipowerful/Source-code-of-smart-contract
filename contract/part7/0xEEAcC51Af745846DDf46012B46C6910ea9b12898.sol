// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Dogc is ERC20 {
    constructor() ERC20("Dogc", "DOGC") {
        _mint(msg.sender, 100000000000 * 10 ** decimals());
    }
}