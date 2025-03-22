// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { LibZip } from "@solady/utils/LibZip.sol";

/**
 * @title CreateMyToken Batch Executor
 * @author CreateMyToken (https://www.createmytoken.com/)
 * @dev Batch Executor is able to interact with multiple modules in a single transaction, enabling
 *      complex contract deployment and initialization strategies. Supports calldata compression.
 */
contract CreateMyTokenBatchExecutor {
    struct CallDispatch {
        bool allowFailure;
        address target;
        uint256 value;
        bytes data;
    }

    struct CallResult {
        bool success;
        bytes data;
    }

    /*
     ** Errors
     */
    error BatchExecutor__CallFailed(uint256 i, bytes returnData);
    error BatchExecutor__ValueMismatch();

    function batchExecute(CallDispatch[] calldata calls) external payable returns (CallResult[] memory results) {
        uint256 valueAccumulator;
        uint256 length = calls.length;
        results = new CallResult[](length);

        for (uint256 i = 0; i < length; i++) {
            CallDispatch calldata call = calls[i];
            CallResult memory result = results[i];

            valueAccumulator += call.value;

            (result.success, result.data) = call.target.call{ value: call.value }(call.data);
            if (!result.success && !call.allowFailure) {
                revert BatchExecutor__CallFailed(i, result.data);
            }
        }

        require(msg.value == valueAccumulator, BatchExecutor__ValueMismatch());
    }

    fallback() external payable {
        LibZip.cdFallback();
    }

    receive() external payable {}
}