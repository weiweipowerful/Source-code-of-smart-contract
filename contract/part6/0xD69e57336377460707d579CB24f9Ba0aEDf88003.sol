// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IRewards } from "src/interfaces/rewarders/IRewards.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { EIP712, ECDSA } from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { Errors } from "src/utils/Errors.sol";

/// @notice Distribute rewards based on proof
contract Rewards is IRewards, SecurityBase, SystemComponent, EIP712 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    /// =====================================================
    /// Constant Vars
    /// =====================================================

    bytes32 private constant _RECIPIENT_TYPEHASH =
        keccak256("Recipient(uint256 chainId,uint256 cycle,address wallet,uint256 amount)");

    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @inheritdoc IRewards
    IERC20 public immutable override rewardToken;

    /// @inheritdoc IRewards
    mapping(address => uint256) public override claimedAmounts;

    /// @inheritdoc IRewards
    address public override rewardsSigner;

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry,
        IERC20 _rewardToken,
        address _rewardsSigner
    )
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
        EIP712("sTOKE Rewards", "1")
    {
        Errors.verifyNotZero(address(_rewardToken), "token");
        Errors.verifyNotZero(address(_rewardsSigner), "signerAddress");

        // slither-disable-next-line missing-zero-check
        rewardToken = _rewardToken;
        // slither-disable-next-line missing-zero-check
        rewardsSigner = _rewardsSigner;
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @inheritdoc IRewards
    function claim(Recipient calldata recipient, uint8 v, bytes32 r, bytes32 s) external override returns (uint256) {
        if (recipient.wallet != msg.sender) {
            revert Errors.SenderMismatch(recipient.wallet, msg.sender);
        }

        return _claim(recipient, v, r, s, msg.sender);
    }

    /// @inheritdoc IRewards
    function claimFor(
        Recipient calldata recipient,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256) {
        if (msg.sender != address(systemRegistry.autoPoolRouter())) {
            revert Errors.AccessDenied();
        }

        return _claim(recipient, v, r, s, recipient.wallet);
    }

    /// @inheritdoc IRewards
    function setSigner(
        address newSigner
    ) external override onlyOwner {
        Errors.verifyNotZero(newSigner, "newSigner");

        // slither-disable-next-line missing-zero-check
        rewardsSigner = newSigner;

        emit SignerSet(newSigner);
    }

    /// @inheritdoc IRewards
    function getClaimableAmount(
        Recipient calldata recipient
    ) external view override returns (uint256) {
        return recipient.amount - claimedAmounts[recipient.wallet];
    }

    /// @notice Returns the signer of the given payload
    function verifyRecipientSignature(
        Recipient calldata recipient,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external view returns (address) {
        return genHash(recipient).recover(v, r, s);
    }

    /// =====================================================
    /// Functions - Public
    /// =====================================================

    /// @inheritdoc IRewards
    function genHash(
        Recipient memory recipient
    ) public view returns (bytes32) {
        return _hashTypedDataV4(_hashRecipient(recipient));
    }

    /// =====================================================
    /// Functions - Private
    /// =====================================================

    // @dev bytes32 s is bytes calldata signature
    function _claim(
        Recipient calldata recipient,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address sendTo
    ) private returns (uint256) {
        address signatureSigner = genHash(recipient).recover(v, r, s);

        if (signatureSigner != rewardsSigner) {
            revert Errors.InvalidSigner(signatureSigner);
        }

        if (recipient.chainId != _getChainID()) {
            revert Errors.InvalidChainId(recipient.chainId);
        }

        uint256 claimedAmount = claimedAmounts[recipient.wallet];
        uint256 claimableAmount = recipient.amount - claimedAmount;

        if (claimableAmount == 0) {
            revert Errors.ZeroAmount();
        }

        if (claimableAmount > rewardToken.balanceOf(address(this))) {
            revert Errors.InsufficientBalance(address(rewardToken));
        }

        claimedAmounts[recipient.wallet] = claimedAmount + claimableAmount;

        emit Claimed(recipient.cycle, recipient.wallet, claimableAmount);

        rewardToken.safeTransfer(sendTo, claimableAmount);

        return claimableAmount;
    }

    function _getChainID() private view returns (uint256) {
        return block.chainid;
    }

    function _hashRecipient(
        Recipient memory recipient
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(_RECIPIENT_TYPEHASH, recipient.chainId, recipient.cycle, recipient.wallet, recipient.amount)
        );
    }
}