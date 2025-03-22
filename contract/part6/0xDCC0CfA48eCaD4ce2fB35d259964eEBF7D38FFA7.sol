// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {ICircleCctp} from "interfaces/ICircleCctp.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract YeiCctpAgent is Ownable {
    event FeesUpdated(uint256 newFeeEthDecimal, uint256 newFeeOtherChainsDecimal);
    event DepositForBurn(address indexed from, uint256 amount, uint64 indexed burnResult);
    event FeesWithdrawn(address indexed owner, uint256 balance);

    using SafeERC20 for IERC20;

    address public circleCctpContract;
    IERC20 public usdcToken;
    bool public isEthereum;

    // Decimal-based fee representation, with a unit of 10^18 (e.g., 0.01 represents 1%)
    uint256 public feeEthDecimal;
    uint256 public feeOtherChainsDecimal;

    constructor(
        address _circleCctpContract,
        address _usdcToken,
        bool _isEthereum,
        uint256 _feeEthDecimal,
        uint256 _feeOtherChainsDecimal
    ) Ownable(msg.sender) {
        circleCctpContract = _circleCctpContract;
        usdcToken = IERC20(_usdcToken);
        isEthereum = _isEthereum;

        feeEthDecimal = _feeEthDecimal;
        feeOtherChainsDecimal = _feeOtherChainsDecimal;
    }

    function depositForBurn(uint256 amount, uint32 destinationDomain, bytes32 mintRecipient, address burnToken)
        public
        returns (uint64)
    {
        uint256 amountAfterFee = amount - getFee(amount);

        usdcToken.safeTransferFrom(msg.sender, address(this), amount);
        usdcToken.safeIncreaseAllowance(circleCctpContract, amountAfterFee);

        uint64 burnResult =
            ICircleCctp(circleCctpContract).depositForBurn(amountAfterFee, destinationDomain, mintRecipient, burnToken);
        emit DepositForBurn(msg.sender, amountAfterFee, burnResult);

        return burnResult;
    }

    function getFee(uint256 amount) internal view returns (uint256) {
        uint256 feeDecimal = isEthereum ? feeEthDecimal : feeOtherChainsDecimal;
        return amount * feeDecimal / 1e18;
    }

    function getCurrentFeeDecimal() external view returns (uint256) {
        return isEthereum ? feeEthDecimal : feeOtherChainsDecimal;
    }

    function updateFees(uint256 _feeEthDecimal, uint256 _feeOtherChainsDecimal) external onlyOwner {
        feeEthDecimal = _feeEthDecimal;
        feeOtherChainsDecimal = _feeOtherChainsDecimal;

        emit FeesUpdated(feeEthDecimal, feeOtherChainsDecimal);
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = usdcToken.balanceOf(address(this));
        require(balance > 0, "No fees to withdraw");

        usdcToken.safeTransfer(owner(), balance);

        emit FeesWithdrawn(owner(), balance);
    }
}