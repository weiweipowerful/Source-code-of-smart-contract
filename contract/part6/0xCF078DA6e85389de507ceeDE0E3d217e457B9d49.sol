// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SkaiToken is ERC20 {

    constructor(
        string memory name,
        string memory symbol,
        uint256 totalSupply_,
        address receiver
    ) ERC20(name, symbol) {
        _mint(receiver, totalSupply_);
    }

}