// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BurnMintERC677} from "@chainlink/contracts-ccip/src/v0.8/shared/token/ERC677/BurnMintERC677.sol";

contract AstarToken is BurnMintERC677 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 maxSupply_
    ) BurnMintERC677(name, symbol, decimals_, maxSupply_) {}
}