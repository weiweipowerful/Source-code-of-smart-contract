// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Author: @DuckJHN
contract POPGToken is ERC20, ERC20Permit, Ownable {
    uint256 public constant MAX_SUPPLY = 10_000_000_000 * 10**18;

    constructor(address _vestingWallet)
        ERC20("POPG", "POPG")
        ERC20Permit("POPG Token")
        Ownable(msg.sender)
    {
        _mint(_vestingWallet, MAX_SUPPLY);
    }

    function burn(uint256 amount) public  {
        _burn(msg.sender, amount);
    }

}