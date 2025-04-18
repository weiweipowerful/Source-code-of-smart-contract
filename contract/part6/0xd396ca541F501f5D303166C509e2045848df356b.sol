// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BasicRoyalties, ERC2981 } from "../../lib/creator-token-contracts/contracts/programmable-royalties/BasicRoyalties.sol";
import { ILandToken } from "./ILandToken.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { ERC721VotesC, ERC721, EIP712 } from "./ERC721VotesC.sol";
import "../../lib/creator-token-contracts/contracts/interfaces/ICreatorTokenTransferValidator.sol";


/**
 * @title LandToken
 * @dev ERC721 token contract with Merkle tree-based airdrop issuance and custom URI handling.
 * @custom:security-contact [email protected]
 */
contract LandToken is Ownable, ERC721VotesC, BasicRoyalties, ILandToken {
    /// @dev Thrown when trying to issue a token that has already been claimed.
    /// @param tokenId The ID of the token that has already been claimed.
    /// @param owner The current owner of the token.
    error ID_CLAIMED(uint256 tokenId, address owner);

    /// @dev Thrown when a Merkle proof is invalid for the provided recipient and token ID.
    error INVALID_PROOF();

    /// @dev Thrown when querying a token ID that does not exist.
    /// @param tokenId The ID of the token that does not exist.
    error NONEXISTENT_ID(uint256 tokenId);

    /// @notice URI containing contract-level metadata.
    string public contractURI;

    /// @notice Base URI for the token metadata.
    string public baseURI;

    /// @notice Root of the Merkle tree used to verify issuance eligibility.
    bytes32 public immutable root;

    /// @notice Per-token URIs
    mapping(uint256 => string) private tokenURIs;

    /// @notice Event emitted when the base URI is updated
    event BaseURIUpdated(string newBaseURI);

    /// @notice ERC-4906 compatible event emitted when individual token URIs are updated
    event MetadataUpdate(uint256 _tokenId);

    /// @notice Event emitted when the contract URI is updated
    event ContractURIUpdated(string newContractURI);

    /**
     * @notice Constructor to initialize the LandToken contract.
     * @param royaltyReceiver_ The address to receive royalty payments.
     * @param royaltyFeeNumerator_ The royalty fee numerator (out of 10,000).
     * @param tokenName_ The name of the token collection.
     * @param tokenSymbol_ The symbol of the token collection.
     * @param contractURI_ The URI pointing to contract-level metadata.
     * @param baseURI_ The base URI for token metadata.
     * @param version_ The EIP712 contract version identifier
     * @param root_ The root of the Merkle tree for claim validation.
     */
    constructor(
        address royaltyReceiver_,
        uint96 royaltyFeeNumerator_,
        string memory tokenName_,
        string memory tokenSymbol_,
        string memory contractURI_,
        string memory baseURI_,
        string memory version_,
        bytes32 root_
    )
        ERC721(tokenName_, tokenSymbol_)
        BasicRoyalties(royaltyReceiver_, royaltyFeeNumerator_)
        EIP712(tokenName_, version_)
    {
        root = root_;
        baseURI = baseURI_;
        contractURI = contractURI_;
    }

    /**
     * @notice User claims a token to a recipient if the Merkle proof is valid and the token has not been claimed.
     * @dev This function verifies the Merkle proof before minting the token.
     * @dev If _burn is implemented, then the ID_CLAIMED revert should be changed to check the proof instead.
     * @param proof The Merkle proof that validates the recipient's claim.
     * @param recipient The address of the recipient.
     * @param tokenId The ID of the token to be issued.
     * @custom:throws ID_CLAIMED if the token has already been claimed.
     * @custom:throws INVALID_PROOF if the provided Merkle proof is invalid.
     */
    function claim(bytes32[] memory proof, address recipient, uint256 tokenId) public override {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(recipient, tokenId))));

        if (_exists(tokenId)) {
            revert ID_CLAIMED(tokenId, ownerOf(tokenId));
        }
        if (!MerkleProof.verify(proof, root, leaf)) {
            revert INVALID_PROOF();
        }

        _safeMint(recipient, tokenId);
    }

    /**
     * @notice Issues a token to a recipient if the Merkle proof is valid and the token has not been claimed.
     * @dev This function verifies the Merkle proof before minting the token.
     * @dev If _burn is implemented, then the ID_CLAIMED revert should be changed to check the proof instead.
     * @param proof The Merkle proof that validates the recipient's claim.
     * @param recipient The address of the recipient.
     * @param tokenId The ID of the token to be issued.
     * @custom:throws ID_CLAIMED if the token has already been claimed.
     * @custom:throws INVALID_PROOF if the provided Merkle proof is invalid.
     */
    function issue(bytes32[] memory proof, address recipient, uint256 tokenId, string memory metadata) public override onlyOwner {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(recipient, tokenId))));

        if (_exists(tokenId)) {
            revert ID_CLAIMED(tokenId, ownerOf(tokenId));
        }
        if (!MerkleProof.verify(proof, root, leaf)) {
            revert INVALID_PROOF();
        }

        tokenURIs[tokenId] = metadata;
        _safeMint(recipient, tokenId);
    }

    /**
     * @notice Returns the token URI for a given token ID.
     * @dev Concatenates the base URI with the token ID. Or if set, returns the per token URI.
     * @param tokenId The ID of the token to query.
     * @return The token URI string.
     * @custom:throws NONEXISTENT_ID if the token ID does not exist.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) {
            revert NONEXISTENT_ID(tokenId);
        }

        string memory _tokenURI = tokenURIs[tokenId];
        if (bytes(_tokenURI).length == 0) {
            return string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json"));
        }

        return _tokenURI;
    }

    /**
     * @notice Updates the contract-level metadata URI.
     * @dev Only the owner can call this function.
     * @param newContractURI The new contract URI to be set.
     */
    function setContractURI(string calldata newContractURI) public override onlyOwner {
        contractURI = newContractURI;
        emit ContractURIUpdated(newContractURI);
    }

    /**
     * @notice Updates the token base metadata URI.
     * @dev Only the owner can call this function.
     * @param newBaseURI The new base URI to be set.
     */
    function setBaseURI(string calldata newBaseURI) public override onlyOwner {
        baseURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @notice Updates the default royalty basis points for all tokens.
     * @dev Only the contract owner can call this function.
     * This function sets a default royalty that applies to all tokens if no specific token royalty is set.
     * @param receiver The address to receive the royalty payments.
     * @param feeNumerator The royalty fee in basis points.
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public override onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @notice Updates the royalty basis points for a specific token.
     * @dev Only the contract owner can call this function.
     * This function sets a custom royalty for a specific token, overriding the default royalty.
     * @param tokenId The ID of the token for which the royalty is being set.
     * @param receiver The address to receive the royalty payments for the specified token.
     * @param feeNumerator The royalty fee in basis points.
     */
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public override onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     * @param tokenId The ID of the token for which the URI is being set.
     * @param _tokenURI The URI being set.
     * - `tokenId` must exist.
     */
    function setTokenURI(uint256 tokenId, string memory _tokenURI) public override onlyOwner {
        if (!_exists(tokenId)) {
            revert NONEXISTENT_ID(tokenId);
        }
        tokenURIs[tokenId] = _tokenURI;

        emit MetadataUpdate(tokenId);
    }

    /**
     * @dev Required override, returns supported interface ID
     * @param interfaceId Supported interface ID
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721VotesC, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}