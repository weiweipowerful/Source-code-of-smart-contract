/**
 *Submitted for verification at Etherscan.io on 2024-09-12
*/

// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20 ^0.8.0 ^0.8.20 ^0.8.7;

// contracts/interfaces/ISyrupDrip.sol

interface ISyrupDrip {

    /**************************************************************************************************************************************/
    /*** Events                                                                                                                         ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev   Emitted when new token allocations have been set.
     *  @param root     Root of the Merkle tree containing the new token allocations.
     *  @param deadline Deadline for claiming the allocations.
     *  @param maxId    Maximum unique identifier of all the token allocations.
     */
    event Allocated(bytes32 indexed root, uint256 deadline, uint256 maxId);

    /**
     *  @dev   Emitted when a token allocation has been claimed.
     *  @param id      Unique identifier of the token allocation.
     *  @param account Address of the account that received the tokens.
     *  @param amount  Amount of received tokens.
     */
    event Claimed(uint256 indexed id, address indexed account, uint256 amount);

    /**
     *  @dev   Emitted when tokens are reclaimed from the contract.
     *  @param account Address of the account the tokens were sent to.
     *  @param amount  Amount of reclaimed tokens.
     */
    event Reclaimed(address indexed account, uint256 amount);

    /**
     *  @dev   Emitted when a token allocation has been claimed and staked.
     *  @param id      Unique identifier of the token allocation.
     *  @param account Address of the account that staked.
     *  @param assets  Amount of assets staked.
     *  @param shares  Amount of shares minted.
     */
    event Staked(uint256 indexed id, address indexed account, uint256 assets, uint256 shares);

    /**************************************************************************************************************************************/
    /*** State-Changing Functions                                                                                                       ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev   Sets new token allocations.
     *         This will cancel all of the current token allocations.
     *         Can only be called by the protocol admins.
     *  @param root     Root of the Merkle tree containing the token allocations.
     *  @param deadline Timestamp after which tokens can no longer be claimed.
     *  @param maxId    Maximum unique identifier of all the token allocations.
     */
    function allocate(bytes32 root, uint256 deadline, uint256 maxId) external;

    /**
     *  @dev   Claims a token allocation.
     *         Can only claim a token allocation once.
     *         Can only be claimed before the deadline expires.
     *         Can only be claimed if the Merkle proof is valid.
     *  @param id           Unique identifier of the token allocation.
     *  @param account      Address of the token recipient.
     *  @param claimAmount  Amount of tokens to claim.
     *  @param proof        Proof that the recipient is part of the Merkle tree of token allocations.
     */
    function claim(uint256 id, address account, uint256 claimAmount, bytes32[] calldata proof) external;

    /**
     *  @dev   Claims a token allocation and stakes the claimed tokens.
     *         Can only claim a token allocation once.
     *         Can only be claimed before the deadline expires.
     *         Can only be claimed if the Merkle proof is valid.
     *  @param id          Unique identifier of the token allocation.
     *  @param account     Address of the token recipient.
     *  @param claimAmount Amount of tokens to claim.
     *  @param stakeAmount Amount of tokens to stake.
     *  @param proof       Proof that the recipient is part of the Merkle tree of token allocations.
     */
    function claimAndStake(uint256 id, address account, uint256 claimAmount, uint256 stakeAmount, bytes32[] calldata proof) external;

    /**
     *  @dev   Reclaims tokens from the contract.
     *         Can only be called by the protocol admins.
     *  @param to     Address of the token recipient
     *  @param amount Amount of tokens reclaimed.
     */
    function reclaim(address to, uint256 amount) external;

    /**************************************************************************************************************************************/
    /*** View Functions                                                                                                                 ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev    Returns the address of the claimable ERC-20 token.
     *  @return asset Address of the ERC-20 token.
     */
    function asset() external view returns (address asset);

    /**
     *  @dev    Returns a bitmap that defines which token allocations have been claimed.
     *  @param  index  Index of the bitmap array.
     *  @return bitmap Bitmap of claimed token allocations.
     */
    function bitmaps(uint256 index) external view returns (uint256 bitmap);

