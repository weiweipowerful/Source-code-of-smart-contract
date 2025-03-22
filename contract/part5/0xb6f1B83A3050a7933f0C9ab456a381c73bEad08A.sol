// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract USTT is ERC20, Ownable {
    constructor() ERC20("TEDR", "USTT") Ownable() {}

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external onlyOwner returns (bool) {
        _burn(from, amount);
        return true;
    }

    function decimals() override public pure returns (uint8) {
        return 6;
    }
}