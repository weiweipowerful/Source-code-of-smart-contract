// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title ISLAND Token
/// @custom:security-contact [email protected]
contract ISLAND is OFT, ERC20Permit {
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate,
        address _multisig,
        uint256 _supply
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) ERC20Permit(_name) {
        if (_supply > 0) {
            _mint(_multisig, _supply);
        }
    }
}