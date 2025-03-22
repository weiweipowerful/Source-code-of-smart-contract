// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Tether is ERC20 {
  constructor() ERC20("Tether", "ERC20") {
    _mint(msg.sender, 1000000000 * (10 ** uint256(decimals())));
  }
}