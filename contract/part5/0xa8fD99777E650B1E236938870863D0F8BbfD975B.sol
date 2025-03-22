// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract GdnPaymentReceiver is Ownable {
    IERC20 public usdToken;
    using SafeERC20 for IERC20;
    address public beneficiary;

    event PaymentReceived(
        address indexed payer,
        uint256 amount,
        string orderId
    );

    event Withdrawn(address indexed beneficiary, uint256 amount);

    modifier onlyBeneficiary() {
        require(
            msg.sender == beneficiary,
            "Only beneficiary can call this function"
        );
        _;
    }

    constructor(
        address usdTokenAddress,
        address initialOwner
    ) Ownable(initialOwner) {
        usdToken = IERC20(usdTokenAddress);
        beneficiary = initialOwner;
    }

    // usdToken can set by owner
    function setUsdToken(address newUsdToken) external onlyOwner {
        usdToken = IERC20(newUsdToken);
    }

    function setBeneficiary(address newBeneficiary) external onlyOwner {
        require(newBeneficiary != address(0), "Invalid address");
        beneficiary = newBeneficiary;
    }

    function pay(uint256 amount, string memory orderId) external {
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(orderId).length > 0, "Order ID cannot be empty");

        usdToken.safeTransferFrom(msg.sender, address(this), amount);

        emit PaymentReceived(msg.sender, amount, orderId);
    }

    function withdrawUSD(uint256 amount) external onlyBeneficiary {
        require(amount > 0, "Amount must be greater than 0");
        require(
            usdToken.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );

        usdToken.safeTransfer(beneficiary, amount);

        // Emit the event to log the withdrawal
        emit Withdrawn(beneficiary, amount);
    }

    function getContractBalance() external view returns (uint256) {
        return usdToken.balanceOf(address(this));
    }
}