// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./DEXIndex.sol";

contract DEXNFT is ERC721, ERC721URIStorage, ERC721Burnable, Ownable {
    uint256 private _nextTokenId;

    struct PurchaseInfo {
        uint256 amount;
        address createAddress;
        uint256[]  tokenAmounts;
    }

    mapping(uint256 => PurchaseInfo) public purchaseInfo;
    mapping(address => bool) public authorizedContracts;

    constructor(address initialOwner)
        ERC721("DEXNFT", "DEXN")
        Ownable(initialOwner)
    {}

    modifier onlyAuthorized() {
        require(authorizedContracts[msg.sender], "Caller is not authorized");
        _;
    }

    
    function authorizeContract(address contractAddress) public onlyOwner {
        authorizedContracts[contractAddress] = true;
    }

    function revokeContract(address contractAddress) public onlyOwner {
        authorizedContracts[contractAddress] = false;
    }

    function safeMint(
        address to,
        string memory uri,
        uint256 amount,
        address createAddress,
        uint256[] memory tokenAmounts
    ) public onlyAuthorized returns (uint256, address, uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        purchaseInfo[tokenId] = PurchaseInfo(amount, createAddress,tokenAmounts);
        return (tokenId, createAddress, amount);
    }


    function getPurchaseDetails(uint256 tokenId) public view returns (uint256, address,uint256[] memory) {
        PurchaseInfo memory info = purchaseInfo[tokenId];
        return (info.amount, info.createAddress,info.tokenAmounts);
    }

    // The following functions are overrides required by Solidity.

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    

     // Overrides the standard burn function to prevent recursion
    function burn(uint256 tokenId) public virtual override {
        //发送事件,表明赎回esdt
        _burn(tokenId);
        delete purchaseInfo[tokenId];
    } 

    //加入事件
    event redeemedToken(address indexed nftOwner,uint256  tokenId);
    event redeemedEsdt(address indexed nftOwner, uint256  tokenId);


    function redeemEsdt(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "You do not own this NFT");
        (, address createAddress, ) = getPurchaseDetails(tokenId);
        DEXIndex dexIndex = DEXIndex(createAddress);
        dexIndex.redeemEsdt(tokenId,msg.sender);
        burn(tokenId);
        emit redeemedEsdt(msg.sender, tokenId);
    }

   function redeemToken(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "You do not own this NFT");
        emit redeemedToken(msg.sender, tokenId);
    }
    
    event ownerSendToken(address indexed nftOwner, uint256  tokenId);

    //token
    function redeem(uint256 tokenId,uint256 percent) public onlyOwner {
        (, address createAddress, ) = getPurchaseDetails(tokenId);
        DEXIndex dexIndex = DEXIndex(createAddress);
        dexIndex.redeem(tokenId,ownerOf(tokenId),percent);
        burn(tokenId);
        emit ownerSendToken(msg.sender, tokenId);
    }
}