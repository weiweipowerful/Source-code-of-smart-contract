// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MetaTrustCoin is ERC20, ERC20Capped, Ownable {
    constructor(address initialOwner) ERC20("MetaTrustCoin", "MTC") ERC20Capped(500_000_000 * 10**18) Ownable(initialOwner) {
        uint256 initialSupply = 50_000_000 * 10**18;
        _mint(msg.sender, initialSupply);
    }

    function mint(address account, uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= cap(), "Exceeds cap");
        _mint(account, amount);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped) {
        super._update(from, to, value);
    }
}