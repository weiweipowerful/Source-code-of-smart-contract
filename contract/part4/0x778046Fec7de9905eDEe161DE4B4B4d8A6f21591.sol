// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {MerkleDistributorWithDeadline} from "./MerkleDistributorWithDeadline.sol";

contract MerkleDistributorAdjustable is MerkleDistributorWithDeadline {
    error ZeroMerkleRoot();
    error StaleMerkleRoot();
    error UsedMerkleRoot();
    error TooEarly();

    // Wed Mar 13 2024 08:00:00 GMT+0000
    uint256 internal constant START = 1710316800;
    // Each epoch is 7 days
    uint256 internal constant EPOCH = 604800;

    bytes32 public proposedMerkleRoot;

    mapping(bytes32 => bool) public usedMerkleRoot;

    constructor(address token_, bytes32 merkleRoot_, uint256 endTime_, address beneficiary_)
        MerkleDistributorWithDeadline(token_, merkleRoot_, endTime_, beneficiary_)
    {
        proposedMerkleRoot = merkleRoot_;
    }

    function epoch() public view returns (uint256) {
        return (block.timestamp - START) / EPOCH;
    }

    function updateEndTime(uint256 endTime_) external onlyOwner {
        if (endTime_ < block.timestamp) revert TooEarly();
        endTime = endTime_;
    }

    // ASSUMPTIONS
    // 1. Every user has at most ONE associated leaf in the Merkle tree. 
    // 2. The leaf associated with an account tracks the TOTAL amount of tokens given to the user. 
    //    since the first epoch. This value monotonically increases with each epoch and each new Merkle tree
    //    proposed. User can only claim this amount - total claimed already
    function proposeMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        if (merkleRoot_ == bytes32(0)) revert ZeroMerkleRoot();
        if (usedMerkleRoot[merkleRoot_]) revert UsedMerkleRoot();
        proposedMerkleRoot = merkleRoot_;
    }

    function updateMerkleRoot() external onlyOwner {
        if (merkleRoot == proposedMerkleRoot) revert StaleMerkleRoot();
        merkleRoot = proposedMerkleRoot;
        usedMerkleRoot[merkleRoot] = true;
    }
}