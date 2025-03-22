// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 *
                 ƒƒƒƒƒƒƒ
              ƒƒƒƒƒƒƒƒƒƒ ƒƒƒƒƒƒ
             ƒƒƒƒƒƒƒƒƒƒƒ ƒƒƒƒƒƒ
            ƒƒƒƒƒƒƒ      ƒƒƒƒƒƒ
            ƒƒƒƒƒƒ       ƒƒƒƒƒƒ
            ƒƒƒƒƒƒ       ƒƒƒƒƒƒ       ƒƒƒƒƒƒƒƒƒƒƒƒƒ   ƒƒƒƒƒƒƒ          ƒƒƒƒƒƒ
           ƒƒƒƒƒƒƒ       ƒƒƒƒƒƒ    ƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒ  ƒƒƒƒƒƒ         ƒƒƒƒƒƒ
       ƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒ   ƒƒƒƒƒƒ   ƒƒƒƒƒƒƒ      ƒƒƒƒƒƒƒ  ƒƒƒƒƒƒ        ƒƒƒƒƒƒ
       ƒƒƒƒƒƒƒƒƒƒƒƒƒƒ    ƒƒƒƒƒƒ   ƒƒƒƒƒƒ        ƒƒƒƒƒƒ  ƒƒƒƒƒƒ       ƒƒƒƒƒƒ
          ƒƒƒƒƒƒƒ        ƒƒƒƒƒƒ                 ƒƒƒƒƒƒ   ƒƒƒƒƒƒ     ƒƒƒƒƒƒ
          ƒƒƒƒƒƒ         ƒƒƒƒƒƒ          ƒƒƒƒƒƒƒƒƒƒƒƒƒ    ƒƒƒƒƒƒ    ƒƒƒƒƒƒ
          ƒƒƒƒƒƒ         ƒƒƒƒƒƒ    ƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒ    ƒƒƒƒƒƒ   ƒƒƒƒƒƒ
         ƒƒƒƒƒƒƒ         ƒƒƒƒƒƒ  ƒƒƒƒƒƒƒƒ       ƒƒƒƒƒƒ     ƒƒƒƒƒƒ  ƒƒƒƒƒ
         ƒƒƒƒƒƒ          ƒƒƒƒƒƒ  ƒƒƒƒƒƒ         ƒƒƒƒƒƒ      ƒƒƒƒƒƒƒƒƒƒƒƒ
         ƒƒƒƒƒƒ          ƒƒƒƒƒƒ  ƒƒƒƒƒƒ        ƒƒƒƒƒƒƒ      ƒƒƒƒƒƒƒƒƒƒƒ
        ƒƒƒƒƒƒƒ          ƒƒƒƒƒƒ  ƒƒƒƒƒƒƒ     ƒƒƒƒƒƒƒƒƒ       ƒƒƒƒƒƒƒƒƒ
        ƒƒƒƒƒƒ           ƒƒƒƒƒƒ   ƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒ        ƒƒƒƒƒƒƒƒ
       ƒƒƒƒƒƒƒ           ƒƒƒƒƒƒ      ƒƒƒƒƒƒƒƒ    ƒƒƒƒƒƒ       ƒƒƒƒƒƒƒ
       ƒƒƒƒƒƒ                                                 ƒƒƒƒƒƒ
  ƒƒƒƒƒƒƒƒƒƒƒ                                           ƒƒƒƒƒƒƒƒƒƒƒ
  ƒƒƒƒƒƒƒƒƒ                                             ƒƒƒƒƒƒƒƒƒƒ
  ƒƒƒƒƒƒ                                                ƒƒƒƒƒƒƒƒ
                                                       ƒƒƒƒƒƒƒƒ
 */

import {ERC20Permit, ERC20, Nonces} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract FlayToken is ERC20, ERC20Permit, ERC20Votes {
    constructor(
        address tokenIssuer
    ) ERC20("Flayer", "FLAY") ERC20Permit("Flayer") {
        _mint({
            account: tokenIssuer,
            value: 1_000_000_000 ether // 1 billion tokens
        });
    }

    /// Override required functions from inherited contracts
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}