// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "erc721a/contracts/extensions/ERC721AQueryable.sol";
contract Polyhedra2024 is Ownable, ERC721AQueryable  {
    string private metadataUri;

    uint256 public mintLimit;
    uint256 public mintStartTime;
    uint256 public mintEndTime;


    modifier checkMintTimes() {
        require(block.timestamp >= mintStartTime, "The event has not started yet.");
        require(block.timestamp <= mintEndTime, "The event has ended.");
        _;
    }

    constructor(
        uint256 _mintStartTime,
        uint256 _mintEndTime,
        uint256 _mintLimit,
        string memory _metadataUri
    ) ERC721A("Polyhedra 2024", "Polyhedra 2024") {
        require(_mintStartTime < _mintEndTime, "Invalid StartTimes");
        require(_mintLimit > 0, "Invalid MintLimit");
        mintStartTime = _mintStartTime;
        mintEndTime = _mintEndTime;
        mintLimit = _mintLimit;
        metadataUri = _metadataUri;
    }

    function mint() external   checkMintTimes {
        require(_numberMinted(msg.sender) + 1 <= mintLimit, "You have reached the claim limit.");
        _safeMint(msg.sender, 1);
    }

    function batchMint(uint256 _size) external   checkMintTimes {
        require(_numberMinted(msg.sender) + _size <= mintLimit, "You have reached the claim limit.");
        _safeMint(msg.sender, _size);
    }

    function getMintSurplus(address userAddress) view external returns (uint256) {
        return mintLimit - _numberMinted(userAddress);
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");
        return metadataUri;
    }

    function setMintTimes(uint256 _mintStartTime, uint256 _mintEndTime) external onlyOwner {
        require(_mintStartTime < _mintEndTime, "Invalid StartTimes");
        mintStartTime = _mintStartTime;
        mintEndTime = _mintEndTime;
    }

    function setMintLimit(uint256 _mintLimit) external onlyOwner {
        mintLimit = _mintLimit;
    }

    function setMetadataUri(string memory _newMetadataUri) external onlyOwner {
        metadataUri = _newMetadataUri;
    }

}