// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable, Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {MerkleProof} from "openzeppelin/utils/cryptography/MerkleProof.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "openzeppelin/utils/cryptography/MessageHashUtils.sol";

import {StakeManager} from "src/StakeManager.sol";

contract TokenDistributor is Ownable2Step {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user claims tokens.
    /// @param user The user address.
    /// @param amount The amount of tokens claimed.
    event Claimed(address indexed user, uint256 amount);

    /// @notice Emitted when the owner withdraws tokens.
    /// @param owner The owner address.
    /// @param amount The amount of tokens withdrawn.
    event Withdrawn(address indexed owner, uint256 amount);

    /// @notice Emitted when the signer is set.
    /// @param signer The signer address.
    event SigneUpdated(address indexed signer);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount();
    error AlreadyClaimed();
    error InvalidProof();
    error InvalidToken();
    error EmptyProof();
    error ClaimFinished();
    error ClaimNotFinished();
    error InvalidSignature();

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The merkle root hash.
    bytes32 public immutable MERKLE_ROOT;

    /// @notice The token contract.
    IERC20 public immutable TOKEN;

    /// @notice The timestamp when the claim period ends.
    uint256 public immutable CLAIM_END;

    /// @notice The timestamp of when vesting starts.
    uint256 public immutable VESTING_START;

    /// @notice The total vesting time in seconds.
    uint256 public immutable VESTING_TIME;

    /// @notice The stake manager contract.
    StakeManager public immutable STAKE_MANAGER;

    /// @notice The signer address.
    address public signer;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of claimed status.
    mapping(address user => bool claimed) public hasClaimed;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Define the merkle root, base signer, token and owner.
    /// @param _merkleRoot The merkle root hash.
    /// @param _token The token address.
    /// @param _owner The owner address.
    /// @param _vestingStart The vesting start timestamp in seconds.
    /// @param _vestingTime The amount of seconds to end vesting period in.
    /// @param _endTime The amount of seconds to end claim period in.
    /// @param _stakeManager The stake manager address.
    /// @param _validator The validator address to delegate.
    constructor(
        bytes32 _merkleRoot,
        address _token,
        uint256 _tokenAmount,
        address _owner,
        uint256 _vestingStart,
        uint256 _vestingTime,
        uint256 _endTime,
        address _stakeManager,
        address _validator
    ) Ownable(_owner) {
        if (_token == address(0)) revert InvalidToken();

        MERKLE_ROOT = _merkleRoot;
        TOKEN = IERC20(_token);
        VESTING_START = _vestingStart;
        VESTING_TIME = _vestingTime;
        CLAIM_END = _vestingStart + _endTime;
        STAKE_MANAGER = StakeManager(_stakeManager);

        TOKEN.transferFrom(msg.sender, address(this), _tokenAmount);
        TOKEN.approve(address(STAKE_MANAGER), _tokenAmount);
        STAKE_MANAGER.stake(_tokenAmount);
        STAKE_MANAGER.delegate(_validator);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the vested amount of tokens for a vesting schedule
    /// @param amount total amount to claim
    function vestedAmount(uint256 amount) public view returns (uint256) {
        if (block.timestamp < VESTING_START) {
            return 0;
        } else if (block.timestamp > VESTING_START + VESTING_TIME) {
            return amount;
        } else {
            return (amount / 2) + ((amount / 2) * (block.timestamp - VESTING_START) / VESTING_TIME);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim tokens using a signature and merkle proof.
    /// @param _amount Amount of tokens to claim.
    /// @param _merkleProof Merkle proof of claim.
    /// @param _signature Signature of the claim.
    function claim(uint256 _amount, bytes32[] calldata _merkleProof, bytes calldata _signature) external {
        if (_amount == 0) revert InvalidAmount();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();
        if (_merkleProof.length == 0) revert EmptyProof();
        if (block.timestamp >= CLAIM_END) revert ClaimFinished();

        // Check the signature
        _signatureCheck(_amount, _signature, msg.sender);

        // Generate the leaf
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, _amount))));

        // Verify the merkle proof
        if (!MerkleProof.verify(_merkleProof, MERKLE_ROOT, leaf)) revert InvalidProof();

        // Unstake the tokens
        STAKE_MANAGER.unstake(_amount);

        // Mark as claimed and send the tokens
        hasClaimed[msg.sender] = true;
        uint256 amountClaimable = vestedAmount(_amount);
        TOKEN.safeTransfer(msg.sender, amountClaimable);

        // Send forgone tokens to elixirMultisig
        if (block.timestamp < VESTING_START + VESTING_TIME) {
            TOKEN.safeTransfer(owner(), _amount - amountClaimable);
        }

        emit Claimed(msg.sender, vestedAmount(_amount));
    }

    /// @notice Set the signer address.
    /// @param _signer The signer address.
    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
        emit SigneUpdated(_signer);
    }

    /// @notice Withdraw tokens from the contract.
    function withdraw(uint256 amount) external onlyOwner {
        STAKE_MANAGER.unstake(amount);
        TOKEN.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal function to check the signature
    /// @param _amount amount of tokens to claim
    /// @param _signature signature of the claim
    /// @param _onBehalfOf address of the user claiming the airdrop
    function _signatureCheck(uint256 _amount, bytes calldata _signature, address _onBehalfOf) internal view {
        if (_signature.length == 0) revert InvalidSignature();

        bytes32 messageHash = keccak256(abi.encodePacked(_onBehalfOf, _amount, address(this), block.chainid));
        bytes32 prefixedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        address recoveredSigner = ECDSA.recover(prefixedHash, _signature);

        if (recoveredSigner != signer) revert InvalidSignature();
    }
}