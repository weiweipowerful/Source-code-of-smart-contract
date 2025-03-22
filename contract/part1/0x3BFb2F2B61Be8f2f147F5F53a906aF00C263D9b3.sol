// contracts/GameItem.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract FreysaNFT is ERC721 {
    event FreysaNFTDeployed(address contractAddress, string name);

    uint256 private _nextTokenId;
    address payable public owner;
    address public airdropManager;
    string private __baseURI;
    string public _contractURIPath;
    uint256 public _maxSupply;

    uint256 public mintPrice;
    constructor(
        string memory name,
        string memory baseURI,
        string memory symbol,
        uint256 maxSupply
    ) ERC721(name, symbol) {
        owner = payable(msg.sender);
        airdropManager = msg.sender;
        __baseURI = baseURI;
        mintPrice = 0.25 ether;
        _maxSupply = maxSupply;

        emit FreysaNFTDeployed(address(this), name);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyAirdropManager() {
        require(
            msg.sender == airdropManager,
            "Only airdrop manager can call this function"
        );
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        owner = payable(newOwner);
    }

    function setAirdropManager(address newAirdropManager) public onlyOwner {
        require(
            newAirdropManager != address(0),
            "New airdrop manager cannot be zero address"
        );
        airdropManager = newAirdropManager;
    }

    function getAirdropManager() public view returns (address) {
        return airdropManager;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return __baseURI;
    }

    function setBaseURI(string memory baseURI_) public onlyOwner {
        __baseURI = baseURI_;
    }

    function mint(address player) public payable returns (uint256) {
        require(msg.value >= mintPrice, "Insufficient funds");
        require(_nextTokenId < _maxSupply, "Max supply reached");

        (bool success, ) = owner.call{value: msg.value}("");
        require(success, "Transfer to owner failed");

        uint256 tokenId = _nextTokenId++;
        _mint(player, tokenId);

        return tokenId;
    }

    function getNumberOfTokensMinted() public view returns (uint256) {
        return _nextTokenId;
    }

    function airdrop(address[] calldata addresses) public onlyAirdropManager {
        for (uint256 i = 0; i < addresses.length; i++) {
            uint256 tokenId = _nextTokenId++;
            _mint(addresses[i], tokenId);
        }
    }

    function setContractURI(string memory contractURIPath) public onlyOwner {
        _contractURIPath = contractURIPath;
    }

    function contractURI() public view returns (string memory) {
        return _contractURIPath;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        string memory metadataUri = string(
            abi.encodePacked(__baseURI, "/", Strings.toString(tokenId), ".json")
        );

        return metadataUri;
    }
}