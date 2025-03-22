// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ETH01 is ERC20, Ownable {
    constructor() ERC20("ETH0.1", "ETH0.1") Ownable(msg.sender) {
        _mint(msg.sender, 100_000_000 * 10 ** decimals()); // 100 млн токенов
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}