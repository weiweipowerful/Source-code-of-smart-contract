// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;

import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @title Dirt Simple Non-Fungible Token Staking Contract
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @notice Allows for the deposit and withdrawal of NFTs from a specified collection. 
/// @dev Allows external query of all NFTs a user has staked with historical data on their last staked/unstaked timestamp.
contract GenesisNFTStaking is IERC721Receiver, ERC165 {
    using EnumerableSet for EnumerableSet.UintSet;
    IERC721 private immutable _underlying;

    struct StakingData {
        uint256 last_staked;
        uint256 last_unstaked;
        address last_staker;
    }

    mapping(uint256 => StakingData) public staking_data;
    mapping(address => EnumerableSet.UintSet) staked_tokens;

    error ERC721UnsupportedToken(address token);
    error MustInitiateStakingFromSelf();
    error TokenNotStakedByAddress(uint256 tokenID, address sender);

    event TokenStaked(uint256 tokenID, address staker);
    event TokenUnstaked(uint256 tokenID, address staker);

    constructor(IERC721 underlyingToken) {
        _underlying = underlyingToken;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function deposit(uint256[] memory tokenIds) public virtual returns (bool) {
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ++i) {
            underlying().safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }
        return true;
    }

    function withdraw(uint256[] memory tokenIds) public virtual returns (bool) {
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            if (staked_tokens[msg.sender].contains(tokenId)) {
                staking_data[tokenId].last_unstaked = block.timestamp;
                staked_tokens[msg.sender].remove(tokenId);
                emit TokenUnstaked(tokenId, msg.sender);
                underlying().safeTransferFrom(address(this), msg.sender, tokenId);
            } else {
                revert TokenNotStakedByAddress(tokenId, msg.sender);
            }
        }

        return true;
    }

    /**
     * @dev Used by front-end user to determine which tokens are CURRENTLY staked in the contract.
     */
    function StakedTokens(address staker) public view returns (uint256[] memory ret) {
        uint256 length = staked_tokens[staker].length();
        ret = new uint256[](length);
        for(uint i = 0; i < length; i++) {
            ret[i] = staked_tokens[staker].at(i);
        }
    }

    /**
     * @dev Used by back-end system to query latest staking data from a list of token IDs.
     */
    function TokenData(uint256[] memory tokenIds) public view returns (StakingData[] memory ret) {
        uint256 length = tokenIds.length;
        ret = new StakingData[](length);
        for(uint i = 0; i < length; i++) {
            ret[i] = staking_data[tokenIds[i]];
        }
    }

    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be
     * reverted.
     *
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external returns (bytes4) {
        if (address(underlying()) != msg.sender) {
            revert ERC721UnsupportedToken(msg.sender);
        }
        if (staking_data[tokenId].last_staker == address(0)) {
            staking_data[tokenId] = StakingData(block.timestamp, 0, from);
        } else {
            staking_data[tokenId].last_staked = block.timestamp;
            staking_data[tokenId].last_staker = from;
        }

        staked_tokens[from].add(tokenId);
        emit TokenStaked(tokenId, from);
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @dev Returns the underlying token.
     */
    function underlying() public view virtual returns (IERC721) {
        return _underlying;
    }
}