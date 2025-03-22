// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/// @notice OFT is an ERC-20 token that extends the OFTCore contract.
contract Seedworld is OFT {
    constructor(
        string memory _name,
        string memory _symbol,
        address _mintTo,
        uint256 _amount,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) {
        if (_amount > 0) {
            _mint(_mintTo, _amount * 10 ** decimals());
        }
    }
}