// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Zulu is ERC20, ERC20Permit, ERC20Pausable, Ownable {
  uint256 public immutable maxSupply = 1_000_000_000 * 10 ** 18;

  constructor() ERC20("Zulu Network", "ZULU") ERC20Permit("Zulu Network") Ownable(msg.sender) {
    _mint(msg.sender, maxSupply);
  }

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
  }

  function burn(uint256 amount) public onlyOwner {
    _burn(msg.sender, amount);
  }

  // overrides
  function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
    super._update(from, to, value);
  }
}