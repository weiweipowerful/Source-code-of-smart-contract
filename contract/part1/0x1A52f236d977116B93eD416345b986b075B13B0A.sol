//SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import "@limitbreak/creator-token-standards/src/erc721c/v2/ERC721C.sol";
import "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IStakedToken.sol";
import "./interfaces/IDelegateRegistry.sol";
import "./UriManager.sol";

contract SynergySeed is
    OwnableBasic,
    ERC721C,
    BasicRoyalties,
    Pausable,
    EIP712,
    UriManager
{
    address public signer;
    mapping(address => uint256) public mintLimits;
    address public stakingAddress;
    IStakedToken public stakedSynergySeed;

    struct MintRequest {
        address account;
        uint256 tokenId;
        uint256 expiresAtBlock;
    }

    bytes32 private constant MINT_REQUEST_TYPE_HASH =
        keccak256(
            "MintRequest(address account,uint256 tokenId,uint256 expiresAtBlock)"
        );

    IDelegateRegistry public constant DELEGATE_REGISTRY =
        IDelegateRegistry(0x00000000000000447e69651d841bD8D104Bed493);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory prefix_,
        string memory suffix_,
        address royaltyReceiver_,
        uint96 royaltyFeeNumerator_,
        address signer_,
        address stakedSynergySeedAddress_
    )
        ERC721OpenZeppelin(name_, symbol_)
        BasicRoyalties(royaltyReceiver_, royaltyFeeNumerator_)
        EIP712("SYNERGY-SEED", "0.1.0")
        UriManager(prefix_, suffix_)
    {
        _pause();
        signer = signer_;
        stakedSynergySeed = IStakedToken(stakedSynergySeedAddress_);
    }

    function mint(
        MintRequest calldata request_,
        bytes calldata signature_
    ) external whenAuthorized(request_, signature_) whenNotPaused {
        address account = request_.account;
        require(
            account == msg.sender ||
                DELEGATE_REGISTRY.checkDelegateForAll(msg.sender, account, ""),
            "Invalid account"
        );
        stakedSynergySeed.mint(account, request_.tokenId);
        _callMint(stakingAddress, request_.tokenId);
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

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireMinted(tokenId);
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
    ) public view virtual override(ERC721C, ERC2981) returns (bool) {
        return
            ERC721C.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    function _callMint(address account_, uint256 amount_) internal {
        require(tx.origin == msg.sender, "No bots");
        _safeMint(account_, amount_);
    }

    function _hashTypedData(
        MintRequest calldata request_
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    MINT_REQUEST_TYPE_HASH,
                    request_.account,
                    request_.tokenId,
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