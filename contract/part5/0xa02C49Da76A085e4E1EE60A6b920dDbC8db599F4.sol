// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title Treat token contract
/// @notice ERC20 token contract for Treat token
/// @dev Tokens are minted upfront and sent to the deployer
contract Treat is ERC20, ERC20Burnable {
    constructor(uint256 _amount) payable ERC20("Shiba Inu Treat", "TREAT") {
        _mint(msg.sender, _amount * 1e18);
    }
}