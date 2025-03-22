// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { ILeiaNFT } from "./ILeiaNFT.sol";

/// @title LeiaClaims contract
/// @notice Implements the claiming of Leia token and NFT
/// @dev The claims contract allows you to claim leia tokens and nfts
contract LeiaClaims is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Max length of the array
    uint8 private constant MAX_LENGTH = 6;

    /// @notice The address of leia token
    IERC20 public immutable LEIA;

    /// @notice The address of leia nft contract
    ILeiaNFT public immutable leiaNFT;

    /// @notice The address will distribute leia tokens
    address public leiaWallet;

    /// @notice The address of signerWallet
    address public signerWallet;

    /// @notice The tokens root of the tree
    bytes32 public root;

    /// @notice Gives info of user's leia token claim
    mapping(address => bool) public isClaimed;

    /// @notice Gives info about address's permission
    mapping(address => bool) public blacklistAddress;

    /// @dev Emitted when address of leia wallet is updated
    event LeiaWalletUpdated(address indexed prevAddress, address indexed newAddress);

    /// @dev Emitted when leia token are claimed
    event Claimed(address indexed by, uint256 leiaAmount, uint256[] indexed ids, uint256[] indexed quantity);

    /// @dev Emitted when address of signer is updated
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

    /// @dev Emitted when blacklist access of address is updated
    event BlacklistUpdated(address indexed which, bool indexed accessNow);

    /// @dev Emitted when merkle root is updated
    event RootUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot);

    /// @notice Thrown when address is blacklisted
    error Blacklisted();

    /// @notice Thrown when updating an address with zero address
    error ZeroAddress();

    /// @notice Thrown when root value is zero
    error InvalidRoot();

    /// @notice Thrown when Merkle proof is invalid
    error InvalidProof();

    /// @notice Thrown when tokens are already claimed
    error AlreadyClaimed();

    /// @notice Thrown when trying to mint nft Id greater than 5
    error InvalidNftType();

    /// @notice Thrown when two array lengths does not match
    error ArrayLengthMismatch();

    /// @notice Thrown when updating with the same value as previously stored
    error IdenticalValue();

    /// @notice Thrown when Sign is invalid
    error InvalidSignature();

    /// @dev Restricts when updating wallet/contract address to zero address
    modifier checkAddressZero(address which) {
        if (which == address(0)) {
            revert ZeroAddress();
        }
        _;
    }

    /// @dev Confirms whether the user is blacklisted
    modifier notBlackListed(address user) {
        if (blacklistAddress[user]) {
            revert Blacklisted();
        }
        _;
    }

    /// @dev Constructor
    /// @param leiaToken The address of leia token
    /// @param leiaNFTAddress The address of leia nft contract
    /// @param owner The address of the owner wallet
    /// @param leiaWalletAddress The address of the wallet that which transfer tokens
    /// @param signerAddress The address of the signer wallet
    /// @param merkleRoot The merkle root of the tree
    constructor(
        IERC20 leiaToken,
        ILeiaNFT leiaNFTAddress,
        address owner,
        address leiaWalletAddress,
        address signerAddress,
        bytes32 merkleRoot
    ) Ownable(owner) {
        if (
            address(leiaToken) == address(0) ||
            address(leiaNFTAddress) == address(0) ||
            leiaWalletAddress == address(0) ||
            signerAddress == address(0)
        ) {
            revert ZeroAddress();
        }

        if (merkleRoot == bytes32(0)) {
            revert InvalidRoot();
        }

        LEIA = leiaToken;
        leiaNFT = leiaNFTAddress;
        leiaWallet = leiaWalletAddress;
        signerWallet = signerAddress;
        root = merkleRoot;
    }

    /// @notice Claims leia tokens and nfts only when `claimNFT` is true
    /// @param amountToClaim The leia token amount to claim
    /// @param merkleProof The merkleProof is valid if and only if the rebuilt hash matches the root of the tree
    /// @param ids The token ids that will be minted to `to`
    /// @param quantity The amount of nfts that will be minted to `to`
    /// @param claimNFT The user want to claim nft or not
    /// @param v The `v` signature parameter
    /// @param r The `r` signature parameter
    /// @param s The `s` signature parameter
    function claimLeia(
        uint256 amountToClaim,
        bytes32[] calldata merkleProof,
        uint256[] calldata ids,
        uint256[] calldata quantity,
        bool claimNFT,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant notBlackListed(msg.sender) {
        if (isClaimed[msg.sender]) {
            revert AlreadyClaimed();
        }

        _verifySign(amountToClaim, ids, quantity, v, r, s);

        if (ids.length != quantity.length) {
            revert ArrayLengthMismatch();
        }

        if (ids.length > MAX_LENGTH) {
            revert InvalidNftType();
        }

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amountToClaim, ids, quantity));
        bool success = MerkleProof.verify(merkleProof, root, leaf);

        if (!success) {
            revert InvalidProof();
        }

        isClaimed[msg.sender] = true;
        LEIA.safeTransferFrom(leiaWallet, msg.sender, amountToClaim);

        if (claimNFT && ids.length > 0) {
            leiaNFT.mint(msg.sender, ids, quantity);
        }

        emit Claimed({ by: msg.sender, leiaAmount: amountToClaim, ids: ids, quantity: quantity });
    }

    /// @notice Changes leia wallet to a new address
    /// @param newLeiaWallet The address of the new leia wallet
    function changeLeiaWallet(address newLeiaWallet) external checkAddressZero(newLeiaWallet) onlyOwner {
        address oldWallet = leiaWallet;

        if (oldWallet == newLeiaWallet) {
            revert IdenticalValue();
        }

        emit LeiaWalletUpdated({ prevAddress: oldWallet, newAddress: newLeiaWallet });

        leiaWallet = newLeiaWallet;
    }

    /// @notice Changes signer wallet address
    /// @param newSigner The address of the new signer wallet
    function changeSigner(address newSigner) external checkAddressZero(newSigner) onlyOwner {
        address oldSigner = signerWallet;

        if (oldSigner == newSigner) {
            revert IdenticalValue();
        }

        emit SignerUpdated({ oldSigner: oldSigner, newSigner: newSigner });

        signerWallet = newSigner;
    }

    /// @notice Changes the access of any address in contract interaction
    /// @param which The address for which access is updated
    /// @param access The access decision of `which` address
    function updateBlackListedUser(address which, bool access) external checkAddressZero(which) onlyOwner {
        bool oldAccess = blacklistAddress[which];

        if (oldAccess == access) {
            revert IdenticalValue();
        }

        emit BlacklistUpdated({ which: which, accessNow: access });

        blacklistAddress[which] = access;
    }

    /// @notice Updates the merkle root with a new value
    /// @param newRoot The new merkle root
    function updateRoot(bytes32 newRoot) external onlyOwner {
        bytes32 oldRoot = root;

        if (oldRoot == newRoot) {
            revert IdenticalValue();
        }

        if (newRoot == bytes32(0)) {
            revert InvalidRoot();
        }

        emit RootUpdated({ oldRoot: oldRoot, newRoot: newRoot });

        root = newRoot;
    }

    /// @dev The helper function which verifies signature, signed by signer wallet, reverts if invalid
    function _verifySign(
        uint256 leiaTokenAmount,
        uint256[] calldata ids,
        uint256[] calldata quantity,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private view {
        bytes32 encodedMessageHash = keccak256(abi.encodePacked(msg.sender, leiaTokenAmount, ids, quantity));

        if (signerWallet != ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(encodedMessageHash), v, r, s)) {
            revert InvalidSignature();
        }
    }
}