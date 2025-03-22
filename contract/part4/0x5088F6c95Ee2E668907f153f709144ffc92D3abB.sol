// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {ERC721, Strings} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract BeeOS is ERC721, ERC2981, AccessControl {
    using Strings for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    string private _unrevealedURI;
    string private _revealedURI;
    uint256 private _nextTokenId = 1;

    address public owner;
    uint256 public revealTime;

    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    constructor(
        address defaultAdmin,
        address minter,
        address admin,
        address royalty,
        address _owner,
        uint256 reveal,
        string memory revealedURI,
        string memory unrevealedURI
    ) ERC721("BeeOS", "BeeOS") {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(ADMIN_ROLE, defaultAdmin);
        _grantRole(ADMIN_ROLE, admin);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setDefaultRoyalty(royalty, 500);
        revealTime = reveal;
        _revealedURI = revealedURI;
        _unrevealedURI = unrevealedURI;
        owner = _owner;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        if (block.timestamp >= revealTime) return string(abi.encodePacked(_revealedURI, tokenId.toString(), ".json"));
        else return string(abi.encodePacked(_unrevealedURI, tokenId.toString(), ".json"));
        
    }

    function safeMint(
        address to
    ) public onlyRole(MINTER_ROLE) returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    function mintMany(
        address to,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) {
        for (uint256 i = 0; i < amount; i++) {
            safeMint(to);
        }
    }

    function setRevealedURI(string memory newURI) external onlyRole(ADMIN_ROLE) {
        _revealedURI = newURI;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function setUnrevealedURI(string memory newURI) external onlyRole(ADMIN_ROLE) {
        _unrevealedURI = newURI;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function setRevealedTime(uint256 time) external onlyRole(ADMIN_ROLE) {
        revealTime = time;
    }

    function setDefaultRoyalty(address recipient, uint96 feeNumerator) external onlyRole(ADMIN_ROLE) {
        _setDefaultRoyalty(recipient, feeNumerator);
    }

    function emitMetadataUpdate() external onlyRole(ADMIN_ROLE) {
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, AccessControl, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}