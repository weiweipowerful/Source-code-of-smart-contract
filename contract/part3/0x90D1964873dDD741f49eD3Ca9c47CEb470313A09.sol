/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {IUniswapV2Router02} from "./vendor/uniswap/interfaces/IUniswapV2Router02.sol";
import {Memecoin} from './vendor/Memecoin.sol';


contract HenloToken is Memecoin {
    uint256 public constant MAX_TOTAL_SUPPLY = 210_690_000_000_000 ether;
    uint256 public constant LP_SUPPLY = 21_069_000_000_000 ether; // 10%
    uint256 public constant CREATOR_VEST = 21_069_000_000_000 ether; // 10%
    uint256 public constant CLAIM_SUPPLY = 147_483_000_000_000 ether; // 70%
    uint256 public constant NFT_CLAIM_SUPPLY = 21_069_000_000_000 ether; // 10%
    uint256 public constant UNLOCK_PERIOD = 52 weeks;
    uint256 public immutable CREATION_TIME;

    uint256 public constant GAIAS_NFT_SPLIT = 750; // 7.5%
    uint256 public constant SCROLLS_NFT_SPLIT = 25; // 0.25%
    uint256 public constant MEDIA_NFT_SPLIT = 25; // 0.25%
    uint256 public constant PAPERS_NFT_SPLIT = 200; // 2%
    uint256 public constant NFT_SPLIT_DENOMINATOR = 10000;

    IUniswapV2Router02 public constant _UNISWAP_V2_ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    uint256 public constant _maxTransactionAmount = 3_160_350_000_000 ether; // 1.5% of total supply
    uint256 public constant _maxPerWallet = 2_106_900_000_000 ether; // 1% of total supply

    uint256 public vestBurned;
    uint256 public vestClaimed;
    uint256 public lastVestTime;

    mapping(uint256 => bytes32) public weeklyClaimMerkleRoots;
    // @dev: This is a packed array of booleans for each week
    mapping(uint256 week => mapping (uint256 => uint256)) private claimedBitMap;

    event SetWeeklyClaimMerkleRoot(uint256 week, bytes32 merkleRoot, uint256 claimTotal);
    event EndWeeklyClaim(uint256 week);
    event Claim(address user, uint256 index, uint256 week, uint256 amount);
    
    error InvalidProof();
    error AlreadyClaimed();
    error ClaimTotalTooHigh(uint256 maxClaimTotal);

    modifier withMint() {
        _isMinting = 1;
        _;
        _isMinting = 2;
    }
    
    constructor() Memecoin("Henlo", "HENLO", _UNISWAP_V2_ROUTER, _maxTransactionAmount, _maxPerWallet) {
        CREATION_TIME = block.timestamp;
        lastVestTime = block.timestamp;

        _mint(msg.sender, LP_SUPPLY);
    }

    function setMerkleRoot(uint256 week, bytes32 merkleRoot, uint256 claimTotal) external onlyOwner {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply + claimTotal > MAX_TOTAL_SUPPLY) {
            revert ClaimTotalTooHigh(MAX_TOTAL_SUPPLY - _totalSupply);
        }

        weeklyClaimMerkleRoots[week] = merkleRoot;
        emit SetWeeklyClaimMerkleRoot(week, merkleRoot, claimTotal);
    }

    function endClaimWeek(uint256 week) external onlyOwner {
        weeklyClaimMerkleRoots[week] = bytes32(0);
        emit EndWeeklyClaim(week);
    }

    function isClaimed(uint256 index, uint256 week) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[week][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function claim(bytes32[] memory proof, uint256 index, uint256 week, uint256 amount) external {
        claim(proof, index, week, amount, msg.sender);
    }

    function claim(bytes32[] memory proof, uint256 index, uint256 week, uint256 amount, address to) public {
        if (isClaimed(index, week)) revert AlreadyClaimed();

        bytes32 merkleRoot = weeklyClaimMerkleRoots[week];
        bytes32 leaf = keccak256(abi.encodePacked(index, msg.sender, week, amount));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert InvalidProof();

        _setClaimed(index, week);
        emit Claim(msg.sender, index, week, amount);

        _safeMint(amount, to);
    }

    function vest() external onlyOwner {
        vest(owner());
    }

    function vest(address to) public onlyOwner {
        if (vestClaimed >= CREATOR_VEST) revert AlreadyClaimed();

        uint256 claimAmount = _updateVest();
        _safeMint(claimAmount, to);
    }
    
    function forfeitVest() external onlyOwner() {
        if (vestClaimed >= CREATOR_VEST) revert AlreadyClaimed();

        uint256 claimAmount = _updateVest();
        vestBurned += claimAmount;
    }

    function _updateVest() private returns (uint256 claimAmount) {
        claimAmount = CREATOR_VEST * (block.timestamp - lastVestTime) / UNLOCK_PERIOD;
        lastVestTime = block.timestamp;
        vestClaimed += claimAmount;

        if (vestClaimed > CREATOR_VEST) {
            claimAmount -= vestClaimed - CREATOR_VEST;
            vestClaimed = CREATOR_VEST;
        }

        if (vestClaimed > MAX_TOTAL_SUPPLY) {
            claimAmount -= vestClaimed - MAX_TOTAL_SUPPLY;
            vestClaimed = MAX_TOTAL_SUPPLY;
        }
    }

    function _setClaimed(uint256 index, uint256 week) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[week][claimedWordIndex] = claimedBitMap[week][claimedWordIndex] | (1 << claimedBitIndex);
    }

    function _safeMint(uint256 amount, address to) private withMint {
        uint256 _totalSupply = totalSupply();

        if (_totalSupply + amount > MAX_TOTAL_SUPPLY) {
            _mint(to, MAX_TOTAL_SUPPLY - _totalSupply);
        } else {
            _mint(to, amount);
        }
    }
}