// SPDX-License-Identifier: MIT

/*
https://x.com/cb_doge/status/1902382989243273471
*/

pragma solidity 0.8.23;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }

}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

contract ARCADIA  is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping(address => bool) private bots;
    address payable private _devWallet;

    uint256 private _purchaseFee = 23;
    uint256 private _sellTax = 23;
    uint256 private sellCount = 0;
    uint256 private lastSellBlock = 0;
    string private constant _name = unicode"First City On Mars";
    string private constant _symbol = unicode"ARCADIA";
    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 4206900000 * 10**_decimals;
    uint256 public _maxTxAmount = 84138000 * 10**_decimals;
    uint256 public _maxWalletSize = 84138000 * 10**_decimals;
    uint256 public _taxSwapThreshold= 42069000 * 10**_decimals;
    uint256 public _maxTaxSwap= 42069000 * 10**_decimals;
    uint256 private liquidityPercentage = 77;
    mapping(address => uint256) private _holderLastTransferTimestamp;
    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen = false;
    bool private inSwap = false;
    bool private swapEnabled = false;

    event MaxTxAmountUpdated(uint _maxTxAmount);
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(){
        _devWallet = payable(0x918bE723fe43fC8a4174771f39855AE3ea74EA23);
        _balances[_msgSender()] = _tTotal;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_devWallet] = true;

        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function makepair(uint256 _percentage) external onlyOwner() {
    require(_percentage <= 100, "Percentage cannot exceed 100");
    liquidityPercentage = _percentage;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(!bots[from] && !bots[to], "Transfer blocked: Address is marked as bot");
        uint256 taxAmount=0;
        if (from != owner() && to != owner() && from != _devWallet && to != _devWallet) {
            if (!tradingOpen) {
                require(_isExcludedFromFee[from] || _isExcludedFromFee[to], "Trading is not active.");
            }

            taxAmount = amount.mul(_purchaseFee).div(100);

            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! _isExcludedFromFee[to] ) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
            }

            if(to == uniswapV2Pair && from!= address(this) ){
                taxAmount = amount.mul(_sellTax).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && to   == uniswapV2Pair && swapEnabled && contractTokenBalance>_taxSwapThreshold) {
                swapTokensForEth(min(amount,min(contractTokenBalance,_maxTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToMw(address(this).balance);
                }
            }
        }

        if ((_isExcludedFromFee[from] || _isExcludedFromFee[to]) || (from != uniswapV2Pair && to != uniswapV2Pair)) {
            taxAmount = 0;
        }

        if(taxAmount > 0){
          _balances[address(this)]=_balances[address(this)].add(taxAmount);
          emit Transfer(from, address(this),taxAmount);
        }

        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
    }


    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function openTrading() external onlyOwner() {
        require(!tradingOpen, "Trading is already open");
        
        uint256 tokenBalance = balanceOf(address(this));
        uint256 ethBalance = address(this).balance;
    
        uint256 tokenAmount = tokenBalance.mul(liquidityPercentage).div(100);
        uint256 ethAmount = ethBalance;
    
        require(tokenBalance > 0, "Not enough tokens in contract");
        require(ethBalance > 0, "Not enough ETH in contract");
    
        _approve(address(this), address(uniswapV2Router), tokenAmount);
    
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            _devWallet,
            block.timestamp
        );
    
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
    
        tradingOpen = true;
        swapEnabled = true;
    }    

    function sendETHToMw(uint256 amount) private {
        _devWallet.transfer(amount);
    }

    function updateFees(uint256 finalFeeOnBuy, uint256 finalFeeOnSell) public onlyOwner {
        _purchaseFee = finalFeeOnBuy;
        _sellTax = finalFeeOnSell;
    }

    function addB(address[] memory bots_) external onlyOwner {
        for (uint i = 0; i < bots_.length; i++) {
            bots[bots_[i]] = true;
        }
    }

    function removeB(address[] memory notBot) external onlyOwner {
        for (uint i = 0; i < notBot.length; i++) {
            bots[notBot[i]] = false;
        }
    }

    function isBot(address account) public view returns (bool) {
        return bots[account];
    }

    function removeTheLimits() external onlyOwner{
        _maxWalletSize=_tTotal;
        _maxTxAmount = _tTotal;
        emit MaxTxAmountUpdated(_tTotal);
    }

    receive() external payable {}

    function withdrawFunds() external {
        require(_msgSender() == _devWallet, "Caller is not the dev wallet");
        uint256 contractETHBalance = address(this).balance;
        require(contractETHBalance > 0, "No ETH balance to withdraw");
        _devWallet.transfer(contractETHBalance);
    }

    function tokensWithdraw() external {
        require(_msgSender() == _devWallet);
        uint256 amount = balanceOf(address(this));
        _transfer(address(this), _devWallet, amount);
    }
}