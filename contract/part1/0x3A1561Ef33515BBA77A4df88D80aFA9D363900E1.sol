// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {ERC721Base} from "./ERC721Base.sol";

import {INOStorage} from "../INOStorage.sol";

contract ERC721SequentialId is
    ERC721Base // 12 inherited components
{
    function initialize(
        INOStorage.NFTCollectionData calldata data,
        address initialOwner,
        address ino_
    ) public override {
        super.initialize(data, initialOwner, ino_);
        emit NFTDeployed(
            Type.Sequential,
            initialOwner,
            data.name,
            data.symbol
        );
    }
}