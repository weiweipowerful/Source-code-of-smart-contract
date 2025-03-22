// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract OptopiaAI is ERC20Permit, ERC20Burnable, Ownable2Step {
	uint256 public constant maxCap = 10_000_000_000 ether;

	error CapExceeded(uint256 cap, uint256 amount);

	constructor(address owner) ERC20("Optopia AI", "OPAI") ERC20Permit("Optopia AI") Ownable(owner) {}

	function mint(address to, uint256 amount) external onlyOwner {
		if (totalSupply() + amount > maxCap) {
			revert CapExceeded(maxCap, amount);
		}
		_mint(to, amount);
	}
}