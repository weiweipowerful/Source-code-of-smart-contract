// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title OX Coin (OX)
 * @notice OX Coin is an ERC20 token deployed on Ethereum mainnet, using
 * OpenZeppelin v5 libraries. For other EVM chains, it is bridged
 * through LayerZero's ProxyOFT and OFT contracts.
 * OX is deployed with a maximum mintable supply of 9,857,348,536 tokens,
 * and the mints by treasury are dependent upon the old OX burns.
 * Treasury address, which is also responsible for ownership of this
 * contract till ownership is renounced & set to null, is
 * eth:0x4B214e2a2a9716bfF0C20EbDA912B13c7a184E23. The minting can only
 * be done till ownership is renounced.
 */

contract OXCoin is ERC20, ERC20Burnable, Ownable, ERC20Permit {

    uint256 private constant MAXIMUM_SUPPLY = 9857348536 * 10**18;

    constructor(address treasuryMultisig)
        ERC20("OX Coin", "OX")
        ERC20Permit("OX Coin")
        Ownable(treasuryMultisig)
    {}

    /**
     * @notice Mints new OX Coin and assigns them to the specified address
     * @dev Only callable by the owner till ownership is not reounced and
     * maximum supply is not exceeded.
     * @param to The address to which the newly minted OX will be assigned
     * @param amount The amount of OX to mint and assign to the `to` address
     */
    function mint(address to, uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= MAXIMUM_SUPPLY, "OX Coin: Maximum supply exceeded");
        _mint(to, amount);
    }
}