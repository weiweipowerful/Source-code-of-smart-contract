// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract PirateToken is ERC20, ERC20Burnable, ERC20Permit {
    string constant NAME = "Pirate Nation Token";
    string constant SYMBOL = "PIRATE";
    uint256 constant TOTAL_SUPPLY = 1_000_000_000 ether; 

    constructor() ERC20(NAME, SYMBOL) ERC20Permit(NAME) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}