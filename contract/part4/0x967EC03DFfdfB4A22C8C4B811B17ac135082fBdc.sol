// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import { ISymbiosisRouter } from "../interfaces/ISymbiosisRouter.sol";
import "../lib/DataTypes.sol";
import "../dexs/SwitchV2.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SwitchSymbiosis is SwitchV2 {
    using UniversalERC20 for IERC20;
    using SafeERC20 for IERC20;
    address public symbiosisRouter;
    address public symbiosisGateway;
    address public nativeWrap;

    struct SymbiosisMetaRouteData {
        bytes firstSwapCalldata;
        bytes secondSwapCalldata;
        address[] approvedTokens;
        address firstDexRouter;
        address secondDexRouter;
        uint256 amount;
        bool nativeIn;
        address relayRecipient;
        bytes otherSideCalldata;
    }

    struct TransferArgsSymbiosis {
        address fromToken;
        address destToken;
        address symbiosisMaker;
        address partner;
        uint256 partnerFeeRate;
        uint256 amount;
        uint256 estimatedDstTokenAmount;
        uint64 dstChainId;
        bytes32 id;
        bytes32 bridge;
        SymbiosisMetaRouteData symbiosisData;
    }

    struct SwapArgsSymbiosis {
        address fromToken;
        address bridgeToken;
        address destToken;
        address symbiosisMaker;
        address partner;
        uint256 partnerFeeRate;
        uint256 amount;
        uint256 estimatedDstTokenAmount;
        uint256 dstChainId;
        uint256[] srcDistribution;
        bytes32 id;
        bytes32 bridge;
        SymbiosisMetaRouteData symbiosisData;
        bytes aggregatorInfo;
    }

    event SymbiosisRouterSet(address symbiosisRouter);
    event SymbiosisGatewaySet(address symbiosisGateway);
    event NativeWrapSet(address _nativeWrap);

    constructor(
        address _weth,
        address _otherToken,
        uint256[] memory _pathCountAndSplit,
        address[] memory _factories,
        address _switchViewAddress,
        address _switchEventAddress,
        address _symbiosisRouter,
        address _symbiosisGateway,
        address _feeCollector
    ) SwitchV2(
        _weth,
        _otherToken,
        _pathCountAndSplit[0],
        _pathCountAndSplit[1],
        _factories,
        _switchViewAddress,
        _switchEventAddress,
        _feeCollector
    )
        public
    {
        symbiosisRouter = _symbiosisRouter;
        symbiosisGateway = _symbiosisGateway;
        nativeWrap = _weth;
    }

    function setSymbiosisRouter(address _symbiosisRouter) external onlyOwner {
        symbiosisRouter = _symbiosisRouter;
        emit SymbiosisRouterSet(_symbiosisRouter);
    }

    function setSymbiosisGateway(address _symbiosisGateWay) external onlyOwner {
        symbiosisGateway = _symbiosisGateWay;
        emit SymbiosisGatewaySet(_symbiosisGateWay);
    }

    function setNativeWrap(address _newNativeWrap) external onlyOwner {
        nativeWrap = _newNativeWrap;
        emit NativeWrapSet(nativeWrap);
    }

    function transferBySymbiosis(
        TransferArgsSymbiosis calldata transferArgs
    )
        external
        payable
        nonReentrant
    {
        require(transferArgs.amount > 0, "The amount must be greater than zero");
        require(block.chainid != transferArgs.dstChainId, "Cannot bridge to same network");

        IERC20(transferArgs.fromToken).universalTransferFrom(msg.sender, address(this), transferArgs.amount);
        uint256 amountAfterFee = _getAmountAfterFee(
            IERC20(transferArgs.fromToken),
            transferArgs.amount,
            transferArgs.partner,
            transferArgs.partnerFeeRate
        );
        bool isNative = IERC20(transferArgs.fromToken).isETH();
        if (isNative) {
            ISymbiosisRouter(symbiosisRouter).metaRoute{value: amountAfterFee}(
                ISymbiosisRouter.MetaRouteTransaction(
                    transferArgs.symbiosisData.firstSwapCalldata,
                    transferArgs.symbiosisData.secondSwapCalldata,
                    transferArgs.symbiosisData.approvedTokens,
                    transferArgs.symbiosisData.firstDexRouter,
                    transferArgs.symbiosisData.secondDexRouter,
                    amountAfterFee,
                    transferArgs.symbiosisData.nativeIn,
                    transferArgs.symbiosisData.relayRecipient,
                    transferArgs.symbiosisData.otherSideCalldata
                )
            );
        } else {
            // Give Symbiosis bridge approval
            IERC20(transferArgs.fromToken).safeApprove(symbiosisGateway, 0);
            IERC20(transferArgs.fromToken).safeApprove(symbiosisGateway, amountAfterFee);

            ISymbiosisRouter(symbiosisRouter).metaRoute(
                ISymbiosisRouter.MetaRouteTransaction(
                    transferArgs.symbiosisData.firstSwapCalldata,
                    transferArgs.symbiosisData.secondSwapCalldata,
                    transferArgs.symbiosisData.approvedTokens,
                    transferArgs.symbiosisData.firstDexRouter,
                    transferArgs.symbiosisData.secondDexRouter,
                    amountAfterFee,
                    transferArgs.symbiosisData.nativeIn,
                    transferArgs.symbiosisData.relayRecipient,
                    transferArgs.symbiosisData.otherSideCalldata
                )
            );

        }

        _emitCrossChainTransferRequest(
            transferArgs,
            bytes32(0),
            amountAfterFee,
            msg.sender,
            DataTypes.SwapStatus.Succeeded
        );
    }

    function swapBySymbiosis(
        SwapArgsSymbiosis calldata swapArgs
    )
        external
        payable
        nonReentrant
    {
        require(swapArgs.amount > 0, "The amount must be greater than zero");
        require(block.chainid != swapArgs.dstChainId, "Cannot bridge to same network");

        IERC20(swapArgs.fromToken).universalTransferFrom(msg.sender, address(this), swapArgs.amount);
        uint256 returnAmount = 0;
        uint256 amountAfterFee = _getAmountAfterFee(
            IERC20(swapArgs.fromToken),
            swapArgs.amount,
            swapArgs.partner,
            swapArgs.partnerFeeRate
        );

        address bridgeToken = swapArgs.bridgeToken;
        if (swapArgs.fromToken == swapArgs.bridgeToken) {
            returnAmount = amountAfterFee;
        } else {
            if (swapArgs.aggregatorInfo.length > 0) {
                returnAmount = _swapThruAggregator(swapArgs, amountAfterFee);
            } else {
                (returnAmount, ) = _swapBeforeSymbiosis(swapArgs, amountAfterFee);
            }
        }

        bool isNativeBridgeToken = IERC20(swapArgs.bridgeToken).isETH();

        if (isNativeBridgeToken) {
            ISymbiosisRouter(symbiosisRouter).metaRoute{value: returnAmount}(
                ISymbiosisRouter.MetaRouteTransaction(
                    swapArgs.symbiosisData.firstSwapCalldata,
                    swapArgs.symbiosisData.secondSwapCalldata,
                    swapArgs.symbiosisData.approvedTokens,
                    swapArgs.symbiosisData.firstDexRouter,
                    swapArgs.symbiosisData.secondDexRouter,
                    returnAmount,
                    swapArgs.symbiosisData.nativeIn,
                    swapArgs.symbiosisData.relayRecipient,
                    swapArgs.symbiosisData.otherSideCalldata
                )
            );
        } else {
            IERC20(bridgeToken).universalApprove(symbiosisGateway, returnAmount);
            ISymbiosisRouter(symbiosisRouter).metaRoute(
                ISymbiosisRouter.MetaRouteTransaction(
                    swapArgs.symbiosisData.firstSwapCalldata,
                    swapArgs.symbiosisData.secondSwapCalldata,
                    swapArgs.symbiosisData.approvedTokens,
                    swapArgs.symbiosisData.firstDexRouter,
                    swapArgs.symbiosisData.secondDexRouter,
                    returnAmount,
                    swapArgs.symbiosisData.nativeIn,
                    swapArgs.symbiosisData.relayRecipient,
                    swapArgs.symbiosisData.otherSideCalldata
                )
            );
        }

        _emitCrossChainSwapRequest(
            swapArgs,
            bytes32(0),
            returnAmount,
            msg.sender,
            DataTypes.SwapStatus.Succeeded
        );
    }

    function _swapBeforeSymbiosis(
        SwapArgsSymbiosis calldata swapArgs,
        uint256 amount
    )
        private
        returns
    (
        uint256 returnAmount,
        uint256 parts
    )
    {
        parts = 0;
        uint256 lastNonZeroIndex = 0;
        for (uint i = 0; i < swapArgs.srcDistribution.length; i++) {
            if (swapArgs.srcDistribution[i] > 0) {
                parts += swapArgs.srcDistribution[i];
                lastNonZeroIndex = i;
            }
        }

        require(parts > 0, "invalid distribution param");

        // break function to avoid stack too deep error
        returnAmount = _swapInternalForSingleSwap(
            swapArgs.srcDistribution,
            amount,
            parts,
            lastNonZeroIndex,
            IERC20(swapArgs.fromToken),
            IERC20(swapArgs.bridgeToken)
        );
        require(returnAmount > 0, "Swap failed from dex");

        switchEvent.emitSwapped(
            msg.sender,
            address(this),
            IERC20(swapArgs.fromToken),
            IERC20(swapArgs.bridgeToken),
            amount,
            returnAmount,
            0
        );
    }

    function _swapThruAggregator(
        SwapArgsSymbiosis calldata swapArgs,
        uint256 amount
    )
        private
        returns (uint256 returnAmount)
    {
        // break function to avoid stack too deep error
        returnAmount = _swapInternalWithAggregator(
            IERC20(swapArgs.fromToken),
            IERC20(swapArgs.bridgeToken),
            amount,
            address(this),
            swapArgs.aggregatorInfo
        );
    }

    function _emitCrossChainTransferRequest(
        TransferArgsSymbiosis calldata transferArgs,
        bytes32 transferId,
        uint256 returnAmount,
        address sender,
        DataTypes.SwapStatus status
    )
        internal
    {
        switchEvent.emitCrosschainSwapRequest(
            transferArgs.id,
            transferId,
            transferArgs.bridge,
            sender,
            transferArgs.fromToken,
            transferArgs.fromToken,
            transferArgs.destToken,
            transferArgs.amount,
            returnAmount,
            transferArgs.estimatedDstTokenAmount,
            status
        );
    }

    function _emitCrossChainSwapRequest(
        SwapArgsSymbiosis calldata swapArgs,
        bytes32 transferId,
        uint256 returnAmount,
        address sender,
        DataTypes.SwapStatus status
    )
        internal
    {
        switchEvent.emitCrosschainSwapRequest(
            swapArgs.id,
            transferId,
            swapArgs.bridge,
            sender,
            swapArgs.fromToken,
            swapArgs.bridgeToken,
            swapArgs.destToken,
            swapArgs.amount,
            returnAmount,
            swapArgs.estimatedDstTokenAmount,
            status
        );
    }
}