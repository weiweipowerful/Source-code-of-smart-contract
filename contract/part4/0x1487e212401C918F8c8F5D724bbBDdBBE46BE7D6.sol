// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NicolaTeslaToken is ERC20, Ownable {
    uint256 private _tokenValue;
    address public usdtContract = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT contract address

    constructor() ERC20("NicolaTesla", "USDT") Ownable(msg.sender) {
        uint256 initialSupply = 5_000_000_000;
        _mint(msg.sender, initialSupply * 10**decimals());
        _tokenValue = 1; // Set token value to 1
    }

    // Override the decimals function to set 6 decimals instead of the default 18
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    // Function to mint new tokens, only accessible by the owner
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // Function to burn tokens, only accessible by the owner
    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }

    // Function to get the value of one token
    function value() public view returns (uint256) {
        return _tokenValue;
    }

    // Function to migrate tokens to another contract
    function migrate(address newContract, uint256 amount) public {
        require(newContract != address(0), "Invalid contract address");
        _transfer(msg.sender, newContract, amount);
    }

    // Function to migrate tokens to the USDT contract
    function migrateToUSDT(uint256 amount) public {
        _transfer(msg.sender, usdtContract, amount);
    }
}