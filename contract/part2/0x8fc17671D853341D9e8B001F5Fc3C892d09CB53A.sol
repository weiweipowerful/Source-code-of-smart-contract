// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { OFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";

contract BlockGames is OFT {
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate,
        uint256 _totalSupply,
        address _initialMintRecipient
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) {
        _mint(_initialMintRecipient, _totalSupply); // mints total supply to the specified mint recipient
    }
}