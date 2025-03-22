// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

import {BitmapBT404Mirror} from "../bt404/BitmapBT404Mirror.sol";

contract BitmapPunks721 is BitmapBT404Mirror {
    constructor(address _traitRegistry, address _traitOwner) BitmapBT404Mirror(tx.origin) {
        _initializeBT404Mirror(tx.origin);
        _initializeTraitsMetadata(_traitRegistry, _traitOwner);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory _name = name();
        (string memory attributesJson, string memory imageURI) =
            _getTokenAttributesAndImage(tokenId);

        return string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    string.concat(
                        '{"external_url":"https://bitmappunks.com","description":"A fully-onchain, ultra-large, hybrid collection.","name":"',
                        _name,
                        " #",
                        LibString.toString(tokenId),
                        '","attributes":',
                        attributesJson,
                        ',"image":"',
                        imageURI,
                        '"}'
                    )
                )
            )
        );
    }
}