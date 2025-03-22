// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20, with no permissions or minting.
 * @author CreateMyToken (https://www.createmytoken.com/)
 */
contract FairLaunchERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol, uint256 _supply) ERC20(_name, _symbol) {
        _mint(msg.sender, _supply);
    }
}