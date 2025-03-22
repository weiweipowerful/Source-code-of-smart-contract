// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC721, ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IDragonOG} from './interfaces/IDragonOG.sol';

contract DragonOG is IDragonOG, ERC721Enumerable, Ownable2Step {
    using Strings for uint256;
    
    uint256 private _nextTokenId = 1;
    string private _baseTokenURI;
    uint256 public constant MAXIMUM_TOKEN_ID = 3999;

    constructor(string memory baseURI) ERC721("Trusta OG Dragon", "DRAGONOG") Ownable(msg.sender)
    {
        _baseTokenURI = baseURI;
    }

    function mint(address to) public override onlyOwner returns(uint256) {
        uint256 tokenId = _nextTokenId;
        if (tokenId > MAXIMUM_TOKEN_ID){
            revert OutOfStock(address(this));
        }
        _nextTokenId += 1;
        _mint(to, tokenId);
        return tokenId;
    }

    function setBaseURI(string memory baseURI) public override onlyOwner {
        _baseTokenURI = baseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory baseURI = _baseTokenURI;
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

}