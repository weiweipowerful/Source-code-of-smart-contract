// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";

import { IApeCoinStaking } from "./lib/IApeCoinStaking.sol";

/**
 * @title ApeOFTAdapter
 * @notice This contract enables the bridging of ApeCoin using LayerZero's Omnichain Fungible Token (OFT) protocol, with
 *         ApeCoinStaking serving as the lockbox.
 */
contract ApeOFTAdapter is OFTAdapter {
    using SafeERC20 for IERC20;

    IApeCoinStaking public immutable apeCoinStaking;

    /// @dev Minimum amount required for staking deposits.
    uint256 private constant MIN_DEPOSIT = 1e18;

    /**
     * @notice Constructor for ApeOFTAdapter.
     * @param _token The address of the token being adapted (ApeCoin).
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _delegate The LayerZero delegate address, also set as the contract owner.
     * @param _apeCoinStaking The address of the ApeCoinStaking contract.
     */
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate,
        IApeCoinStaking _apeCoinStaking
    ) OFTAdapter(_token, _lzEndpoint, _delegate) Ownable(_delegate) {
        apeCoinStaking = _apeCoinStaking;
        innerToken.approve(address(apeCoinStaking), type(uint256).max);
    }

    /**
     * @dev Transfers tokens from the sender to the contract, claims any earned ApeCoin rewards,
     *      and stakes them if the balance exceeds the minimum deposit amount.
     * @param _from The address to debit from.
     * @param _amountLD The amount of tokens to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     *
     * @dev msg.sender will need to approve this _amountLD of tokens to be locked inside of the contract.
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        innerToken.safeTransferFrom(_from, address(this), amountSentLD);
        apeCoinStaking.claimSelfApeCoin();

        uint256 totalDeposit = innerToken.balanceOf(address(this));
        if (totalDeposit >= MIN_DEPOSIT) {
            apeCoinStaking.depositSelfApeCoin(totalDeposit);
        }
    }

    /**
     * @dev Internal function to handle token crediting and ApeCoinStaking withdrawal if necessary.
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     * @dev _srcEid The source chain ID.
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal virtual override returns (uint256 amountReceivedLD) {
        apeCoinStaking.claimSelfApeCoin();
        uint256 balance = innerToken.balanceOf(address(this));
        if (balance < _amountLD) {
            apeCoinStaking.withdrawSelfApeCoin(_amountLD - balance);
        }

        innerToken.safeTransfer(_to, _amountLD);
        return _amountLD;
    }
}