// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IDelegateRegistry} from "src/lib/IDelegateRegistry.sol";
import {IDelegationRegistry} from "src/lib/IDelegationRegistry.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Presale} from "src/Presale.sol";

/// @title Vesting
/// @notice Block Games vesting contract
/// @author karooolis
contract Vesting is ReentrancyGuard {
    /*==============================================================
                      CONSTANTS & IMMUTABLES
    ==============================================================*/

    /// @notice The presale contract address
    Presale public immutable presale;

    /// @notice The Dice NFT contract address
    address public immutable diceNFT;

    /// @notice The Dice token address
    address public immutable diceToken;

    /// @notice The vesting start timestamp
    uint256 public immutable vestingStart;

    /// @notice The vesting end timestamp
    uint256 public immutable vestingEnd;

    /// @notice The immediate vested tokens in percentage (10_000 basis points)
    uint256 public immutable immediateVestedPct;

    /// @notice The delegate registry v2 contract address
    IDelegateRegistry public immutable delegateRegistryV2;

    /// @notice The delegate registry v1 contract address
    IDelegationRegistry public immutable delegateRegistryV1;

    /*==============================================================
                       STORAGE VARIABLES
    ==============================================================*/

    /// @notice Already claimed tokens when user contributed
    mapping(address => uint256) public contributedClaimed;

    /// @notice Already claimed tokens when user claimed for a specific Dice NFT token
    mapping(uint256 => uint256) public diceNFTClaimed;

    /*==============================================================
                            FUNCTIONS
    ==============================================================*/

    /// @notice Vesting contract constructor
    /// @param _presale The presale contract address
    /// @param _diceNFT The Dice NFT contract address
    /// @param _diceToken The Dice token address
    /// @param _vestingStart The vesting start timestamp
    /// @param _vestingEnd The vesting end timestamp
    /// @param _immediateVestedPct The immediate vested tokens in percentage
    /// @param _delegateRegistryV1 The delegate registry v1 contract address
    /// @param _delegateRegistryV2 The delegate registry v2 contract address
    constructor(
        address _presale,
        address _diceNFT,
        address _diceToken,
        uint256 _vestingStart,
        uint256 _vestingEnd,
        uint256 _immediateVestedPct,
        address _delegateRegistryV1,
        address _delegateRegistryV2
    ) {
        presale = Presale(_presale);
        diceNFT = _diceNFT;
        diceToken = _diceToken;
        vestingStart = _vestingStart;
        vestingEnd = _vestingEnd;
        immediateVestedPct = _immediateVestedPct;
        delegateRegistryV1 = IDelegationRegistry(_delegateRegistryV1);
        delegateRegistryV2 = IDelegateRegistry(_delegateRegistryV2);
    }

    /// @notice Claim vested tokens for contributed tokens.
    function claimContributed() external nonReentrant {
        (,, uint256 vestedTokens) = getVestedContributed();
        _claimContributed(vestedTokens);
    }

    /// @notice Claim vested tokens for contributed tokens.
    /// @dev The vestable tokens are calculated based on the total tokens contributed, plus Open phase allocation.
    /// @param _proof The merkle proof
    /// @param _ethAmount The Open phase allocation (ETH)
    /// @param _tokensAmount The Open phase allocation (tokens)
    function claimContributed(bytes32[] calldata _proof, uint256 _ethAmount, uint256 _tokensAmount)
        external
        nonReentrant
    {
        (,, uint256 vestedTokens) = getVestedContributed(_proof, _ethAmount, _tokensAmount);
        _claimContributed(vestedTokens);
    }

    /// @notice Claim vested tokens for a specific Dice NFT token.
    /// @param _proof The Merkle proof for the Dice NFT token.
    /// @param _tokenId The token ID to claim vested tokens for.
    /// @param _totalTokens The maximum amount of tokens to claim.
    function claimDiceNFT(bytes32[] calldata _proof, uint256 _tokenId, uint256 _totalTokens)
        external
        nonReentrant
    {
        _verifyTokenOwner(diceNFT, _tokenId);

        (, uint256 vestedTokens) = getVestedDiceNFT(_proof, _tokenId, _totalTokens);

        // Check if there is anything to claim
        if (vestedTokens == 0) {
            revert NoTokensToClaim();
        }

        // Update claimed
        diceNFTClaimed[_tokenId] += vestedTokens;

        // Transfer vested tokens
        IERC20(diceToken).transfer(msg.sender, vestedTokens);

        emit DiceNFTClaimed(msg.sender, _tokenId, vestedTokens);
    }

    /// @notice Get the vested tokens for contributed tokens.
    /// @return totalTokens The total amount of tokens contributed.
    /// @return claimedTokens The amount of tokens already claimed.
    /// @return vestedTokens The amount of vested tokens available for claiming.
    function getVestedContributed()
        public
        view
        returns (uint256 totalTokens, uint256 claimedTokens, uint256 vestedTokens)
    {
        totalTokens = presale.tokensEligible(msg.sender);
        claimedTokens = contributedClaimed[msg.sender];
        vestedTokens = _getVestedTokens(totalTokens, claimedTokens);
    }

    /// @notice Get the vested tokens for contributed tokens if included in Open phase allocations.
    /// @param _proof The merkle proof
    /// @param _ethAmount The Open phase allocation (ETH)
    /// @param _tokensAmount The Open phase allocation (tokens)
    /// @return totalTokens The total amount of tokens contributed.
    /// @return claimedTokens The amount of tokens already claimed.
    /// @return vestedTokens The amount of vested tokens available for claiming.
    function getVestedContributed(bytes32[] calldata _proof, uint256 _ethAmount, uint256 _tokensAmount)
        public
        view
        returns (uint256 totalTokens, uint256 claimedTokens, uint256 vestedTokens)
    {
        _verifyOpenTierAllocation(_proof, _ethAmount, _tokensAmount);
        totalTokens = presale.tokensEligible(msg.sender) + _tokensAmount;
        claimedTokens = contributedClaimed[msg.sender];
        vestedTokens = _getVestedTokens(totalTokens, claimedTokens);
    }

    /// @notice Get the vested tokens for a specific Dice NFT token.
    /// @param _proof The Merkle proof for the Dice NFT token.
    /// @param _tokenId The token ID to claim vested tokens for.
    /// @param _totalTokens The maximum amount of tokens to claim.
    /// @return claimedTokens The amount of tokens already claimed.
    /// @return vestedTokens The amount of vested tokens available for claiming.
    function getVestedDiceNFT(bytes32[] calldata _proof, uint256 _tokenId, uint256 _totalTokens)
        public
        view
        returns (uint256 claimedTokens, uint256 vestedTokens)
    {
        _verifyDiceNFTVesting(_proof, _tokenId, _totalTokens);
        claimedTokens = diceNFTClaimed[_tokenId];
        vestedTokens = _getVestedTokens(_totalTokens, diceNFTClaimed[_tokenId]);
    }

    /*==============================================================
                       INTERNAL FUNCTIONS
    ==============================================================*/

    /// @notice Claim vested tokens for contributed tokens.
    /// @param _vestedTokens The amount of vested tokens to claim.
    function _claimContributed(uint256 _vestedTokens) internal {
        // Check if there is anything to claim
        if (_vestedTokens == 0) {
            revert NoTokensToClaim();
        }

        // Update claimed
        contributedClaimed[msg.sender] += _vestedTokens;

        // Transfer vested tokens
        IERC20(diceToken).transfer(msg.sender, _vestedTokens);

        emit ContributedClaimed(msg.sender, _vestedTokens);
    }

    /// @notice Returns the amount of vested tokens available for claiming.
    /// @param _totalTokens The total amount of tokens vestable over time.
    /// @param _claimedTokens The amount of tokens already claimed.
    /// @return The amount of vested tokens available for claiming.
    function _getVestedTokens(uint256 _totalTokens, uint256 _claimedTokens) internal view returns (uint256) {
        uint256 immediateVested = _totalTokens * immediateVestedPct / 10_000;
        if (block.timestamp < vestingStart) {
            if (immediateVested < _claimedTokens) {
                return 0;
            }
            return immediateVested - _claimedTokens;
        }

        uint256 totalVestable = _totalTokens - immediateVested;
        uint256 timestamp = block.timestamp > vestingEnd ? vestingEnd : block.timestamp;
        uint256 totalVested = (timestamp - vestingStart) * totalVestable / (vestingEnd - vestingStart) + immediateVested;
        return totalVested - _claimedTokens;
    }

    /// @notice Verify the merkle proof
    /// @param _proof The merkle proof
    /// @param _tokenId The token ID to claim vested tokens for.
    /// @param _totalTokens The total amount of tokens vestable over time.
    function _verifyDiceNFTVesting(bytes32[] calldata _proof, uint256 _tokenId, uint256 _totalTokens) internal view {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_tokenId, _totalTokens))));
        bytes32 root = presale.diceNFTsTokensEligibleMerkleRoot();
        if (!MerkleProof.verify(_proof, root, leaf)) {
            revert InvalidDiceNFTVestingProof();
        }
    }

    /// @notice Verify the merkle proof
    /// @param _proof The merkle proof
    /// @param _ethAmount The amount to verify
    /// @param _tokensAmount The amount to verify
    function _verifyOpenTierAllocation(bytes32[] calldata _proof, uint256 _ethAmount, uint256 _tokensAmount)
        internal
        view
    {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, _ethAmount, _tokensAmount))));
        bytes32 root = presale.openPhaseAllocationsMerkleRoot();
        if (!MerkleProof.verify(_proof, root, leaf)) {
            revert InvalidOpenTierAllocationsMerkleProof();
        }
    }

    /// @notice Verifies if the caller is the owner of a given token or a valid delegate.
    /// @param _collection The address of the collection contract.
    /// @param _tokenId The token ID to verify ownership or delegation for.
    function _verifyTokenOwner(address _collection, uint256 _tokenId) internal view {
        address _tokenOwner = IERC721(_collection).ownerOf(_tokenId);

        // Check sender is owner
        if (_tokenOwner == msg.sender) {
            return;
        }

        // Check with delegate registry v2
        if (delegateRegistryV2.checkDelegateForERC721(msg.sender, _tokenOwner, _collection, _tokenId, "")) {
            return;
        }

        // Check with delegate registry v1
        if (delegateRegistryV1.checkDelegateForToken(msg.sender, _tokenOwner, _collection, _tokenId)) {
            return;
        }

        // Revert if not owner or delegate
        revert NotTokenOwner(_collection, _tokenId);
    }

    /*==============================================================
                            EVENTS
    ==============================================================*/

    /// @notice Emitted when tokens are claimed for contributed tokens.
    /// @param claimer The address of the claimer.
    /// @param tokensAmount The amount of tokens claimed.
    event ContributedClaimed(address indexed claimer, uint256 indexed tokensAmount);

    /// @notice Emitted when tokens are claimed for a specific Dice NFT token.
    /// @param claimer The address of the claimer.
    /// @param tokenId The token ID claimed for.
    /// @param tokensAmount The amount of tokens claimed.
    event DiceNFTClaimed(address indexed claimer, uint256 indexed tokenId, uint256 indexed tokensAmount);

    /*==============================================================
                            ERRORS
    ==============================================================*/

    /// @notice Revert if there are no tokens to claim.
    error NoTokensToClaim();

    /// @notice Revert if the caller is not the owner of the token or a valid delegate.
    /// @param collection The address of the collection contract.
    /// @param tokenId The token ID to verify ownership or delegation for.
    error NotTokenOwner(address collection, uint256 tokenId);

    /// @notice Revert if the merkle proof is invalid.
    error InvalidDiceNFTVestingProof();

    /// @notice Revert if the merkle proof for Open phase allocations is invalid
    error InvalidOpenTierAllocationsMerkleProof();
}