    /**
     *  @dev    Returns the deadline for the current token allocations.
     *  @return deadline Timestamp before which allocations can be claimed.
     */
    function deadline() external view returns (uint256 deadline);

    /**
     *  @dev    Returns the address of the `MapleGlobals` contract.
     *  @return globals Address of the `MapleGlobals` contract.
     */
    function globals() external view returns (address globals);

    /**
     *  @dev    Returns the maximum identifier of all the current token allocations.
     *  @return maxId Maximum identifier of all the current token allocations.
     */
    function maxId() external view returns (uint256 maxId);

    /**
     *  @dev    Returns the root of the Merkle tree containing the current token allocations.
     *  @return root Root of the Merkle tree.
     */
    function root() external view returns (bytes32 root);

    /**
     *  @dev    Returns the address of the `StakedSyrup` contract.
     *  @return stakedSyrup Address of the `StakedSyrup` contract.
     */
    function stakedSyrup() external view returns (address stakedSyrup);

}

// contracts/interfaces/Interfaces.sol

interface IBalancerVaultLike {

    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    function swap(
        SingleSwap calldata singleSwap,
        FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256 assetDelta);

}

interface IERC20Like_0 {

    function allowance(address owner, address spender) external view returns (uint256 allowance);

    function balanceOf(address account) external view returns (uint256 balance);

    function DOMAIN_SEPARATOR() external view returns (bytes32 domainSeparator);

    function PERMIT_TYPEHASH() external view returns (bytes32 permitTypehash);

    function approve(address spender, uint256 amount) external returns (bool success);

    function permit(address owner, address spender, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    function transfer(address recipient, uint256 amount) external returns (bool success);

    function transferFrom(address owner, address recipient, uint256 amount) external returns (bool success);

}

interface IGlobalsLike {

    function governor() external view returns (address governor);

    function operationalAdmin() external view returns (address operationalAdmin);

}

interface IMigratorLike {

    function migrate(address receiver, uint256 mplAmount) external returns (uint256 syrupAmount);

}

interface IPoolLike is IERC20Like_0 {

    function asset() external view returns (address asset);

    function convertToExitAssets(uint256 shares) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function manager() external view returns (address manager);

}

interface IPoolManagerLike {

    function poolPermissionManager() external view returns (address poolPermissionManager);

}

interface IPoolPermissionManagerLike {

    function hasPermission(address poolManager, address lender, bytes32 functionId) external view returns (bool hasPermission);

    function permissionAdmins(address account) external view returns (bool isAdmin);

    function setLenderBitmaps(address[] calldata lenders, uint256[] calldata bitmaps) external;

}

interface IPSMLike {

    function buyGem(address account, uint256 daiAmount) external;

    function tout() external view returns (uint256 tout);  // This is the fee charged for conversion

}

interface ISDaiLike {

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

}

interface IRDTLike {

    function asset() external view returns (address asset);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

}

interface IStakedSyrupLike {

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

}

// modules/erc20-helper/src/interfaces/IERC20Like.sol

/// @title Interface of the ERC20 standard as needed by ERC20Helper.
interface IERC20Like_1 {

    function approve(address spender_, uint256 amount_) external returns (bool success_);

    function transfer(address recipient_, uint256 amount_) external returns (bool success_);

