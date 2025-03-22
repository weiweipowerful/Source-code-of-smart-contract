// SPDX-License-Identifier: GPL-3.0-or-later
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./utils/TokenSalePurchase.sol";
import "./utils/RecoverableFunds.sol";

/**
 * @title TokenSale
 * @dev Main contract for managing token sales, including deposit, payment, withdraw, vesting, and fund recovery.
 * Inherits from Ownable2Step, RecoverableFunds and TokenSalePurchase.
 */
contract TokenSale is Ownable2Step, RecoverableFunds, TokenSalePurchase {
    /**
     * @dev Constructor to initialize the TokenSale contract with initial configurations.
     * @param sellableToken The address of the token that will be sold.
     * @param sellableTokenDecimals The number of decimals of the sellable token.
     *
     * Ownable(address initialOwner)
     * TeamWallet(address teamWallet)
     * RaisedFunds(bool autoWithdrawnRaisedFunds)
     * SellableToken(address sellableToken, uint8 sellableTokenDecimals)
     * PaymentToken(address[] memory tokens)
     * PaymentTokenDeposit(bool depositsEnabled)
     * Whitelist(bool whitelistingByDeposit, bytes32 merkleRoot)
     * Signature(address signer)
     * TokenSaleVesting(tokenVesting)
     * TokenSalePurchase(isReleaseAllowed, isBuyAllowed, isBuyWithProofAllowed, isBuyWithPriceAllowed)
     */
    constructor(
        address sellableToken,
        uint8 sellableTokenDecimals
    )
        Ownable(_msgSender())
        TeamWallet(address(0))
        RaisedFunds(false)
        SellableToken(sellableToken, sellableTokenDecimals)
        PaymentToken(new address[](0))
        PaymentTokenDeposit(false)
        Whitelist(false, bytes32(0))
        Signature(address(0))
        TokenSaleVesting(address(0))
        TokenSalePurchase(false, false, false, false)
    {}

    /**
     * @notice Returns the type of the token sale.
     * @return A string representing the type of the token sale.
     */
    function tokenSaleType() external pure returns (string memory) {
        return "full";
    }

    /**
     * @notice Returns the version of the token sale contract.
     * @return A string representing the version of the token sale contract.
     */
    function tokenSaleVersion() external pure returns (string memory) {
        return "1";
    }

    /**
     * @notice Pauses or unpauses the contract.
     * @dev Can only be called by the contract owner.
     * @param status A boolean indicating whether to pause (true) or unpause (false) the contract.
     */
    function setPause(bool status) external onlyOwner {
        if (status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @notice Returns the recoverable funds for a specific token.
     * @dev Overrides the getRecoverableFunds function from the RecoverableFunds contract.
     * Calculates the recoverable balance by excluding deposits and unclaimed raised funds for payment tokens.
     * @param token The address of the token.
     * @return The amount of recoverable funds.
     */
    function getRecoverableFunds(
        address token
    ) public view override returns (uint256) {
        uint256 accountedFunds = _getTotalTokenDeposit(token) +
            _getRaisedUnclaimed(token);
        if (accountedFunds > 0) {
            if (token == address(0)) {
                return address(this).balance - accountedFunds;
            } else {
                return IERC20(token).balanceOf(address(this)) - accountedFunds;
            }
        } else {
            return super.getRecoverableFunds(token);
        }
    }
}