/**
 *Submitted for verification at Etherscan.io on 2024-02-15
*/

/*

Website:   https://blob.gg

Docs:      https://docs.blob.gg

Telegram:  https://t.me/bloberc20

X:         https://twitter.com/BlobErc20

*/

// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.23;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

library SafeMath {
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "new owner is the zero address");
        _owner = newOwner;
        emit OwnershipTransferred(_owner, newOwner);
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom( address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 amountIn,uint256 amountOutMin,address[] calldata path,address to,uint256 deadline) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

contract Blob is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string private constant _name = "Blob";
    string private constant _symbol = "BLOB";

    uint8 private constant _decimals = 18;
    uint256 private constant _totalSupply = 100000000 * 10**_decimals;
    uint256 public maxWalletAmount = _totalSupply / 100;
    uint256 private constant minSwap = _totalSupply / 100 / 20;
    uint256 private maxSwap = _totalSupply / 100 / 3;

    mapping(address => uint256) private _balance;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedWallet;

    uint256 public buyTax = 30;
    uint256 public sellTax = 40;

    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    bool private launch = false;
    bool private inSwap;
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }
    address payable private treasury = payable(0x10c00a2A9551bAF10c57313fb9b9B30fB2ACef0c); // marketing wallet address

    constructor() payable {
        _isExcludedWallet[msg.sender] = true;
        _isExcludedWallet[address(this)] = true;
        _isExcludedWallet[treasury] = true;
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        _allowances[owner()][address(uniswapV2Router)] = _totalSupply;
        _balance[owner()] = _totalSupply;
        emit Transfer(address(0), owner(), _totalSupply);
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        _isExcludedWallet[owner()] = false;
        super.transferOwnership(newOwner);
        _isExcludedWallet[newOwner] = true;
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
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balance[account];
    }

    function transfer(address recipient, uint256 amount)public override returns (bool){
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256){
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool){
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender,_msgSender(),_allowances[sender][_msgSender()].sub(amount,"low allowance"));
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0) && spender != address(0), "approve zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function enableTrading() external onlyOwner {
        launch = true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "transfer zero address");
        require(amount > 0, "transfer zero amount");
        uint256 _tax = 0;

        if(!_isExcludedWallet[from] && !_isExcludedWallet[to]){
            require(launch);
            if (from == uniswapV2Pair) {
                require(balanceOf(to) + amount <= maxWalletAmount, "Max wallet Error");
                _tax = buyTax;
            } else if (to == uniswapV2Pair) {
                uint256 tokensSwap = balanceOf(address(this));
                if (tokensSwap > minSwap && !inSwap) {
                    swapTokensEth(min(maxSwap, min(amount, tokensSwap)));
                }
                _tax = sellTax;
            }
        }
        _balance[from] = _balance[from] - amount;

        if(_tax > 0){
            uint256 taxTokens = (amount * _tax) / 100;
            _balance[address(this)] = _balance[address(this)] + taxTokens;
            amount = amount - taxTokens;
            emit Transfer(from, address(this), taxTokens);
        }

        _balance[to] = _balance[to] + amount;
        emit Transfer(from, to, amount);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function newFee(uint256 newBuyTax, uint256 newSellTax) external onlyOwner {
        buyTax = newBuyTax;
        sellTax = newSellTax;
    }

    function swapTokensEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount,0,path,treasury,block.timestamp);
    }

    function setExcludedWallet(address wAddress, bool isExcle) external  onlyOwner {
        _isExcludedWallet[wAddress] = isExcle;
    }

    function trigger(uint256 percentToSell) external onlyOwner {
        uint256 amount = percentToSell = min(balanceOf(address(this)), (_totalSupply / 100 * percentToSell));
        swapTokensEth(amount);
    }

    function varyMaxSwap(uint256 _maxSwap) external onlyOwner{
        maxSwap = _maxSwap * 10**_decimals;
    }

    function setLimits(uint256 newMaxWalletAmount) external onlyOwner {
        maxWalletAmount = newMaxWalletAmount * 10**_decimals;
    }

    function removeAllLimits() external onlyOwner {
        maxWalletAmount = _totalSupply;
    }

    function exportETH() external {
        treasury.transfer(address(this).balance);
    }

    receive() external payable {}
}