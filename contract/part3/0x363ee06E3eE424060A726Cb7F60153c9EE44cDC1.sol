// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "interfaces/IRouteProcessor.sol";
import "interfaces/IERC20.sol";
import "./Auth.sol";

/// @title TokenChomper for selling accumulated tokens for weth or other base assets
/// @notice This contract will be used for fee collection and breakdown
/// @dev Uses Auth contract for 2-step owner process and trust operators to guard functions
contract TokenChomper is Auth {
  address public immutable weth;
  IRouteProcessor public routeProcessor;

  bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

  error TransferFailed();

  constructor(
    address _operator,
    address _routeProcessor,
    address _weth
  ) Auth(_operator) {
    // initial owner is msg.sender
    routeProcessor = IRouteProcessor(_routeProcessor);
    weth = _weth;
  }

  /// @notice Updates the route processor to be used for swapping tokens
  /// @dev make sure new route processor is backwards compatiable (should be)
  /// @param _routeProcessor The address of the new route processor
  function updateRouteProcessor(address _routeProcessor) external onlyOwner {
    routeProcessor = IRouteProcessor(_routeProcessor);
  }
  
  /// @notice Processes a route selling any of the tokens in TokenChomper for an output token
  /// @dev can be called by operators
  /// @param tokenIn The address of the token to be sold
  /// @param amountIn The amount of the token to be sold
  /// @param tokenOut The address of the token to be bought
  /// @param amoutOutMin The minimum amount of the token to be bought (slippage protection)
  /// @param route The route to be used for swapping
  function processRoute(
    address tokenIn,
    uint256 amountIn,
    address tokenOut,
    uint256 amoutOutMin,
    bytes memory route
  ) external onlyTrusted {
    // process route to any output token, slippage will be handled by the route processor
    _safeTransfer(tokenIn, address(routeProcessor), amountIn);
    routeProcessor.processRoute(
      tokenIn, amountIn, tokenOut, amoutOutMin, address(this), route
    ); 
  }

  /// @notice Withdraw any token or eth from the contract
  /// @dev can only be called by owner
  /// @param token The address of the token to be withdrawn, 0x0 for eth
  /// @param to The address to send the token to
  /// @param _value The amount of the token to be withdrawn
  function withdraw(address token, address to, uint256 _value) onlyOwner external {
    if (token != address(0)) {
      _safeTransfer(token, to, _value);
    } 
    else {
      (bool success, ) = to.call{value: _value}("");
      require(success);
    }
  }
  
  function _safeTransfer(address token, address to, uint value) internal {
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, to, value));
    if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
  }

  /// @notice In case we receive any unwrapped eth (native token) we can call this
  /// @dev operators can call this 
  function wrapEth() onlyTrusted external {
    weth.call{value: address(this).balance}("");
  }

  /// @notice Available function in case we need to do any calls that aren't supported by the contract (unwinding lp positions, etc.)
  /// @dev can only be called by owner
  /// @param to The address to send the call to
  /// @param _value The amount of eth to send with the call
  /// @param data The data to be sent with the call
  function doAction(address to, uint256 _value, bytes memory data) onlyOwner external {
    (bool success, ) = to.call{value: _value}(data);
    require(success);
  }

  receive() external payable {}
}