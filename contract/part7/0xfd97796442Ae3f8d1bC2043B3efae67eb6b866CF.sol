// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract StakeStoneRewardDistributor is AccessControl {
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    bytes32 public root;

    uint256 public terminatingStartTime;
    bool public terminated;

    mapping(address => mapping(address => uint256)) public claimed;

    // Constructor
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Public
    function claim(
        bytes32[][] memory _proof,
        address[] memory _token,
        uint256[] memory _totalClaimableAmount,
        uint256[] memory _claimAmount
    ) external {
        require(terminated == false, "Claim terminated");

        uint256 length = _proof.length;
        for (uint256 i = 0; i < length; i++) {
            address token = _token[i];
            uint256 totalClaimableAmount = _totalClaimableAmount[i];
            uint256 claimAmount = _claimAmount[i];

            bytes32 leaf = keccak256(
                bytes.concat(
                    keccak256(
                        abi.encode(msg.sender, token, totalClaimableAmount)
                    )
                )
            );
            require(MerkleProof.verify(_proof[i], root, leaf), "Invalid proof");
            claimed[msg.sender][token] += claimAmount;
            require(
                claimed[msg.sender][token] <= totalClaimableAmount,
                "Invalid amount"
            );
            TransferHelper.safeTransfer(token, msg.sender, claimAmount);
        }
    }

    // Owner
    function startTerminate() external onlyRole(SETTER_ROLE) {
        terminatingStartTime = block.timestamp;
    }

    function finalTerminate(
        address[] memory _tokens
    ) external onlyRole(SETTER_ROLE) {
        require(
            block.timestamp - terminatingStartTime > 30 days,
            "Still terminating"
        );

        for (uint256 i = 0; i < _tokens.length; i++) {
            TransferHelper.safeTransfer(
                _tokens[i],
                msg.sender,
                IERC20(_tokens[i]).balanceOf(address(this))
            );
        }

        terminated = true;
    }

    function setRoot(bytes32 _root) external onlyRole(SETTER_ROLE) {
        root = _root;
    }
}