// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable2Step} from "openzeppelin-solidity/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin-solidity/contracts/security/Pausable.sol";
import {Address} from "openzeppelin-solidity/contracts/utils/Address.sol";
import {IMagpieRouterV3} from "./interfaces/IMagpieRouterV3.sol";
import {LibAsset} from "./libraries/LibAsset.sol";
import {LibRouter, SwapData} from "./libraries/LibRouter.sol";

error ExpiredTransaction();
error InsufficientAmountOut();
error InvalidCall();
error InvalidCommand();
error InvalidTransferFromCall();
error ApprovalFailed();
error TransferFromFailed();
error TransferFailed();
error UniswapV3InvalidAmount();
error InvalidCaller();
error InvalidAmountIn();
error InvalidSignature();
error InvalidOutput();
error InvalidNativeAmount();

enum CommandAction {
    Call, // Represents a generic call to a function within a contract.
    Approval, // Represents an approval operation.
    TransferFrom, // Indicates a transfer-from operation.
    Transfer, // Represents a direct transfer operation.
    Wrap, // This action is used for wrapping native tokens.
    Unwrap, // This action is used for unwrapping native tokens.
    Balance, // Checks the balance of an account or contract for a specific asset.
    Math,
    Comparison,
    EstimateGasStart,
    EstimateGasEnd
}

