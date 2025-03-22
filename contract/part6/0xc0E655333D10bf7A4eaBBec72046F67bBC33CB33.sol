// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.21;

import { AccessControl }     from "@openzeppelin/contracts/access/AccessControl.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MerkleProof }       from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/*

███████╗██████╗  █████╗ ██████╗ ██╗  ██╗    ██████╗ ███████╗██╗    ██╗ █████╗ ██████╗ ██████╗ ███████╗
██╔════╝██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝    ██╔══██╗██╔════╝██║    ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝
███████╗██████╔╝███████║██████╔╝█████╔╝     ██████╔╝█████╗  ██║ █╗ ██║███████║██████╔╝██║  ██║███████╗
╚════██║██╔═══╝ ██╔══██║██╔══██╗██╔═██╗     ██╔══██╗██╔══╝  ██║███╗██║██╔══██║██╔══██╗██║  ██║╚════██║
███████║██║     ██║  ██║██║  ██║██║  ██╗    ██║  ██║███████╗╚███╔███╔╝██║  ██║██║  ██║██████╔╝███████║
╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝

*/

contract SparkRewards is AccessControl {

    using SafeERC20 for IERC20;

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event Claimed(
        uint256 indexed epoch, address indexed account, address indexed token, uint256 amount
    );
    event EpochIsClosed(uint256 indexed epoch, bool isClosed);
    event MerkleRootUpdated(bytes32 oldMerkleRoot, bytes32 newMerkleRoot);
    event WalletUpdated(address indexed oldWallet, address indexed newWallet);

    /**********************************************************************************************/
    /*** State variables and constants                                                          ***/
    /**********************************************************************************************/

    bytes32 public constant EPOCH_ROLE       = keccak256("EPOCH_ROLE");
    bytes32 public constant MERKLE_ROOT_ROLE = keccak256("MERKLE_ROOT_ROLE");

    address public wallet;
    bytes32 public merkleRoot;

    // epoch => isClosed
    mapping(uint256 => bool) public epochClosed;

    // account => token => epoch => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public cumulativeClaimed;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** Configuration functions                                                                ***/
    /**********************************************************************************************/

    function setWallet(address wallet_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit WalletUpdated(wallet, wallet_);
        wallet = wallet_;
    }

    function setMerkleRoot(bytes32 merkleRoot_) external onlyRole(MERKLE_ROOT_ROLE) {
        emit MerkleRootUpdated(merkleRoot, merkleRoot_);
        merkleRoot = merkleRoot_;
    }

    function setEpochClosed(uint256 epoch, bool isClosed) external onlyRole(EPOCH_ROLE) {
        emit EpochIsClosed(epoch, isClosed);
        epochClosed[epoch] = isClosed;
    }

    /**********************************************************************************************/
    /*** User functions                                                                         ***/
    /**********************************************************************************************/

    function claim(
        uint256 epoch,
        address account,
        address token,
        uint256 cumulativeAmount,
        bytes32 expectedMerkleRoot,
        bytes32[] calldata merkleProof
    ) external returns (uint256 claimedAmount) {
        require(merkleRoot == expectedMerkleRoot, "SparkRewards/merkle-root-mismatch");
        require(!epochClosed[epoch],              "SparkRewards/epoch-not-enabled");

        // Construct the leaf
        bytes32 leaf = keccak256(bytes.concat(
            keccak256(abi.encode(epoch, account, token, cumulativeAmount))
        ));

        // Verify the proof
        require(MerkleProof.verifyCalldata(merkleProof, expectedMerkleRoot, leaf), "SparkRewards/invalid-proof");

        // Mark it claimed
        uint256 preClaimed = cumulativeClaimed[account][token][epoch];
        require(preClaimed < cumulativeAmount, "SparkRewards/nothing-to-claim");
        cumulativeClaimed[account][token][epoch] = cumulativeAmount;

        // Send the token
        claimedAmount = cumulativeAmount - preClaimed;
        IERC20(token).safeTransferFrom(wallet, account, claimedAmount);
        emit Claimed(epoch, account, token, claimedAmount);
    }

}