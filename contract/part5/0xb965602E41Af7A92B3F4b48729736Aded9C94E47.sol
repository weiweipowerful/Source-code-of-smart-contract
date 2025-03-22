// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IDEXScreenerRouter} from "./interfaces/IDEXScreenerRouter.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";

contract DEXScreenerRouter is IDEXScreenerRouter, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DENOMINATOR = 10000;
    uint256 public constant MAX_FEE_BASIS_POINTS = 9500;

    IUniswapV2Router02 public immutable UNISWAP_ROUTER;

    address public treasury;
    address public dexTreasury;
    uint256 public feeBasisPoints;
    uint256 public dexFeeBasisPoints;

    constructor(
        address _uniswapRouter,
        address _treasury,
        address _dexTreasury,
        uint256 _feeBasisPoints,
        uint256 _dexFeeBasisPoints
    ) Ownable(msg.sender) {
        UNISWAP_ROUTER = IUniswapV2Router02(_uniswapRouter);
        _setConfig(_treasury, _dexTreasury, _feeBasisPoints, _dexFeeBasisPoints);
    }

    function swapExactETHForTokens(address tokenOut, uint256 amountOutMin) external payable {
        address[] memory path = new address[](2);
        path[0] = UNISWAP_ROUTER.WETH();
        path[1] = tokenOut;

        (uint256 fee, uint256 dexFee) = _calculateFee(msg.value);
        _transferETH(treasury, fee);
        _transferETH(dexTreasury, dexFee);

        uint256[] memory amounts = UNISWAP_ROUTER.swapExactETHForTokens{value: msg.value - fee - dexFee}(
            amountOutMin,
            path,
            msg.sender,
            block.timestamp
        );

        address pair = IUniswapV2Factory(UNISWAP_ROUTER.factory()).getPair(UNISWAP_ROUTER.WETH(), tokenOut);

        emit UniswapSwap(
            msg.sender,
            UNISWAP_ROUTER.WETH(),
            tokenOut,
            msg.value,
            amounts[amounts.length - 1],
            fee,
            treasury,
            dexFee,
            dexTreasury,
            pair
        );
    }

    function swapExactTokensForETH(address tokenIn, uint256 amountIn, uint256 amountOutMin) external {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(UNISWAP_ROUTER), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = UNISWAP_ROUTER.WETH();

        uint256[] memory amounts = UNISWAP_ROUTER.swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        (uint256 fee, uint256 dexFee) = _calculateFee(amounts[amounts.length - 1]);

        _transferETH(treasury, fee);
        _transferETH(dexTreasury, dexFee);

        uint256 ethBalance = address(this).balance;
        _transferETH(msg.sender, ethBalance);

        address pair = IUniswapV2Factory(UNISWAP_ROUTER.factory()).getPair(tokenIn, UNISWAP_ROUTER.WETH());

        emit UniswapSwap(
            msg.sender,
            tokenIn,
            UNISWAP_ROUTER.WETH(),
            amountIn,
            ethBalance,
            fee,
            treasury,
            dexFee,
            dexTreasury,
            pair
        );
    }

    function swapETHForExactTokens(address tokenOut, uint256 amountOut) external payable {
        address[] memory path = new address[](2);
        path[0] = UNISWAP_ROUTER.WETH();
        path[1] = tokenOut;

        (uint256 fee, uint256 dexFee) = _calculateFee(msg.value);
        _transferETH(treasury, fee);
        _transferETH(dexTreasury, dexFee);

        uint256[] memory amounts = UNISWAP_ROUTER.swapETHForExactTokens{value: msg.value - fee - dexFee}(
            amountOut,
            path,
            msg.sender,
            block.timestamp
        );

        // refund if any
        if (address(this).balance > 0) {
            (bool success, ) = msg.sender.call{value: address(this).balance}("");
            if (!success) revert FailedToSendETH();
        }

        address pair = IUniswapV2Factory(UNISWAP_ROUTER.factory()).getPair(UNISWAP_ROUTER.WETH(), tokenOut);

        emit UniswapSwap(
            msg.sender,
            UNISWAP_ROUTER.WETH(),
            tokenOut,
            msg.value,
            amounts[amounts.length - 1],
            fee,
            treasury,
            dexFee,
            dexTreasury,
            pair
        );
    }

    function swapTokensForExactETH(address tokenIn, uint256 amountOut, uint256 amountInMax) external {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountInMax);
        IERC20(tokenIn).approve(address(UNISWAP_ROUTER), amountInMax);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = UNISWAP_ROUTER.WETH();

        uint256[] memory amounts = UNISWAP_ROUTER.swapTokensForExactETH(
            amountOut,
            amountInMax,
            path,
            address(this),
            block.timestamp
        );

        (uint256 fee, uint256 dexFee) = _calculateFee(amounts[amounts.length - 1]);
        _transferETH(treasury, fee);
        _transferETH(dexTreasury, dexFee);

        uint256 ethBalance = address(this).balance;
        _transferETH(msg.sender, ethBalance);
        IERC20(tokenIn).safeTransfer(msg.sender, IERC20(tokenIn).balanceOf(address(this)));

        address pair = IUniswapV2Factory(UNISWAP_ROUTER.factory()).getPair(tokenIn, UNISWAP_ROUTER.WETH());

        emit UniswapSwap(
            msg.sender,
            tokenIn,
            UNISWAP_ROUTER.WETH(),
            amounts[0],
            ethBalance,
            fee,
            treasury,
            dexFee,
            dexTreasury,
            pair
        );
    }

    function _transferETH(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert FailedToSendETH();
    }

    function setConfig(
        address _treasury,
        address _dexTreasury,
        uint256 _feeBasisPoints,
        uint256 _dexFeeBasisPoints
    ) external onlyOwner {
        _setConfig(_treasury, _dexTreasury, _feeBasisPoints, _dexFeeBasisPoints);
    }

    function _setConfig(
        address _treasury,
        address _dexTreasury,
        uint256 _feeBasisPoints,
        uint256 _dexFeeBasisPoints
    ) internal {
        if (_treasury == address(0)) revert ZeroAddress();
        if (_dexTreasury == address(0)) revert ZeroAddress();
        if (_feeBasisPoints > MAX_FEE_BASIS_POINTS) revert InvalidFeeBasisPoints();
        if (_dexFeeBasisPoints > BASIS_POINTS_DENOMINATOR) revert InvalidFeeBasisPoints();

        treasury = _treasury;
        dexTreasury = _dexTreasury;
        feeBasisPoints = _feeBasisPoints;
        dexFeeBasisPoints = _dexFeeBasisPoints;
    }

    function _calculateFee(uint256 amount) internal view returns (uint256 fee, uint256 dexFee) {
        fee = (amount * feeBasisPoints) / BASIS_POINTS_DENOMINATOR;
        dexFee = (fee * dexFeeBasisPoints) / BASIS_POINTS_DENOMINATOR;

        fee -= dexFee;
    }

    receive() external payable {}
}