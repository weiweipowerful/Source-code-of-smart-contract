/**
 *Submitted for verification at Etherscan.io on 2024-12-19
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

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
        require(c / a == b, "SafeMath: multiplication overflow");
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

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
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
}

contract MYST is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public _isExcludedFromFee;
    mapping(address => bool) public automatedMarketMakerPairs;

    uint8 private constant _decimals = 18;
    uint256 private constant _tTotal = 100000000 * 10**_decimals; 
    string private constant _name = unicode"MYST";  
    string private constant _symbol = unicode"$MYST"; 
    uint256 public _taxSwapThreshold= 100000 * 10**_decimals;
    uint256 public maxMystPerWallet = 2000000 * 10 ** decimals();

    uint256 public _mystBuyTax = 5; 
    uint256 public _mystSellTax = 5;
    uint256 public _mystTransferTax = 5;

    address payable public _mystTaxWallet = payable(0xBf5e6D128e92bE2Cb3a2a7f5Ee527d6f5b62F779);

    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    bool private inSwap = false;
    bool private swapEnabled = true;

    bool public tradeEnabled = false;

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    event TaxWalletPaymentRevert(address indexed taxWallet, uint256 amount);


    constructor () {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); // mainnet router address
      //  IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); // test router address
        
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

        _balances[_msgSender()] = _tTotal;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_mystTaxWallet] = true;
        automatedMarketMakerPairs[uniswapV2Pair] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
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
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount=0;
        if (!_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {

            require(tradeEnabled, "Trading not enabled");

            if(!automatedMarketMakerPairs[to]){
               require(balanceOf(to) + amount <= maxMystPerWallet, "Higher than the limit Of MYST Per Wallet.");
            }

            if(_mystTransferTax > 0) {
            if(!automatedMarketMakerPairs[to] && !automatedMarketMakerPairs[from]) {
                taxAmount = amount.mul(_mystTransferTax).div(100);
            }
            }

            if(_mystBuyTax > 0) {
            if (automatedMarketMakerPairs[from] == true) {
                taxAmount = amount.mul(_mystBuyTax).div(100);
            }
            }

            if(_mystSellTax > 0) {
            if(automatedMarketMakerPairs[to] == true){
                taxAmount = amount.mul(_mystSellTax).div(100);
            }
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && automatedMarketMakerPairs[to] == true && swapEnabled && contractTokenBalance>_taxSwapThreshold) {
                swapTokensForEth(contractTokenBalance);
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }

        if(taxAmount>0){
          _balances[address(this)]=_balances[address(this)].add(taxAmount);
          emit Transfer(from, address(this),taxAmount);
        }
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
    }


    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        if(tokenAmount==0){return;}
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function sendETHToFee(uint256 amount) private {
        (bool callSuccess, ) = payable(_mystTaxWallet).call{value: amount}("");

        if (!callSuccess) {
        // Log the failure but do not revert the transaction
        emit TaxWalletPaymentRevert(_mystTaxWallet, amount);
    }

    }


    receive() external payable {}

    function RecoverLostEth() public onlyOwner {
        require(address(this).balance > 0, "No stuck Eth");
        uint256 ethBalance = address(this).balance;

        (bool callSuccess, ) = payable(msg.sender).call{value: ethBalance}(
            ""
        );
        require(callSuccess, "Call failed");
    }

    function updateMystWalletLimit(uint256 _maxLimit) public onlyOwner{
        require(_maxLimit > totalSupply().div(200),"Limit too less");
        maxMystPerWallet = _maxLimit;
    }

    function whiteListFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function updateTaxes(uint256 buyFee, uint256 sellFee) public onlyOwner {
        _mystBuyTax = buyFee;
        _mystSellTax = sellFee;
    }

    function updateTransferTax(uint256 _transferTax) public onlyOwner {
        _mystTransferTax = _transferTax;
    }

    function changeTaxSwapLimit(uint256 _taxLimit) public onlyOwner{
        require(_taxLimit > 0, "Tax limit too low");
        _taxSwapThreshold = _taxLimit;
    }

    function setAutomatedMarketMakerPair(address _pair) public onlyOwner{
        automatedMarketMakerPairs[_pair] = true;
    }

    function removeAutomatedMarketMakerPair(address _pair) public onlyOwner{
        automatedMarketMakerPairs[_pair] = false;
    }

    function launchMyst() public onlyOwner {
        require(tradeEnabled != true, "Trade already enabled");
        tradeEnabled = true;
    }
    
    }