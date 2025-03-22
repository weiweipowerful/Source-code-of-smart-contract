// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Roles} from "./utils/Roles.sol";
import {IUTB} from "./interfaces/IUTB.sol";
import {IUTBExecutor} from "./interfaces/IUTBExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IUTBFeeManager} from "./interfaces/IUTBFeeManager.sol";
import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";
import {ISwapper} from "./interfaces/ISwapper.sol";
import {SwapInstructions, SwapParams, FeeData, Fee, BridgeInstructions, SwapAndExecuteInstructions} from "./CommonTypes.sol";
import {Withdrawable} from "./utils/Withdrawable.sol";

contract UTB is IUTB, Roles, Withdrawable {
    constructor() Roles(msg.sender) {}

    IUTBExecutor public executor;
    IUTBFeeManager public feeManager;
    IWETH public wrapped;
    mapping(uint8 id => address swapper) public swappers;
    mapping(uint8 id => address bridgeAdapter) public bridgeAdapters;
    bool public isActive = true;

    /**
     * @dev only support calling swapAndExecute and bridgeAndExecute if active
     */
    modifier isUtbActive() {
        if (!isActive) revert UTBPaused();
        _;
    }

    modifier onlyWrapped() {
        if (msg.sender != address(wrapped)) revert OnlyWrapped();
        _;
    }

    /**
     * @dev Transfers fees from the sender to the fee recipients.
     * @param feeData The bridge fee in native, as well as utb fee tokens and amounts.
     * @param packedInfo The fees and swap instructions which were used to generate the signature.
     * @param signature The ECDSA signature to verify the fee structure.
     */
    function _retrieveAndCollectFees(
        FeeData calldata feeData,
        SwapParams memory swapParams,
        bytes memory packedInfo,
        bytes calldata signature
    ) private returns (uint256 value) {
        if (feeData.chainId != block.chainid) revert InvalidFees();
        if (block.timestamp > feeData.deadline) revert ExpiredFees();

        if (address(feeManager) != address(0)) {
            feeManager.verifySignature(packedInfo, signature);
            value += feeData.bridgeFee;
            Fee[] memory fees = feeData.appFees;
            for (uint i = 0; i < fees.length; i++) {
                Fee memory fee = fees[i];
                if (fee.token != address(0)) {
                    SafeERC20.safeTransferFrom(
                        IERC20(fee.token),
                        msg.sender,
                        fee.recipient,
                        fee.amount
                    );
                } else {
                    (bool success, ) = address(fee.recipient).call{value: fee.amount}("");
                    value += fee.amount;
                    if (!success) revert ProtocolFeeCannotBeFetched();
                }
            }
        }

        uint256 valueRequired = swapParams.tokenIn == address(0)
            ? swapParams.amountIn + value
            : value;

        if (msg.value < valueRequired) revert NotEnoughNative();
    }

    /**
     * @dev Refunds the specified refund address.
     * @param to The address receiving the refund.
     * @param amount The amount of the refund.
     */
    function _refundUser(address to, address token, uint256 amount) private {
        if ( amount > 0 ) {
            if (token == address(0)) {
                (bool success, ) = to.call{value: amount}("");
                if (!success) revert RefundFailed();
            } else {
                SafeERC20.safeTransfer(IERC20(token), to, amount);
            }
        }
    }

    /**
     * @dev Sets the executor.
     * @param _executor The address of the executor.
     */
    function setExecutor(address _executor) public onlyAdmin {
        executor = IUTBExecutor(_executor);
        emit SetExecutor(_executor);
    }

    /**
     * @dev Sets the wrapped native token.
     * @param _wrapped The address of the wrapped token.
     */
    function setWrapped(address _wrapped) public onlyAdmin {
        wrapped = IWETH(_wrapped);
        emit SetWrapped(_wrapped);
    }

    /**
     * @dev Sets the fee manager.
     * @param _feeManager The address of the fee manager.
     */
    function setFeeManager(address _feeManager) public onlyAdmin {
        feeManager = IUTBFeeManager(_feeManager);
        emit SetFeeManager(_feeManager);
    }

    /**
     * @dev toggles active state
     */
    function toggleActive() public onlyAdmin {
        isActive = !isActive;
        emit SetIsActive(isActive);
    }

    /**
     * @dev Checks if there is a swap being performed
     */
    function _isSwapping(SwapParams memory swapParams) private pure returns (bool) {
        return swapParams.additionalArgs.length != 0;
    }

    /**
     * @dev Checks if there is no swap being performed
     */
    function _isNotSwapping(SwapParams memory swapParams) private pure returns (bool) {
        return swapParams.tokenIn == swapParams.tokenOut;
    }

    /**
     * @dev Checks if there is a wrap being performed
     */
    function _isWrapping(SwapParams memory swapParams) private view returns (bool) {
        return swapParams.tokenIn == address(0) && swapParams.tokenOut == address(wrapped);
    }

    /**
     * @dev Checks if there is an unwrap being performed
     */
    function _isUnwrapping(SwapParams memory swapParams) private view returns (bool) {
        return swapParams.tokenIn == address(wrapped) && swapParams.tokenOut == address(0);
    }

    /**
     * @dev Performs a swap with the requested swapper and swap calldata.
     * @param swapInstructions The swapper ID and calldata to execute a swap.
     */
    function _performSwap(
        SwapInstructions memory swapInstructions
    ) private returns (address tokenOut, uint256 amountOut, uint256 value) {
        SwapParams memory swapParams = swapInstructions.swapParams;

        (tokenOut, amountOut, value) = _swapHandler(swapInstructions);

        amountOut -= swapParams.dustOut;

        _refundUser(
            swapParams.refund,
            tokenOut,
            swapParams.dustOut
        );
    }

    /**
     * @dev Routes swap operations to the appropriate handler based on the swap type
     * @param swapInstructions The swap instructions containing swap parameters and swapper ID
     */
    function _swapHandler(
        SwapInstructions memory swapInstructions
    ) private returns (address tokenOut, uint256 amountOut, uint256 value) {
        SwapParams memory swapParams = swapInstructions.swapParams;

        if (_isSwapping(swapParams)) {
            return _handleSwap(swapParams, swappers[swapInstructions.swapperId]);
        }

        if (_isNotSwapping(swapParams)) {
            return _handleNoSwap(swapParams);
        }

        if (_isWrapping(swapParams)) {
            return _handleWrap(swapParams);
        }

        if (_isUnwrapping(swapParams)) {
            return _handleUnwrap(swapParams);
        }

        revert InvalidSwapParams();
    }

    /**
     * @dev Handles a swap operation using the specified swapper contract.
     * @param swapParams The swap parameters containing token addresses and amounts.
     * @param swapper The address of the swapper contract to execute the swap.
     */
    function _handleSwap(
        SwapParams memory swapParams,
        address swapper
    ) private returns (address tokenOut, uint256 amountOut, uint256 value) {
        if (swapParams.tokenIn == address(0)) {
            wrapped.deposit{value: swapParams.amountIn}();
            value = swapParams.amountIn;
            swapParams.tokenIn = address(wrapped);
        } else {
            SafeERC20.safeTransferFrom(
                IERC20(swapParams.tokenIn),
                msg.sender,
                address(this),
                swapParams.amountIn
            );
        }

        SafeERC20.forceApprove(IERC20(swapParams.tokenIn), swapper, swapParams.amountIn);

        (tokenOut, amountOut) = ISwapper(swapper).swap(swapParams);

        if (tokenOut == address(0)) {
            wrapped.withdraw(amountOut);
        }
    }

    /**
     * @dev Handles a direct transfer when input and output tokens are the same.
     * @param swapParams The swap parameters containing token addresses and amounts.
     */
    function _handleNoSwap(
        SwapParams memory swapParams
    ) private returns (address tokenOut, uint256 amountOut, uint256 value) {
        if (swapParams.tokenIn == address(0)) {
            return (address(0), swapParams.amountIn, swapParams.amountIn);
        } else {
            SafeERC20.safeTransferFrom(
                IERC20(swapParams.tokenIn),
                msg.sender,
                address(this),
                swapParams.amountIn
            );
            return (swapParams.tokenIn, swapParams.amountIn, 0);
        }
    }

    /**
     * @dev Handles wrapping of native tokens to wrapped tokens.
     * @param swapParams The swap parameters containing token addresses and amounts.
     */
    function _handleWrap(
        SwapParams memory swapParams
    ) private returns (address tokenOut, uint256 amountOut, uint256 value) {
        wrapped.deposit{value: swapParams.amountIn}();
        return (address(wrapped), swapParams.amountIn, swapParams.amountIn);
    }

    /**
     * @dev Handles unwrapping of wrapped tokens to native tokens.
     * @param swapParams The swap parameters containing token addresses and amounts.
     */
    function _handleUnwrap(
        SwapParams memory swapParams
    ) private returns (address tokenOut, uint256 amountOut, uint256 value) {
        SafeERC20.safeTransferFrom(
            IERC20(wrapped),
            msg.sender,
            address(this),
            swapParams.amountIn
        );
        wrapped.withdraw(swapParams.amountIn);
        return (address(0), swapParams.amountIn, 0);
    }

    /// @inheritdoc IUTB
    function swapAndExecute(
        SwapAndExecuteInstructions calldata instructions,
        FeeData calldata feeData,
        bytes calldata signature
    )
        public
        payable
        isUtbActive
    {
        emit Swapped(
            instructions.txId,
            feeData.appId,
            TxInfo({
                amountIn: instructions.swapInstructions.swapParams.amountIn,
                tokenIn: instructions.swapInstructions.swapParams.tokenIn,
                tokenOut: instructions.swapInstructions.swapParams.tokenOut,
                target: instructions.target,
                affiliateId: feeData.affiliateId,
                fees: feeData.appFees
            })
        );

        uint256 value = _retrieveAndCollectFees(
            feeData,
            instructions.swapInstructions.swapParams,
            abi.encode(instructions, feeData),
            signature
        );

        value += _swapAndExecute(
            instructions.swapInstructions,
            instructions.target,
            instructions.paymentOperator,
            instructions.payload,
            instructions.refund,
            instructions.executionFee
        );

        _refundUser(instructions.refund, address(0), msg.value - value);
    }

    /**
     * @dev Swaps currency from the incoming to the outgoing token and executes a transaction with payment.
     * @param swapInstructions The swapper ID and calldata to execute a swap.
     * @param target The address of the target contract for the payment transaction.
     * @param paymentOperator The operator address for payment transfers requiring ERC20 approvals.
     * @param payload The calldata to execute the payment transaction.
     * @param refund The account receiving any refunds, typically the EOA which initiated the transaction.
     * @param executionFee Forwards additional native fees required for executing the payment transaction.
     */
    function _swapAndExecute(
        SwapInstructions memory swapInstructions,
        address target,
        address paymentOperator,
        bytes memory payload,
        address refund,
        uint256 executionFee
    ) private returns (uint256 value) {
        address tokenOut;
        uint256 amountOut;
        (tokenOut, amountOut, value) = _performSwap(swapInstructions);
        if (executionFee > 0) value += executionFee;
        if (tokenOut == address(0)) {
            executor.execute{value: amountOut + executionFee}(
                target,
                paymentOperator,
                payload,
                tokenOut,
                amountOut,
                refund,
                executionFee
            );
        } else {
            SafeERC20.forceApprove(IERC20(tokenOut), address(executor), amountOut);
            executor.execute{value: executionFee}(
                target,
                paymentOperator,
                payload,
                tokenOut,
                amountOut,
                refund,
                executionFee
            );
        }
    }

    /**
     * @dev Checks if the bridge token is native, and approves the bridge adapter to transfer ERC20 if required.
     * @param instructions The bridge data, token swap data, and payment transaction payload.
     * @param amt2Bridge The amount of the bridge token being transferred to the bridge adapter.
     */
    function _approveAndCheckIfNative(
        BridgeInstructions memory instructions,
        uint256 amt2Bridge
    ) private returns (bool) {
        IBridgeAdapter bridgeAdapter = IBridgeAdapter(bridgeAdapters[instructions.bridgeId]);
        address bridgeToken = bridgeAdapter.getBridgeToken(
            instructions.additionalArgs
        );
        if (bridgeToken != address(0)) {
            SafeERC20.forceApprove(IERC20(bridgeToken), address(bridgeAdapter), amt2Bridge);
            return false;
        }
        return true;
    }

    /// @inheritdoc IUTB
    function bridgeAndExecute(
        BridgeInstructions memory instructions,
        FeeData calldata feeData,
        bytes calldata signature
    )
        public
        payable
        isUtbActive
    {
        emit BridgeCalled(
            instructions.txId,
            feeData.appId,
            instructions.dstChainId,
            TxInfo({
                amountIn: instructions.preBridge.swapParams.amountIn,
                tokenIn: instructions.preBridge.swapParams.tokenIn,
                tokenOut: instructions.postBridge.swapParams.tokenOut,
                target: instructions.target,
                affiliateId: feeData.affiliateId,
                fees: feeData.appFees
            })
        );

        uint256 feeValue = _retrieveAndCollectFees(
            feeData,
            instructions.preBridge.swapParams,
            abi.encode(instructions, feeData),
            signature
        );

        ( , uint256 amt2Bridge, uint256 swapValue) = _performSwap(instructions.preBridge);

        instructions.postBridge.swapParams.amountIn = amt2Bridge;

        _refundUser(instructions.refund, address(0), msg.value - feeValue - swapValue);

        _callBridge(amt2Bridge, feeData.bridgeFee, instructions);
    }

    /**
     * @dev Calls the bridge adapter to bridge funds, and approves the bridge adapter to transfer ERC20 if required.
     * @param amt2Bridge The amount of the bridge token being bridged via the bridge adapter.
     * @param bridgeFee The fee being transferred to the bridge adapter and finally to the bridge.
     * @param instructions The bridge data, token swap data, and payment transaction payload.
     */
    function _callBridge(
        uint256 amt2Bridge,
        uint bridgeFee,
        BridgeInstructions memory instructions
    ) private {
        bool native = _approveAndCheckIfNative(instructions, amt2Bridge);

        IBridgeAdapter(bridgeAdapters[instructions.bridgeId]).bridge{
            value: bridgeFee + (native ? amt2Bridge : 0)
        }(
            IBridgeAdapter.BridgeCall({
                amount: amt2Bridge,
                postBridge: instructions.postBridge,
                dstChainId: instructions.dstChainId,
                target: instructions.target,
                paymentOperator: instructions.paymentOperator,
                payload: instructions.payload,
                additionalArgs: instructions.additionalArgs,
                refund: instructions.refund,
                txId: instructions.txId
            })
        );
    }

    /// @inheritdoc IUTB
    function receiveFromBridge(
        SwapInstructions memory postBridge,
        address target,
        address paymentOperator,
        bytes memory payload,
        address refund,
        uint8 bridgeId,
        bytes32 txId
    ) public payable {
        if (msg.sender != bridgeAdapters[bridgeId]) revert OnlyBridgeAdapter();
        emit ReceivedFromBridge(txId);
        _swapAndExecute(postBridge, target, paymentOperator, payload, refund, 0);
    }

    /// @inheritdoc IUTB
    function registerSwapper(address swapper) public onlyAdmin {
        ISwapper s = ISwapper(swapper);
        swappers[s.ID()] = swapper;
        emit RegisteredSwapper(swapper);
    }

    /// @inheritdoc IUTB
    function registerBridge(address bridge) public onlyAdmin {
        IBridgeAdapter b = IBridgeAdapter(bridge);
        bridgeAdapters[b.ID()] = bridge;
        emit RegisteredBridgeAdapter(bridge);
    }

    receive() external payable onlyWrapped {}
}