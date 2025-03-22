// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract Rekt is Ownable, ERC20, ERC20Burnable, ERC20Pausable, ERC20Permit {
    constructor(
        string memory name_,
        string memory symbol_
    ) Ownable(msg.sender) ERC20(name_, symbol_) ERC20Permit(name_) {
        _mint(
            0x424De83E135d0BE9a4b6b1268b04BCD4D92F7C98,
            420_690_000_000_000 ether
        );
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}