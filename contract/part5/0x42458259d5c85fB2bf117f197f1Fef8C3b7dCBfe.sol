// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import '../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import '../lib/reactive-lib/src/abstract-base/AbstractCallback.sol';
import './AbstractDispenser.sol';
import './AbstractFeeCalculator.sol';
import './AbstractBridgehead.sol';
import './BridgeLib.sol';

/// @title Interface for extended ERC20 tokens used by the ERC20/REACT bridge.
interface IERC20ForciblyMintableBurnable is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/// @title Implements the ERC20/non-reactive part of the bridge using the abstract protocol defined in `AbstractBridgehead`.
/// @dev The transport to the other part of the bridge is implemented as log records intercepted by the Reactive Network and delivered to the reactive contract on the other side.
contract Bridge is AbstractCallback, AbstractDispenser, AbstractFeeCalculator, AbstractBridgehead {
    event InitialMessage(
        uint256 indexed tx,
        uint256 indexed index,
        uint256 indexed amount,
        address sender,
        address recipient
    );

    event Confirmation(
        uint256 indexed rq,
        uint256 indexed tx,
        uint256 indexed index,
        uint256 amount,
        address sender,
        address recipient
    );

    event Rejection(
        uint256 indexed rq,
        uint256 indexed tx,
        uint256 indexed index,
        uint256 amount,
        address sender,
        address recipient
    );

    event ConfirmationRequest(
        uint256 indexed rq,
        uint256 indexed tx,
        uint256 indexed index,
        uint256 amount,
        address sender,
        address recipient
    );

    event DeliveryConfirmation(
        uint256 indexed tx,
        uint256 indexed index,
        uint256 indexed amount,
        address sender,
        address recipient
    );

    event DeliveryRejection(
        uint256 indexed tx,
        uint256 indexed index,
        uint256 indexed amount,
        address sender,
        address recipient
    );

    /// @notice Address of the Wrapped REACT, or any other token to be bridged.
    IERC20ForciblyMintableBurnable wreact;

    /// @notice Indicated whether `wreact` can be minted. Will lock the incoming tokens otherwise.
    bool is_mintable;

    /// @notice Indicated whether token burning should be through `burn(uint256)` or `burn(address,uint256)` method.
    bool is_standard_burn;

    /// @notice The amount of extra gas the bridging party will pay for to account for confirmation callbacks.
    uint256 public gas_fee;

    constructor(
        address _callback_proxy,
        uint8 _confirmations,
        bool _allow_cancellations,
        uint256 _cancellation_threshold,
        IERC20ForciblyMintableBurnable _wreact,
        bool _is_mintable,
        bool _is_standard_burn,
        uint256 _fixed_fee,
        uint256 _perc_fee,
        uint256 _gas_fee
    ) AbstractCallback(
        _callback_proxy
    ) AbstractFeeCalculator(
        _fixed_fee,
        _perc_fee
    ) AbstractBridgehead(
        _confirmations,
        _allow_cancellations,
        _cancellation_threshold
    ) payable {
        wreact = _wreact;
        is_mintable = _is_mintable;
        is_standard_burn = _is_standard_burn;
        gas_fee = _gas_fee;
    }

    // Outbox methods

    /// @notice Initiate the bridging sequence from ERC20 to native REACT.
    /// @param uniqueish A reasonably unique-ish number identifying this transaction, provided by the client. Should be unique across messages with the same sender-recipient-amount combination.
    /// @param recipient Recipient's addres on the Reactive Network side.
    /// @param amount Amount of ERC20 to be bridged. 1-to-1 minus the bridging fee.
    function bridge(uint256 uniqueish, address recipient, uint256 amount) external payable onlyActive {
        uint256 extra_gas_price = tx.gasprice * gas_fee;
        require(msg.value >= extra_gas_price, 'Insufficient fee paid for bridging - pay at least tx.gas times gas_fee()');
        if (msg.value > extra_gas_price) {
            (bool success,) = payable(msg.sender).call{ value: msg.value - extra_gas_price }(new bytes(0));
            require(success, 'Unable to return the excess fee');
        }
        require(wreact.balanceOf(msg.sender) >= amount, 'Insufficient funds');
        require(wreact.allowance(msg.sender, address(this)) >= amount, 'Insufficient approved funds');
        require(_computeFee(amount) < amount, 'Not enough to cover the fee');
        wreact.transferFrom(msg.sender, address(this), amount);
        MessageId memory message = MessageId({
            tx: uniqueish,
            index: gasleft(),
            amount: amount,
            sender: msg.sender,
            recipient: recipient
        });
        _sendMessage(message);
    }

    /// @notice Cancels the previously sent briging request, if allowed and possible.
    /// @param uniqueish A reasonably unique-ish number identifying this transaction, provided by the client. Must be unique across messages with the same sender-recipient-amount combination.
    /// @param index `gasleft()` at the point where the original message ID has been computed.
    /// @param recipient Recipient's addres on the Reactive Network side.
    /// @param amount Amount of ERC20 to be bridged. 1-to-1 minus the bridging fee.
    function cancel(uint256 uniqueish, uint256 index, address recipient, uint256 amount) external {
        MessageId memory message = MessageId({
            tx: uniqueish,
            index: index,
            amount: amount,
            sender: msg.sender,
            recipient: recipient
        });
        _cancelMessage(message);
    }

    // Outbox callbacks

    /// @notice Entry point for the confirmation requests received as callback transactions from the reactive part of the bridge.
    /// @param rvm_id RVM ID (i.e., reactive contract's deployer address) injected by the reactive node.
    /// @param submsg_id ID of the confirmation request.
    /// @param txh Original unique-ish number identifying the message.
    /// @param index `gasleft()` at the moment the original message ID has been computed.
    /// @param amount Amount sent.
    /// @param sender Sender address.
    /// @param recipient Recipient address.
    function requestConfirmation(
        address rvm_id,
        uint256 submsg_id,
        uint256 txh,
        uint256 index,
        uint256 amount,
        address sender,
        address recipient
    ) external authorizedSenderOnly rvmIdOnly(rvm_id) {
        MessageId memory message = MessageId({
            tx: txh,
            index: index,
            amount: amount,
            sender: sender,
            recipient: recipient
        });
        _processConfirmationRequest(submsg_id, message);
    }

    /// @notice Entry point for the delivery confirmations received as callback transactions from the reactive part of the bridge.
    /// @param rvm_id RVM ID (i.e., reactive contract's deployer address) injected by the reactive node.
    /// @param txh Original unique-ish number identifying the message.
    /// @param index `gasleft()` at the moment the original message ID has been computed.
    /// @param amount Amount sent.
    /// @param sender Sender address.
    /// @param recipient Recipient address.
    function confirmDelivery(
        address rvm_id,
        uint256 txh,
        uint256 index,
        uint256 amount,
        address sender,
        address recipient
    ) external authorizedSenderOnly rvmIdOnly(rvm_id) {
        MessageId memory message = MessageId({
            tx: txh,
            index: index,
            amount: amount,
            sender: sender,
            recipient: recipient
        });
        _processDeliveryConfirmation(message);
    }

    /// @notice Entry point for the delivery rejections received as callback transactions from the reactive part of the bridge.
    /// @param rvm_id RVM ID (i.e., reactive contract's deployer address) injected by the reactive node.
    /// @param txh Original unique-ish number identifying the message.
    /// @param index `gasleft()` at the moment the original message ID has been computed.
    /// @param amount Amount sent.
    /// @param sender Sender address.
    /// @param recipient Recipient address.
    function rejectDelivery(
        address rvm_id,
        uint256 txh,
        uint256 index,
        uint256 amount,
        address sender,
        address recipient
    ) external authorizedSenderOnly rvmIdOnly(rvm_id) {
        MessageId memory message = MessageId({
            tx: txh,
            index: index,
            amount: amount,
            sender: sender,
            recipient: recipient
        });
        _processDeliveryRejection(message);
    }

    // Outbox transport

    /// @notice Initial message implemented as a log record intercepted by the Reactive Network.
    /// @inheritdoc AbstractBridgehead
    function _sendInitialMessage(MessageId memory id) override internal {
        emit InitialMessage(
            id.tx,
            id.index,
            id.amount,
            id.sender,
            id.recipient
        );
    }

    /// @notice Confirmation sending implemented as a log record intercepted by the Reactive Network.
    /// @inheritdoc AbstractBridgehead
    function _sendConfirmation(uint256 submsg_id, MessageId memory id) override internal {
        emit Confirmation(
            submsg_id,
            id.tx,
            id.index,
            id.amount,
            id.sender,
            id.recipient
        );
    }

    /// @notice Rejection sending implemented as a log record intercepted by the Reactive Network.
    /// @inheritdoc AbstractBridgehead
    function _sendRejection(uint256 submsg_id, MessageId memory id) override internal {
        emit Rejection(
            submsg_id,
            id.tx,
            id.index,
            id.amount,
            id.sender,
            id.recipient
        );
    }

    /// @notice Returning the message boils down to sending the locked tokens back to the sender.
    /// @inheritdoc AbstractBridgehead
    function _returnMessage(MessageId memory id) override internal {
        require(wreact.balanceOf(address(this)) >= id.amount, 'Insufficient funds');
        wreact.transfer(id.sender, id.amount);
    }

    /// @notice Finalizing the message is a no-op in token-locking mode. Burnable tokens are burned to finalize.
    /// @inheritdoc AbstractBridgehead
    function _finalizeMessage(MessageId memory id) override internal {
        require(wreact.balanceOf(address(this)) >= id.amount, 'Insufficient funds');
        if (is_mintable) {
            if (is_standard_burn) {
                wreact.burn(id.amount);
            } else {
                wreact.burn(address(this), id.amount);
            }
        }
    }

    // Inbox methods

    /// @notice Attempt to retry the delivery of a stuck message.
    /// @dev Must be attempted by the message recipient.
    /// @param uniqueish A reasonably unique-ish number identifying this transaction, provided by the client. Must be unique across messages with the same sender-recipient-amount combination.
    /// @param index `gasleft()` at the point where the original message ID has been computed.
    /// @param sender Sender's address on the Reactive Network side.
    /// @param recipient Recipient's address on the destination network side.
    /// @param amount Amount of ERC20 to be bridged. 1-to-1 minus the bridging fee.
    /// @param uniqueish_2 A reasonably unique-ish number to avoid confirmation request collision with the stuck one.
    function retry(uint256 uniqueish, uint256 index, address sender, address recipient, uint256 amount, uint256 uniqueish_2) external {
        MessageId memory message = MessageId({
            tx: uniqueish,
            index: index,
            amount: amount,
            sender: sender,
            recipient: recipient
        });
        _retry(_genId(uniqueish_2), message);
    }

    // Inbox callbacks

    /// @notice Entry point for initial messages received as callback transactions from the reactive part of the bridge.
    /// @param rvm_id RVM ID (i.e., reactive contract's deployer address) injected by the reactive node.
    /// @param txh Original unique-ish number identifying the message.
    /// @param index `gasleft()` at the moment the original message ID has been computed.
    /// @param amount Amount sent.
    /// @param sender Sender address.
    /// @param recipient Recipient address.
    function initialMessage(
        address rvm_id,
        uint256 txh,
        uint256 index,
        uint256 amount,
        address sender,
        address recipient
    ) external authorizedSenderOnly rvmIdOnly(rvm_id) {
        MessageId memory message = MessageId({
            tx: txh,
            index: index,
            amount: amount,
            sender: sender,
            recipient: recipient
        });
        _processInitialMessage(_genId(txh), message);
    }

    /// @notice Entry point for the message confirmations received as callback transactions from the reactive part of the bridge.
    /// @param rvm_id RVM ID (i.e., reactive contract's deployer address) injected by the reactive node.
    /// @param submsg_id ID of the confirmation request.
    /// @param txh Original unique-ish number identifying the message.
    /// @param index `gasleft()` at the moment the original message ID has been computed.
    /// @param amount Amount sent.
    /// @param sender Sender address.
    /// @param recipient Recipient address.
    function confirm(
        address rvm_id,
        uint256 submsg_id,
        uint256 txh,
        uint256 index,
        uint256 amount,
        address sender,
        address recipient
    ) external authorizedSenderOnly rvmIdOnly(rvm_id) {
        MessageId memory message = MessageId({
            tx: txh,
            index: index,
            amount: amount,
            sender: sender,
            recipient: recipient
        });
        _processConfirmation(submsg_id, _genId(submsg_id), message);
    }

    /// @notice Entry point for message rejections received as callback transactions from the reactive part of the bridge.
    /// @param rvm_id RVM ID (i.e., reactive contract's deployer address) injected by the reactive node.
    /// @param submsg_id ID of the confirmation request.
    /// @param txh Original unique-ish number identifying the message.
    /// @param index `gasleft()` at the moment the original message ID has been computed.
    /// @param amount Amount sent.
    /// @param sender Sender address.
    /// @param recipient Recipient address.
    function reject(
        address rvm_id,
        uint256 submsg_id,
        uint256 txh,
        uint256 index,
        uint256 amount,
        address sender,
        address recipient
    ) external authorizedSenderOnly rvmIdOnly(rvm_id) {
        MessageId memory message = MessageId({
            tx: txh,
            index: index,
            amount: amount,
            sender: sender,
            recipient: recipient
        });
        _processRejection(submsg_id, message);
    }

    // Inbox transport

    /// @notice Confirmation request sending implemented as a log record intercepted by the Reactive Network.
    /// @inheritdoc AbstractBridgehead
    function _sendConfirmationRequest(uint256 submsg_id, MessageId memory id) override internal {
        emit ConfirmationRequest(
            submsg_id,
            id.tx,
            id.index,
            id.amount,
            id.sender,
            id.recipient
        );
    }

    /// @notice Delivery is from token reserves if not mintable. New tokens are minted for delivery otherwise.
    /// @inheritdoc AbstractBridgehead
    function _deliver(MessageId memory id) override internal {
        if (is_mintable) {
            try wreact.mint(id.recipient, id.amount - _computeFee(id.amount)) {
                _confirmDelivery(id);
            } catch {
                _rejectDelivery(id);
            }
        } else {
            try wreact.transfer(id.recipient, id.amount - _computeFee(id.amount)) {
                _confirmDelivery(id);
            } catch {
                _rejectDelivery(id);
            }
        }
    }

    /// @notice Delivery confirmation sending implemented as a log record intercepted by the Reactive Network.
    /// @inheritdoc AbstractBridgehead
    function _sendDeliveryConfirmation(MessageId memory id) override internal {
        emit DeliveryConfirmation(
            id.tx,
            id.index,
            id.amount,
            id.sender,
            id.recipient
        );
    }

    /// @notice Delivery rejection sending implemented as a log record intercepted by the Reactive Network.
    /// @inheritdoc AbstractBridgehead
    function _sendDeliveryRejection(MessageId memory id) override internal {
        emit DeliveryRejection(
            id.tx,
            id.index,
            id.amount,
            id.sender,
            id.recipient
        );
    }
}