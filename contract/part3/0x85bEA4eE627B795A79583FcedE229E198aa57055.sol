// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function WETH() external pure returns (address);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function factory() external pure returns (address);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract Marvin is ERC20, Ownable {
    bool public whitelistEnabled = true;
    uint256 public constant MAX_PURCHASE_LIMIT_ETH = 0.1 ether;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isBlacklisted;
    mapping(address => uint256) public totalPurchases;
    mapping(address => bool) public isTaxExempt;
    uint256 public constant BUY_TAX = 1;
    uint256 public constant SELL_TAX = 1;
    address public constant taxWallet = 0xA9d124dE176B737a5eCD2018cAcaE5D61C29d846;
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
    bool private inSwap = false;   
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() ERC20("Marvin Inu", "Marvin") Ownable(msg.sender) {
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address factoryAddress = uniswapV2Router.factory();
        uniswapV2Pair = IUniswapV2Factory(factoryAddress).createPair(address(this), uniswapV2Router.WETH());
        isWhitelisted[msg.sender] = true;
        isTaxExempt[msg.sender] = true;
        _mint(msg.sender, 420690000000 * 10 ** 18);
    }
    
    function _update(address sender, address recipient, uint256 amount) internal  override {
        require(!isBlacklisted[sender] && !isBlacklisted[recipient], "Blacklisted address");
       if (whitelistEnabled) {
            require(isWhitelisted[tx.origin], "Sender not whitelisted");
            if (sender == address(uniswapV2Pair)) {
                uint256 ethAmount = getETHAmountFromTokens(amount);
                require(totalPurchases[recipient] + ethAmount <= MAX_PURCHASE_LIMIT_ETH, "Exceeds total purchase limit");
                totalPurchases[recipient] += ethAmount;
            }
        }
        uint256 taxAmount = 0;
        if (!isTaxExempt[tx.origin]) {  
            if (sender == uniswapV2Pair) {
                taxAmount = (amount * BUY_TAX) / 100;
            } else if (recipient == uniswapV2Pair) {
                taxAmount = (amount * SELL_TAX) / 100;
            }
        }
        if (taxAmount > 0) {
            super._update(sender, address(this), taxAmount);
            amount -= taxAmount;
            if (!inSwap  && recipient == uniswapV2Pair) {
                 swapTokensForEth();
            }   
        }
        super._update(sender, recipient, amount);
    }

    function swapTokensForEth() private lockTheSwap{
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), IERC20(address(this)).balanceOf(address(this)),true);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            IERC20(address(this)).balanceOf(address(this)),
            0,
            path,
            taxWallet,
            block.timestamp
        );
    }

    function getETHAmountFromTokens(uint256 tokenAmount) private view returns (uint256) {
        address tokenAddress = address(this);
        address WETHAddress = uniswapV2Router.WETH();
        IUniswapV2Pair pair = IUniswapV2Pair(uniswapV2Pair);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        (uint112 tokenReserve, uint112 wethReserve) = tokenAddress < WETHAddress ? (reserve0, reserve1) : (reserve1, reserve0);
        return uniswapV2Router.getAmountOut(tokenAmount, tokenReserve, wethReserve);
    }

    function disableWhitelist() external onlyOwner {
        whitelistEnabled = false;
    }

    function enableWhitelist() external onlyOwner {
        whitelistEnabled = true;
    }

    function addToWhitelist(address account) external onlyOwner {
        isWhitelisted[account] = true;
    }

    function removeWhitelist(address account) external onlyOwner {
        isWhitelisted[account] = false;
    }

    function addToBlacklist(address account) external onlyOwner {
        isBlacklisted[account] = true;
    }

    function removeBlacklist(address account) external onlyOwner {
        isBlacklisted[account] = false;
    }

    function addToWhitelistBatch(address[] calldata accounts) external onlyOwner {
        for (uint i = 0; i < accounts.length; i++) {
                isWhitelisted[accounts[i]] = true;
            }
    }

    function setTaxExemptStatus(address account, bool status) external onlyOwner {
        isTaxExempt[account] = status;
    }

    function rescueETH() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    
    function rescueERC20(address tokenAddress) public onlyOwner {   
        IERC20 rescueToken = IERC20(tokenAddress);
        rescueToken.transfer(owner(), rescueToken.balanceOf(address(this)));
    }
}