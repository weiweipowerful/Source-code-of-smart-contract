// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts-v5/access/Ownable2Step.sol";
import {MerkleProof} from "@openzeppelin/contracts-v5/utils/cryptography/MerkleProof.sol";

import {ILock} from "./interfaces/ILock.sol";
import {ICumulativeMerkleDrop} from "./interfaces/ICumulativeMerkleDrop.sol";

/// Contract which manages initial distribution of the SWELL token via merkle drop claim process.
contract CumulativeMerkleDrop is Ownable2Step, ICumulativeMerkleDrop {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint8 private constant OPEN = 1;
    uint8 private constant NOT_OPEN = 2;
    
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICumulativeMerkleDrop
    IERC20 public immutable token;

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICumulativeMerkleDrop
    uint8 public claimIsOpen;

    /// @inheritdoc ICumulativeMerkleDrop
    ILock public stakingContract;

    /// @inheritdoc ICumulativeMerkleDrop
    bytes32 public merkleRoot;

    /// @inheritdoc ICumulativeMerkleDrop
    mapping(address => uint256) public cumulativeClaimed;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _token) Ownable(_owner) {
        if (_token == address(0)) revert ADDRESS_NULL();

        claimIsOpen = NOT_OPEN;
        token = IERC20(_token);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyClaimOpen() {
        if (claimIsOpen != OPEN) revert CLAIM_CLOSED();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICumulativeMerkleDrop
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        if (_merkleRoot == merkleRoot) revert SAME_MERKLE_ROOT();
        emit MerkleRootUpdated(merkleRoot, _merkleRoot);
        merkleRoot = _merkleRoot;
    }

    /// @inheritdoc ICumulativeMerkleDrop
    function setStakingContract(address _stakingContract) external onlyOwner {
        if (_stakingContract == address(0)) revert ADDRESS_NULL();
        address oldStakingContract = address(stakingContract);
        
        if (_stakingContract == oldStakingContract) revert SAME_STAKING_CONTRACT();
        if (ILock(_stakingContract).token() != token) revert STAKING_TOKEN_MISMATCH();
        emit StakingContractUpdated(oldStakingContract, _stakingContract);
        stakingContract = ILock(_stakingContract);
        token.approve(address(_stakingContract), type(uint256).max);

        if (oldStakingContract != address(0)) {
            token.approve(oldStakingContract, 0);
        }
    }

    /// @inheritdoc ICumulativeMerkleDrop
    function clearStakingContract() external onlyOwner {
        address oldStakingContract = address(stakingContract);
        if (oldStakingContract == address(0)) revert SAME_STAKING_CONTRACT();
        emit StakingContractCleared();
        stakingContract = ILock(address(0));
        token.approve(oldStakingContract, 0);
    }

    /// @inheritdoc ICumulativeMerkleDrop
    function setClaimStatus(uint8 status) external onlyOwner {
        if (status != OPEN && status != NOT_OPEN) revert INVALID_STATUS();
        emit ClaimStatusUpdated(claimIsOpen, status);
        claimIsOpen = status;
    }

    /*//////////////////////////////////////////////////////////////
                             MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICumulativeMerkleDrop
    function claimAndLock(uint256 cumulativeAmount, uint256 amountToLock, bytes32[] calldata merkleProof)
        external
        onlyClaimOpen
    {
        // Verify the merkle proof
        if (!verifyProof(merkleProof, cumulativeAmount, msg.sender)) revert INVALID_PROOF();

        // Mark it claimed
        uint256 preclaimed = cumulativeClaimed[msg.sender];
        if (preclaimed >= cumulativeAmount) revert NOTHING_TO_CLAIM();
        cumulativeClaimed[msg.sender] = cumulativeAmount;

        // Send the token
        uint256 amount = cumulativeAmount - preclaimed;
        if (amountToLock > 0) {
            if (amountToLock > amount) revert AMOUNT_TO_LOCK_GT_AMOUNT_CLAIMED();
            // Ensure the staking contract is set before locking
            if (address(stakingContract) == address(0)) revert STAKING_NOT_AVAILABLE();
            stakingContract.lock(msg.sender, amountToLock);
        }

        if (amount != amountToLock) token.transfer(msg.sender, amount - amountToLock);

        emit Claimed(msg.sender, amount, amountToLock);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICumulativeMerkleDrop
    function verifyProof(bytes32[] calldata proof, uint256 amount, address addr) public view returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr, amount))));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }
}