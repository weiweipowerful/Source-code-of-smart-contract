// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AuthNoOwner, Authority} from "../governance/AuthNoOwner.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapFacility} from "../interfaces/ISwapFacility.sol";

import {
    IOFT,
    SendParam,
    OFTLimit,
    OFTReceipt,
    OFTFeeDetail,
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/// @title Swap Facility
/// @notice dss-lite-psm inspired swap facility for efficient 1:1 swaps between a collateral token and an OFT compatible, mintable debt token.
/// @dev Input tokens are stored at a vault address.
/// @dev Fees are pull-model. Accumulated, to be swept to a feeRecipient address.
/// @dev collateralToken must have >= 8 and <= 18 decimals
contract SwapFacilitySwapAndBridgeZap is AuthNoOwner, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    ISwapFacility public immutable swapFacility;
    IERC20 public immutable collateralToken;
    IERC20 public immutable debtToken;

    error InvalidAddress();
    error InvalidFee();

    /// @notice Creates a new SwapFacility logic contract.
    /// @param _authority The address of the authority contract.
    /// @param _swapFacility The address of the swap facility contract.
    constructor(address _authority, address _swapFacility) ReentrancyGuard() Pausable() {
        if (_authority == address(0)) revert InvalidAddress();
        if (_swapFacility == address(0)) revert InvalidAddress();

        _initializeAuthority(_authority);
        swapFacility = ISwapFacility(_swapFacility);

        collateralToken = IERC20(address(swapFacility.collateralToken()));
        debtToken = IERC20(address(swapFacility.debtToken()));

        collateralToken.forceApprove(address(swapFacility), type(uint256).max);
        debtToken.forceApprove(address(swapFacility), type(uint256).max);
    }

    /*
        === Swap Functions ===
    */

    /// @notice Swaps an exact amount of input tokens for output tokens and sends them cross-chain via LayerZero
    /// @param collateralIn The amount of collateral tokens to swap
    /// @param sendParam The LayerZero send parameters including destination chain and recipient.
    /// @dev sendParam.amountLD will be overridden to the actual amount out of the swap.
    /// @dev sendParam.minAmountLD also factors in fees from the swap.
    /// @dev sendParam.minAmountLD can be considered the debtOutMin parameter from the non crosschain function variant.
    /// @param lzFee The LayerZero messaging fee parameters
    /// @param refundAddress The address to receive any excess funds
    /// @param deadline The timestamp by which the initial swap must be completed (does not apply to cross-chain completion)
    /// @return debtOut The amount of debt tokens expected to be received. Does not factor in fees or slippage from LayerZero operation.
    /// @return fee The fee amount charged in debt tokens
    function swapExactCollateralForDebtAndLZSend(
        uint256 collateralIn,
        SendParam memory sendParam,
        MessagingFee calldata lzFee,
        address refundAddress,
        uint256 deadline // Deadline for initial swap, not for crosschain completion
    ) public payable virtual whenNotPaused nonReentrant returns (uint256 debtOut, uint256 fee) {
        require(sendParam.composeMsg.length == 0, "No compose");
        require(sendParam.oftCmd.length == 0, "No oftCmd");

        if (msg.value < lzFee.nativeFee || lzFee.lzTokenFee != 0) revert InvalidFee(); // No LZ token fees

        collateralToken.safeTransferFrom(msg.sender, address(this), collateralIn);

        (debtOut, fee) =
            swapFacility.swapExactCollateralForDebt(collateralIn, sendParam.minAmountLD, address(this), deadline);
        sendParam.amountLD = debtOut;

        IOFT(address(debtToken)).send{value: msg.value}(sendParam, lzFee, refundAddress); // Send debt tokens cross-chain
    }

    /// @notice Global pause.
    function pause() external requiresAuth whenNotPaused {
        _pause();
    }

    /// @notice Global unpause.
    function unpause() external requiresAuth whenPaused {
        _unpause();
    }
}