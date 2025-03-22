// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable2Step} from "openzeppelin-solidity/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin-solidity/contracts/security/Pausable.sol";
import {Address} from "openzeppelin-solidity/contracts/utils/Address.sol";
import {IMagpieStargateBridgeV3} from "./interfaces/IMagpieStargateBridgeV3.sol";
import {LibAsset} from "./libraries/LibAsset.sol";
import {LibBridge, DepositData, SwapData} from "./libraries/LibBridge.sol";
import {LibRouter, SwapData} from "./libraries/LibRouter.sol";
import {IStargate, MessagingFee, Ticket} from "./interfaces/stargate/IStargate.sol";
import {MessagingFee, OFTReceipt, SendParam} from "./interfaces/stargate/IOFT.sol";

error InvalidCaller();
error ReentrancyError();
error DepositIsNotFound();
error InvalidFrom();
error InvalidStargateAddress();
error InvalidAddress();

contract MagpieStargateBridgeV3 is IMagpieStargateBridgeV3, Ownable2Step, Pausable {
    using LibAsset for address;

    mapping(address => bool) public internalCaller;
    address public weth;
    bytes32 public networkIdAndRouterAddress;
    uint64 public swapSequence;
    mapping(bytes32 => mapping(address => uint256)) public deposit;
    mapping(address => address) public assetToStargate;
    mapping(address => address) public stargateToAsset;
    address public swapFeeAddress;
    address public lzAddress;

    /// @dev Restricts swap functions with signatures to only be called by whitelisted internal caller.
    modifier onlyInternalCaller() {
        if (!internalCaller[msg.sender]) {
            revert InvalidCaller();
        }
        _;
    }

    /// @dev See {IMagpieStargateBridgeV3-updateInternalCaller}
    function updateInternalCaller(address caller, bool value) external onlyOwner {
        internalCaller[caller] = value;

        emit UpdateInternalCaller(msg.sender, caller, value);
    }

    /// @dev See {IMagpieStargateBridgeV3-updateWeth}
    function updateWeth(address value) external onlyOwner {
        weth = value;
    }

    /// @dev See {IMagpieStargateBridgeV3-updateNetworkIdAndRouterAddress}
    function updateNetworkIdAndRouterAddress(bytes32 value) external onlyOwner {
        networkIdAndRouterAddress = value;
    }

    /// @dev See {IMagpieStargateBridgeV3-updateAssetToStargate}
    function updateAssetToStargate(address assetAddress, address stargateAddress) external onlyOwner {
        assetToStargate[assetAddress] = stargateAddress;

        emit UpdateAssetToStargate(msg.sender, assetAddress, stargateAddress);
    }

    /// @dev See {IMagpieStargateBridgeV3-updateStargateToAsset}
    function updateStargateToAsset(address stargateAddress, address assetAddress) external onlyOwner {
        stargateToAsset[stargateAddress] = assetAddress;

        emit UpdateStargateToAsset(msg.sender, stargateAddress, assetAddress);
    }

    /// @dev See {IMagpieStargateBridgeV3-updateSwapFeeAddress}
    function updateSwapFeeAddress(address value) external onlyOwner {
        swapFeeAddress = value;
    }

    /// @dev See {IMagpieStargateBridgeV3-updateLzAddress}
    function updateLzAddress(address value) external onlyOwner {
        lzAddress = value;
    }

    /// @dev See {IMagpieStargateBridgeV3-pause}
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /// @dev See {IMagpieStargateBridgeV3-unpause}
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }

    /// @dev See {IMagpieStargateBridgeV3-swapInWithMagpieSignature}
    function swapInWithMagpieSignature(bytes calldata) external payable whenNotPaused returns (uint256 amountOut) {
        SwapData memory swapData = LibRouter.getData();
        amountOut = swapIn(swapData, true);
    }

    /// @dev See {IMagpieStargateBridgeV3-swapInWithUserSignature}
    function swapInWithUserSignature(bytes calldata) external payable onlyInternalCaller returns (uint256 amountOut) {
        SwapData memory swapData = LibRouter.getData();
        if (swapData.fromAssetAddress.isNative()) {
            revert InvalidAddress();
        }
        amountOut = swapIn(swapData, false);
    }

    /// @dev Verifies the signature for a swap operation.
    /// @param swapData The SwapData struct containing swap details.
    /// @param useCaller Flag indicating whether to use the caller's address for verification.
    /// @return signer The address of the signer if the signature is valid.
    function verifySignature(SwapData memory swapData, bool useCaller) private view returns (address) {
        uint256 messagePtr;
        bool hasAffiliate = swapData.hasAffiliate;
        uint256 swapMessageLength = hasAffiliate ? 384 : 320;
        uint256 messageLength = swapMessageLength + 288;
        assembly {
            messagePtr := mload(0x40)
            mstore(0x40, add(messagePtr, messageLength))
            // hasAffiliate
            switch hasAffiliate
            case 1 {
                // keccak256("Swap(address srcBridge,address srcSender,address srcRecipient,address srcFromAsset,address srcToAsset,uint256 srcDeadline,uint256 srcAmountOutMin,uint256 srcSwapFee,uint256 srcAmountIn,address affiliate,uint256 affiliateFee,bytes32 dstRecipient,bytes32 dstFromAsset,bytes32 dstToAsset,uint256 dstAmountOutMin,uint256 dstSwapFee,uint16 dstNetworkId,bytes32 dstBridge,uint32 bridgeEid,uint128 bridgeGasLimit)")
                mstore(messagePtr, 0x07027edd06d933ad801aa68db7f468ac156371697ee92619cb7c9fc17182dd5d)
            }
            default {
                // keccak256("Swap(address srcBridge,address srcSender,address srcRecipient,address srcFromAsset,address srcToAsset,uint256 srcDeadline,uint256 srcAmountOutMin,uint256 srcSwapFee,uint256 srcAmountIn,bytes32 dstRecipient,bytes32 dstFromAsset,bytes32 dstToAsset,uint256 dstAmountOutMin,uint256 dstSwapFee,uint16 dstNetworkId,bytes32 dstBridge,uint32 bridgeEid,uint128 bridgeGasLimit)")
                mstore(messagePtr, 0x1db1b92ed04ecdb7f72b6c3262412f537c913b3092d701262b450e81e0ea1298)
            }

            let bridgeDataPosition := shr(240, calldataload(add(66, calldataload(36))))
            let currentMessagePtr := add(messagePtr, swapMessageLength)
            mstore(currentMessagePtr, calldataload(bridgeDataPosition)) // toAddress
            currentMessagePtr := add(currentMessagePtr, 32)
            mstore(currentMessagePtr, calldataload(add(bridgeDataPosition, 32))) // fromAssetAddress
            currentMessagePtr := add(currentMessagePtr, 32)
            mstore(currentMessagePtr, calldataload(add(bridgeDataPosition, 64))) // toAssetAddress
            currentMessagePtr := add(currentMessagePtr, 32)
            mstore(currentMessagePtr, calldataload(add(bridgeDataPosition, 96))) // amountOutMin
            currentMessagePtr := add(currentMessagePtr, 32)
            mstore(currentMessagePtr, calldataload(add(bridgeDataPosition, 128))) // swapFee
            currentMessagePtr := add(currentMessagePtr, 32)
            mstore(currentMessagePtr, shr(240, calldataload(add(bridgeDataPosition, 160)))) // recipientNetworkId
            currentMessagePtr := add(currentMessagePtr, 32)
            mstore(currentMessagePtr, calldataload(add(bridgeDataPosition, 162))) // recipientAddress

            currentMessagePtr := add(currentMessagePtr, 32)
            mstore(currentMessagePtr, shr(224, calldataload(add(bridgeDataPosition, 194)))) // dstEid
            currentMessagePtr := add(currentMessagePtr, 32)
            mstore(currentMessagePtr, shr(128, calldataload(add(bridgeDataPosition, 198)))) // gasLimit
        }

        return
            LibRouter.verifySignature(
                // keccak256(bytes("Magpie Stargate Bridge")),
                0x5849a3e6bffd5f0e36a7aae05a726cce29f47268bb265a1987242a08e94dc59e,
                // keccak256(bytes("3")),
                0x2a80e1ef1d7842f27f2e6be0972bb708b9a135c38860dbe73c27c3486c34f4de,
                swapData,
                messagePtr,
                messageLength,
                useCaller,
                2
            );
    }

    /// @dev Executes an inbound swap operation.
    /// @param useCaller Flag indicating whether to use the caller's address for the swap.
    /// @return amountOut The amount received as output from the swap operation.
    function swapIn(SwapData memory swapData, bool useCaller) private returns (uint256 amountOut) {
        swapSequence++;
        uint64 currentSwapSequence = swapSequence;

        uint16 networkId;
        address routerAddress;

        assembly {
            let currentNetworkIdAndRouterAddress := sload(networkIdAndRouterAddress.slot)
            networkId := shr(240, currentNetworkIdAndRouterAddress)
            routerAddress := shr(16, shl(16, currentNetworkIdAndRouterAddress))
        }

        address fromAddress = verifySignature(swapData, useCaller);

        if (swapData.hasPermit) {
            LibRouter.permit(swapData, fromAddress);
        }
        LibRouter.transferFees(swapData, fromAddress, swapData.swapFee == 0 ? address(0) : swapFeeAddress);

        bytes memory encodedDepositData = new bytes(236); // 194 + 42
        LibBridge.fillEncodedDepositData(encodedDepositData, networkId, currentSwapSequence);
        bytes32 depositDataHash = keccak256(encodedDepositData);

        amountOut = LibBridge.swapIn(swapData, encodedDepositData, fromAddress, routerAddress, weth);

        bridgeIn(
            LibBridge.getFee(swapData),
            fromAddress,
            swapData.toAssetAddress,
            amountOut,
            swapData.amountOutMin,
            depositDataHash
        );

        if (currentSwapSequence != swapSequence) {
            revert ReentrancyError();
        }
    }

    /// @dev Retrieves extra options for SendParam, encoded as bytes.
    /// @param gasLimit The gas limit to be included in the extra options.
    /// @return optionsBytes The encoded extra options as bytes.
    function getExtraOptions(uint128 gasLimit) private pure returns (bytes memory) {
        uint16 type3 = 3;
        uint8 workerId = 1;
        uint16 index = 0;
        uint8 optionType = 3;
        uint16 optionLength = 19; // uint16 + uint128 + 1
        return abi.encodePacked(type3, workerId, optionLength, optionType, index, gasLimit);
    }

    /// @dev Constructs a SendParam struct with specified amount and encoded deposit data.
    /// @param amount The amount to be sent.
    /// @param amountMin The minimum amount to be sent.
    /// @param depositDataHash Encoded hash related to the crosschain transaction.
    /// @return sendParam The constructed SendParam struct.
    function getSendParam(
        uint256 amount,
        uint256 amountMin,
        bytes32 depositDataHash
    ) private pure returns (SendParam memory) {
        bytes32 receiver;
        uint32 dstEid;
        uint128 gasLimit;
        assembly {
            let bridgeDataPosition := shr(240, calldataload(add(66, calldataload(36))))

            receiver := calldataload(add(bridgeDataPosition, 162))
            dstEid := shr(224, calldataload(add(bridgeDataPosition, 194)))
            gasLimit := shr(128, calldataload(add(bridgeDataPosition, 198)))
        }

        return
            SendParam({
                dstEid: dstEid,
                to: receiver,
                amountLD: amount,
                minAmountLD: amountMin,
                extraOptions: getExtraOptions(gasLimit),
                composeMsg: LibBridge.encodeDepositDataHash(depositDataHash),
                oftCmd: ""
            });
    }

    /// @dev Bridges an inbound asset transfer into the contract.
    /// @param bridgeFee Bridge fee that has to be payed in native token.
    /// @param refundAddress If the operation fails, tokens will be transferred to this address.
    /// @param toAssetAddress The address of the asset being bridged into the contract.
    /// @param amount The amount of the asset being transferred into the contract.
    /// @param amountMin The minimum amount of the asset being transferred into the contract.
    /// @param depositDataHash Encoded hash related to the crosschain transaction.
    function bridgeIn(
        uint256 bridgeFee,
        address refundAddress,
        address toAssetAddress,
        uint256 amount,
        uint256 amountMin,
        bytes32 depositDataHash
    ) private {
        address currentStargateAddress = assetToStargate[toAssetAddress];

        if (currentStargateAddress == address(0)) {
            revert InvalidStargateAddress();
        }

        uint256 valueToSend = bridgeFee;

        if (toAssetAddress.isNative()) {
            valueToSend += amount;
        } else {
            toAssetAddress.approve(currentStargateAddress, amount);
        }

        SendParam memory sendParam = getSendParam(amount, amountMin, depositDataHash);
        IStargate(currentStargateAddress).sendToken{value: valueToSend}(
            sendParam,
            MessagingFee({nativeFee: bridgeFee, lzTokenFee: 0}),
            refundAddress
        );
    }

    /// @dev See {IMagpieStargateBridgeV3-swapOut}
    function swapOut(bytes calldata) external onlyInternalCaller returns (uint256 amountOut) {
        address routerAddress;
        uint16 networkId;
        assembly {
            let currentNetworkIdAndRouterAddress := sload(networkIdAndRouterAddress.slot)
            networkId := shr(240, currentNetworkIdAndRouterAddress)
            routerAddress := shr(16, shl(16, currentNetworkIdAndRouterAddress))
        }

        SwapData memory swapData = LibRouter.getData();
        bytes32 depositDataHash = LibBridge.getDepositDataHash(swapData, networkId, address(this));
        uint256 depositAmount = deposit[depositDataHash][swapData.fromAssetAddress];

        if (depositAmount == 0) {
            revert DepositIsNotFound();
        }

        deposit[depositDataHash][swapData.fromAssetAddress] = 0;

        amountOut = LibBridge.swapOut(swapData, depositAmount, depositDataHash, routerAddress, weth, swapFeeAddress);
    }

    // @dev Extracts and returns the deposit amount from the encoded bytes.
    // @param encodedAmount The bytes array containing the encoded amount.
    // @return amount The decoded uint256 deposit amount.
    function getDepositAmount(bytes memory encodedAmount) private pure returns (uint256 amount) {
        assembly {
            amount := mload(add(encodedAmount, 32))
        }
    }

    event Deposit(bytes32 depositDataHash, uint256 amount);

    /// @dev See {IMagpieStargateBridgeV3-lzCompose}
    function lzCompose(address from, bytes32, bytes calldata message, address, bytes calldata) external payable {
        address assetAddress = stargateToAsset[from];
        if (assetToStargate[assetAddress] != from) {
            revert InvalidFrom();
        }
        if (msg.sender != lzAddress) {
            revert InvalidCaller();
        }

        bytes32 depositDataHash = LibBridge.decodeDepositDataHash(message[76:]);
        uint256 currentDeposit = deposit[depositDataHash][assetAddress] + getDepositAmount(message[12:44]);

        deposit[depositDataHash][assetAddress] += currentDeposit;

        emit Deposit(depositDataHash, currentDeposit);
    }

    /// @dev See {IMagpieStargateBridgeV3-multicall}
    function multicall(bytes[] calldata data) external onlyOwner returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }

    /// @dev Used to receive ethers
    receive() external payable {}
}