    function transferFrom(address owner_, address recipient_, uint256 amount_) external returns (bool success_);

}

// modules/open-zeppelin/contracts/utils/cryptography/MerkleProof.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/cryptography/MerkleProof.sol)

/**
 * @dev These functions deal with verification of Merkle Tree proofs.
 *
 * The tree and the proofs can be generated using our
 * https://github.com/OpenZeppelin/merkle-tree[JavaScript library].
 * You will find a quickstart guide in the readme.
 *
 * WARNING: You should avoid using leaf values that are 64 bytes long prior to
 * hashing, or use a hash function other than keccak256 for hashing leaves.
 * This is because the concatenation of a sorted pair of internal nodes in
 * the Merkle tree could be reinterpreted as a leaf value.
 * OpenZeppelin's JavaScript library generates Merkle trees that are safe
 * against this attack out of the box.
 */
library MerkleProof {
    /**
     *@dev The multiproof provided is not valid.
     */
    error MerkleProofInvalidMultiproof();

    /**
     * @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        return processProof(proof, leaf) == root;
    }

    /**
     * @dev Calldata version of {verify}
     */
    function verifyCalldata(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        return processProofCalldata(proof, leaf) == root;
    }

    /**
     * @dev Returns the rebuilt hash obtained by traversing a Merkle tree up
     * from `leaf` using `proof`. A `proof` is valid if and only if the rebuilt
     * hash matches the root of the tree. When processing the proof, the pairs
     * of leafs & pre-images are assumed to be sorted.
     */
    function processProof(bytes32[] memory proof, bytes32 leaf) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = _hashPair(computedHash, proof[i]);
        }
        return computedHash;
    }

    /**
     * @dev Calldata version of {processProof}
     */
    function processProofCalldata(bytes32[] calldata proof, bytes32 leaf) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = _hashPair(computedHash, proof[i]);
        }
        return computedHash;
    }

    /**
     * @dev Returns true if the `leaves` can be simultaneously proven to be a part of a Merkle tree defined by
     * `root`, according to `proof` and `proofFlags` as described in {processMultiProof}.
     *
     * CAUTION: Not all Merkle trees admit multiproofs. See {processMultiProof} for details.
     */
    function multiProofVerify(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        return processMultiProof(proof, proofFlags, leaves) == root;
    }

    /**
     * @dev Calldata version of {multiProofVerify}
     *
     * CAUTION: Not all Merkle trees admit multiproofs. See {processMultiProof} for details.
     */
    function multiProofVerifyCalldata(
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        return processMultiProofCalldata(proof, proofFlags, leaves) == root;
    }

    /**
     * @dev Returns the root of a tree reconstructed from `leaves` and sibling nodes in `proof`. The reconstruction
     * proceeds by incrementally reconstructing all inner nodes by combining a leaf/inner node with either another
     * leaf/inner node or a proof sibling node, depending on whether each `proofFlags` item is true or false
     * respectively.
     *
     * CAUTION: Not all Merkle trees admit multiproofs. To use multiproofs, it is sufficient to ensure that: 1) the tree
     * is complete (but not necessarily perfect), 2) the leaves to be proven are in the opposite order they are in the
     * tree (i.e., as seen from right to left starting at the deepest layer and continuing at the next layer).
     */
    function processMultiProof(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32[] memory leaves
    ) internal pure returns (bytes32 merkleRoot) {
        // This function rebuilds the root hash by traversing the tree up from the leaves. The root is rebuilt by
        // consuming and producing values on a queue. The queue starts with the `leaves` array, then goes onto the
        // `hashes` array. At the end of the process, the last hash in the `hashes` array should contain the root of
        // the Merkle tree.
        uint256 leavesLen = leaves.length;
        uint256 proofLen = proof.length;
        uint256 totalHashes = proofFlags.length;

        // Check proof validity.
        if (leavesLen + proofLen != totalHashes + 1) {
            revert MerkleProofInvalidMultiproof();
        }

        // The xxxPos values are "pointers" to the next value to consume in each array. All accesses are done using
        // `xxx[xxxPos++]`, which return the current value and increment the pointer, thus mimicking a queue's "pop".
        bytes32[] memory hashes = new bytes32[](totalHashes);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        uint256 proofPos = 0;
        // At each step, we compute the next hash using two values:
        // - a value from the "main queue". If not all leaves have been consumed, we get the next leaf, otherwise we
        //   get the next hash.
        // - depending on the flag, either another value from the "main queue" (merging branches) or an element from the
        //   `proof` array.
        for (uint256 i = 0; i < totalHashes; i++) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = proofFlags[i]
                ? (leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++])
                : proof[proofPos++];
            hashes[i] = _hashPair(a, b);
        }

        if (totalHashes > 0) {
            if (proofPos != proofLen) {
                revert MerkleProofInvalidMultiproof();
            }
            unchecked {
                return hashes[totalHashes - 1];
            }
        } else if (leavesLen > 0) {
            return leaves[0];
        } else {
            return proof[0];
        }
    }

    /**
     * @dev Calldata version of {processMultiProof}.
     *
     * CAUTION: Not all Merkle trees admit multiproofs. See {processMultiProof} for details.
     */
    function processMultiProofCalldata(
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        bytes32[] memory leaves
    ) internal pure returns (bytes32 merkleRoot) {
        // This function rebuilds the root hash by traversing the tree up from the leaves. The root is rebuilt by
        // consuming and producing values on a queue. The queue starts with the `leaves` array, then goes onto the
        // `hashes` array. At the end of the process, the last hash in the `hashes` array should contain the root of
        // the Merkle tree.
        uint256 leavesLen = leaves.length;
        uint256 proofLen = proof.length;
        uint256 totalHashes = proofFlags.length;

        // Check proof validity.
        if (leavesLen + proofLen != totalHashes + 1) {
            revert MerkleProofInvalidMultiproof();
        }

        // The xxxPos values are "pointers" to the next value to consume in each array. All accesses are done using
        // `xxx[xxxPos++]`, which return the current value and increment the pointer, thus mimicking a queue's "pop".
        bytes32[] memory hashes = new bytes32[](totalHashes);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        uint256 proofPos = 0;
        // At each step, we compute the next hash using two values:
        // - a value from the "main queue". If not all leaves have been consumed, we get the next leaf, otherwise we
        //   get the next hash.
        // - depending on the flag, either another value from the "main queue" (merging branches) or an element from the
        //   `proof` array.
        for (uint256 i = 0; i < totalHashes; i++) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = proofFlags[i]
                ? (leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++])
                : proof[proofPos++];
            hashes[i] = _hashPair(a, b);
        }

        if (totalHashes > 0) {
            if (proofPos != proofLen) {
                revert MerkleProofInvalidMultiproof();
            }
            unchecked {
                return hashes[totalHashes - 1];
            }
        } else if (leavesLen > 0) {
            return leaves[0];
        } else {
            return proof[0];
        }
    }

    /**
     * @dev Sorts the pair (a, b) and hashes the result.
     */
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    /**
     * @dev Implementation of keccak256(abi.encode(a, b)) that doesn't allocate or expand memory.
     */
    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}

