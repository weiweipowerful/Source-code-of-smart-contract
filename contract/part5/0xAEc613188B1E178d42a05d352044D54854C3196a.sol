// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract SUIDesciAgents is ERC20, ERC20Burnable, Ownable {
    bool private initialized;

    constructor() ERC20("SUI Desci Agents", "DESCI") {
    }

    function initialize(
        address owner
    ) external {
        require(!initialized, "Contract is already initialized");

        _transferOwnership(owner);
        initialized = true;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}