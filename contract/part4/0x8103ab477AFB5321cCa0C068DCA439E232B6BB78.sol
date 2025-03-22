// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./parts/SanderBusiness.sol";
import "@openzeppelin/contracts/access/Ownable.sol";




/// @title MultiCallSender
/// @notice A contract for validating and executing multiple ERC20 token transfers
contract MultiCallSender is SanderBusiness, Ownable {

    /// @notice Validates multiple token transfer requests by checking contract presence and allowances.
    /// @param tokenAddresses The address of the ERC20 token contract.
    /// @param recipients An array of addresses to which the tokens are to be sent.
    /// @param amounts An array of token amounts to be transferred to the corresponding recipients.
    /// @return results array of Status structures indicating the possibility of each transfer.
    /// @dev The lengths of the `recipients` and `amounts` arrays must be equal.
    function validateMultipleSend(address[] memory tokenAddresses, address[] memory recipients, uint256[] memory amounts) external view returns (Status[] memory results) {
        require(recipients.length == amounts.length, "Incorrect parameters");
        return _validateMultipleSend(tokenAddresses, recipients, amounts);
    }



    /// @notice Executes multiple token transfers after validating them.
    /// If a transfer fails, it will be skipped and the process will continue with the next one.
    /// @param tokenAddresses The address of the ERC20 token contract.
    /// @param recipients An array of addresses to which the tokens are to be sent.
    /// @param amounts An array of token amounts to be transferred to the corresponding recipients.
    /// @return results array of Status structures indicating the result of each transfer attempt.
    function executeMultipleSend(address[] memory tokenAddresses, address[] memory recipients, uint256[] memory amounts) public onlyOwner returns (Status[] memory results) {
        require(recipients.length == amounts.length, "Incorrect parameters");
        return _executeMultipleSend(tokenAddresses, recipients, amounts);
    }

}