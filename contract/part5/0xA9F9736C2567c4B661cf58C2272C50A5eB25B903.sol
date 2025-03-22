// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC721Extended is IERC721 {
    function totalSupply() external view returns (uint256);
}

contract EthereumToolkit is Ownable {
    // Fixed chunk size for token search
    uint256 private constant CHUNK_SIZE = 5000;
    
    // Pack structs to use fewer storage slots
    struct EthTransfer {
        uint96 amount;
        address recipient;
    }

    struct ERC721Transfer {
        uint32 tokenId;
        address recipient;
    }

    // Custom errors for gas optimization
    error ZeroAddress();
    error EmptyArray();
    error TransferFailed();
    error InvalidNFT();
    error InsufficientBalance();
    error NotApproved();
    error InvalidRange();
    error RangeTooLarge();

    // Minimal events
    event AssetTransferred(address indexed token, address indexed recipient, uint256 amount);
    event AssetRescued(address indexed token, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function walletOfOwner(
        IERC721Extended nft,
        address owner,
        uint256 startId,
        uint256 endId
    ) external view returns (uint256[] memory) {
        if (address(nft) == address(0)) revert InvalidNFT();
        if (owner == address(0)) revert ZeroAddress();
        if (endId < startId) revert InvalidRange();
        if (endId - startId >= CHUNK_SIZE) revert RangeTooLarge();
        
        uint256 balance = nft.balanceOf(owner);
        if (balance == 0) return new uint256[](0);
        
        uint256[] memory tokenIds = new uint256[](balance);
        uint256 tokenIndex;
        
        for (uint256 tokenId = startId; tokenId <= endId && tokenIndex < balance;) {
            try nft.ownerOf(tokenId) returns (address tokenOwner) {
                if (tokenOwner == owner) {
                    tokenIds[tokenIndex] = tokenId;
                    unchecked { tokenIndex++; }
                }
            } catch {}
            unchecked { tokenId++; }
        }
        
        // Trim array if needed
        if (tokenIndex < balance) {
            assembly {
                mstore(tokenIds, tokenIndex)
            }
        }
        
        return tokenIds;
    }

    function getEthBalances(address[] calldata addresses) external view returns (uint256[] memory) {
        if (addresses.length == 0) revert EmptyArray();
        
        uint256[] memory balances = new uint256[](addresses.length);
        for (uint256 i; i < addresses.length;) {
            if (addresses[i] == address(0)) revert ZeroAddress();
            balances[i] = addresses[i].balance;
            unchecked { i++; }
        }
        return balances;
    }

    function getERC721Balance(IERC721 nft, address[] calldata addresses) external view returns (uint256[] memory) {
        if (address(nft) == address(0)) revert InvalidNFT();
        if (addresses.length == 0) revert EmptyArray();
        
        uint256[] memory balances = new uint256[](addresses.length);
        for (uint256 i; i < addresses.length;) {
            if (addresses[i] == address(0)) revert ZeroAddress();
            balances[i] = nft.balanceOf(addresses[i]);
            unchecked { i++; }
        }
        return balances;
    }

    function batchTransferERC721(IERC721 nft, ERC721Transfer[] calldata transfers) external {
        if (address(nft) == address(0)) revert InvalidNFT();
        if (transfers.length == 0) revert EmptyArray();
        
        for (uint256 i; i < transfers.length;) {
            if (transfers[i].recipient == address(0)) revert ZeroAddress();
            
            if (!nft.isApprovedForAll(msg.sender, address(this)) && 
                nft.getApproved(transfers[i].tokenId) != address(this)) revert NotApproved();
            
            nft.transferFrom(msg.sender, transfers[i].recipient, transfers[i].tokenId);
            emit AssetTransferred(address(nft), transfers[i].recipient, transfers[i].tokenId);
            unchecked { i++; }
        }
    }

    function disperseEther(address[] calldata recipients) external payable {
        if (recipients.length == 0) revert EmptyArray();
        uint256 value = msg.value / recipients.length;
        
        for (uint256 i; i < recipients.length;) {
            if (recipients[i] == address(0)) revert ZeroAddress();
            (bool success, ) = recipients[i].call{value: value}("");
            if (!success) revert TransferFailed();
            emit AssetTransferred(address(0), recipients[i], value);
            unchecked { i++; }
        }
    }

    function disperseEther(EthTransfer[] calldata transfers) external payable {
        if (transfers.length == 0) revert EmptyArray();
        
        for (uint256 i; i < transfers.length;) {
            if (transfers[i].recipient == address(0)) revert ZeroAddress();
            (bool success, ) = transfers[i].recipient.call{value: transfers[i].amount}("");
            if (!success) revert TransferFailed();
            emit AssetTransferred(address(0), transfers[i].recipient, transfers[i].amount);
            unchecked { i++; }
        }
    }

    function rescueEth() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientBalance();
        
        (bool success, ) = msg.sender.call{value: balance}("");
        if (!success) revert TransferFailed();
        
        emit AssetRescued(address(0), balance);
    }

    function rescueERC721(IERC721 nft, uint256 tokenId) external onlyOwner {
        if (address(nft) == address(0)) revert InvalidNFT();
        if (!nft.supportsInterface(0x80ac58cd)) revert InvalidNFT();
        
        nft.transferFrom(address(this), msg.sender, tokenId);
        emit AssetRescued(address(nft), tokenId);
    }

    receive() external payable {}
}