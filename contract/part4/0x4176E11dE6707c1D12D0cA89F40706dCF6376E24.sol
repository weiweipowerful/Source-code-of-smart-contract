// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import {OFTAdapter} from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {MessagingReceipt, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {EigenpieConfigRoleChecker} from "../utils/EigenpieConfigRoleChecker.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEigenpieConfig} from "../utils/EigenpieConfigRoleChecker.sol";
import {UtilLib} from "../utils/UtilLib.sol";

/// @dev Contract used for Origin chain where the token is already deployed
contract MLRTOFTAdapter is OFTAdapter, EigenpieConfigRoleChecker, ReentrancyGuard, Pausable {
    uint128 public gasForDestinationLzReceive = 850000;

    event BridgeMLRT(
        address indexed from,
        uint32 indexed dstEid,
        uint256 amountSent,
        uint256 amountReceived,
        bytes32 indexed guid,
        address refundAddress
    );
    event MlrtReceived(
        uint32 indexed srcEid,
        address indexed to,
        uint256 amount
    );
    event GasForDestinationLzReceiveUpdated(uint128 gas);

    error InvalidGasForDestinationValue();

    /// @notice Initializes the contract
    /// @param _token Token address
    /// @param _lzEndpoint LayerZero endpoint address
    /// @param _delegate Delegate address
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate,
        address _eigenpieConfigAddr
    ) OFTAdapter(_token, _lzEndpoint, _delegate) {
        gasForDestinationLzReceive = 850000;
        eigenpieConfig = IEigenpieConfig(_eigenpieConfigAddr);
    }

    /// @notice Bridges tokens to another chain
    /// @param _dstEid Destination chain ID
    /// @param _dstGasCost Gas cost for the destination chain
    /// @param _amountLD Amount of tokens to send in Local Decimals
    /// @param _minAmountLD Minimum amount to receive after bridging in local Decimals
    function bridgeMLRT(
        uint32 _dstEid,
        uint128 _dstGasCost,
        uint256 _amountLD,
        uint256 _minAmountLD,
        address _receiver,
        address _refundAddress
    ) external payable nonReentrant{
        UtilLib.checkNonZeroAddress(_receiver);
        (uint256 amountSentLD, uint256 amountReceivedLD) = _debit(
            msg.sender,
            _amountLD,
            _minAmountLD,
            _dstEid
        );

        (
            bytes memory message,
            bytes memory options
        ) = _buildCustomMsgAndOptions(
                _dstEid,
                amountReceivedLD,
                _getDestinationGasCost(_dstGasCost),
                _receiver
            );

        MessagingReceipt memory msgReceipt = _lzSend(
            _dstEid,
            message,
            options,
            MessagingFee(msg.value, 0),
            payable(_refundAddress)
        );

        emit BridgeMLRT(
            msg.sender,
            _dstEid,
            amountSentLD,
            amountReceivedLD,
            msgReceipt.guid,
            _refundAddress
        );
    }

    /// @notice Estimates gas fees for bridging
    /// @param _dstEid Destination chain ID
    /// @param _dstGasCost Gas cost for the destination chain
    /// @param _amount Amount of tokens to send
    /// @param _minAmount Minimum amount to receive after bridging
    /// @return fee Estimated messaging fee
    function getEstimateGasFees(
        uint32 _dstEid,
        uint128 _dstGasCost,
        uint256 _amount,
        uint256 _minAmount,
        address _receiver
    ) public view returns (MessagingFee memory fee) {
        (, uint256 amountReceived) = _debitView(_amount, _minAmount, _dstEid);

        (
            bytes memory message,
            bytes memory options
        ) = _buildCustomMsgAndOptions(
                _dstEid,
                amountReceived,
                _getDestinationGasCost(_dstGasCost),
                _receiver
            );

        return _quote(_dstEid, message, options, false);
    }

    /* ============ Internal Functions ============ */

    /// @dev Adjusts the gas cost based on the destination chain
    function _getDestinationGasCost(
        uint128 _dstGasCost
    ) internal view returns (uint128) {
        return
            _dstGasCost <= gasForDestinationLzReceive
                ? gasForDestinationLzReceive
                : _dstGasCost;
    }

    /// @dev Builds the options for LayerZero messaging
    function _buildCustomMsgAndOptions(
        uint32 _dstEid,
        uint256 amountReceived,
        uint128 _gas,
        address _receiver
    ) internal view returns (bytes memory message, bytes memory options) {
        (message, ) = OFTMsgCodec.encode(
            bytes32(uint256(uint160(_receiver))),
            _toSD(amountReceived),
            new bytes(0)
        );

        options = this.combineOptions(
            _dstEid,
            SEND,
            OptionsBuilder.addExecutorLzReceiveOption(
                OptionsBuilder.newOptions(),
                _gas,
                0
            )
        );
    }

    /// @dev Handles debiting tokens from sender
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override whenNotPaused returns (uint, uint) {
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    /// @dev Handles crediting tokens to the receiver
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal override whenNotPaused returns (uint) {
        return super._credit(_to, _amountLD, _srcEid);
    }

    /* ============ Admin Functions ============ */

    /// @notice Pauses the contract
    function pause() external onlyPauser {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyDefaultAdmin {
        _unpause();
    }

    /// @dev Update gas for dest lz receive
    function updateGasForDestinationLzReceive(
        uint128 _gasForDestinationLzReceive
    ) external onlyDefaultAdmin {
        if(_gasForDestinationLzReceive == 0) {
            revert InvalidGasForDestinationValue();
        }
        gasForDestinationLzReceive = _gasForDestinationLzReceive;

        emit GasForDestinationLzReceiveUpdated(_gasForDestinationLzReceive);
    }

    /// @notice Allows the admin to transfer locked assets to a specified address
    /// @param _to The recipient address to which the locked assets will be transferred
    /// @param _amount The amount of assets to transfer
    function transferLockedAsset(
        address _to,
        uint256 _amount
    ) external onlyDefaultAdmin {
        UtilLib.checkNonZeroAddress(_to);
        IERC20(token()).transfer(_to, _amount);
    }
}