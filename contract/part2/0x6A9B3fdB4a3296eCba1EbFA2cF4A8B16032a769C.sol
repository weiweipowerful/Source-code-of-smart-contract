//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract BitsmileyToken is ERC20 {
    constructor() ERC20("bitSmiley", "SMILE") {
        _mint(msg.sender, 210000000 ether);
    }
}