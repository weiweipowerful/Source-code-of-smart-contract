// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract GURUToken is ERC20, ERC20Permit {
    // GURU token decimal
    uint8 public constant _decimals = 18;
    // Total supply for the GURU token = 1B
    uint256 private _totalSupply = 1000000000 * (10 ** uint256(_decimals));
    // Token GURU deployer
    address private _guruSafe;

    constructor(address guruSafe) ERC20("GURU Token", "GURU") ERC20Permit("GURU") {
        _guruSafe = guruSafe;
        // Transfer to Guru Safe
        _mint(_guruSafe, _totalSupply);
    }
}