contract MagpieRouterV3 is IMagpieRouterV3, Ownable2Step, Pausable {
    using LibAsset for address;

    mapping(address => bool) public internalCaller;
    mapping(address => bool) public bridge;
    address public swapFeeAddress;

    /// @dev Restricts swap functions with signatures to only be called by whitelisted internal caller.
    modifier onlyInternalCaller() {
        if (!internalCaller[msg.sender]) {
            revert InvalidCaller();
        }
        _;
    }

    /// @dev Restricts swap functions with signatures to be called only by bridge.
    modifier onlyBridge() {
        if (!bridge[msg.sender]) {
            revert InvalidCaller();
        }
        _;
    }

    /// @dev See {IMagpieRouterV3-updateInternalCaller}
    function updateInternalCaller(address caller, bool value) external onlyOwner {
        internalCaller[caller] = value;

        emit UpdateInternalCaller(msg.sender, caller, value);
    }

    /// @dev See {IMagpieRouterV3-updateBridge}
    function updateBridge(address caller, bool value) external onlyOwner {
        bridge[caller] = value;

        emit UpdateBridge(msg.sender, caller, value);
    }

    /// @dev See {IMagpieRouterV3-updateSwapFeeAddress}
    function updateSwapFeeAddress(address value) external onlyOwner {
        swapFeeAddress = value;
    }

    /// @dev See {IMagpieRouterV3-pause}
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /// @dev See {IMagpieRouterV3-unpause}
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }

    /// @dev See {IMagpieRouterV3-multicall}
    function multicall(bytes[] calldata data) external onlyOwner returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }

    /// @dev Handle uniswapV3SwapCallback requests from any protocol that is based on UniswapV3. We dont check for factory since this contract is not supposed to store tokens. We protect the user by handling amountOutMin check at the end of execution by comparing starting and final balance at the destination address.
    fallback() external {
        int256 amount0Delta;
        int256 amount1Delta;
        address assetIn;
        uint256 callDataSize;
        assembly {
            amount0Delta := calldataload(4)
            amount1Delta := calldataload(36)
            assetIn := shr(96, calldataload(132))
            callDataSize := calldatasize()
        }

        if (callDataSize != 164) {
            revert InvalidCall();
        }

        if (amount0Delta <= 0 && amount1Delta <= 0) {
            revert UniswapV3InvalidAmount();
        }

        uint256 amount = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        assetIn.transfer(msg.sender, amount);
    }

    /// @dev Retrieves the address to be used for a swap operation.
    /// @param swapData The data structure containing information about the swap.
    /// @param useCaller Boolean indicating whether to use the caller's address.
    /// @param checkSignature Boolean indicating whether to validate the signature.
    /// @return fromAddress The address to be used for the swap operation.
    function getFromAddress(
        SwapData memory swapData,
        bool useCaller,
        bool checkSignature
    ) private view returns (address fromAddress) {
        if (checkSignature) {
            bool hasAffiliate = swapData.hasAffiliate;
            uint256 messagePtr;
            uint256 messageLength = hasAffiliate ? 384 : 320;
            assembly {
                messagePtr := mload(0x40)
                mstore(0x40, add(messagePtr, messageLength))
                switch hasAffiliate
                case 1 {
                    // keccak256("Swap(address router,address sender,address recipient,address fromAsset,address toAsset,uint256 deadline,uint256 amountOutMin,uint256 swapFee,uint256 amountIn,address affiliate,uint256 affiliateFee)")
                    mstore(messagePtr, 0x64d67eff2ff010acba1b1df82fb327ba0dc6d2965ba6b0b472bc14c494c8b4f6)
                }
                default {
                    // keccak256("Swap(address router,address sender,address recipient,address fromAsset,address toAsset,uint256 deadline,uint256 amountOutMin,uint256 swapFee,uint256 amountIn)")
                    mstore(messagePtr, 0x783528850c43ab6adcc3a843186a6558aa806707dd0abb3d2909a2a70b7f22a3)
                }
            }
            fromAddress = LibRouter.verifySignature(
                // keccak256(bytes("Magpie Router")),
                0x86af987965544521ef5b52deabbeb812d3353977e11a2dbe7e0f4905d1e60721,
                // keccak256(bytes("3")),
                0x2a80e1ef1d7842f27f2e6be0972bb708b9a135c38860dbe73c27c3486c34f4de,
                swapData,
                messagePtr,
                messageLength,
                useCaller,
                2
            );
        } else {
            if (useCaller) {
                fromAddress = msg.sender;
            } else {
                revert InvalidCall();
            }
        }
    }

    /// @dev Swaps tokens based on the provided swap data.
    /// @param swapData The data structure containing information about the swap operation.
    /// @param fromAddress The address initiating the swap. This address is responsible for the input assets.
    /// @param fullAmountIn The full amount that was used for the operation. If its 0 then event wont be emited.
    /// @return amountOut The amount of tokens or assets received after the swap.
    /// @return gasUsed The amount of gas consumed by the recorded operation.
    function swap(
        SwapData memory swapData,
        address fromAddress,
        uint256 fullAmountIn
    ) private returns (uint256 amountOut, uint256 gasUsed) {
        address fromAssetAddress = swapData.fromAssetAddress;
        address toAssetAddress = swapData.toAssetAddress;
        address toAddress = swapData.toAddress;
        uint256 amountOutMin = swapData.amountOutMin;
        uint256 amountIn = swapData.amountIn;
        uint256 transferFromAmount;

        amountOut = toAssetAddress.getBalanceOf(toAddress);

        (transferFromAmount, gasUsed) = execute(fromAddress, fromAssetAddress);

        amountOut = toAssetAddress.getBalanceOf(toAddress) - amountOut;

        if (amountOut < amountOutMin) {
            revert InsufficientAmountOut();
        }

        if (!fromAssetAddress.isNative() && amountIn != transferFromAmount) {
            revert InvalidAmountIn();
        }

        if (fullAmountIn > 0) {
            emit Swap(fromAddress, toAddress, fromAssetAddress, toAssetAddress, fullAmountIn, amountOut);
        }
    }

    /// @dev See {IMagpieRouterV3-estimateSwapGas}
    function estimateSwapGas(
        bytes calldata
    ) external payable whenNotPaused returns (uint256 amountOut, uint256 gasUsed) {
        SwapData memory swapData = LibRouter.getData();
        address fromAddress = getFromAddress(swapData, true, true);
        if (swapData.hasPermit) {
            LibRouter.permit(swapData, fromAddress);
        }
        LibRouter.transferFees(swapData, fromAddress, swapData.swapFee == 0 ? address(0) : swapFeeAddress);
        (amountOut, gasUsed) = swap(
            swapData,
            fromAddress,
            swapData.amountIn + swapData.swapFee + swapData.affiliateFee
        );
    }

    /// @dev See {IMagpieRouterV3-swapWithMagpieSignature}
    function swapWithMagpieSignature(bytes calldata) external payable whenNotPaused returns (uint256 amountOut) {
        SwapData memory swapData = LibRouter.getData();
        address fromAddress = getFromAddress(swapData, true, true);
        if (swapData.hasPermit) {
            LibRouter.permit(swapData, fromAddress);
        }
        LibRouter.transferFees(swapData, fromAddress, swapData.swapFee == 0 ? address(0) : swapFeeAddress);
        (amountOut, ) = swap(swapData, fromAddress, swapData.amountIn + swapData.swapFee + swapData.affiliateFee);
    }

    /// @dev See {IMagpieRouterV3-swapWithUserSignature}
    function swapWithUserSignature(bytes calldata) external payable onlyInternalCaller returns (uint256 amountOut) {
        SwapData memory swapData = LibRouter.getData();
        if (msg.value > 0) {
            revert InvalidNativeAmount();
        }
        address fromAddress = getFromAddress(swapData, false, true);
        if (swapData.hasPermit) {
            LibRouter.permit(swapData, fromAddress);
        }
        LibRouter.transferFees(swapData, fromAddress, swapData.swapFee == 0 ? address(0) : swapFeeAddress);
        (amountOut, ) = swap(swapData, fromAddress, swapData.amountIn + swapData.swapFee + swapData.affiliateFee);
    }

    /// @dev See {IMagpieRouterV3-swapWithoutSignature}
    function swapWithoutSignature(bytes calldata) external payable onlyBridge returns (uint256 amountOut) {
        SwapData memory swapData = LibRouter.getData();
        address fromAddress = getFromAddress(swapData, true, false);
        (amountOut, ) = swap(swapData, fromAddress, 0);
    }

    /// @dev Prepares CommandData for command iteration.
    function getCommandData()
        private
        pure
        returns (uint16 commandsOffset, uint16 commandsOffsetEnd, uint16 outputsLength)
    {
        assembly {
            commandsOffset := add(70, shr(240, calldataload(68))) // dataOffset + dataLength
            commandsOffsetEnd := add(68, calldataload(36)) // commandsOffsetEnd / swapArgsOffset + swapArgsLength (swapArgsOffset - 32)
            outputsLength := shr(240, calldataload(70)) // dataOffset + 32
        }
    }

    /// @dev Handles the execution of a sequence of commands for the swap operation.
    /// @param fromAddress The address from which the assets will be swapped.
    /// @param fromAssetAddress The address of the asset to be swapped.
    /// @return transferFromAmount The amount transferred from the specified address.
    /// @return gasUsed The amount of gas used during the execution of the swap.
    function execute(
        address fromAddress,
        address fromAssetAddress
    ) private returns (uint256 transferFromAmount, uint256 gasUsed) {
        (uint16 commandsOffset, uint16 commandsOffsetEnd, uint16 outputsLength) = getCommandData();

        uint256 outputPtr;
        assembly {
            outputPtr := mload(0x40)
            mstore(0x40, add(outputPtr, outputsLength))
        }

        uint256 outputOffsetPtr = outputPtr;

        unchecked {
            for (uint256 i = commandsOffset; i < commandsOffsetEnd; ) {
                (transferFromAmount, gasUsed, outputOffsetPtr) = executeCommand(
                    i,
                    fromAddress,
                    fromAssetAddress,
                    outputPtr,
                    outputOffsetPtr,
                    transferFromAmount,
                    gasUsed
                );
                i += 9;
            }
        }

        if (outputOffsetPtr > outputPtr + outputsLength) {
            revert InvalidOutput();
        }
    }

    /// @dev Builds the input for a specific command.
    /// @param i Command data position.
    /// @param outputPtr Memory pointer of the currently available output.
    /// @return input Calculated input data.
    /// @return nativeAmount Native token amount.
    function getInput(uint256 i, uint256 outputPtr) private view returns (bytes memory input, uint256 nativeAmount) {
        assembly {
            let sequencesPositionEnd := shr(240, calldataload(add(i, 5)))

            input := mload(0x40)
            nativeAmount := 0

            let j := shr(240, calldataload(add(i, 3))) // sequencesPosition
            let inputOffsetPtr := add(input, 32)

            for {

            } lt(j, sequencesPositionEnd) {

            } {
                let sequenceType := shr(248, calldataload(j))

                switch sequenceType
                // NativeAmount
                case 0 {
                    switch shr(240, calldataload(add(j, 3)))
                    case 1 {
                        nativeAmount := mload(add(outputPtr, shr(240, calldataload(add(j, 1)))))
                    }
                    default {
                        let p := shr(240, calldataload(add(j, 1)))
                        nativeAmount := shr(shr(248, calldataload(p)), calldataload(add(p, 1)))
                    }
                    j := add(j, 5)
                }
                // Selector
                case 1 {
                    mstore(inputOffsetPtr, calldataload(shr(240, calldataload(add(j, 1)))))
                    inputOffsetPtr := add(inputOffsetPtr, 4)
                    j := add(j, 3)
                }
                // Address
                case 2 {
                    mstore(inputOffsetPtr, shr(96, calldataload(shr(240, calldataload(add(j, 1))))))
                    inputOffsetPtr := add(inputOffsetPtr, 32)
                    j := add(j, 3)
                }
                // Amount
                case 3 {
                    let p := shr(240, calldataload(add(j, 1)))
                    mstore(inputOffsetPtr, shr(shr(248, calldataload(p)), calldataload(add(p, 1))))
                    inputOffsetPtr := add(inputOffsetPtr, 32)
                    j := add(j, 3)
                }
                // Data
                case 4 {
                    let l := shr(240, calldataload(add(j, 3)))
                    calldatacopy(inputOffsetPtr, shr(240, calldataload(add(j, 1))), l)
                    inputOffsetPtr := add(inputOffsetPtr, l)
                    j := add(j, 5)
                }
                // CommandOutput
                case 5 {
                    mstore(inputOffsetPtr, mload(add(outputPtr, shr(240, calldataload(add(j, 1))))))
                    inputOffsetPtr := add(inputOffsetPtr, 32)
                    j := add(j, 3)
                }
                // RouterAddress
                case 6 {
                    mstore(inputOffsetPtr, address())
                    inputOffsetPtr := add(inputOffsetPtr, 32)
                    j := add(j, 1)
                }
                // SenderAddress
                case 7 {
                    mstore(inputOffsetPtr, caller())
                    inputOffsetPtr := add(inputOffsetPtr, 32)
                    j := add(j, 1)
                }
                default {
                    // InvalidSequenceType
                    mstore(0, 0xa90b6fde00000000000000000000000000000000000000000000000000000000)
                    revert(0, 4)
                }
            }

            mstore(input, sub(inputOffsetPtr, add(input, 32)))
            mstore(0x40, inputOffsetPtr)
        }
    }

    /// @dev Executes a command call with the given parameters.
    /// @param i The command data position.
    /// @param outputPtr The pointer to the output location in memory.
    /// @param outputOffsetPtr The pointer to the offset of the output in memory.
    /// @return New outputOffsetPtr position.
    function executeCommandCall(uint256 i, uint256 outputPtr, uint256 outputOffsetPtr) private returns (uint256) {
        bytes memory input;
        uint256 nativeAmount;
        (input, nativeAmount) = getInput(i, outputPtr);
        uint256 outputLength;
        assembly {
            outputLength := shr(240, calldataload(add(i, 1)))

            switch shr(224, mload(add(input, 32))) // selector
            case 0 {
                // InvalidSelector
                mstore(0, 0x7352d91c00000000000000000000000000000000000000000000000000000000)
                revert(0, 4)
            }
            case 0x23b872dd {
                // Blacklist transferFrom in custom calls
                // InvalidTransferFromCall
                mstore(0, 0x1751a8e400000000000000000000000000000000000000000000000000000000)
                revert(0, 4)
            }
            default {
                let targetAddress := shr(96, calldataload(shr(240, calldataload(add(i, 7))))) // targetPosition
                if eq(targetAddress, address()) {
                    // InvalidCall
                    mstore(0, 0xae962d4e00000000000000000000000000000000000000000000000000000000)
                    revert(0, 4)
                }
                if iszero(
                    call(
                        gas(),
                        targetAddress,
                        nativeAmount,
                        add(input, 32),
                        mload(input),
                        outputOffsetPtr,
                        outputLength
                    )
                ) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }
        }
        outputOffsetPtr += outputLength;

        return outputOffsetPtr;
    }

    /// @dev Executes a command approval with the given parameters.
    /// @param i The command data position.
    /// @param outputPtr The pointer to the output location in memory.
    function executeCommandApproval(uint256 i, uint256 outputPtr) private {
        (bytes memory input, ) = getInput(i, outputPtr);

        address self;
        address spender;
        uint256 amount;
        assembly {
            self := mload(add(input, 32))
            spender := mload(add(input, 64))
            amount := mload(add(input, 96))
        }
        self.approve(spender, amount);
    }

    /// @dev Executes a transfer command from a specific address and asset.
    /// @param i The command position.
    /// @param outputPtr The pointer to the output location in memory.
    /// @param fromAssetAddress The address of the asset to transfer from.
    /// @param fromAddress The address to transfer the asset from.
    /// @param transferFromAmount The accumulated amount of the asset to transfer.
    /// @return Accumulated transfer amount.
    function executeCommandTransferFrom(
        uint256 i,
        uint256 outputPtr,
        address fromAssetAddress,
        address fromAddress,
        uint256 transferFromAmount
    ) private returns (uint256) {
        (bytes memory input, ) = getInput(i, outputPtr);

        uint256 amount;
        assembly {
            amount := mload(add(input, 64))
        }
        if (amount > 0) {
            address to;
            assembly {
                to := mload(add(input, 32))
            }
            fromAssetAddress.transferFrom(fromAddress, to, amount);
            transferFromAmount += amount;
        }

        return transferFromAmount;
    }

    /// @dev Executes a transfer command with the given parameters.
    /// @param i The command data position.
    /// @param outputPtr The pointer to the output location in memory.
    function executeCommandTransfer(uint256 i, uint256 outputPtr) private {
        (bytes memory input, ) = getInput(i, outputPtr);

        uint256 amount;
        assembly {
            amount := mload(add(input, 96))
        }
        if (amount > 0) {
            address self;
            address recipient;
            assembly {
                self := mload(add(input, 32))
                recipient := mload(add(input, 64))
            }
            self.transfer(recipient, amount);
        }
    }

    /// @dev Executes a wrap command with the given parameters.
    /// @param i The command data position.
    /// @param outputPtr The pointer to the output location in memory.
    function executeCommandWrap(uint256 i, uint256 outputPtr) private {
        (bytes memory input, ) = getInput(i, outputPtr);

        address self;
        uint256 amount;
        assembly {
            self := mload(add(input, 32))
            amount := mload(add(input, 64))
        }
        self.wrap(amount);
    }

    /// @dev Executes an unwrap command with the given parameters.
    /// @param i The command data position.
    /// @param outputPtr The pointer to the output location in memory.
    function executeCommandUnwrap(uint256 i, uint256 outputPtr) private {
        (bytes memory input, ) = getInput(i, outputPtr);

        address self;
        uint256 amount;
        assembly {
            self := mload(add(input, 32))
            amount := mload(add(input, 64))
        }
        self.unwrap(amount);
    }

    /// @dev Executes a balance command and returns the resulting balance.
    /// @param i The command data position.
    /// @param outputPtr The pointer to the output location in memory.
    /// @param outputOffsetPtr The pointer to the offset of the output in memory.
    /// @return New outputOffsetPtr position.
    function executeCommandBalance(
        uint256 i,
        uint256 outputPtr,
        uint256 outputOffsetPtr
    ) private view returns (uint256) {
        (bytes memory input, ) = getInput(i, outputPtr);

        address self;
        uint256 amount;
        assembly {
            self := mload(add(input, 32))
        }

        amount = self.getBalance();

        assembly {
            mstore(outputOffsetPtr, amount)
        }

        outputOffsetPtr += 32;

        return outputOffsetPtr;
    }

    /// @dev Executes a mathematical command.
    /// @param i The command data position.
    /// @param outputPtr The pointer to the output location in memory.
    /// @param outputOffsetPtr The pointer to the offset of the output in memory.
    /// @return New outputOffsetPtr position.
    function executeCommandMath(uint256 i, uint256 outputPtr, uint256 outputOffsetPtr) private view returns (uint256) {
        (bytes memory input, ) = getInput(i, outputPtr);

        assembly {
            function math(currentInputPtr) -> amount {
                let currentOutputPtr := mload(0x40)
                let j := 0
                let amount0 := 0
                let amount1 := 0
                let operator := 0

                for {

                } lt(j, 10) {

                } {
                    let pos := add(currentInputPtr, mul(j, 3))
                    let amount0Index := shr(248, mload(add(pos, 1)))
                    switch lt(amount0Index, 10)
                    case 1 {
                        amount0 := mload(add(currentOutputPtr, mul(amount0Index, 32)))
                    }
                    default {
                        amount0Index := sub(amount0Index, 10)
                        amount0 := mload(add(add(currentInputPtr, 32), mul(amount0Index, 32)))
                    }
                    let amount1Index := shr(248, mload(add(pos, 2)))
                    switch lt(amount1Index, 10)
                    case 1 {
                        amount1 := mload(add(currentOutputPtr, mul(amount1Index, 32)))
                    }
                    default {
                        amount1Index := sub(amount1Index, 10)
                        amount1 := mload(add(add(currentInputPtr, 32), mul(amount1Index, 32)))
                    }
                    operator := shr(248, mload(pos))

                    switch operator
                    // None
                    case 0 {
                        let finalPtr := add(currentOutputPtr, mul(sub(j, 1), 32))
                        amount := mload(finalPtr)
                        mstore(0x40, add(finalPtr, 32))
                        leave
                    }
                    // Add
                    case 1 {
                        mstore(add(currentOutputPtr, mul(j, 32)), add(amount0, amount1))
                    }
                    // Sub
                    case 2 {
                        mstore(add(currentOutputPtr, mul(j, 32)), sub(amount0, amount1))
                    }
                    // Mul
                    case 3 {
                        mstore(add(currentOutputPtr, mul(j, 32)), mul(amount0, amount1))
                    }
                    // Div
                    case 4 {
                        mstore(add(currentOutputPtr, mul(j, 32)), div(amount0, amount1))
                    }
                    // Pow
                    case 5 {
                        mstore(add(currentOutputPtr, mul(j, 32)), exp(amount0, amount1))
                    }
                    // Abs128
                    case 6 {
                        if gt(amount0, 170141183460469231731687303715884105727) {
                            let mask := sar(127, amount0)
                            amount0 := xor(amount0, mask)
                            amount0 := sub(amount0, mask)
                        }
                        mstore(add(currentOutputPtr, mul(j, 32)), amount0)
                    }
                    // Abs256
                    case 7 {
                        if gt(amount0, 57896044618658097711785492504343953926634992332820282019728792003956564819967) {
                            let mask := sar(255, amount0)
                            amount0 := xor(amount0, mask)
                            amount0 := sub(amount0, mask)
                        }
                        mstore(add(currentOutputPtr, mul(j, 32)), amount0)
                    }
                    // Shr
                    case 8 {
                        mstore(add(currentOutputPtr, mul(j, 32)), shr(amount0, amount1))
                    }
                    // Shl
                    case 9 {
                        mstore(add(currentOutputPtr, mul(j, 32)), shl(amount0, amount1))
                    }

                    j := add(j, 1)
                }

                let finalPtr := add(currentOutputPtr, mul(9, 32))
                amount := mload(finalPtr)
                mstore(0x40, add(finalPtr, 32))
            }

            mstore(outputOffsetPtr, math(add(input, 32)))
        }

        outputOffsetPtr += 32;

        return outputOffsetPtr;
    }

    /// @dev Executes a comparison command.
    /// @param i The command data position.
    /// @param outputPtr The pointer to the output location in memory.
    /// @param outputOffsetPtr The pointer to the offset of the output in memory.
    /// @return New outputOffsetPtr position.
    function executeCommandComparison(
        uint256 i,
        uint256 outputPtr,
        uint256 outputOffsetPtr
    ) private view returns (uint256) {
        (bytes memory input, ) = getInput(i, outputPtr);

        assembly {
            function comparison(currentInputPtr) -> amount {
                let currentOutputPtr := mload(0x40)
                let j := 0
                let amount0 := 0
                let amount1 := 0
                let amount2 := 0
                let amount3 := 0
                let operator := 0

                for {

                } lt(j, 6) {

                } {
                    let pos := add(currentInputPtr, mul(j, 5))
                    let amount0Index := shr(248, mload(add(pos, 1)))
                    switch lt(amount0Index, 6)
                    case 1 {
                        amount0 := mload(add(currentOutputPtr, mul(amount0Index, 32)))
                    }
                    default {
                        amount0Index := sub(amount0Index, 6)
                        amount0 := mload(add(add(currentInputPtr, 32), mul(amount0Index, 32)))
                    }
                    let amount1Index := shr(248, mload(add(pos, 2)))
                    switch lt(amount1Index, 6)
                    case 1 {
                        amount1 := mload(add(currentOutputPtr, mul(amount1Index, 32)))
                    }
                    default {
                        amount1Index := sub(amount1Index, 6)
                        amount1 := mload(add(add(currentInputPtr, 32), mul(amount1Index, 32)))
                    }
                    let amount2Index := shr(248, mload(add(pos, 3)))
                    switch lt(amount2Index, 6)
                    case 1 {
                        amount2 := mload(add(currentOutputPtr, mul(amount2Index, 32)))
                    }
                    default {
                        amount2Index := sub(amount2Index, 6)
                        amount2 := mload(add(add(currentInputPtr, 32), mul(amount2Index, 32)))
                    }
                    let amount3Index := shr(248, mload(add(pos, 4)))
                    switch lt(amount3Index, 6)
                    case 1 {
                        amount3 := mload(add(currentOutputPtr, mul(amount3Index, 32)))
                    }
                    default {
                        amount3Index := sub(amount3Index, 6)
                        amount3 := mload(add(add(currentInputPtr, 32), mul(amount3Index, 32)))
                    }
                    operator := shr(248, mload(pos))

                    switch operator
                    // None
                    case 0 {
                        let finalPtr := add(currentOutputPtr, mul(sub(j, 1), 32))
                        amount := mload(finalPtr)
                        mstore(0x40, add(finalPtr, 32))
                        leave
                    }
                    // Lt
                    case 1 {
                        switch lt(amount0, amount1)
                        case 1 {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount2)
                        }
                        default {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount3)
                        }
                    }
                    // Lte
                    case 2 {
                        switch or(lt(amount0, amount1), eq(amount0, amount1))
                        case 1 {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount2)
                        }
                        default {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount3)
                        }
                    }
                    // Gt
                    case 3 {
                        switch gt(amount0, amount1)
                        case 1 {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount2)
                        }
                        default {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount3)
                        }
                    }
                    // Gte
                    case 4 {
                        switch or(gt(amount0, amount1), eq(amount0, amount1))
                        case 1 {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount2)
                        }
                        default {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount3)
                        }
                    }
                    // Eq
                    case 5 {
                        switch eq(amount0, amount1)
                        case 1 {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount2)
                        }
                        default {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount3)
                        }
                    }
                    // Ne
                    case 6 {
                        switch eq(amount0, amount1)
                        case 1 {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount3)
                        }
                        default {
                            mstore(add(currentOutputPtr, mul(j, 32)), amount2)
                        }
                    }

                    j := add(j, 1)
                }

                let finalPtr := add(currentOutputPtr, mul(5, 32))
                amount := mload(finalPtr)
                mstore(0x40, add(finalPtr, 32))
            }

            mstore(outputOffsetPtr, comparison(add(input, 32)))
        }

        outputOffsetPtr += 32;

        return outputOffsetPtr;
    }

    /// @dev Handles the execution of the specified command commands for the swap operation.
    /// @param i The command data position.
    /// @param fromAddress The wallet / contract of the fromAssetAddress.
    /// @param fromAssetAddress The asset will be transfered from the user.
    /// @param outputPtr Starting position of the output memory pointer.
    /// @param outputOffsetPtr Current position of the output memory pointer.
    /// @param transferFromAmount Accumulated transferred amount.
    /// @param gasUsed Recorded gas between commands.
    function executeCommand(
        uint256 i,
        address fromAddress,
        address fromAssetAddress,
        uint256 outputPtr,
        uint256 outputOffsetPtr,
        uint256 transferFromAmount,
        uint256 gasUsed
    ) private returns (uint256, uint256, uint256) {
        CommandAction commandAction;
        assembly {
            commandAction := shr(248, calldataload(i))
        }

        if (commandAction == CommandAction.Call) {
            outputOffsetPtr = executeCommandCall(i, outputPtr, outputOffsetPtr);
        } else if (commandAction == CommandAction.Approval) {
            executeCommandApproval(i, outputPtr);
        } else if (commandAction == CommandAction.TransferFrom) {
            transferFromAmount = executeCommandTransferFrom(
                i,
                outputPtr,
                fromAssetAddress,
                fromAddress,
                transferFromAmount
            );
        } else if (commandAction == CommandAction.Transfer) {
            executeCommandTransfer(i, outputPtr);
        } else if (commandAction == CommandAction.Wrap) {
            executeCommandWrap(i, outputPtr);
        } else if (commandAction == CommandAction.Unwrap) {
            executeCommandUnwrap(i, outputPtr);
        } else if (commandAction == CommandAction.Balance) {
            outputOffsetPtr = executeCommandBalance(i, outputPtr, outputOffsetPtr);
        } else if (commandAction == CommandAction.Math) {
            outputOffsetPtr = executeCommandMath(i, outputPtr, outputOffsetPtr);
        } else if (commandAction == CommandAction.Comparison) {
            outputOffsetPtr = executeCommandComparison(i, outputPtr, outputOffsetPtr);
        } else if (commandAction == CommandAction.EstimateGasStart) {
            gasUsed = gasleft();
        } else if (commandAction == CommandAction.EstimateGasEnd) {
            gasUsed -= gasleft();
        } else {
            revert InvalidCommand();
        }

        return (transferFromAmount, gasUsed, outputOffsetPtr);
    }

    /// @dev Used to receive ethers
    receive() external payable {}
}