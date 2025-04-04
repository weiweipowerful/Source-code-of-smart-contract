// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC20} from "./lib/solmate/ERC20.sol";
import {RolesAuthority} from "./RolesAuthority.sol";

/* The purpose of this token is to temporarily be nontransferable except for special cases.
  This is done by role-based access control. The token implements its own authorisation logic (by inheriting from RolesAuthority). It points to itself as its authority.

  The owner is then able to define who can call what functions of the token, then make the function public at a later stage (at an extra cost of 1 SLOAD).
*/
contract Token is ERC20, RolesAuthority {
  // We pass all arguments to the ancestors except the authority argument which is the token itself.
  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    address _owner
  ) ERC20(_name, _symbol, _decimals) RolesAuthority(_owner) {
    _mint(_owner, 100_000_000 * 1e18);
  }

  // `transfer` now `requiresAuth`.
  function transfer(address to, uint256 amount)
    public
    override
    requiresAuth
    returns (bool)
  {
    return super.transfer(to, amount);
  }

  // `transferFrom` now `requiresAuth`.
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public override requiresAuth returns (bool) {
    return super.transferFrom(from, to, amount);
  }

  // `mint` is added to the external interface, and also `requiresAuth`
  function mint(address to, uint256 amount) external requiresAuth {
    _mint(to, amount);
  }

  // `burn` is added to the external interface
  function burn(uint256 amount) external {
    _burn(msg.sender, amount);
  }

  // manually distribute the token based on the off-chain calculated balances.
  function migration(address[] calldata users, uint256[] calldata balances) external requiresAuth {
    uint256 length = users.length;
    address admin = owner;

    for (uint256 i; i < length; ++i) {
      address user = users[i];
      uint256 balance = balances[i];

      unchecked {
        balanceOf[user] += balance;
        balanceOf[admin] -= balance; 
      }

      emit Transfer(admin, user, balance);
    }
  }
}