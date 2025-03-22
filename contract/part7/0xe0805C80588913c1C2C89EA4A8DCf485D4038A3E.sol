/*

  ____  _ _            _       ____  _            _    
 |  _ \(_) |          (_)     |  _ \| |          | |   
 | |_) |_| |_ ___ ___  _ _ __ | |_) | | __ _  ___| | __
 |  _ <| | __/ __/ _ \| | '_ \|  _ <| |/ _` |/ __| |/ /
 | |_) | | || (_| (_) | | | | | |_) | | (_| | (__|   < 
 |____/|_|\__\___\___/|_|_| |_|____/|_|\__,_|\___|_|\_\
                                                       
                                                       

https://bblack.io/
https://t.me/Bitcoin_Black_Card
https://x.com/btc_blackcard
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function circulatingSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);}

abstract contract Ownable {
    address internal owner;
    constructor(address _owner) {owner = _owner;}
    modifier onlyOwner() {require(isOwner(msg.sender), "!OWNER"); _;}
    function isOwner(address account) public view returns (bool) {return account == owner;}
    function transferOwnership(address payable adr) public onlyOwner {owner = adr; emit OwnershipTransferred(adr);}
    event OwnershipTransferred(address owner);
}

interface IFactory{
        function createPair(address tokenA, address tokenB) external returns (address pair);
        function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IRouter {
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

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline) external;
}

contract CARD is IERC20, Ownable {
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public _isExcludedFromFee;
   
    string private constant _name = "BitcoinBlack";
    string private constant _symbol = "CARD";
    uint8 private constant _decimals = 9;
    uint256 private _totalSupply = 100000000 * (10 ** _decimals);
    
    uint256 private _maxTransferAmount = 1000000 * 10**_decimals;
    uint256 private _maxTxAmount = 1000000 * 10**_decimals;
    uint256 private _maxWalletToken = 1000000 * 10**_decimals;
    uint256 private _swapThreshold = 60000 * 10**_decimals;
    uint256 private _minTokenAmount = 10000 * 10**_decimals;

    uint256 private liquidityFee = 0;
    uint256 private marketingFee = 50;
    uint256 private developmentFee = 50;
    uint256 private burnFee = 0;
    uint256 private buyFee = 0;
    uint256 private sellFee = 0;
    uint256 private transferFee = 0;
    uint256 private denominator = 1000;
    
     IRouter router;
    address private pair;
    bool private tradeEnable = false;
    bool private swapEnabled = false;
    uint256 private swapTimes;
    bool private swapping; 
    
    modifier lockTheSwap {
        swapping = true; _; swapping = false;
        }

    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private development_receiver = 0x5675BeB314d2b938fF9A36fa1BF28910bb4c5aA7; 
    address private marketing_receiver = 0x63A660013a8b4CAa9020a48ff8Ba86322C7b0787;
    

    constructor() Ownable(msg.sender) {
        IRouter _router = IRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address _pair = IFactory(_router.factory()).createPair(address(this), _router.WETH());
        router = _router;
        pair = _pair;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[development_receiver] = true;
        _isExcludedFromFee[marketing_receiver] = true;
        _isExcludedFromFee[msg.sender] = true;
        
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable {}
    
    function name() public pure returns (string memory) {
        return _name;
        }
    
    function symbol() public pure returns (string memory) {
        return _symbol;
        }
   
    function decimals() public pure returns (uint8) {
        return _decimals;
        }
    
    function enableTrading() external onlyOwner {
        require(!tradeEnable,"trading is already open");
        tradeEnable = true;
        swapEnabled = true;
        }
    
    function getOwner() external view override returns (address) {
         return owner; 
         }
   
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
        }
    
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
        }
    
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);return true;
        }
   
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
        }
    
    function isCont(address addr) internal view returns (bool) {
        uint size; assembly { size := extcodesize(addr) } return size > 0;
         }
   
    function setWhitelistWallet(address _address, bool _enabled) external onlyOwner {
        _isExcludedFromFee[_address] = _enabled;
        }
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);return true;
        }
   
    function circulatingSupply() public view override returns (uint256) {
        return _totalSupply - (balanceOf(DEAD)) - (balanceOf(address(0)));
        }
    
    function setFeeWallets(address _newMarketingWallet, address _newDevelopmentWallet) external onlyOwner {
       require(_newMarketingWallet != address(this), "CA will not be the Fee Reciever");
       require(_newMarketingWallet != address(0), "0 addy will not be the fee Reciever");
       require(_newDevelopmentWallet != address(this), "CA will not be the Fee Reciever");
       require(_newDevelopmentWallet != address(0), "0 addy will not be the fee Reciever");
       marketing_receiver = _newMarketingWallet;
       development_receiver = _newDevelopmentWallet;
       _isExcludedFromFee[_newMarketingWallet] = true;
       _isExcludedFromFee[_newDevelopmentWallet] = true;
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > uint256(0), "Transfer amount must be greater than zero");
        require(amount <= balanceOf(sender),"You are trying to transfer more than your balance");
         
         if (!_isExcludedFromFee[sender] && !_isExcludedFromFee[recipient]){
             require(tradeEnable, "Trading not enabled");
        }
         
         if (!_isExcludedFromFee[sender] && !_isExcludedFromFee[recipient] && recipient != address(pair) && recipient != address(DEAD)){
            require((_balances[recipient] + (amount)) <= _maxWalletToken, "Exceeds maximum wallet amount.");
      }
        
        if (sender != pair){
        require(amount <= _maxTransferAmount || _isExcludedFromFee[sender] || _isExcludedFromFee[recipient], "TX Limit Exceeded");
        require(amount <= _maxTxAmount || _isExcludedFromFee[sender] || _isExcludedFromFee[recipient], "TX Limit Exceeded");
      }
          
      if (recipient == pair && !_isExcludedFromFee[sender]){
         swapTimes += uint256(1);
      }
       
        swapBack(sender, recipient, amount);
        _balances[sender] = _balances[sender] - (amount);
        uint256 amountReceived = shouldTakeFee(sender, recipient) ? takeFee(sender, recipient, amount) : amount;
        _balances[recipient] = _balances[recipient] + (amountReceived);
        emit Transfer(sender, recipient, amountReceived);
    }

    function setFee(uint256 _liquidity, uint256 _marketing, uint256 _burn, uint256 _development, uint256 _buyFee, uint256 _sell, uint256 _trans) external onlyOwner {
        liquidityFee = _liquidity;
        marketingFee = _marketing;
        burnFee = _burn;
        developmentFee = _development;
        buyFee = _buyFee;
        sellFee = _sell;
        transferFee = _trans;
    }

    function setMxTxAmount(uint256 maxTxAmount, uint256 maxTransferAmount, uint256 maxWalletToken) external onlyOwner {
          _maxTransferAmount = maxTxAmount * 10**_decimals;
          _maxTxAmount = maxTransferAmount * 10**_decimals;
          _maxWalletToken = maxWalletToken * 10**_decimals;
    }

    function removeAllLimit() external onlyOwner {
          _maxTransferAmount = _totalSupply;
          _maxTxAmount = _totalSupply;
          _maxWalletToken = _totalSupply;
    }

    function swapAndLiquify(uint256 tokens) private lockTheSwap {
        uint256 _denominator = (liquidityFee + (1) + (marketingFee) + (developmentFee)) * (2);
        uint256 tokensToAddLiquidityWith = tokens * (liquidityFee) / (_denominator);
        uint256 toSwap = tokens - (tokensToAddLiquidityWith);
        uint256 initialBalance = address(this).balance;
       
        swapTokensForETH(toSwap);
       
        uint256 deltaBalance = address(this).balance - (initialBalance);
        uint256 unitBalance= deltaBalance / (_denominator - (liquidityFee));
        
        uint256 ETHToAddLiquidityWith = unitBalance * (liquidityFee);
        if(ETHToAddLiquidityWith > uint256(0)){
            addLiquidity(tokensToAddLiquidityWith, ETHToAddLiquidityWith); 
            }
        
        uint256 marketingAmt = unitBalance * (2) * (marketingFee);
        if(marketingAmt > 0){
            payable(marketing_receiver).transfer(marketingAmt);
            }
       
       uint256 developmentFeeAmt = unitBalance * (2) * (developmentFee);
        if(developmentFeeAmt > 0){
            payable(development_receiver).transfer(developmentFeeAmt);
            }
        
        uint256 remainingBalance = address(this).balance;
        if(remainingBalance > uint256(0)){
            payable(development_receiver).transfer(remainingBalance);
            }
   }

    function addLiquidity(uint256 tokenAmount, uint256 ETHAmount) private {
        _approve(address(this), address(router), tokenAmount);
        router.addLiquidityETH{value: ETHAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner,
            block.timestamp);
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        require(tokenAmount > 0, "amount must be greeter than 0");
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        _approve(address(this), address(router), tokenAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp);
    }

    function shouldSwapBack(address sender, address recipient, uint256 amount) internal view returns (bool) {
        bool aboveMin = amount >= _minTokenAmount;
        bool aboveThreshold = balanceOf(address(this)) >= _swapThreshold;
        return !swapping && swapEnabled && tradeEnable && aboveMin && !_isExcludedFromFee[sender] && recipient == pair && swapTimes >= uint256(0) && aboveThreshold;
    }

    function swapBack(address sender, address recipient, uint256 amount) internal {
        if(shouldSwapBack(sender, recipient, amount)){
            swapAndLiquify(_swapThreshold); swapTimes = uint256(0);
            }
    }

    function shouldTakeFee(address sender, address recipient) internal view returns (bool) {
        return !_isExcludedFromFee[sender] && !_isExcludedFromFee[recipient];
    }

    function getTotalFee(address sender, address recipient) internal view returns (uint256) {
        if(recipient == pair){
            return sellFee;
            }
        
        if(sender == pair){
            return buyFee;
            }
       
        return transferFee;
    }

    function takeFee(address sender, address recipient, uint256 amount) internal returns (uint256) {
        if(getTotalFee(sender, recipient) > 0){
        uint256 feeAmount = amount / (denominator) * (getTotalFee(sender, recipient));
        _balances[address(this)] = _balances[address(this)] + (feeAmount);
        emit Transfer(sender, address(this), feeAmount);
        if(burnFee > uint256(0)){_transfer(address(this), address(DEAD), amount / (denominator) * (burnFee));}
        return amount - (feeAmount);} return amount;
    }

   function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, currentAllowance - amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

}