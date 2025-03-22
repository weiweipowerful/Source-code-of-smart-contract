// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.17;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC2771Context } from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

import { IWrappedNative } from "./IWrappedNative.sol";
import { VM } from "./weiroll/VM.sol";
import { PreventTampering } from "./PreventTampering.sol";

import { ZapParams, ZapERC20Params } from "./IRTokenZapper.sol";
import { ZapperExecutor, DeployFolioConfig, ExecuteDeployOutput } from "./ZapperExecutor.sol";

struct ZapperOutput {
    uint256[] dust;
    uint256 amountOut;
    uint256 gasUsed;
}

contract Zapper2 is ReentrancyGuard {
    IWrappedNative internal immutable wrappedNative;
    ZapperExecutor internal immutable zapperExecutor;

    constructor(
        IWrappedNative wrappedNative_,
        ZapperExecutor executor_
    ) {
        wrappedNative = wrappedNative_;
        zapperExecutor = executor_;
    }

    receive() external payable {}

    function zap(ZapParams calldata params) external payable nonReentrant returns (ZapperOutput memory) {
        uint256 startGas = gasleft();
        return zapInner(params, balanceOf(params.tokenOut, params.recipient), startGas);
    }
    function zapDeploy(
        ZapParams calldata params,
        DeployFolioConfig calldata config,
        bytes32 nonce
    ) external payable nonReentrant returns (ZapperOutput memory out) {
        uint256 startGas = gasleft();
        pullFundsFromSender(params.tokenIn, params.amountIn, address(zapperExecutor));
        // STEP 1: Execute
        ExecuteDeployOutput memory deployOutput = zapperExecutor.executeDeploy(
            params.commands,
            params.state,
            params.tokens,
            config,
            params.recipient,
            nonce
        );
        out.amountOut = deployOutput.amountOut;
        out.dust = deployOutput.dust;

        require(out.amountOut > params.amountOut, "INSUFFICIENT_OUT");


        out.gasUsed = startGas - gasleft();
    }
    function validateTokenOut(address tokenOut) private {
        uint256 codeSizeTokenOut = 0;
        assembly {
            codeSizeTokenOut := extcodesize(tokenOut)
        }
        require(codeSizeTokenOut == 0, "RETRY");
    }

    function zapInner(ZapParams memory params, uint256 initialBalance, uint256 startGas) private returns (ZapperOutput memory out) {
        require(params.amountIn != 0, "INVALID_INPUT_AMOUNT");
        require(params.amountOut != 0, "INVALID_OUTPUT_AMOUNT");

        pullFundsFromSender(params.tokenIn, params.amountIn, address(zapperExecutor));
        // STEP 1: Execute
        out.dust = zapperExecutor.execute(
            params.commands,
            params.state,
            params.tokens
        ).dust;

        // STEP 2: Verify that the user has gotten the tokens they requested
        uint256 newBalance = balanceOf(params.tokenOut, params.recipient);
        require(newBalance > initialBalance, "INVALID_NEW_BALANCE");
        uint256 difference = newBalance - initialBalance;
        require(difference >= params.amountOut, "INSUFFICIENT_OUT");

        out.amountOut = difference;
        out.gasUsed = startGas - gasleft();
    }

    function pullFundsFromSender(
        address token,
        uint256 amount,
        address to
    ) private {
        if (token != address(0)) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, to, amount);
        } else {
            require(msg.value >= amount, "INSUFFICIENT_ETH");
            wrappedNative.deposit{ value: amount }();
            SafeERC20.safeTransfer(IERC20(address(wrappedNative)), to, amount);
        }   
    }


    function balanceOf(address token, address account) private view returns (uint256) {
        if (token != address(0)) {
            // Check if token address contains bytecode
            return IERC20(token).balanceOf(account);
        } else {
            return account.balance;
        }
    }


    /** Stubs for old interface  */
    function translateOldStyleZap(ZapERC20Params calldata params) private returns (ZapperOutput memory) {
        uint256 startGas = gasleft();
        ZapParams memory zapParams = ZapParams({
            tokenIn: address(params.tokenIn),
            amountIn: params.amountIn,
            commands: params.commands,
            state: params.state,
            tokens: params.tokens,
            amountOut: params.amountOut,
            tokenOut: address(params.tokenOut),
            recipient: msg.sender
        });

        return zapInner(zapParams, balanceOf(address(params.tokenOut), msg.sender), startGas);
    }

    function zapERC20(ZapERC20Params calldata params) external  nonReentrant returns (ZapperOutput memory) {
        return translateOldStyleZap(params);
    }
    function zapETH(ZapERC20Params calldata params) external payable nonReentrant returns (ZapperOutput memory) {
        return translateOldStyleZap(params);
    }
    function zapToETH(ZapERC20Params calldata params) external payable nonReentrant returns (ZapperOutput memory) {
        return translateOldStyleZap(params);
    }

}