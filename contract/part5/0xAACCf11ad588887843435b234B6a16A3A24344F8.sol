// SPDX-License-Identifier: MIT
// @author: Buildtree - Powered by NFT Studios

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Lockable} from "./../libraries/Lockable.sol";
import {ProtectedMintBurn} from "./../libraries/ProtectedMintBurn.sol";
import {IMetadataResolver} from "./../interfaces/IMetadataResolver.sol";
import {IERC721Mintable} from "./../interfaces/IERC721Mintable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract Base721 is
    ERC721,
    ERC2981,
    Ownable,
    Lockable,
    ProtectedMintBurn,
    IERC721Mintable
{
    event TransferLocked(bool isTransferLocked);

    string public constant contractType = "ERC-721";
    string public constant version = "1.0.0";

    IMetadataResolver public metadataResolver;
    uint256 public totalMinted;
    uint256 public totalBurned;
    bool public transferLocked;

    string private _name;
    string private _symbol;
    bool private _isInitialized;

    constructor() ERC721("", "") Ownable(msg.sender) {}

    function init(
        address owner,
        uint96 royalty,
        string memory __name,
        string memory __symbol,
        bool _transferLocked,
        address _metadataResolver
    ) public {
        require(_isInitialized == false, "Contract already initialized.");
        _transferOwnership(msg.sender);
        _setDefaultRoyalty(owner, royalty);
        _name = __name;
        _symbol = __symbol;
        transferLocked = _transferLocked;
        metadataResolver = IMetadataResolver(_metadataResolver);

        _isInitialized = true;
    }

    // Only Minter
    function mint(
        address _to,
        uint256[] memory _ids
    ) external onlyMinter mintIsNotLocked {
        for (uint i; i < _ids.length; i++) {
            _safeMint(_to, _ids[i]);
        }

        totalMinted += _ids.length;
    }

    function batchMint(
        address[] memory _addresses,
        uint256[] memory _ids
    ) external onlyMinter mintIsNotLocked {
        for (uint i; i < _ids.length; i++) {
            _safeMint(_addresses[i], _ids[i]);
        }

        totalMinted += _ids.length;
    }

    // Only Burner
    function burn(uint256[] memory _ids) external onlyBurner burnIsNotLocked {
        for (uint i; i < _ids.length; i++) {
            _burn(_ids[i]);
        }

        totalBurned += _ids.length;
    }

    // Only owner
    function setDefaultRoyalty(
        address _receiver,
        uint96 _feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(_receiver, _feeNumerator);
    }

    function setTokenRoyalty(
        uint256 _tokenId,
        address _receiver,
        uint96 _feeNumerator
    ) external onlyOwner {
        _setTokenRoyalty(_tokenId, _receiver, _feeNumerator);
    }

    function setMetadataResolver(
        address _metadataResolverAddress
    ) external onlyOwner metadataIsNotLocked {
        metadataResolver = IMetadataResolver(_metadataResolverAddress);
    }

    function setTransferLocked(bool _transferLocked) external onlyOwner {
        transferLocked = _transferLocked;

        emit TransferLocked(_transferLocked);
    }

    // Public
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view virtual override returns (string memory) {
        require(_ownerOf(_tokenId) != address(0), "Token does not exists");

        return metadataResolver.getTokenURI(address(this), _tokenId);
    }

    function totalSupply() public view returns (uint256) {
        return totalMinted - totalBurned;
    }

    function exists(uint256 _tokenId) external view returns (bool) {
        return _ownerOf(_tokenId) != address(0);
    }

    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);

        // Check that either the token is being minted
        // or that the transfer is unlocked
        require(
            from == address(0) || !transferLocked,
            "The token can not be transferred at this time."
        );

        return super._update(to, tokenId, auth);
    }
}