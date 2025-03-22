// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract OndoAI is ERC20, ERC20Burnable, Ownable {

    constructor(uint256 totalAmount) Ownable(msg.sender) ERC20("Ondo DeFAI", "ONDOAI") {
        _mint(msg.sender, totalAmount);
    }
}