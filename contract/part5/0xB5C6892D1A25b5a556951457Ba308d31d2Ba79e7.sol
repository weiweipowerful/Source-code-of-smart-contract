//SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import "@limitbreak/creator-token-standards/src/erc721c/v2/ERC721AC.sol";
import "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IStakedToken.sol";
import "./Supply.sol";
import "./OwnerMint.sol";
import "./UriManager.sol";

contract MythicSeed is
    OwnableBasic,
    ERC721AC,
    BasicRoyalties,
    Pausable,
    EIP712,
    Supply,
    OwnerMint,
    UriManager
{
    address public signer;
    mapping(address => uint256) public mintLimits;
    address public stakingAddress;
    IStakedToken public stakedMythicSeed;

    struct MintRequest {
        address account;
        uint256 mintLimit;
        bool stakeTokens;
        uint256 expiresAtBlock;
    }

    bytes32 private constant MINT_REQUEST_TYPE_HASH =
        keccak256(
            "MintRequest(address account,uint256 mintLimit,bool stakeTokens,uint256 expiresAtBlock)"
        );

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory prefix_,
        string memory suffix_,
        address royaltyReceiver_,
        uint96 royaltyFeeNumerator_,
        address signer_,
        address stakedMythicSeedAddress_
    )
        ERC721AC(name_, symbol_)
        BasicRoyalties(royaltyReceiver_, royaltyFeeNumerator_)
        EIP712("MYTHIC-SEED", "0.1.0")
        Supply(maxSupply_)
        UriManager(prefix_, suffix_)
    {
        _pause();
        signer = signer_;
        stakedMythicSeed = IStakedToken(stakedMythicSeedAddress_);
    }

    function mint(
        uint256 amount_,
        MintRequest calldata request_,
        bytes calldata signature_
    ) external whenAuthorized(request_, signature_) whenNotPaused {
        require(request_.account == msg.sender, "Invalid account");
        require(
            mintLimits[msg.sender] + amount_ <= request_.mintLimit,
            "Exceeds limit"
        );

        mintLimits[msg.sender] += amount_;

        if (request_.stakeTokens) {
            uint256 nextTokenId = _nextTokenId();
            for (uint256 i = nextTokenId; i < nextTokenId + amount_; i++) {
                stakedMythicSeed.mint(msg.sender, i);
            }
            _callMint(stakingAddress, amount_);
        } else {
            _callMint(msg.sender, amount_);
        }
    }

    function setSigner(address signer_) public {
        _requireCallerIsContractOwner();
        signer = signer_;
    }

    function setStakingAddress(address stakingAddress_) public {
        _requireCallerIsContractOwner();
        stakingAddress = stakingAddress_;
    }

    function setDefaultRoyalty(address receiver_, uint96 feeNumerator_) public {
        _requireCallerIsContractOwner();
        _setDefaultRoyalty(receiver_, feeNumerator_);
    }

    function setTokenRoyalty(
        uint256 tokenId_,
        address receiver_,
        uint96 feeNumerator_
    ) public {
        _requireCallerIsContractOwner();
        _setTokenRoyalty(tokenId_, receiver_, feeNumerator_);
    }

    function pause() public {
        _requireCallerIsContractOwner();
        _pause();
    }

    function unpause() public {
        _requireCallerIsContractOwner();
        _unpause();
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (!_exists(tokenId)) {
            revert URIQueryForNonexistentToken();
        }

        return _buildUri(tokenId);
    }

    function isApprovedForAll(
        address owner_,
        address operator_
    ) public view virtual override returns (bool) {
        return
            super.isApprovedForAll(owner_, operator_) ||
            msg.sender == stakingAddress;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721AC, ERC2981) returns (bool) {
        return
            ERC721AC.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _ownerMint(address account_, uint256 amount_) internal override {
        _callMint(account_, amount_);
    }

    function _callMint(
        address account_,
        uint256 amount_
    ) internal onlyInSupply(amount_) {
        require(tx.origin == msg.sender, "No bots");
        _safeMint(account_, amount_);
    }

    function _currentSupply() internal view override returns (uint256) {
        return totalSupply();
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _hashTypedData(
        MintRequest calldata request_
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    MINT_REQUEST_TYPE_HASH,
                    request_.account,
                    request_.mintLimit,
                    request_.stakeTokens,
                    request_.expiresAtBlock
                )
            );
    }

    modifier whenAuthorized(
        MintRequest calldata request_,
        bytes calldata signature_
    ) {
        bytes32 structHash = _hashTypedData(request_);
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature_);
        require(recoveredSigner == signer, "Unauthorized mint");
        require(request_.expiresAtBlock > block.number, "Expired signature");
        _;
    }
}