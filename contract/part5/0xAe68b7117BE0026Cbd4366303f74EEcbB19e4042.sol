// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Ownable} from "../utils/Ownable.sol";
import {RescueFundsLib} from "../lib/RescueFundsLib.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {AuthenticationLib} from "./../lib/AuthenticationLib.sol";
import {CurrencyLib} from "./../lib/CurrencyLib.sol";
import {BungeeGateway} from "../core/BungeeGateway.sol";
import {FulfilExec as SingleOutputFulfilExec, SingleOutputRequestImpl} from "../core/SingleOutputRequestImpl.sol";

contract Solver is Ownable {
    struct Action {
        address target;
        uint256 value;
        bytes data;
    }

    struct SwapAction {
        uint256 fulfilExecIndex;
        Action swapActionData;
    }

    // @todo standardize errors
    error ActionFailed();
    error ActionsFailed(uint256 index);
    error InvalidSigner();
    error InvalidNonce();
    error InvalidSwapActions();
    error SwapActionFailed(uint256 index);
    error SwapOutputInsufficient(uint256 index);
    error TransferFailed();
    error InvalidCaller();

    uint8 public constant SINGLE_OUTPUT_IMPL_ID = 1;
    uint8 public constant SWAP_REQUEST_IMPL_ID = 2;

    address public constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice address of the signer
    address internal SOLVER_SIGNER;

    /// @notice mapping to track used nonces of SOLVER_SIGNER
    mapping(uint256 nonce => bool isNonceUsed) public nonceUsed;

    /**
     * @notice Constructor.
     * @param _owner address of the contract owner
     * @param _solverSigner address of the signer
     */
    constructor(address _owner, address _solverSigner) Ownable(_owner) {
        SOLVER_SIGNER = _solverSigner;
    }

    function setSolverSigner(address _solverSigner) external onlyOwner {
        SOLVER_SIGNER = _solverSigner;
    }

    /// @dev separate specific functions for extract, fulfil, settle
    /// so that easier to index and track costs
    function performExtraction(uint256 nonce, Action calldata action, bytes calldata signature) external {
        // @todo assembly encode and hash - can look at solady
        verifySignature(keccak256(abi.encode(block.chainid, address(this), nonce, action)), signature);

        // verify nonce
        assembly {
            // load data slot from mapping
            mstore(0, nonce)
            mstore(0x20, nonceUsed.slot)
            let dataSlot := keccak256(0, 0x40)

            // check if nonce is used
            if and(sload(dataSlot), 0xff) {
                mstore(0x00, 0x756688fe) // revert InvalidNonce();
                revert(0x1c, 0x04)
            }

            // if not used mark as used
            /// @dev not cleaning all the bits, just setting the first bit to 1
            sstore(dataSlot, 0x01)
        }

        /// @dev no need for approvals in extraction

        bool success = _performAction(action);
        assembly {
            /// @dev not cleaning all the bits, just using success as is
            if iszero(success) {
                mstore(0x00, 0x080a1c27) // revert ActionFailed();
                revert(0x1c, 0x04)
            }
        }
    }

    function performSettlement(uint256 nonce, Action calldata action, bytes calldata signature) external {
        verifySignature(keccak256(abi.encode(block.chainid, address(this), nonce, action)), signature);

        // verify nonce
        assembly {
            // load data slot from mapping
            mstore(0, nonce)
            mstore(0x20, nonceUsed.slot)
            let dataSlot := keccak256(0, 0x40)

            // check if nonce is used
            if and(sload(dataSlot), 0xff) {
                mstore(0x00, 0x756688fe) // revert InvalidNonce();
                revert(0x1c, 0x04)
            }

            // if not used mark as used
            /// @dev not cleaning all the bits, just setting the first bit to 1
            sstore(dataSlot, 0x01)
        }

        /// @dev no need for approvals in settlement

        bool success = _performAction(action);
        assembly {
            /// @dev not cleaning all the bits, just using success as is
            if iszero(success) {
                mstore(0x00, 0x080a1c27) // revert ActionFailed();
                revert(0x1c, 0x04)
            }
        }
    }

    /**
     * @notice Convenience function that helps perform a destination swap and fulfil the request.
     * @dev Can be used to perform a single swap and single fulfilment
     * @dev Modifies the fulfilAmount of the fulfilExec to the received amount from the swap
     */
    function performFulfilment(
        uint256 nonce,
        bytes[] calldata approvals,
        address bungeeGateway,
        uint256 value,
        Action calldata swapActionData,
        SingleOutputFulfilExec memory fulfilExec,
        bytes calldata signature
    ) external {
        verifySignature(
            keccak256(
                abi.encode(
                    block.chainid,
                    address(this),
                    nonce,
                    approvals,
                    bungeeGateway,
                    value,
                    swapActionData,
                    fulfilExec
                )
            ),
            signature
        );

        // verify nonce
        assembly {
            // load data slot from mapping
            mstore(0, nonce)
            mstore(0x20, nonceUsed.slot)
            let dataSlot := keccak256(0, 0x40)

            // check if nonce is used
            if and(sload(dataSlot), 0xff) {
                mstore(0x00, 0x756688fe) // revert InvalidNonce();
                revert(0x1c, 0x04)
            }

            // if not used mark as used
            /// @dev not cleaning all the bits, just setting the first bit to 1
            sstore(dataSlot, 0x01)
        }

        // _setApprovals(approvals);
        if (approvals.length > 0) {
            for (uint256 i = 0; i < approvals.length; i++) {
                // @todo assembly
                (address token, address spender, uint256 amount) = abi.decode(
                    approvals[i],
                    (address, address, uint256)
                );
                SafeTransferLib.safeApprove(token, spender, amount);
            }
        }

        if (swapActionData.target != address(0)) {
            // check pre balance
            // @todo assembly
            bool isNativeToken = fulfilExec.request.basicReq.outputToken == NATIVE_TOKEN_ADDRESS;
            uint256 beforeBalance = CurrencyLib.balanceOf(fulfilExec.request.basicReq.outputToken, address(this));

            // Perform swap action
            bool success = _performAction(swapActionData);
            if (!success) {
                // @todo replace with assembly
                revert SwapActionFailed(0);
            }

            // check post balance
            uint256 swapActionOutput = CurrencyLib.balanceOf(fulfilExec.request.basicReq.outputToken, address(this)) -
                beforeBalance;
            if (fulfilExec.fulfilAmount > swapActionOutput) {
                revert SwapOutputInsufficient(0);
            }

            // Overwrite the fulfilAmount with the received amount
            fulfilExec.fulfilAmount = swapActionOutput;
            // also update fulfilExec.msgValue & value sent to gateway if native token
            if (isNativeToken) {
                fulfilExec.msgValue = swapActionOutput;
                value = swapActionOutput;
            }
        }

        // perform fulfilment
        SingleOutputFulfilExec[] memory fulfilExecs = new SingleOutputFulfilExec[](1);
        fulfilExecs[0] = fulfilExec;
        BungeeGateway(payable(bungeeGateway)).executeImpl{value: value}(
            SINGLE_OUTPUT_IMPL_ID,
            abi.encodeCall(SingleOutputRequestImpl.fulfilRequests, (fulfilExecs))
        );
    }

    /**
     * @notice Convenience function that helps perform a destination swap and fulfil the request.
     * @dev Can be used to perform a batch of (swap & fulfilment)
     * @dev Modifies the fulfilAmounts of each fulfilExecs to the received amount from the swap
     */
    function performBatchFulfilment(
        uint256 nonce,
        bytes[] calldata approvals,
        address bungeeGateway,
        uint256 value,
        SwapAction[] calldata swapActions,
        SingleOutputFulfilExec[] memory fulfilExecs,
        bytes calldata signature
    ) external {
        verifySignature(
            keccak256(
                abi.encode(
                    block.chainid,
                    address(this),
                    nonce,
                    approvals,
                    bungeeGateway,
                    value,
                    swapActions,
                    fulfilExecs
                )
            ),
            signature
        );

        // verify nonce
        assembly {
            // load data slot from mapping
            mstore(0, nonce)
            mstore(0x20, nonceUsed.slot)
            let dataSlot := keccak256(0, 0x40)

            // check if nonce is used
            if and(sload(dataSlot), 0xff) {
                mstore(0x00, 0x756688fe) // revert InvalidNonce();
                revert(0x1c, 0x04)
            }

            // if not used mark as used
            /// @dev not cleaning all the bits, just setting the first bit to 1
            sstore(dataSlot, 0x01)
        }

        // _setApprovals(approvals);
        if (approvals.length > 0) {
            for (uint256 i = 0; i < approvals.length; i++) {
                (address token, address spender, uint256 amount) = abi.decode(
                    approvals[i],
                    (address, address, uint256)
                );
                SafeTransferLib.safeApprove(token, spender, amount);
            }
        }

        // if there are swap actions, they should be equal to the number of fulfilExecs
        assembly {
            // if (swapActions.length > 0 && swapActions.length != fulfilExecs.length)
            if and(
                gt(swapActions.length, 0),
                iszero(
                    eq(
                        swapActions.length, // swapActions is calldata
                        mload(fulfilExecs) // fulfilExecs is memory
                    )
                )
            ) {
                mstore(0x00, 0x91433bb2) // revert InvalidSwapActions()
                revert(0x1c, 0x04)
            }
        }

        for (uint256 i = 0; i < swapActions.length; i++) {
            SwapAction calldata swapAction = swapActions[i];

            // check pre balance
            bool isNativeToken = fulfilExecs[swapAction.fulfilExecIndex].request.basicReq.outputToken ==
                NATIVE_TOKEN_ADDRESS;
            uint256 beforeBalance = CurrencyLib.balanceOf(
                fulfilExecs[swapAction.fulfilExecIndex].request.basicReq.outputToken,
                address(this)
            );

            // Perform swap action
            bool success = _performAction(swapAction.swapActionData);
            if (!success) {
                revert SwapActionFailed(i);
            }

            // check post balance
            uint256 swapActionOutput = CurrencyLib.balanceOf(
                fulfilExecs[swapAction.fulfilExecIndex].request.basicReq.outputToken,
                address(this)
            ) - beforeBalance;
            if (fulfilExecs[swapAction.fulfilExecIndex].fulfilAmount > swapActionOutput) {
                revert SwapOutputInsufficient(i);
            }

            // Overwrite the fulfilAmount with the received amount
            fulfilExecs[swapAction.fulfilExecIndex].fulfilAmount = swapActionOutput;
            // also update fulfilExec.msgValue & value sent to gateway if native token
            if (isNativeToken) {
                // update total value based on the difference bw old and new balance
                value = value + (swapActionOutput - fulfilExecs[swapAction.fulfilExecIndex].msgValue); // new value - old value
                fulfilExecs[swapAction.fulfilExecIndex].msgValue = fulfilExecs[swapAction.fulfilExecIndex].fulfilAmount;
            }
        }

        // perform fulfilment
        BungeeGateway(payable(bungeeGateway)).executeImpl{value: value}(
            SINGLE_OUTPUT_IMPL_ID,
            abi.encodeCall(SingleOutputRequestImpl.fulfilRequests, (fulfilExecs))
        );
    }

    function performActions(
        uint256 nonce,
        bytes[] calldata approvals,
        Action[] calldata actions,
        bytes calldata signature
    ) external {
        verifySignature(keccak256(abi.encode(block.chainid, address(this), nonce, approvals, actions)), signature);

        // verify nonce
        assembly {
            // load data slot from mapping
            mstore(0, nonce)
            mstore(0x20, nonceUsed.slot)
            let dataSlot := keccak256(0, 0x40)

            // check if nonce is used
            if and(sload(dataSlot), 0xff) {
                mstore(0x00, 0x756688fe) // revert InvalidNonce();
                revert(0x1c, 0x04)
            }

            // if not used mark as used
            /// @dev not cleaning all the bits, just setting the first bit to 1
            sstore(dataSlot, 0x01)
        }

        // _setApprovals(approvals);
        if (approvals.length > 0) {
            for (uint256 i = 0; i < approvals.length; i++) {
                (address token, address spender, uint256 amount) = abi.decode(
                    approvals[i],
                    (address, address, uint256)
                );
                SafeTransferLib.safeApprove(token, spender, amount);
            }
        }

        for (uint256 i = 0; i < actions.length; i++) {
            bool success = _performAction(actions[i]);
            if (!success) {
                // TODO: should we bubble up the revert reasons? slightly hard to debug. need to run the txn with traces
                revert ActionsFailed(i);
            }
        }
    }

    /// @dev Does not revert on failure. Caller should check the return value.
    function _performAction(Action calldata action) internal returns (bool success) {
        assembly {
            // Load the data offset and length from the calldata
            let action_dataLength := calldataload(add(action, 96))

            // load calldata to memory to use for call()
            let freeMemPtr := mload(64)
            calldatacopy(
                freeMemPtr,
                add(
                    add(action, 32),
                    calldataload(add(action, 64)) // action_dataOffset - offset of action.data data part
                ), // action_dataStart - start of action.data data part
                action_dataLength
            )

            // Perform the call
            success := call(
                gas(), // Forward all available gas
                calldataload(action), // Target address - first 32 bytes starting from action offset
                calldataload(add(action, 32)), // call value to send - second 32 bytes starting from action offset
                freeMemPtr, // Input data start
                action_dataLength, // Input data length
                0, // Output data start (not needed)
                0 // Output data length (not needed)
            )
        }
    }

    function verifySignature(bytes32 messageHash, bytes calldata signature) public view {
        if (!(SOLVER_SIGNER == AuthenticationLib.authenticate(messageHash, signature))) {
            assembly {
                mstore(0x00, 0x815e1d64) // revert InvalidSigner();
                revert(0x1c, 0x04)
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Rescues funds from the contract if they are locked by mistake.
     * @param token_ The address of the token contract.
     * @param rescueTo_ The address where rescued tokens need to be sent.
     * @param amount_ The amount of tokens to be rescued.
     */
    function rescueFunds(address token_, address rescueTo_, uint256 amount_) external onlyOwner {
        RescueFundsLib.rescueFunds(token_, rescueTo_, amount_);
    }

    /*//////////////////////////////////////////////////////////////
                             RECEIVE ETHER
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}

    fallback() external payable {}
}