// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

///////////|\\\\\\\\\\\
//   .     '     ,   \\
//     _________     \\
//  _ /_|_____|_\ _  \\
//    '. \   / .'    \\
//      '.\ /.'      \\
//        '.'        \\
///////////|\\\\\\\\\\\

pragma solidity ^0.8.22;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract HandsNFTAI is ERC721, Ownable {
    using Strings for uint256;

    uint256 private _nextTokenId;

    string public baseURI = "https://store.handsnft.fun/metadata/";

    constructor(
        address _initialOwner
    ) ERC721("HandsNFT AI", "HAI") Ownable(_initialOwner) {}

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);

        string memory basePath = _baseURI();
        return
            bytes(basePath).length > 0
                ? string.concat(basePath, tokenId.toString(), ".json")
                : "";
    }

    function safeMint(address to) public onlyOwner {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }
}