// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintableToken} from "./interfaces/IMintableToken.sol";

import {OFTAdapter} from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import {
    MessagingFee, MessagingReceipt, OFTReceipt, SendParam
} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CortexAdapter
/// @notice CortexAdapter is a contract that adapts the Cortex-like ERC-20 token to the OFT functionality.
/// This enables cross-chain transfers of the underlying ERC-20 token, requiring it to follow the
/// IMintableToken interface: mint(address to, uint256 amount) and burnFrom(address from, uint256 amount).
/// @dev WARNING: The CortexAdapter implementation does not support fees on burning and minting tokens,
/// which is a very rare use case anyway.
contract CortexAdapter is OFTAdapter {
    /// @dev Error thrown when the receiver address is zero. Follows EIP-6093 signature.
    error ERC20InvalidReceiver(address receiver);

    constructor(
        address _token,
        address _endpoint,
        address _owner
    )
        OFTAdapter(_token, _endpoint, _owner)
        Ownable(_owner)
    {}

    /// @notice Returns the shared decimals of the underlying token for all chains.
    /// @dev This is sufficient for tokens with a total supply lower than 18,446,744,073.709551615 units.
    function sharedDecimals() public view virtual override returns (uint8) {
        return 9;
    }

    /// @notice Internal function to execute the send operation.
    /// @dev We override this function to ensure that the receiver address is not zero.
    /// Rest of the logic remains the same.
    function _send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    )
        internal
        virtual
        override
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        if (_sendParam.to == 0) {
            revert ERC20InvalidReceiver(address(0));
        }
        return super._send(_sendParam, _fee, _refundAddress);
    }

    /// @notice Burns tokens from the sender's balance to prepare for sending.
    /// @dev The sender must approve this contract to burn the specified amount of tokens.
    /// @dev WARNING: The CortexAdapter implementation does not support fees on burning and minting tokens,
    /// which is a very rare use case anyway.
    /// @param _from                The address to debit from.
    /// @param _amountLD            The amount of tokens to send in local decimals.
    /// @param _minAmountLD         The minimum amount to send in local decimals.
    /// @param _dstEid              The destination endpoint ID.
    ///
    /// @return amountSentLD        The amount sent in local decimals.
    /// @return amountReceivedLD    The amount received in local decimals on the remote.
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    )
        internal
        virtual
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        // Burn the tokens from the sender's balance.
        IMintableToken(address(innerToken)).burnFrom(_from, amountSentLD);
    }

    /// @notice Mints tokens to the specified address upon receiving them.
    /// @dev WARNING: The CortexAdapter implementation does not support fees on burning and minting tokens,
    /// which is a very rare use case anyway.
    /// @param _to                  The address to credit to.
    /// @param _amountLD            The amount to credit in local decimals.
    ///
    /// @return amountReceivedLD    The amount of tokens actually received in local decimals.
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    )
        internal
        virtual
        override
        returns (uint256 amountReceivedLD)
    {
        // Mints the tokens and transfers to the recipient.
        IMintableToken(address(innerToken)).mint(_to, _amountLD);
        return _amountLD;
    }
}