// modules/erc20-helper/src/ERC20Helper.sol

/**
 * @title Small Library to standardize erc20 token interactions.
 */
library ERC20Helper {

    /**************************************************************************************************************************************/
    /*** Internal Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function transfer(address token_, address to_, uint256 amount_) internal returns (bool success_) {
        return _call(token_, abi.encodeWithSelector(IERC20Like_1.transfer.selector, to_, amount_));
    }

    function transferFrom(address token_, address from_, address to_, uint256 amount_) internal returns (bool success_) {
        return _call(token_, abi.encodeWithSelector(IERC20Like_1.transferFrom.selector, from_, to_, amount_));
    }

    function approve(address token_, address spender_, uint256 amount_) internal returns (bool success_) {
        // If setting approval to zero fails, return false.
        if (!_call(token_, abi.encodeWithSelector(IERC20Like_1.approve.selector, spender_, uint256(0)))) return false;

        // If `amount_` is zero, return true as the previous step already did this.
        if (amount_ == uint256(0)) return true;

        // Return the result of setting the approval to `amount_`.
        return _call(token_, abi.encodeWithSelector(IERC20Like_1.approve.selector, spender_, amount_));
    }

    function _call(address token_, bytes memory data_) private returns (bool success_) {
        if (token_.code.length == uint256(0)) return false;

        bytes memory returnData;
        ( success_, returnData ) = token_.call(data_);

        return success_ && (returnData.length == uint256(0) || abi.decode(returnData, (bool)));
    }

}

// contracts/SyrupDrip.sol

contract SyrupDrip is ISyrupDrip {

    /**************************************************************************************************************************************/
    /*** State Variables                                                                                                                ***/
    /**************************************************************************************************************************************/

    address public immutable override asset;
    address public immutable override globals;
    address public immutable override stakedSyrup;

    bytes32 public override root;

    uint256 public override deadline;
    uint256 public override maxId;

    mapping(uint256 => uint256) public override bitmaps;

    /**************************************************************************************************************************************/
    /*** Constructor                                                                                                                    ***/
    /**************************************************************************************************************************************/

    constructor(address asset_, address globals_, address stakedSyrup_) {
        asset       = asset_;
        globals     = globals_;
        stakedSyrup = stakedSyrup_;

        // Approve the staked syrup contract to transfer the asset.
        require(ERC20Helper.approve(asset_, stakedSyrup_, type(uint256).max), "SD:C:APPROVAL_FAILED");
    }

    /**************************************************************************************************************************************/
    /*** Modifiers                                                                                                                      ***/
    /**************************************************************************************************************************************/

    modifier onlyProtocolAdmins {
        address globals_ = globals;

        require(
            msg.sender == IGlobalsLike(globals_).governor() ||
            msg.sender == IGlobalsLike(globals_).operationalAdmin(),
            "SD:NOT_AUTHORIZED"
        );

        _;
    }

    /**************************************************************************************************************************************/
    /*** External Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function allocate(bytes32 root_, uint256 deadline_, uint256 maxId_) external override onlyProtocolAdmins {
        require(deadline_ >= block.timestamp, "SD:A:INVALID_DEADLINE");
        require(maxId_ >= maxId,              "SD:A:INVALID_MAX_ID");

        root     = root_;
        deadline = deadline_;
        maxId    = maxId_;

        emit Allocated(root_, deadline_, maxId_);
    }

    function claim(uint256 id_, address owner_, uint256 claimAmount_, bytes32[] calldata proof_) external override {
        _claim(id_, owner_, claimAmount_, claimAmount_, proof_);
    }

    function claimAndStake(
        uint256   id_,
        address   owner_,
        uint256   claimAmount_,
        uint256   stakeAmount_,
        bytes32[] calldata proof_
    )
        external override
    {
        require(stakeAmount_ > 0,             "SD:CAS:ZERO_STAKE_AMOUNT");
        require(stakeAmount_ <= claimAmount_, "SD:CAS:INVALID_STAKE_AMOUNT");

        _claim(id_, owner_, claimAmount_, claimAmount_ - stakeAmount_, proof_);

        uint256 shares_ = IStakedSyrupLike(stakedSyrup).deposit(stakeAmount_, owner_);

        emit Staked(id_, owner_, stakeAmount_, shares_);
    }

    function reclaim(address to_, uint256 amount_) external override onlyProtocolAdmins {
        require(amount_ != 0,                              "SD:R:ZERO_AMOUNT");
        require(ERC20Helper.transfer(asset, to_, amount_), "SD:R:TRANSFER_FAIL");

        emit Reclaimed(to_, amount_);
    }

    /**************************************************************************************************************************************/
    /*** View Functions                                                                                                                 ***/
    /**************************************************************************************************************************************/

    // Checks if a token allocation has already been claimed.
    function isClaimed(uint256 id_) public view returns (bool isClaimed_) {
        uint256 key_  = id_ / 256;
        uint256 flag_ = id_ % 256;
        uint256 word_ = bitmaps[key_];
        uint256 mask_ = (1 << flag_);

        isClaimed_ = word_ & mask_ == mask_;
    }

    /**************************************************************************************************************************************/
    /*** Internal Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function _claim(
        uint256   id_,
        address   owner_,
        uint256   claimAmount_,
        uint256   transferAmount_,
        bytes32[] calldata proof_
    )
        internal
    {
        require(!isClaimed(id_),             "SD:C:ALREADY_CLAIMED");
        require(block.timestamp <= deadline, "SD:C:EXPIRED_DEADLINE");

        bytes32 leaf_ = keccak256(bytes.concat(keccak256(abi.encode(id_, owner_, claimAmount_))));

        require(MerkleProof.verify(proof_, root, leaf_), "SD:C:INVALID_PROOF");

        _setClaimed(id_);

        if (transferAmount_ > 0) {
            require(ERC20Helper.transfer(asset, owner_, transferAmount_), "SD:C:TRANSFER_FAIL");
        }

        emit Claimed(id_, owner_, claimAmount_);
    }

    // Registers a token allocation as claimed.
    function _setClaimed(uint256 id_) internal {
        uint256 key_  = id_ / 256;
        uint256 flag_ = id_ % 256;

        bitmaps[key_] = bitmaps[key_] | (1 << flag_);
    }

}