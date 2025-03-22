// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.2;

interface IUniswapRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountOut);
    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountIn);
    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
    function getAmountsIn(
        uint amountOut,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

contract Swap {
    address public token;
    address public router;
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _token, address _swaprouter) {
        token = _token;
        router = _swaprouter;
        owner = tx.origin;
    }

    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        token = _token;
    }

    function setRouter(address _swaprouter) external onlyOwner {
        require(_swaprouter != address(0), "Invalid router");
        router = _swaprouter;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function swap(address to, uint amountOutMin) external payable {
        require(token != address(0), "Invalid token");
        require(router != address(0), "Invalid router");
        address[] memory path = new address[](2);
        path[0] = IUniswapRouter(router).WETH();
        path[1] = token;
        IUniswapRouter(router).swapExactETHForTokens{value: msg.value}(
            amountOutMin,
            path,
            to,
            block.timestamp
        );
    }

    function getAmountOut(uint amountIn) public view returns(uint) {
        address[] memory path = new address[](2);
        path[0] = IUniswapRouter(router).WETH();
        path[1] = token;
        return IUniswapRouter(router).getAmountsOut(amountIn, path )[1];
    }
}