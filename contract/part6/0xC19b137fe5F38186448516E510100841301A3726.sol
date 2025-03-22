// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

import "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "lib/v2-periphery/contracts/interfaces/IERC20.sol";

contract TokenSwap {
    /// @notice Address of the DeepBotRouterV1
    address public immutable DEEP_BOT_ROUTER_V1;

    constructor(address _deepBotRouterV1) public {
        DEEP_BOT_ROUTER_V1 = _deepBotRouterV1;
    }
    
    /// @notice Function to swap exact amount of ERC20 tokens to as much ETH as possible.
    /// @param _tokenIn Address of the input token.
    /// @param _amountIn The amount of input tokens to send.
    /// @param _amountOutMin The minimum amount of ETH that must be received for the transaction not to revert. 
    /// @param _to Recipient of the ETH.
    /// @param _deadline Unix timestamp after which the transaction will revert.
    /// @return Amount of ETH received.
    function swapExactTokensForETH(
        address _tokenIn,
        uint256 _amountIn, 
        uint256 _amountOutMin,  
        address _to, 
        uint256 _deadline
    ) external returns (uint256) {
        IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn);
        IERC20(_tokenIn).approve(DEEP_BOT_ROUTER_V1, _amountIn);

        address[] memory _path = new address[](2);
        _path[0] = _tokenIn;
        _path[1] = IUniswapV2Router02(DEEP_BOT_ROUTER_V1).WETH();
        
        uint256[] memory amounts = IUniswapV2Router02(DEEP_BOT_ROUTER_V1).swapExactTokensForETH(
            _amountIn, 
            _amountOutMin, 
            _path, 
            _to, 
            _deadline
        );

        return amounts[1];
    }

    /// @notice Function to swap exact amount of ETH for as many ERC20 tokens as possible.
    /// @dev Reverts if 'msg.value' sent along is zero.
    /// @param _tokenOut Address of the output token.
    /// @param _amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
    /// @param _to Recipient of the output tokens.
    /// @param _deadline Unix timestamp after which the transaction will revert.
    /// @return Amount of ERC20 tokens received.
    function swapExactETHForTokens(
        address _tokenOut,
        uint256 _amountOutMin,  
        address _to, 
        uint256 _deadline
    ) external payable returns (uint256) {
        require(msg.value > 0, "Insufficient ETH sent.");

        address[] memory _path = new address[](2);
        _path[0] = IUniswapV2Router02(DEEP_BOT_ROUTER_V1).WETH();
        _path[1] = _tokenOut;

        uint256[] memory amounts = IUniswapV2Router02(DEEP_BOT_ROUTER_V1).swapExactETHForTokens{value: msg.value}(
            _amountOutMin, 
            _path, 
            _to, 
            _deadline
        );

        return amounts[1];
    }

    /// @notice Function to swap exact amount of ERC20 tokens that take a fee on transfer to as much ETH as possible.
    /// @param _amountIn The amount of ERC20 tokens to send.
    /// @param _amountOutMin The minimum amount of ETH that must be received for the transaction not to revert.
    /// @param _to Recipient of the ETH.
    /// @param _deadline Unix timestamp after which the transaction will revert.
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _to,
        uint256 _deadline
    ) external {
        IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn);
        IERC20(_tokenIn).approve(DEEP_BOT_ROUTER_V1, _amountIn);

        address[] memory _path = new address[](2);
        _path[0] = _tokenIn;
        _path[1] = IUniswapV2Router02(DEEP_BOT_ROUTER_V1).WETH();

        IUniswapV2Router02(DEEP_BOT_ROUTER_V1).swapExactTokensForETHSupportingFeeOnTransferTokens(
            _amountIn,
            _amountOutMin,
            _path,
            _to,
            _deadline
        );
    }

    /// @notice Function to swap exact amount of ETH for as many ERC20 tokens as possible that take a fee on transfer.
    /// @dev Reverts if 'msg.value' sent along is zero.
    /// @param _amountOutMin The minimum amount of ERC20 tokens that must be received for the transaction not to revert.
    /// @param _to Recipient of the ERC20 tokens.
    /// @param _deadline Unix timestamp after which the transaction will revert.
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        address _tokenOut,
        uint256 _amountOutMin,
        address _to,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Insufficient ETH sent.");

        address[] memory _path = new address[](2);
        _path[0] = IUniswapV2Router02(DEEP_BOT_ROUTER_V1).WETH();
        _path[1] = _tokenOut;

        IUniswapV2Router02(DEEP_BOT_ROUTER_V1).swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(
            _amountOutMin,
            _path,
            _to,
            _deadline
        );
    }
}