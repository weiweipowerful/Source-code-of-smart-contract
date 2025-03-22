// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";


/**
 * @title YOUR Token (YOUR)
 */
contract YourToken is ERC20, ERC20Burnable, ERC20Permit {
    /**
     * @dev Contract constructor.
     */
    constructor()
        ERC20("YOUR AI", "YOURAI")
        ERC20Permit("YOUR AI")
    {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals()); // Initial supply deposited to the address provided here
    }
}