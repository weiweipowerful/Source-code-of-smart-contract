// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IMessagingChannel } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessagingChannel.sol";

import { OApp, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";

import { OFTLimit, OFTReceipt, OFTFeeDetail } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

import { IUsdtOFT, IOFT, SendParam, MessagingReceipt, MessagingFee } from "./IUsdtOFT.sol";

contract UsdtOFT is IUsdtOFT, OApp, OAppOptionsType3 {
    using SafeERC20 for IERC20;

    // MsgTypes
    uint16 public constant WITHDRAW_REMOTE = 1;
    uint16 public constant SEND_OFT = 2;
    uint16 public constant SEND_CREDITS = 3;

    // Endpoint IDs
    uint32 public immutable ARBITRUM_EID; // 30110
    uint32 public immutable CELO_EID; // 30125
    uint32 public immutable ETH_EID; // 30101
    uint32 public immutable TON_EID; // 30152
    uint32 public immutable TRON_EID; // 30420
    uint32 public immutable LOCAL_EID;

    // Credit balances
    mapping(uint32 eid => uint256 credits) public credits;

    IERC20 internal immutable innerToken;

    // Management addresses
    address public lpAdmin;
    address public planner;

    // Fees
    uint256 public feeBalance = 0;
    uint16 public feeBps = 0;
    uint16 public constant BPS_DENOMINATOR = 10000;

    constructor(
        uint32 _arbitrumEid,
        uint32 _celoEid,
        uint32 _ethEid,
        uint32 _tonEid,
        uint32 _tronEid,
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OApp(_lzEndpoint, _delegate) Ownable(_delegate) {
        // @dev Endpoint details
        ARBITRUM_EID = _arbitrumEid;
        CELO_EID = _celoEid;
        ETH_EID = _ethEid;
        TON_EID = _tonEid;
        TRON_EID = _tronEid;
        LOCAL_EID = IMessagingChannel(_lzEndpoint).eid();

        // @dev Only allow the contract to be deployed with the correct endpoint IDs
        if (LOCAL_EID != ARBITRUM_EID && LOCAL_EID != CELO_EID && LOCAL_EID != ETH_EID && LOCAL_EID != TRON_EID) {
            revert InvalidEid();
        }

        // @dev Token details
        if (IERC20Metadata(_token).decimals() != sharedDecimals()) revert InvalidLocalDecimals();
        innerToken = IERC20(_token);

        // @dev Defaults to the lpAdmin AND planner being the delegate
        lpAdmin = _delegate;
        planner = _delegate;
    }

    modifier onlyLpAdminOrOwner() {
        if (msg.sender != lpAdmin && msg.sender != owner()) revert OnlyLpAdminOrOwner();
        _;
    }

    modifier onlyPlanner() {
        if (msg.sender != planner) revert OnlyPlanner();
        _;
    }

    /// ========================== INTERFACE FUNCTIONS =====================================
    function token() public view returns (address) {
        return address(innerToken);
    }

    function approvalRequired() external pure returns (bool) {
        return true;
    }

    function oftVersion() external pure returns (bytes4 interfaceId, uint64 version) {
        // @dev We are using version '0' to indicate that this is a custom oft implementation
        return (type(IOFT).interfaceId, 0);
    }

    function sharedDecimals() public pure returns (uint8) {
        return 6;
    }

    function tvl() external view returns (uint256) {
        // @dev This will also account for tokens accidentally sent directly to this contract, but not accounted for.
        return innerToken.balanceOf(address(this)) - feeBalance;
    }

    /// ========================== OWNER FUNCTIONS =====================================
    function setLpAdmin(address _lpAdmin) external onlyOwner {
        lpAdmin = _lpAdmin;
        emit LpAdminSet(_lpAdmin);
    }

    function setPlanner(address _planner) external onlyOwner {
        planner = _planner;
        emit PlannerSet(_planner);
    }

    function setFeeBps(uint16 _feeBps) external onlyOwner {
        // @dev Fees must be less than 100%
        if (_feeBps >= BPS_DENOMINATOR) revert InvalidFeeBps(_feeBps);
        feeBps = _feeBps;
        emit FeeBpsSet(_feeBps);
    }

    function withdrawFees(address _to, uint256 _amount) external onlyOwner {
        if (_amount > feeBalance) revert InsufficientFeeBalance();
        feeBalance -= _amount;

        if (LOCAL_EID == TRON_EID) {
            // tron USDT does not support safeTransfer
            innerToken.transfer(_to, _amount);
        } else {
            innerToken.safeTransfer(_to, _amount);
        }

        emit FeesWithdrawn(_to, _amount);
    }

    /// ========================== INTERNAL HELPER FUNCTIONS =====================================
    function _assertCredits(uint32 _eid, uint256 _amount) internal view {
        uint256 currentCredits = credits[_eid];
        if (currentCredits < _amount) revert InsufficientCredits(_eid, currentCredits, _amount);
    }

    function _decreaseCredits(uint32 _eid, uint256 _amount) internal {
        // @dev Only do the operation if its greater than 0;
        if (_amount > 0) {
            uint256 currentCredits = credits[_eid];
            if (currentCredits < _amount) revert InsufficientCredits(_eid, currentCredits, _amount);
            credits[_eid] = currentCredits - _amount;
        }
    }

    function _increaseCredits(uint32 _eid, uint256 _amount) internal {
        // @dev Only do the operation if its greater than 0;
        if (_amount > 0) credits[_eid] += _amount;
    }

    function _buildMsgAndOptions(
        uint16 _msgType,
        SendParam calldata _sendParam,
        uint256 _amount
    ) internal view returns (bytes memory message, bytes memory options) {
        // @dev Can't move 0 tokens
        if (_amount == 0) revert InvalidAmount();

        // @dev this OFT does NOT support composing
        if (_sendParam.composeMsg.length > 0) revert ComposeNotSupported();

        // @dev Can safely cast this as uint64,
        // because this is strictly used for USDT implementation where 6 decimals is used.
        // Unless over 18 trillion usdt is minted, this wont be a problem.
        message = abi.encodePacked(_msgType, _sendParam.to, uint64(_amount));
        options = combineOptions(_sendParam.dstEid, _msgType, _sendParam.extraOptions);
    }

    /// ========================== LIQUIDITY FUNCTIONS =====================================
    function depositLocal(uint256 _amount) external {
        innerToken.safeTransferFrom(msg.sender, address(this), _amount);
        _increaseCredits(LOCAL_EID, _amount);
        emit LocalDeposit(_amount);
    }

    function withdrawLocal(address _to, uint256 _amount) external onlyLpAdminOrOwner {
        _decreaseCredits(LOCAL_EID, _amount);

        if (LOCAL_EID == TRON_EID) {
            // tron USDT does not support safeTransfer
            innerToken.transfer(_to, _amount);
        } else {
            innerToken.safeTransfer(_to, _amount);
        }

        emit LocalWithdrawn(_to, _amount);
    }

    function quoteWithdrawRemote(
        SendParam calldata _sendParam,
        bool _payInLzToken
    ) external view returns (MessagingFee memory msgFee) {
        // @dev We use minAmountLd to follow same pattern as the TON implementation
        _assertCredits(_sendParam.dstEid, _sendParam.minAmountLD);

        (bytes memory message, bytes memory options) = _buildMsgAndOptions(
            WITHDRAW_REMOTE,
            _sendParam,
            _sendParam.minAmountLD
        );

        // @dev Calculates the LayerZero fee for the withdrawRemote() operation.
        return _quote(_sendParam.dstEid, message, options, _payInLzToken);
    }

    function withdrawRemote(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable onlyLpAdminOrOwner returns (MessagingReceipt memory msgReceipt) {
        // @dev We use minAmountLd to follow same pattern as the TON implementation
        _decreaseCredits(_sendParam.dstEid, _sendParam.minAmountLD);

        // @dev Generate the message and options
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(
            WITHDRAW_REMOTE,
            _sendParam,
            _sendParam.minAmountLD
        );

        emit RemoteWithdrawn(_sendParam.dstEid, _sendParam.minAmountLD);

        // @dev This is simply a send msg call, WITHOUT the debit logic being applied
        return _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
    }

    /// ========================== CREDIT FUNCTIONS =====================================
    function quoteSendCredits(
        uint32 _dstEid,
        uint64 _creditsArbitrum,
        uint64 _creditsCelo,
        uint64 _creditsEth,
        uint64 _creditsTon,
        uint64 _creditsTron,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) external view returns (MessagingFee memory msgFee) {
        // @dev It's possible for the planner to send 0 totalCredits
        _assertCredits(ARBITRUM_EID, _creditsArbitrum);
        _assertCredits(CELO_EID, _creditsCelo);
        _assertCredits(ETH_EID, _creditsEth);
        _assertCredits(TON_EID, _creditsTon);
        _assertCredits(TRON_EID, _creditsTron);

        bytes memory message = abi.encodePacked(
            SEND_CREDITS,
            _creditsArbitrum,
            _creditsCelo,
            _creditsEth,
            _creditsTon,
            _creditsTron
        );
        bytes memory options = combineOptions(_dstEid, SEND_CREDITS, _extraOptions);

        // @dev Calculates the LayerZero fee for the sendCredits() operation.
        return _quote(_dstEid, message, options, _payInLzToken);
    }

    function sendCredits(
        uint32 _dstEid,
        uint64 _creditsArbitrum,
        uint64 _creditsCelo,
        uint64 _creditsEth,
        uint64 _creditsTon,
        uint64 _creditsTron,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee
    ) external payable onlyPlanner returns (MessagingReceipt memory msgReceipt) {
        // @dev It's possible for the planner to send 0 totalCredits
        _decreaseCredits(ARBITRUM_EID, _creditsArbitrum);
        _decreaseCredits(CELO_EID, _creditsCelo);
        _decreaseCredits(ETH_EID, _creditsEth);
        _decreaseCredits(TON_EID, _creditsTon);
        _decreaseCredits(TRON_EID, _creditsTron);

        bytes memory message = abi.encodePacked(
            SEND_CREDITS,
            _creditsArbitrum,
            _creditsCelo,
            _creditsEth,
            _creditsTon,
            _creditsTron
        );
        bytes memory options = combineOptions(_dstEid, SEND_CREDITS, _extraOptions);

        emit CreditsSent(_dstEid, _creditsArbitrum, _creditsCelo, _creditsEth, _creditsTon, _creditsTron);

        return _lzSend(_dstEid, message, options, _fee, msg.sender);
    }

    function _receiveCredits(bytes calldata _message) internal {
        // @dev It's possible to receive 0 totalCredits
        // @dev MsgType is ignored
        uint64 _creditsArbitrum = uint64(bytes8(_message[2:10]));
        uint64 _creditsCelo = uint64(bytes8(_message[10:18]));
        uint64 _creditsEth = uint64(bytes8(_message[18:26]));
        uint64 _creditsTon = uint64(bytes8(_message[26:34]));
        uint64 _creditsTron = uint64(bytes8(_message[34:42]));

        _increaseCredits(ARBITRUM_EID, _creditsArbitrum);
        _increaseCredits(CELO_EID, _creditsCelo);
        _increaseCredits(ETH_EID, _creditsEth);
        _increaseCredits(TON_EID, _creditsTon);
        _increaseCredits(TRON_EID, _creditsTron);
    }

    /// ========================== OFT FUNCTIONS =====================================
    function _debitView(
        uint256 _amount,
        uint256 _minAmount
    ) internal view returns (uint256 amountSent, uint256 amountReceived) {
        amountSent = _amount;

        // @dev Apply the fee
        uint256 feeAmount = (amountSent * feeBps) / BPS_DENOMINATOR;
        amountReceived = amountSent - feeAmount;

        // @dev Check for slippage.
        if (amountReceived < _minAmount) revert SlippageExceeded(amountReceived, _minAmount);
    }

    function quoteOFT(
        SendParam calldata _sendParam
    )
        external
        view
        virtual
        returns (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt)
    {
        uint256 minAmount = 0;
        uint256 maxAmount = type(uint64).max;
        oftLimit = OFTLimit(minAmount, maxAmount);

        // @dev Unused in this implementation
        oftFeeDetails = new OFTFeeDetail[](0);

        // @dev This is the same as the send() operation, but without the actual send.
        // - amountSent is the amount that would be debited from the sender.
        // - amountReceived is the amount that will be credited to the recipient.
        // The diff is the fee amount to be applied
        (uint256 amountSent, uint256 amountReceived) = _debitView(_sendParam.amountLD, _sendParam.minAmountLD);
        oftReceipt = OFTReceipt(amountSent, amountReceived);
    }

    // @dev The quote is as similar as possible to the actual send() operation.
    function quoteSend(
        SendParam calldata _sendParam,
        bool _payInLzToken
    ) external view returns (MessagingFee memory msgFee) {
        // @dev Mock the amount to receive, this is the same operation used in the send().
        (, uint256 amountReceived) = _debitView(_sendParam.amountLD, _sendParam.minAmountLD);

        // @dev Handle the credits
        _assertCredits(_sendParam.dstEid, amountReceived);

        // @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(SEND_OFT, _sendParam, amountReceived);

        // @dev Calculates the LayerZero fee for the send() operation.
        return _quote(_sendParam.dstEid, message, options, _payInLzToken);
    }

    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        // @dev Applies fees and determines the total amount to deduct from the sender, and the amount received
        (uint256 amountSent, uint256 amountReceived) = _debitView(_sendParam.amountLD, _sendParam.minAmountLD);

        // @dev Lock tokens by moving them into this contract from the caller.
        innerToken.safeTransferFrom(msg.sender, address(this), amountSent);

        // @dev Handle the credits
        _decreaseCredits(_sendParam.dstEid, amountReceived);
        _increaseCredits(LOCAL_EID, amountReceived);

        // @dev Increment the fee balance so we can account for fee withdrawals
        feeBalance += amountSent - amountReceived;

        // @dev Generate the message and options
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(SEND_OFT, _sendParam, amountReceived);

        // @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
        // @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(amountSent, amountReceived);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSent, amountReceived);
    }

    // Used for both OFT receive and withdrawRemote receive
    function _receiveOFT(bytes calldata _message) internal returns (address to, uint256 amountReceived) {
        // @dev Convert bytes 32 to an address
        to = address(uint160(uint256(bytes32(_message[2:34]))));
        amountReceived = uint64(bytes8(_message[34:42]));

        // @dev Unlock the tokens and transfer to the recipient.
        if (LOCAL_EID == TRON_EID) {
            // tron USDT does not support safeTransfer
            innerToken.transfer(to, amountReceived);
        } else {
            innerToken.safeTransfer(to, amountReceived);
        }
    }

    /// ========================== LZ FUNCTIONS =====================================

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal virtual override {
        // @dev Extract the msgType
        uint16 msgType = uint16(bytes2(_message[0:2]));

        if (msgType == SEND_CREDITS) {
            _receiveCredits(_message);
            emit CreditsReceived(_guid, _origin.srcEid, _message);
        } else if (msgType == SEND_OFT) {
            (address to, uint256 amountReceived) = _receiveOFT(_message);
            emit OFTReceived(_guid, _origin.srcEid, to, amountReceived);
        } else if (msgType == WITHDRAW_REMOTE) {
            (address to, uint256 amountReceived) = _receiveOFT(_message);
            emit RemoteWithdrawReceived(_guid, _origin.srcEid, to, amountReceived);
        } else {
            revert InvalidMsgType(msgType);
        }
    }
}