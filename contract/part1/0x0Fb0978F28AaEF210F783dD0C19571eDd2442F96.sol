// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @title Refunds
/// @notice A contract for $BLOCK stake claims
contract Claim is Ownable2Step, ReentrancyGuard {
    /*==============================================================
                      CONSTANTS & IMMUTABLES
    ==============================================================*/

    /// @notice The Block Token token address
    IERC20 public immutable token;

    /// @notice Event emitted when the merkle root for the allowed wallets is set
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

    /*==============================================================
                       STORAGE VARIABLES
    ==============================================================*/

    /// @notice Has claim been claimed
    mapping(bytes => bool) claimed;

    /// @notice The address of the signer
    address public signer;

    /*==============================================================
                            FUNCTIONS
    ==============================================================*/

    /// @notice Claim contract constructor
    /// @param _initialOwner The initial owner of the contract
    /// @param _signer The address of the signer
    /// @param _token The ERC20 token address
    constructor(address _initialOwner, address _signer, address _token) Ownable(_initialOwner) {
        if (_token == address(0)) {
            revert InvalidTokenAddressSet();
        } else if (_signer == address(0)) {
            revert InvalidSignerSet();
        }

        token = IERC20(_token);
        signer = _signer;
    }

    /// @notice Claim tokens from claim
    /// @param _amount Amount of tokens to claim
    /// @param _expiresAt Expiry time of the claim
    /// @param _salt Salt unique to the claim
    /// @param _signature Signature of the claimer
    function claim(uint256 _amount, uint256 _expiresAt, uint256 _salt, bytes calldata _signature) external {
        claim(_amount, _expiresAt, msg.sender, _salt, _signature);
    }

    /// @notice Claim tokens from claim
    /// @param _amount Amount of tokens to claim
    /// @param _expiresAt Expiry time of the claim
    /// @param _receiver The address of the receiver
    /// @param _salt Salt unique to the claim
    /// @param _signature Signature of the claimer
    function claim(uint256 _amount, uint256 _expiresAt, address _receiver, uint256 _salt, bytes calldata _signature)
        public
        nonReentrant
    {
        if (claimed[_signature]) {
            revert AlreadyClaimed();
        } else if (_expiresAt < block.timestamp) {
            revert SignatureExpired();
        }

        _verifySignature(_amount, _expiresAt, _receiver, _salt, _signature);

        claimed[_signature] = true;

        token.transfer(_receiver, _amount);

        emit Claimed(_receiver, _signature, _amount);
    }

    /// @notice Set the signer
    /// @param _signer The address of the signer
    function setSigner(address _signer) external onlyOwner {
        if (_signer == address(0)) {
            revert InvalidSignerSet();
        }

        signer = _signer;
        emit SignerSet(_signer);
    }

    /// @notice Withdraw remaining tokens back to owner
    function withdraw() external onlyOwner {
        // Withdraw remaining tokens back to owner
        uint256 balance = token.balanceOf(address(this));
        token.transfer(owner(), balance);
        emit TokensWithdrawn(balance);
    }

    /*==============================================================
                        INTERNAL FUNCTIONS
    ==============================================================*/

    /// @notice Construct the domain separator
    function _getDomainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    /// @notice Verify the signature
    /// @param _amount The amount of tokens to claim
    /// @param _expiresAt The expiry time of the claim
    /// @param _receiver The address of the receiver
    /// @param _salt The salt unique to the claim
    /// @param _signature The signature of the claimer
    function _verifySignature(
        uint256 _amount,
        uint256 _expiresAt,
        address _receiver,
        uint256 _salt,
        bytes calldata _signature
    ) internal view {
        bytes32 signedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(abi.encode(_getDomainSeparator(), _amount, _expiresAt, _salt, _receiver))
        );
        address recoveredSigner = ECDSA.recover(signedMessageHash, _signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }
    }

    /*==============================================================
                            EVENTS
    ==============================================================*/

    /// @notice Emitted when tokens are claimed
    /// @param claimer The address of the claimer
    /// @param signature The signature of the claimer
    /// @param amount The amount of tokens claimed
    event Claimed(address indexed claimer, bytes signature, uint256 indexed amount);

    /// @notice Emitted when tokens are withdrawn
    /// @param amount The amount of tokens withdrawn
    event TokensWithdrawn(uint256 indexed amount);

    /// @notice Emitted when signer is set
    /// @param signer The address of the signer
    event SignerSet(address indexed signer);

    /*==============================================================
                            ERRORS
    ==============================================================*/

    /// @notice Error when claim already claimed
    error AlreadyClaimed();

    /// @notice Error when invalid signature
    error InvalidSignature();

    /// @notice Error when signature expired
    error SignatureExpired();

    /// @notice Error when adding invalid token address
    error InvalidTokenAddressSet();

    /// @notice Error when adding invalid signer address
    error InvalidSignerSet();
}