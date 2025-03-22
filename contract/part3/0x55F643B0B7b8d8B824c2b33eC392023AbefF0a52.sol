// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import "./lib/Depositor.sol";
import "./lib/Constants.sol";

/// @title E280 Tax Depositor Contract
contract E280TaxDepositor is Ownable2Step, ReentrancyGuard, Depositor {
    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;

    // -------------------------- STATE VARIABLES -------------------------- //

    address public immutable E280;
    address public E280_TAX_DISTRIBUTOR;

    /// @notice ID of the chain for Tax Distributor contract.
    uint32 public DESTINATION_ID = BASE_DST_EID;

    /// @notice Basis point incentive fee paid out for distributing.
    uint16 public incentiveFeeBps = 30;

    /// @notice Gas limit for bridge transaction on destination chain.
    uint128 public gasLimit = MIN_GAS_REQ;

    // ------------------------------- EVENTS ------------------------------ //

    event BridgeOut(bytes32 indexed guid, uint256 amountSent, uint256 amountReceived);

    // ------------------------------- ERRORS ------------------------------ //

    error Prohibited();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientFeeSent();
    error RefundFailed();
    error Unauthorized();

    // ------------------------------ MODIFIERS ---------------------------- //

    modifier onlyWhitelisted() {
        if (!WL_REGISTRY.isWhitelisted(msg.sender)) revert Unauthorized();
        _;
    }

    // ----------------------------- CONSTRUCTOR --------------------------- //

    constructor(address _owner, address _e280, address _taxDistributor) Ownable(_owner) {
        if (_e280 == address(0)) revert ZeroAddress();
        if (_taxDistributor == address(0)) revert ZeroAddress();
        E280 = _e280;
        E280_TAX_DISTRIBUTOR = _taxDistributor;
    }

    // --------------------------- PUBLIC FUNCTIONS ------------------------ //

    /// @notice Bridges all E280 tokens held by the contract to the Tax Distributor contract.
    function bridge() external payable onlyWhitelisted nonReentrant {
        uint256 balance = IERC20(E280).balanceOf(address(this));
        if (balance == 0) revert InsufficientBalance();

        balance = _sanitizeBridgeAmount(balance);
        balance = _processIncentiveFee(E280, balance, incentiveFeeBps);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0);

        SendParam memory params = SendParam({
            dstEid: DESTINATION_ID,
            to: _addressToBytes32(E280_TAX_DISTRIBUTOR),
            amountLD: balance,
            minAmountLD: _removeDust(balance),
            extraOptions: options,
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        IOFT e280 = IOFT(E280);

        MessagingFee memory fee = e280.quoteSend(params, false);
        if (fee.nativeFee > msg.value) revert InsufficientFeeSent();

        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) = e280.send{ value: fee.nativeFee }(
            params,
            fee,
            msg.sender
        );

        uint256 excessFee = msg.value - fee.nativeFee;
        if (excessFee > 0) {
            (bool success, ) = msg.sender.call{ value: excessFee }("");
            if (!success) revert RefundFailed();
        }

        emit BridgeOut(receipt.guid, balance, oftReceipt.amountReceivedLD);
    }

    // ----------------------- ADMINISTRATIVE FUNCTIONS -------------------- //

    /// @notice Sets the incentive fee basis points (bps) for performing distribution.
    /// @param bps The incentive fee in basis points (30 - 500), (100 bps = 1%).
    function setIncentiveFee(uint16 bps) external onlyOwner {
        if (bps < 30 || bps > 500) revert Prohibited();
        incentiveFeeBps = bps;
    }

    /// @notice Sets the gas limit for bridge transaction on destination chain.
    /// @param limit The new cap limit in WEI.
    function setGasLimit(uint128 limit) external onlyOwner {
        if (limit < MIN_GAS_REQ) revert Prohibited();
        gasLimit = limit;
    }

    /// @notice Sets new address for E280 Tax Distributor contract.
    /// @param _address New address of the E280 Tax Distributor.
    /// @param _destinationId LZ Chain ID for the new contract.
    function setTaxDistributor(address _address, uint32 _destinationId) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        if (_destinationId == 0) revert Prohibited();
        E280_TAX_DISTRIBUTOR = _address;
        DESTINATION_ID = _destinationId;
    }

    // ---------------------------- VIEW FUNCTIONS ------------------------- //

    /// @notice Returns parameters for the next Bridge.
    /// @return amount Total E280 amount used in the next call.
    /// @return incentive E280 amount paid out to the caller.
    function getBridgeParams() public view returns (uint256 amount, uint256 incentive) {
        uint256 balance = IERC20(E280).balanceOf(address(this));
        amount = _sanitizeBridgeAmount(balance);
        incentive = _applyBps(amount, incentiveFeeBps);
    }

    // -------------------------- INTERNAL FUNCTIONS ----------------------- //

    function _processIncentiveFee(address token, uint256 amount, uint16 incentiveBps) internal returns (uint256) {
        uint256 incentiveFee = _applyBps(amount, incentiveBps);
        IERC20(token).safeTransfer(msg.sender, incentiveFee);
        return amount - incentiveFee;
    }

    function _applyBps(uint256 amount, uint16 bps) internal pure returns (uint256) {
        return (amount * bps) / BPS_BASE;
    }
}