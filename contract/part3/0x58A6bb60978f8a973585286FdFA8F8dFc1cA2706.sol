// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.19;

import { ReentrancyGuard } from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import { Client } from '@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol';
import { InterportCCIPBridgeCore } from './core/InterportCCIPBridgeCore.sol';
import '../../helpers/TransferHelper.sol' as TransferHelper;

/**
 * @title InterportCCIPTokenBridge
 * @notice The contract bridges ERC-20 tokens with Chainlink CCIP
 */
contract InterportCCIPTokenBridge is InterportCCIPBridgeCore, ReentrancyGuard {
    /**
     * @notice The "bridgeTokens" action parameters
     * @param targetChainId The message target chain ID (EVM)
     * @param targetChainSelector The message target chain selector (CCIP)
     * @param targetRecipient The address of the recipient on the target chain
     * @param tokenAmounts Token amount data
     * @param messagingToken The messaging token address
     */
    struct TokenBridgeAction {
        uint256 targetChainId;
        uint64 targetChainSelector;
        address targetRecipient;
        Client.EVMTokenAmount[] tokenAmounts;
    }

    /**
     * @notice Token bridge action source event
     * @param targetChainId The ID of the target chain
     * @param sourceSender The address of the user on the source chain
     * @param targetRecipient The address of the recipient on the target chain
     * @param tokenAmounts Token amount data
     * @param ccipMessageId The CCIP message ID
     * @param timestamp The timestamp of the action (in seconds)
     */
    event TokenBridgeActionSource(
        uint256 targetChainId,
        address indexed sourceSender,
        address targetRecipient,
        Client.EVMTokenAmount[] tokenAmounts,
        bytes32 indexed ccipMessageId,
        uint256 timestamp
    );

    /**
     * @notice Initializes the contract
     * @param _endpointAddress The cross-chain endpoint address
     * @param _owner The address of the initial owner of the contract
     * @param _managers The addresses of initial managers of the contract
     * @param _addOwnerToManagers The flag to optionally add the owner to the list of managers
     */
    constructor(
        address _endpointAddress,
        address _owner,
        address[] memory _managers,
        bool _addOwnerToManagers
    ) InterportCCIPBridgeCore(_endpointAddress, _owner, _managers, _addOwnerToManagers) {}

    /**
     * @notice Cross-chain bridging of ERC-20 tokens
     * @param _action The action parameters
     * @param _messagingTokenInfo The messaging token info
     */
    function bridgeTokens(
        TokenBridgeAction calldata _action,
        MessagingTokenInfo calldata _messagingTokenInfo
    ) external payable whenNotPaused nonReentrant returns (bytes32 ccipMessageId) {
        (bool isNativeMessagingToken, uint256 ccipSendValue) = _checkMessagingTokenInfo(
            _messagingTokenInfo,
            0
        );

        bool messagingTokenIncluded;

        for (uint256 index; index < _action.tokenAmounts.length; index++) {
            Client.EVMTokenAmount calldata tokenAmountData = _action.tokenAmounts[index];

            uint256 tokenAmountToReceive = tokenAmountData.amount;
            uint256 tokenAmountToApprove = tokenAmountData.amount;

            if (_messagingTokenInfo.token == tokenAmountData.token && !messagingTokenIncluded) {
                messagingTokenIncluded = true;
                tokenAmountToReceive += _messagingTokenInfo.amount;
                tokenAmountToApprove += _messagingTokenInfo.messagingAmount;
            }

            TransferHelper.safeTransferFrom(
                tokenAmountData.token,
                msg.sender,
                address(this),
                tokenAmountToReceive
            );

            TransferHelper.safeApprove(tokenAmountData.token, endpoint, tokenAmountToApprove);
        }

        if (!messagingTokenIncluded && !isNativeMessagingToken) {
            TransferHelper.safeTransferFrom(
                _messagingTokenInfo.token,
                msg.sender,
                address(this),
                _messagingTokenInfo.amount
            );

            TransferHelper.safeApprove(
                _messagingTokenInfo.token,
                endpoint,
                _messagingTokenInfo.messagingAmount
            );
        }

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory ccipMessage = _createCcipMessage(
            _action.targetRecipient,
            new bytes(0),
            _action.tokenAmounts,
            0,
            _messagingTokenInfo.token
        );

        // Send the message
        ccipMessageId = _ccipSend(_action.targetChainSelector, ccipMessage, ccipSendValue);

        for (uint256 index; index < _action.tokenAmounts.length; index++) {
            TransferHelper.safeApprove(_action.tokenAmounts[index].token, endpoint, 0);
        }

        if (!messagingTokenIncluded && !isNativeMessagingToken) {
            TransferHelper.safeApprove(_messagingTokenInfo.token, endpoint, 0);
        }

        emit TokenBridgeActionSource(
            _action.targetChainId,
            msg.sender,
            _action.targetRecipient,
            _action.tokenAmounts,
            ccipMessageId,
            block.timestamp
        );
    }

    /**
     * @notice Cross-chain message fee estimation
     * @param _action The action parameters
     * @return Message fee
     */
    function messageFee(
        TokenBridgeAction calldata _action,
        address _messagingToken
    ) external view returns (uint256) {
        Client.EVM2AnyMessage memory ccipMessage = _createCcipMessage(
            _action.targetRecipient,
            new bytes(0),
            _action.tokenAmounts,
            0,
            _messagingToken
        );

        return _ccipGetFee(_action.targetChainSelector, ccipMessage);
    }
}