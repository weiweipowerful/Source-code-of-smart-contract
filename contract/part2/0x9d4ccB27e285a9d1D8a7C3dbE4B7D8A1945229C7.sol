//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import "@limitbreak/creator-token-standards/src/erc721c/ERC721AC.sol";
import "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./Supply.sol";
import "./OwnerMint.sol";
import "./UriManager.sol";

error UnauthorizedRequest();
error ForbiddenBotRequest();
error InvalidStage();
error AlreadyUsedNonce();
error InvalidAccount();
error InvalidAmount();
error InvalidMintLimit();
error StageLimitReached();

contract BasedNFT is
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
    Stage public stage;
    mapping(Stage => mapping(address => uint256)) public stageMintByAddress;

    enum Stage {
        PriorityWhitelist,
        Whitelist,
        Public
    }

    struct MintRequest {
        address account;
        uint8 stage;
        uint8 mintLimit;
    }
    event StageChanged(Stage stage_);

    bytes32 private constant MINT_REQUEST_TYPE_HASH =
        keccak256("MintRequest(address account,uint8 stage,uint8 mintLimit)");

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory prefix_,
        string memory suffix_,
        address royaltyReceiver_,
        uint96 royaltyFeeNumerator_,
        address signer_
    )
        ERC721AC(name_, symbol_)
        BasicRoyalties(royaltyReceiver_, royaltyFeeNumerator_)
        EIP712("BASED-NFT", "0.1.0")
        Supply(maxSupply_)
        UriManager(prefix_, suffix_)
    {
        _pause();
        signer = signer_;
    }

    function stagedMint(
        uint8 amount_,
        MintRequest calldata request_,
        bytes calldata signature_
    ) external whenNotPaused whenAuthorized(request_, signature_) {
        Stage stage_ = Stage(request_.stage);
        if (request_.account != msg.sender) {
            revert InvalidAccount();
        }
        if (stage_ != stage) {
            revert InvalidStage();
        }

        if (
            stageMintByAddress[stage][request_.account] + amount_ >
            request_.mintLimit
        ) {
            revert StageLimitReached();
        }

        if (stage != Stage.PriorityWhitelist && amount_ > 1) {
            revert InvalidAmount();
        }

        if (stage == Stage.Public && request_.mintLimit > 1) {
            revert InvalidMintLimit();
        }

        stageMintByAddress[stage][request_.account] += amount_;
        _callMint(request_.account, amount_);
    }

    function getActiveStage() public view returns (Stage) {
        return stage;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721AC, ERC2981) returns (bool) {
        return
            ERC721AC.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    function setSigner(address signer_) public {
        _requireCallerIsContractOwner();
        signer = signer_;
    }

    function setDefaultRoyalty(address receiver_, uint96 feeNumerator_) public {
        _requireCallerIsContractOwner();
        _setDefaultRoyalty(receiver_, feeNumerator_);
    }

    function pause() public {
        _requireCallerIsContractOwner();
        _pause();
    }

    function unpause() public {
        _requireCallerIsContractOwner();
        _unpause();
    }

    function setStage(uint8 stage_) public {
        _requireCallerIsContractOwner();
        stage = Stage(stage_);
        emit StageChanged(stage);
    }

    function _callMint(
        address account_,
        uint256 amount_
    ) internal onlyInSupply(amount_) {
        _safeMint(account_, amount_);
    }

    function _currentSupply() internal view override returns (uint256) {
        return totalSupply();
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (!_exists(tokenId)) {
            revert URIQueryForNonexistentToken();
        }

        return _buildUri(tokenId);
    }

    function _hashTypedData(
        MintRequest calldata request_
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    MINT_REQUEST_TYPE_HASH,
                    request_.account,
                    request_.stage,
                    request_.mintLimit
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
        if (recoveredSigner != signer) {
            revert UnauthorizedRequest();
        }
        _;
    }

    function _ownerMint(address account_, uint256 amount_) internal override {
        _callMint(account_, amount_);
    }
}