// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {Context} from "openzeppelin-contracts/utils/Context.sol";
import {Context as LBContext} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC721C} from "limitbreak/erc721c/ERC721C.sol";
import {ERC721OpenZeppelin} from "limitbreak/token/erc721/ERC721OpenZeppelin.sol";
import {MetadataURI} from "limitbreak/token/erc721/MetadataURI.sol";
import {EIP712} from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import "limitbreak/programmable-royalties/BasicRoyalties.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

contract Wildpass is Ownable2Step, ERC721C, MetadataURI, BasicRoyalties, EIP712 {
    using Strings for uint256;

    event ExpectedSignerChanged(address newSigner);

    error InvalidSigner();
    error InvalidTokenId();
    error InvalidReceiver();
    error InvalidArrays();

    struct MintParams {
        address to;
        uint256 tokenId;
    }

    string public constant SIGNING_DOMAIN = "WildcardWildpass";
    string public constant SIGNATURE_VERSION = "1";
    address public expectedSigner;

    constructor(
        address royaltyReceiver_,
        uint96 royaltyFeeNumerator_,
        string memory name_,
        string memory symbol_,
        address expectedSigner_
    )
        ERC721OpenZeppelin(name_, symbol_)
        BasicRoyalties(royaltyReceiver_, royaltyFeeNumerator_)
        EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION)
    {
        expectedSigner = expectedSigner_;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721C, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function mint(MintParams calldata mintParams, bytes calldata signature) public {
        // Wildpass tokenIds start at 1 and go to 4444
        if (mintParams.tokenId == 0 || mintParams.tokenId > 4444) {
            revert InvalidTokenId();
        }

        if (mintParams.to == address(0)) {
            revert InvalidReceiver();
        }

        bytes32 digest = hashMintParams(mintParams);
        address signer = ECDSA.recover(digest, signature);
        if (signer != expectedSigner) {
            revert InvalidSigner();
        }

        _mint(mintParams.to, mintParams.tokenId);
    }

    function bulkMint(MintParams[] calldata mintParams, bytes[] calldata signatures) public {
        if (mintParams.length != signatures.length) {
            revert InvalidArrays();
        }

        for (uint256 i = 0; i < mintParams.length; ++i) {
            mint(mintParams[i], signatures[i]);
        }
    }

    function hashMintParams(MintParams calldata mintParams) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(keccak256("MintParams(address to,uint256 tokenId)"), mintParams.to, mintParams.tokenId)
            )
        );
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), suffixURI)) : "";
    }

    /// @dev Required to return baseTokenURI for tokenURI
    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public {
        _requireCallerIsContractOwner();
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public {
        _requireCallerIsContractOwner();
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function resetTokenRoyalty(uint256 tokenId) public {
        _requireCallerIsContractOwner();
        _resetTokenRoyalty(tokenId);
    }

    function setExpectedSigner(address newSigner) public {
        _requireCallerIsContractOwner();
        expectedSigner = newSigner;
        emit ExpectedSignerChanged(newSigner);
    }

    function _msgData() internal view override(Context, LBContext) returns (bytes calldata) {
        return super._msgData();
    }

    function _msgSender() internal view override(Context, LBContext) returns (address) {
        return super._msgSender();
    }

    function _requireCallerIsContractOwner() internal view virtual override {
        _checkOwner();
    }
}