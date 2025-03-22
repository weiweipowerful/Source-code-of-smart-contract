// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Multicall Helper
 *
 * @notice Simplified version of the OZ Multicall contract
 *
 * @dev Deployed as a standalone helper contract to be used to call multiple contacts in a single batch.
 *      This could be especially useful when combined with the EIP712 meta-transaction
 *      calls on the target contracts.
 *
 * @dev Executes the targets via `call` in their own contexts (storages)
 *
 * @author OpenZeppelin
 * @author Lizard Labs Core Contributors
 */
contract MulticallHelper {
	/**
	 * @dev Multicall support: a function to batch together multiple calls in a single external call.
	 * @dev Receives and executes a batch of function calls on the target contracts.
	 *
	 * @param targets an array of the target contract addresses to execute the calls on
	 * @param data an array of ABI-encoded function calls
	 * @return results an array of ABI-encoded results of the function calls
	 */
	function multicall(address[] calldata targets, bytes[] calldata data) external virtual returns (bytes[] memory results) {
		// verify the arrays' lengths are the same
		require(targets.length == data.length, "array lengths mismatch");

		// the implementation is based on OZ Multicall contract;
		// Context-related stuff is dropped as it's not supported by this contract
		results = new bytes[](data.length);
		for (uint256 i = 0; i < data.length; i++) {
			results[i] = Address.functionCall(targets[i], data[i]);
		}
		return results;
	}
}