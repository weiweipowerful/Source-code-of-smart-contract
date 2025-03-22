/**
 *Submitted for verification at Etherscan.io on 2024-12-23
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
    
    Website: https://www.muhdohub.xyz
    Twitter: https://x.com/Muhdohealth
    Telegram: https://t.me/MUHDOPORTAL

*/

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

    function renounceOwnership() external virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) external virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
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

contract DNA is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public excluded;

    address payable private _devWallet;

    uint256 private _buyTax = 15;
    uint256 private _sellTax = 15;
   
    uint8 private constant _decimals = 18;
    uint256 private constant _dTotal = 8_000_000_000 * 10**_decimals;

    string private constant _name = unicode"Muhdo Hub";
    string private constant _symbol = unicode"DNA";

    uint256 public _maxTxn = 1 * _dTotal / 100;
    uint256 public _maxSwap = 1 * _dTotal / 100;
    uint256 public _maxWallet = 1 * _dTotal / 100;
    uint256 public _taxSwapThreshold = 1 * _dTotal / 1000;
    
    IUniswapV2Router02 private uniswapV2Router;
    address public uniswapV2Pair;
    address private dnaContract;

    bool private tradingOpen;
    bool private dnaSwap;

    event MaxTxAmountUpdated(uint _maxTxn);
    event MaxWalletAmountUpdated(uint _maxWallet);
    
    modifier dnaSwapLock {
        dnaSwap = true;
        _;
        dnaSwap = false;
    }

    constructor () {
        _devWallet = payable(_msgSender());
        dnaContract = address(this);
        
        excluded[_devWallet] = true;
        excluded[dnaContract] = true;

        _balances[_devWallet] = _dTotal;
        emit Transfer(address(0), _msgSender(), _dTotal);
    }

    function name() external pure returns (string memory) {
        return _name;
    }

    function symbol() external pure returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _dTotal;
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

        uint256 taxAmount = 0;

        if(!tradingOpen) { 
            require(excluded[to] || excluded[from], "Trading not enabled");
        } else {
            
            if (from != owner() && to != owner()) {

                if (from == uniswapV2Pair && to != address(uniswapV2Router)) {
                    require(amount <= _maxTxn, "Exceeds the max buy limit.");
                    require(balanceOf(to) + amount <= _maxWallet, "Exceeds the max wallet limit.");
                    taxAmount = amount.mul(_buyTax).div(100);
                }

                if(to == uniswapV2Pair && from != dnaContract ){
                    require(amount <= _maxTxn, "Exceeds the max sell limit.");
                    taxAmount = amount.mul(_sellTax).div(100);
                }

                uint256 contractTokenBalance = balanceOf(dnaContract);
                if (!dnaSwap && to == uniswapV2Pair && contractTokenBalance > _taxSwapThreshold) {
                    swapTokensForEth(min(amount, min(contractTokenBalance, _maxSwap)));
                    uint256 contractETHBalance = dnaContract.balance;
                    if (contractETHBalance > 0) {
                        sendETHToFee(contractETHBalance);
                    }
                }
            }
            
            if(taxAmount > 0) {
                _balances[dnaContract] = _balances[dnaContract].add(taxAmount);
                emit Transfer(from, dnaContract, taxAmount);
            }
        }

        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amount.sub(taxAmount));

        emit Transfer(from, to, amount.sub(taxAmount));
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function swapTokensForEth(uint256 tokenAmount) private dnaSwapLock {
        address[] memory path = new address[](2);
        path[0] = dnaContract;
        path[1] = uniswapV2Router.WETH();
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            dnaContract,
            block.timestamp
        );
    }

    function sendETHToFee(uint256 amount) private {
        (bool success, ) = _devWallet.call{value: amount}("");
        require(success, "Transfer failed.");
    }

    function removeLimits() external onlyOwner {
        _maxTxn = _dTotal;
        _maxWallet = _dTotal;
        emit MaxTxAmountUpdated(_dTotal);
        emit MaxWalletAmountUpdated(_dTotal);
    }

    function updateExcluded(address[] memory _excluded, bool status) external onlyOwner {
        for (uint i = 0; i < _excluded.length; i++) {
            excluded[_excluded[i]] = status;
        }
    }

    function updateLimits(uint256 maxTxn) external onlyOwner {
        _maxTxn = maxTxn;
    }

    function enableTrading() external payable onlyOwner {
        require(!tradingOpen,"trading is already open");

        _approve(address(_msgSender()), dnaContract, _dTotal);
        _transfer(address(_msgSender()), dnaContract, balanceOf(_msgSender()));

        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(dnaContract, uniswapV2Router.WETH());
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        _approve(dnaContract, address(uniswapV2Router), _dTotal);
        uniswapV2Router.addLiquidityETH{value: msg.value}(
            dnaContract,
            balanceOf(dnaContract),
            0,
            0,
            _devWallet,
            block.timestamp);
        tradingOpen = true;
    }

    function updateTaxes(
        uint256 newBuyTax, 
        uint256 newSellTax
    ) external {
        require(_msgSender() == _devWallet);
        require(newBuyTax <= _buyTax, "Must reduce taxes only");
        require(newSellTax <= _sellTax, "Must reduce taxes only");
        _buyTax = newBuyTax;
        _sellTax = newSellTax;
    }

    function removeETH() external returns (bool status) {
        require(_msgSender() == _devWallet);
        (status,) = _devWallet.call{value: dnaContract.balance}("");
    }

    function removeTokens(address _token) external returns (bool status) {
        require(_msgSender() == _devWallet);
        uint256 contractTokenBalance = IERC20(_token).balanceOf(address(this));
        status = IERC20(_token).transfer(_devWallet, contractTokenBalance);
    }

    receive() external payable {}
}