// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MerkleDistributor is Ownable {
    IERC20 public immutable token;
    bytes32 public merkleRoot;

    mapping(bytes32 => mapping(address => bool)) public claimed;

    constructor(IERC20 token_, bytes32 merkleRoot_) {
        token = token_;
        merkleRoot = merkleRoot_;
    }

    function isClaimed(address account) public view returns (bool) {
        return claimed[merkleRoot][account];
    }

    function _setClaimed(address account) private {
        claimed[merkleRoot][account] = true;
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external {
        require(!isClaimed(account), "MerkleDistributor: Drop already claimed.");

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "MerkleDistributor: Invalid proof.");

        // Mark it claimed and send the token.
        _setClaimed(account);
        require(IERC20(token).transfer(account, amount), "MerkleDistributor: Transfer failed.");

        emit Claimed(index, account, amount);
    }

    function rescue(address to, address token_, uint256 amount) external onlyOwner {
        require(IERC20(token_).transfer(to, amount), "MerkleDistributor: Transfer failed.");
    }

    function setMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        merkleRoot = merkleRoot_;
    }

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 index, address account, uint256 amount);
}