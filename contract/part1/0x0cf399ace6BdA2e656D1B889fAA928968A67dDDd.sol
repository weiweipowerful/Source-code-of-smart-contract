// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TTMerkleAirdrop is Ownable {
    using SafeERC20 for IERC20;

    mapping(uint256 => bytes32) public merkleRoots; // 每日一个 Merkle 根
    mapping(address => mapping(uint256 => uint256)) public claimedBitMap;

    event Claimed(uint256 index, address account, uint256 amount, address token);

    constructor() {
    }

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[_msgSender()][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function isClaimed(uint256[] calldata indexes) external view returns (bool[] memory) {
        bool[] memory result = new bool[](indexes.length);
        for (uint256 i = 0; i < indexes.length; i++) {
            result[i] = isClaimed(indexes[i]);
        }
        return result;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[_msgSender()][claimedWordIndex] |= (1 << claimedBitIndex);
    }

    function claim(uint256 index, uint256 amount, address token, bytes32[] calldata merkleProof) external {
        require(!isClaimed(index), "Airdrop: Drop already claimed.");
        require(merkleRoots[index] != 0, "Airdrop: MerkleRoot not set for this day.");

        bytes32 node = keccak256(abi.encodePacked(_msgSender(), amount, token));
        require(MerkleProof.verify(merkleProof, merkleRoots[index], node), "Airdrop: Invalid proof.");

        _setClaimed(index);

        IERC20(token).safeTransfer(_msgSender(), amount);

        emit Claimed(index, _msgSender(), amount, token);
    }

    function claimMultiple(
        uint256[] calldata indexes,
        uint256[] calldata amounts,
        address token,
        bytes32[][] calldata merkleProofs
    ) external {
        require(indexes.length == amounts.length && indexes.length == merkleProofs.length, "Airdrop: Parameters length mismatch.");

        // 总领取的空投数量
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < indexes.length; i++) {
            uint256 index = indexes[i];
            uint256 amount = amounts[i];
            bytes32[] calldata merkleProof = merkleProofs[i];

            require(!isClaimed(index), "Airdrop: Some drops already claimed for this day.");
            bytes32 merkleRoot = merkleRoots[index];
            require(merkleRoot != 0, "Airdrop: MerkleRoot not set for this day.");

            bytes32 leaf = keccak256(abi.encodePacked(_msgSender(), amount, token));
            require(
                MerkleProof.verify(merkleProof, merkleRoot, leaf),
                "Airdrop: Invalid proof."
            );

            _setClaimed(index);

            totalAmount += amount;

            emit Claimed(index, _msgSender(), amount, token);
        }

        // 转移总代币
        IERC20(token).safeTransfer(_msgSender(), totalAmount);
    }

    function setMerkleRoot(uint256 index, bytes32 merkleRoot) external onlyOwner {
        require(merkleRoots[index] == 0, "Airdrop: Merkle root already set.");
        merkleRoots[index] = merkleRoot;
    }

    function drain(address[] calldata token) external onlyOwner {
        for (uint256 i = 0; i < token.length; i++) {
            _drain(token[i]);
        }
    }

    function _drain(address token) private {
        IERC20(token).safeTransfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}