// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FreeMintToken is ERC20, Ownable {

    uint public constant MAX_SUPPLY = 210000000000 * 1 ether;
    uint public constant MINT_AMOUNT = 5000000 * 1 ether;

    mapping(address => bool) private hasMinted;

    constructor() ERC20("Daram", "Daram") Ownable(msg.sender) {

    }

    function mint() external {
        require(totalSupply() + MINT_AMOUNT <= MAX_SUPPLY, "Total supply exceeded");
        require(!hasMinted[msg.sender], "Address has already minted");
        require(msg.sender == tx.origin, "Contracts are not allowed to mint");

        hasMinted[msg.sender] = true;
        _mint(msg.sender, MINT_AMOUNT);
    }

}