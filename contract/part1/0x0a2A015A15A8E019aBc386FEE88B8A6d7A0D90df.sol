// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol';

contract MXNA is ERC20PresetFixedSupply {
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address owner
    ) ERC20PresetFixedSupply(name, symbol, initialSupply, owner) {}
}