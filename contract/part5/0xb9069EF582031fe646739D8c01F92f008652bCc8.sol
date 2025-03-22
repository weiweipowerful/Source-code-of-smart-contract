// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@solady/utils/MerkleProofLib.sol";
import "@solady/utils/ECDSA.sol";
import "@solady/utils/FixedPointMathLib.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./interfaces/IStaking.sol";

//   ____ _ _
//  / ___| (_) __ _ _   _  ___
// | |   | | |/ _` | | | |/ _ \
// | |___| | | (_| | |_| |  __/
//  \____|_|_|\__, |\__,_|\___|        _               _
// |  _ \(_)___| |_|_ __(_) |__  _   _| |_ ___  _ __  / |
// | | | | / __| __| '__| | '_ \| | | | __/ _ \| '__| | |
// | |_| | \__ \ |_| |  | | |_) | |_| | || (_) | |    | |
// |____/|_|___/\__|_|  |_|_.__/ \__,_|\__\___/|_|    |_|

/// @title Distributor1
/// @notice Clique Airdrop contract (Mekle + ECDSA)
/// @author Clique (@Clique2046)
/// @author Eillo (@0xEillo)
contract Distributor is Ownable2Step, Pausable {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    // token to be airdroppped
    address public immutable token;
    // address signing the claims
    address public signer;
    // root of the merkle tree
    bytes32 public claimRoot;
    // staking contract
    address public immutable staking;
    // percentage of tokens to stake (in WAD, where 1e18 = 100%)
    uint256 public stakePercentage;

    // mapping of addresses to whether they have claimed
    mapping(address => bool) public claimed;

    // errors
    error InsufficientBalance();
    error AlreadyClaimed();
    error InvalidSignature();
    error InvalidMerkleProof();
    error UninitializedStaking();
    error InvalidPercentage();

    event AirdropClaimed(address indexed account, uint256 amount);
    event StakePercentageUpdated(uint256 newPercentage);

    /// @notice Construct a new Claim contract
    /// @param _signer address that can sign messages
    /// @param _token address of the token that will be claimed
    /// @param _staking address of the staking contract
    constructor(
        address _signer,
        address _token,
        address _staking
    ) Ownable(msg.sender) {
        signer = _signer;
        token = _token;
        staking = _staking;
        stakePercentage = 0.5e18; // 50% by default
        _pause();
    }

    /// @notice Set new signer which would revoke the previous one
    /// @param _signer address that can sign messages
    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    /// @notice Set the claim root
    /// @param _claimRoot root of the merkle tree
    function setClaimRoot(bytes32 _claimRoot) external onlyOwner {
        claimRoot = _claimRoot;
    }

    /// @notice Withdraw tokens from the contract
    /// @param receiver address to receive the tokens
    /// @param amount amount of tokens to withdraw
    function withdrawTokens(
        address receiver,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(receiver, amount);
    }

    function toggleActive() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    /// @notice Set the percentage of tokens to be staked
    /// @param _percentage percentage in WAD format (1e18 = 100%)
    function setStakePercentage(uint256 _percentage) external onlyOwner {
        if (_percentage > 1e18) revert InvalidPercentage();
        stakePercentage = _percentage;
        emit StakePercentageUpdated(_percentage);
    }

    /// @notice Claim airdrop tokens. Checks for both merkle proof
    //          and signature validation
    /// @param _proof merkle proof of the claim
    /// @param _signature signature of the claim
    /// @param _amount amount of tokens to claim
    /// @param _lockOnly whether the user has claimed the airdrop
    function claim(
        bytes32[] calldata _proof,
        bytes calldata _signature,
        uint256 _amount,
        bool _lockOnly
    ) external whenNotPaused {
        if (IERC20(token).balanceOf(address(this)) < _amount) {
            revert InsufficientBalance();
        }
        if (claimed[msg.sender]) revert AlreadyClaimed();

        if (staking == address(0)) revert UninitializedStaking();

        claimed[msg.sender] = true;
        uint256 _stakingAmount = _amount.mulWad(stakePercentage); // Calculate stake amount based on percentage

        _rootCheck(_proof, _amount, _lockOnly);
        bytes32 messageHash = keccak256(
            abi.encodePacked(msg.sender, _amount, address(this), block.chainid)
        );
        _signatureCheck(messageHash, _signature);

        IERC20(token).approve(staking, _stakingAmount);
        IStaking(staking).stake(_stakingAmount, msg.sender);

        if (_amount - _stakingAmount > 0 && !_lockOnly) {
            IERC20(token).safeTransfer(msg.sender, _amount - _stakingAmount);
        }

        emit AirdropClaimed(msg.sender, _amount);
    }

    function unlock(
        uint256 _reductionBlock,
        bytes calldata _signature
    ) external whenNotPaused {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                msg.sender,
                _reductionBlock,
                address(this),
                block.chainid
            )
        );
        _signatureCheck(messageHash, _signature);
        IStaking.Stake memory stake = IStaking(staking).getStakeInfo(
            msg.sender
        );
        IStaking(staking).unstake(stake.amount, _reductionBlock, msg.sender);
    }

    /// @notice Internal function to check the merkle proof
    /// @param _proof merkle proof of the claim
    /// @param _amount amount of tokens to claim
    /// @param _lockOnly whether the user has claimed the airdrop
    function _rootCheck(
        bytes32[] calldata _proof,
        uint256 _amount,
        bool _lockOnly
    ) internal view {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount, _lockOnly));
        if (!MerkleProofLib.verify(_proof, claimRoot, leaf)) {
            revert InvalidMerkleProof();
        }
    }

    /// @notice Internal function to check the signature
    /// @param _messageHash msg to be verified
    /// @param _signature signature of the msg
    function _signatureCheck(
        bytes32 _messageHash,
        bytes calldata _signature
    ) internal view {
        if (_signature.length == 0) revert InvalidSignature();

        bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(_messageHash);
        address recoveredSigner = ECDSA.recoverCalldata(
            prefixedHash,
            _signature
        );

        if (recoveredSigner != signer) revert InvalidSignature();
    }
}