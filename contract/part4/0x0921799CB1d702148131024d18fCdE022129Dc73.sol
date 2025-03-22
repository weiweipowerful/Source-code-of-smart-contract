// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit, Nonces } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

// LightLink 2024

contract LightLink is ERC20Votes, ERC20Permit {
  constructor() ERC20("LightLink", "LL") ERC20Permit("LightLink") {
    _mint(0xdE2552948aacb82dCa7a04AffbcB1B8e3C97D590, 1000000000 * (10**decimals()));
  }

  function _update(address from, address to, uint256 value) internal virtual override(ERC20, ERC20Votes) {
    ERC20Votes._update(from, to, value);
  }

  function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
    return super.nonces(owner);
  }
}