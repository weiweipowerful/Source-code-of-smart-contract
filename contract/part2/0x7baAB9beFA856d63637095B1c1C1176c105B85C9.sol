// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ONFT721Adapter, ONFT721Core} from "@layerzerolabs/onft-evm/contracts/onft721/ONFT721Adapter.sol";
import {ONFT721MsgCodec} from "@layerzerolabs/onft-evm/contracts/onft721/libs/ONFT721MsgCodec.sol";
import {IOAppMsgInspector} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppMsgInspector.sol";
import {
    SendParam,
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/onft-evm/contracts/onft721/interfaces/IONFT721.sol";

contract GatorBridgeETH is ONFT721Adapter {
    address immutable SWAMP;
    uint256 immutable DST_EID;

    constructor(address token_, address swamp_, uint256 dstEid_, address lzEndpoint_)
        ONFT721Adapter(token_, lzEndpoint_, msg.sender)
    {
        SWAMP = swamp_;
        DST_EID = dstEid_;
    }

    struct SendParamWithoutExtraOptions {
        uint32 dstEid; // Destination LayerZero EndpointV2 ID.
        bytes32 to; // Recipient address.
        uint256 tokenId;
        bytes composeMsg; // The composed message for the send() operation.
        bytes onftCmd; // The ONFT command to be executed, unused in default ONFT implementations.
    }

    function bridge(
        uint256[] memory tokenids,
        MessagingFee calldata fee_,
        bytes calldata extraOptions_,
        address refundAddress_
    ) external payable returns (MessagingReceipt memory msgReceipt) {
        uint32 __dstEid = uint32(DST_EID);
        for (uint256 i; i < tokenids.length; i++) {
            SendParamWithoutExtraOptions memory sp = SendParamWithoutExtraOptions({
                dstEid: __dstEid,
                to: _padAddressTo32Bytes(msg.sender),
                tokenId: tokenids[i],
                composeMsg: "",
                onftCmd: ""
            });
            send(sp, extraOptions_, fee_, refundAddress_);
        }
    }

    /* -«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-« */
    /*                                  overrides                                 */
    /* »-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»- */
    // "overrides" to replace `SendParam` with `SendParamWithoutExtraOptions`
    // - needed because `extraOptions` needs to be calldata, and can't be memory (required by `combineOptions`)
    function send(
        SendParamWithoutExtraOptions memory _sendParam,
        bytes calldata extraOptions_,
        MessagingFee calldata _fee,
        address _refundAddress
    ) public payable returns (MessagingReceipt memory msgReceipt) {
        _debit(msg.sender, _sendParam.tokenId, _sendParam.dstEid);

        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, extraOptions_);

        // @dev Sends the message to the LayerZero Endpoint, returning the MessagingReceipt.
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
        emit ONFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, _sendParam.tokenId);
    }

    function _buildMsgAndOptions(SendParamWithoutExtraOptions memory sendParam_, bytes calldata extraOptions_)
        internal
        view
        returns (bytes memory message, bytes memory options)
    {
        if (sendParam_.to == bytes32(0)) revert InvalidReceiver();
        bool hasCompose;
        (message, hasCompose) = ONFT721MsgCodec.encode(sendParam_.to, sendParam_.tokenId, sendParam_.composeMsg);
        uint16 msgType = hasCompose ? SEND_AND_COMPOSE : SEND;

        options = combineOptions(sendParam_.dstEid, msgType, extraOptions_);

        // @dev Optionally inspect the message and options depending if the OApp owner has set a msg inspector.
        // @dev If it fails inspection, needs to revert in the implementation. ie. does not rely on return boolean
        address inspector = msgInspector; // caches the msgInspector to avoid potential double storage read
        if (inspector != address(0)) IOAppMsgInspector(inspector).inspect(message, options);
    }

    function _padAddressTo32Bytes(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    // override to send multiple layerzero messages in a single transaction
    function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
        // if (msg.value != _nativeFee) revert NotEnoughNative(msg.value); <- update
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    // override to send to & receive from swamp
    function _debit(address _from, uint256 _tokenId, uint32 /*_dstEid*/ ) internal virtual override {
        // @dev Dont need to check onERC721Received() when moving into this contract, ie. no 'safeTransferFrom' required
        innerToken.transferFrom(_from, SWAMP, _tokenId);
    }

    function _credit(address _toAddress, uint256 _tokenId, uint32 /*_srcEid*/ ) internal virtual override {
        // @dev Do not need to check onERC721Received() when moving out of this contract, ie. no 'safeTransferFrom'
        // required
        // @dev The default implementation does not implement IERC721Receiver as 'safeTransferFrom' is not used.
        // @dev If IERC721Receiver is required, ensure proper re-entrancy protection is implemented.
        innerToken.transferFrom(SWAMP, _toAddress, _tokenId);
    }
}