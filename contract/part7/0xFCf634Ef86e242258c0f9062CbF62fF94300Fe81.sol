// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LSDSwapV2 } from "./LSDSwapV2.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IQuoterV2 } from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import { IPeripheryImmutableState } from "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { IWETH9 } from "../weth9/IWETH9.sol";

/// @title LSDSwapWithUniswapV2
/// @dev This contract extends LSDSwapV2 to integrate with Uniswap for token swaps.
contract LSDSwapWithUniswapV2 is LSDSwapV2 {
    /// @notice The address of the uniswap router contract
    address public immutable SWAP_ROUTER;
    /// @notice The address of the uniswap quoter contract
    address public immutable SWAP_QUOTER;
    /// @notice The address of the uniswap v3 factory contract
    address public immutable SWAP_FACTORY;

    /// @dev Constructor to initialize the LSDCrossChainSwap contract with the LzEndpointV2 contract address
    /// @param _swapRouter The address of the uniswap swap router
    /// @param _swapQuoter The address of the uniswap swap quoter
    /// @param _swapFactory The address of the uniswap v3 factory
    /// @param _lzEndpointAddr The address of the LzEndpointV2 contract of LayerZero
    /// @param _owner The address of the owner of the contract
    constructor(
        address _swapRouter,
        address _swapQuoter,
        address _swapFactory,
        address _lzEndpointAddr, // solhint-disable-line no-unused-vars
        address _owner // solhint-disable-line no-unused-vars
    ) LSDSwapV2(_lzEndpointAddr, _owner) {
        SWAP_ROUTER = _swapRouter;
        SWAP_QUOTER = _swapQuoter;
        SWAP_FACTORY = _swapFactory;
    }

    /// @dev Swap tokens using Uniswap
    /// @param fromToken The token to swap from
    /// @param toToken The token to swap to
    /// @param amount The amount of fromToken to swap
    /// @param minAmountOut The minimum amount of toToken to receive
    /// @param path Swap path
    /// @return amountOut The amount of toToken received
    function _tokenSwap(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 minAmountOut,
        bytes memory path
    ) internal virtual override returns (uint256 amountOut) {
        if (fromToken == toToken) {
            return amount;
        }

        address weth9 = IPeripheryImmutableState(SWAP_ROUTER).WETH9();
        address realFromToken = fromToken;
        if (fromToken == address(0)) {
            realFromToken = weth9;
            // if fromToken is ETH, convert it to WETH for swap
            IWETH9(weth9).deposit{ value: amount }();
        }
        address realToToken = toToken;
        if (toToken == address(0)) {
            realToToken = weth9;
        }

        if (realFromToken == realToToken) {
            amountOut = amount;
        } else {
            _checkSwapPath(path, realFromToken, realToToken);

            TransferHelper.safeApprove(realFromToken, SWAP_ROUTER, amount);
            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp + 30 hours,
                amountIn: amount,
                amountOutMinimum: minAmountOut
            });
            amountOut = ISwapRouter(SWAP_ROUTER).exactInput(params);
        }

        // if toToken is ETH, swap for WETH and then withdraw for ETH
        if (toToken == address(0)) {
            IWETH9(realToToken).withdraw(amountOut);
        }
        return amountOut;
    }

    /// @dev Quote token swap using Uniswap
    /// @param path Swap path
    /// @param amount The amount of fromToken to swap
    /// @return amountOut The amount of toToken received
    function _quoteTokenSwap(bytes memory path, uint256 amount) internal virtual override returns (uint256 amountOut) {
        (amountOut, , , ) = IQuoterV2(SWAP_QUOTER).quoteExactInput(path, amount);
        return amountOut;
    }

    /// @dev Get the real token address for the given token
    ///      if token is ETH, return WETH address
    /// @param token The token address
    /// @return realToken The real token address
    function _getRealToken(address token) internal view virtual override returns (address realToken) {
        address weth9 = IPeripheryImmutableState(SWAP_ROUTER).WETH9();
        if (token == address(0)) {
            return weth9;
        }
        return token;
    }
}