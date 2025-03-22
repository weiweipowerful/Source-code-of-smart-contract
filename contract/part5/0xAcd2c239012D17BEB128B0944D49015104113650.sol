// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/// @title Karrat: ERC20 token.

contract Karrat is ERC20, ERC20Votes, ERC20Permit {
    constructor(
        address MULTISIGONE,
        address MULTISIGTWO
    ) ERC20("KarratCoin", "KARRAT") ERC20Permit("KarratCoin") {
        // Mint 1 billion Karrat tokens (with 18 decimal places) 
        uint halfSupply = 500000000 * 1e18;
        _mint(MULTISIGONE, halfSupply);
        _mint(MULTISIGTWO, halfSupply);
    }
        function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}