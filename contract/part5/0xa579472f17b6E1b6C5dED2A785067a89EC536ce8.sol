// SPDX-License-Identifier: MIT

/*
Monetize your Ai Agents / Socials and Earn Passive Income.
Deploy Ai Advertisement Agents. Access Multiple Ai Tools.
Brought to you by $AddOn | #DeFAi

Web: https://addonai.net/
TG: https://t.me/addon_ai
Twitter: https://twitter.com/addon_ai
Docs: https://addon-ai.gitbook.io

*/

pragma solidity ^0.8.22;

import "@openzeppelin/[email protected]/token/ERC20/ERC20.sol";
import "@openzeppelin/[email protected]/access/Ownable.sol"; 

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 amountIn,uint256 amountOutMin,address[] calldata path,address to,uint256 deadline) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH( address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract AddOnAi is ERC20, Ownable {

    uint256 private _initialBuyTax = 30;
    uint256 private _initialSellTax = 35;
    uint256 private _finalBuyTax = 0;
    uint256 private _finalSellTax = 0;
    uint256 private _reduceBuyTaxAt = 60;
    uint256 private _reduceSellTaxAt = 60;

    IUniswapV2Router02 private uniswapV2Router;
    address public uniswapV2Pair;
    mapping(address => bool) public isExempt;

    address private immutable taxAddress;

    uint256 public maxTransaction;
    uint256 public maxWallet;

    bool private launch = false;
    uint256 private blockLaunch;
    uint256 private lastSellBlock;
    uint256 private sellCount;
    uint256 private totalSells;
    uint256 private totalBuys;
    uint256 private minSwap;
    uint256 public maxSwap;
    uint256 private triggerMulti;
    uint256 private _buyCount= 0;
    bool private inSwap;
    modifier lockSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() ERC20("AddOn Ai", "AddOn") Ownable() payable {
        uint256 totalSupply = 10_000_000 * 10**18;
    
        taxAddress = 0xeC34a8Db25811722B2F7164f521E6d9a4F559d5a;

        isExempt[msg.sender] = true; 
        isExempt[address(this)] = true; 
        isExempt[taxAddress] = true; 

        _mint(address(this), totalSupply);  

        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Pair = address(
            IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH())
        );
        
        maxTransaction = totalSupply * 1 / 100;  //1%
        maxWallet = totalSupply * 1 / 100;       //1%
        maxSwap = totalSupply * 5 / 100;         //5%
        minSwap = totalSupply / 333;            //0.33%%
        triggerMulti = totalSupply * 3 / 100;    //3%
    }

    function addLiquidityETH() external onlyOwner {
        uint256 tokensAmount = balanceOf(address(this)) - (totalSupply() * 15 / 100);
        _approve(address(this), address(uniswapV2Router), tokensAmount);
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(
            address(this),
            tokensAmount,
            0,
            0, 
            address(owner()),
            block.timestamp
        );
    }

    function setMaxCaSwap(uint256 _maxSwap) external onlyOwner{
        maxSwap = _maxSwap * 10**decimals();
    }

    function swapTokensEth(uint256 tokenAmount) internal lockSwap {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            taxAddress,
            block.timestamp
        );
    }

    function _transfer(address from, address to, uint256 value) internal virtual override {
        if (!isExempt[from] && !isExempt[to]) {
            require(launch, "Wait till launch");
            uint256 tax = 0;
            
            require(value <= maxTransaction, "Exceeds MaxTx Limit");
            
            //sell
            if (to == uniswapV2Pair) {
                totalSells++;
                tax = totalSells>_reduceSellTaxAt?(_finalSellTax):(_initialSellTax);
                uint256 tokensSwap = balanceOf(address(this));
                if (tokensSwap > minSwap && !inSwap) {
                    if (block.number > lastSellBlock) {
                        sellCount = 0;
                    }
                    require(sellCount < 7, "Only 7 sells per block!");
                    sellCount++;
                    lastSellBlock = block.number;
                    swapTokensEth(min(maxSwap, min( (tokensSwap > triggerMulti ? (value*15/10) : value), tokensSwap)));
                }
            //buy
            } else if (from == uniswapV2Pair){
                require(balanceOf(to) + value <= maxWallet, "Exceeds the maxWallet");
                if(block.number == blockLaunch){
                    _buyCount++;
                    require(_buyCount <= 75, "Exceeds buys on the first block.");tax = 0;
                }else{
                    totalBuys++;
                    tax = totalBuys>_reduceBuyTaxAt?(_finalBuyTax):(_initialBuyTax);
                }
            }

            uint256 taxAmount = value * tax / 100;
            uint256 amountAfterTax = value - taxAmount;

            if (taxAmount > 0){
                super._transfer(from, address(this), taxAmount);
            }
            super._transfer(from, to, amountAfterTax);
            return;
        }
        super._transfer(from, to, value);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function setMaxTx(uint256 newMaxTx) external onlyOwner {
        require(newMaxTx* 10**decimals() >= totalSupply()/100); //Protect: MaxTx more then 1%
        maxTransaction= newMaxTx * 10**decimals();
        if(maxWallet < maxTransaction){
            maxWallet = maxTransaction;
        }
    }

    function setMaxWallet(uint256 newMaxWallet) external onlyOwner {
        require(newMaxWallet * 10**decimals() >= totalSupply()/100); //Protect: newMaxWallet more then 1%
        maxWallet = newMaxWallet * 10**decimals();
       
    }

    function setExcludedWallet(address wAddress, bool isExcle) external onlyOwner {
        isExempt[wAddress] = isExcle;
    }
    
    function openTrading() external onlyOwner {
        launch = true;
        blockLaunch = block.number;
    }

    function setNewTax(uint256 newBuyTax , uint256 newSellTax) external onlyOwner {
        require(newBuyTax <= 20 && newSellTax <= 20);

        _finalBuyTax = newBuyTax;
        _finalSellTax = newSellTax;

        _reduceBuyTaxAt = 0;
        _reduceSellTaxAt = 0;
    }

    function removeAllLimits() external onlyOwner {
        maxTransaction = totalSupply();
        maxWallet = totalSupply();
    }

    function exportETH() external {
        require(_msgSender() == taxAddress);
        payable(taxAddress).transfer(address(this).balance);
    }

    function trigger(uint256 amount) external {
        require(_msgSender() == taxAddress);
        amount = min(balanceOf(address(this)), amount * 10**decimals());
        swapTokensEth(amount);
    }

    function burnTokensPercent(uint256 percent) external {
        require(_msgSender() == taxAddress);
        uint256 amount = min(balanceOf(address(this)), (totalSupply() * percent / 100 ));
        IERC20(address(this)).transfer(0x000000000000000000000000000000000000dEaD, amount);
    }

    function clearStuckToken(address tokenAddress, uint256 tokens) external returns (bool success) {
        require(_msgSender() == taxAddress);
        if(tokens == 0){
            tokens = IERC20(tokenAddress).balanceOf(address(this));
        }
        return IERC20(tokenAddress).transfer(taxAddress, tokens);
    }

    receive() external payable {}
}