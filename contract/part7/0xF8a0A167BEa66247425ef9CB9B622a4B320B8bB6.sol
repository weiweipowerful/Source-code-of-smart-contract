/**
 *Submitted for verification at Etherscan.io on 2024-10-10
*/

// SPDX-License-Identifier: Unlicensed

//Resonator: store, share and acquire files anonymously and safely.

//Website: https://rsntr.io/
//Telegram - https://t.me/resonator_portal
//Twitter - https://x.com/resonator_io


pragma solidity 0.8.25;

interface ERC20 {
    function totalSupply() external view returns (uint256);
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
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

abstract contract Context {
    
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }
}

contract Ownable is Context {
    address public _owner;

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

    function renounceOwnership() external virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDEXRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

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
        uint deadline
    ) external;
}

interface InterfaceLP {}

contract RESONATOR is Ownable, ERC20 {

    address WETH;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant ZERO = 0x0000000000000000000000000000000000000000;

    string constant _name = "Resonator";
    string constant _symbol = "RSN";
    uint8 constant _decimals = 18; 
  

    uint256 _totalSupply = 1e8 * 10**_decimals;

    uint256 public _maxTxAmount = 5e5 * 10**_decimals;
    uint256 public _maxWalletAmount = 1e6 * 10**_decimals;
    uint256 public swapThreshold = 5e5 * 10**_decimals;

    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    
    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;

    uint256 public  buyFee = 30;
    uint256 public  sellFee = 30;
    uint256 private transferFee = 0;
    
    uint256 private lastSwap;
    uint256 private tradingStartTime;

    address private marketingFeeReceiver;
    address private developmentFeeReceiver;
    address private reservesFeeReceiver;

    struct TaxRatio {
       uint256 marketing;
       uint256 development;
       uint256 reserves;
    }

    TaxRatio public taxBreakdown = TaxRatio(40, 40, 20);
    TaxRatio private taxRatio;

    IDEXRouter public router;
    InterfaceLP private pairContract;
    address public pair;
    
    bool public TradingOpen = false;    

    bool public swapEnabled = true;
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    event maxWalletUpdated(uint256 indexed maxWalletAmount);
    event maxTxUpdated(uint256 indexed maxTxAmount);
    event maxLimitsRemoved(uint256 indexed maxWalletToken, uint256 indexed maxTxAmount);
    event exemptFees(address indexed holder, bool indexed exempt);
    event exemptTxLimit(address indexed holder, bool indexed exempt);
    event feesUpdated(uint256 indexed buyFee, uint256 indexed sellFee);
    event feesWalletsUpdated(address indexed marketingFeeReceiver, address indexed devFeeReceiver, address indexed infrastructureFeeReceiver);
    event swapbackSettingsUpdated(bool indexed enabled, uint256 indexed amount);
    event tradingEnabled(bool indexed enabled, uint256 indexed startTime , uint256 indexed lastTokenSwap);
    
    constructor () {
        router = IDEXRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        WETH = router.WETH();
        pair = IDEXFactory(router.factory()).createPair(WETH, address(this));
        pairContract = InterfaceLP(pair);
       
        
        _allowances[address(this)][address(router)] = type(uint256).max;

        marketingFeeReceiver = 0xA7c0F45ED0B6B288b726a0C74c3697Df9565DAC8;
        developmentFeeReceiver = 0x4678ACEC72ABD89b2F4cAeB58e716d09f30232Cd;
        reservesFeeReceiver = 0x40D1bD3c6E9EDAb2cC14FE95Ab10dD9504F3B203;

        isFeeExempt[msg.sender] = true; 
        isTxLimitExempt[msg.sender] = true;
        isTxLimitExempt[pair] = true;
        isTxLimitExempt[marketingFeeReceiver] = true;
        isTxLimitExempt[developmentFeeReceiver] = true;
        isTxLimitExempt[reservesFeeReceiver] = true;
        isTxLimitExempt[address(this)] = true;
        

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);

    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function name() external pure override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) {return owner();}
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if(currentAllowance != type(uint256).max){
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            unchecked {
                _allowances[sender][_msgSender()] = currentAllowance - amount;
            }
        }

        return _transferFrom(sender, recipient, amount);
    }

    function setMaxWallet(uint256 maxWalletAmount) external onlyOwner {
        require(maxWalletAmount >= 1e6, "Max wallet cannot be less than 0.5%.");
        _maxWalletAmount = maxWalletAmount * 10**_decimals;
        emit maxWalletUpdated(_maxWalletAmount);       
    }

    function setMaxTx(uint256 maxTxAmount) external onlyOwner {
        require(maxTxAmount >= 5e5, "Max tx cannot be less than 0.3%." ); 
        _maxTxAmount = maxTxAmount * 10**_decimals;
        emit maxTxUpdated(_maxTxAmount);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {

        if(inSwap){ return _basicTransfer(sender, recipient, amount); }

        if(sender != owner()){
            require(TradingOpen,"Trading not open yet");
        
           }
       
        if (sender != owner() || (recipient != address(this)  && recipient != address(DEAD) && recipient != pair && recipient != marketingFeeReceiver && !isTxLimitExempt[recipient])){
            uint256 heldTokens = balanceOf(recipient);
            require((heldTokens + amount) <= _maxWalletAmount,"Maximum Wallet size has been reached");}
            
       
        checkTxLimit(sender, amount);

        if(
            lastSwap != block.number &&
            _balances[address(this)] >= swapThreshold &&
            swapEnabled &&
            !inSwap &&
            recipient == pair
        ){ 
            swapBack();
            lastSwap = block.number;
            }
        
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }

        uint256 amountReceived = (isFeeExempt[sender] || isFeeExempt[recipient]) ? amount : takeFee(sender, amount, recipient);
        _balances[recipient] += amountReceived;

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }
    
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function checkTxLimit(address sender, uint256 amount) internal view {
        require(amount <= _maxTxAmount || isTxLimitExempt[sender], "Tx Limit Exceeded");
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function takeFee(address sender, uint256 amount, address recipient) internal returns (uint256) {
        uint256 feeAmount = 0;

        if(recipient == pair) {
            feeAmount = (amount * sellFee) / 100;
        } else if(sender == pair) {
            feeAmount = (amount * buyFee) / 100;
        }else{
            feeAmount = (amount * transferFee) / 100;
        }

        _balances[address(this)] += feeAmount;
        emit Transfer(sender, address(this), feeAmount);
        uint256 notFeeAmount = amount - feeAmount;

        return notFeeAmount;
    }

    function removeMaxLimits() external onlyOwner { 
        _maxWalletAmount = _totalSupply;
        _maxTxAmount = _totalSupply;
        emit maxLimitsRemoved(_maxWalletAmount, _maxTxAmount);
    }

    function clearStuckToken(address tokenAddress, uint256 tokens) external onlyOwner returns (bool) {
        require(address(tokenAddress) != address(this), "Cannot withdraw RSN tokens");
        if(tokens == 0){
            tokens = ERC20(tokenAddress).balanceOf(address(this));
        }
        return ERC20(tokenAddress).transfer(msg.sender, tokens);
    }


    function startTrading() external onlyOwner {
        require(!TradingOpen,"Trading already Enabled.");
        TradingOpen = true;
        tradingStartTime = block.timestamp;
        lastSwap = block.number;
        emit tradingEnabled(TradingOpen, tradingStartTime, lastSwap);
    }

    function swapBack() internal swapping {
        if (block.timestamp < tradingStartTime + 10 minutes) {
            taxRatio = TaxRatio(100, 0, 0);
        }else {
            taxRatio = taxBreakdown;
        }

        uint256 amountToSwap = swapThreshold;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 totalETHFee = address(this).balance;
        uint256 marketingEthAmount = (totalETHFee * taxRatio.marketing) / 100;
        uint256 developmentEthAmount = (totalETHFee * taxRatio.development) / 100;
        uint256 reservesEthAmount = totalETHFee - marketingEthAmount - developmentEthAmount;

        (bool tmpSuccess,) = payable(marketingFeeReceiver).call{value: marketingEthAmount}("");
        (tmpSuccess,) = payable(developmentFeeReceiver).call{value: developmentEthAmount}("");
        (tmpSuccess,) = payable(reservesFeeReceiver).call{value: reservesEthAmount}("");
        
        tmpSuccess = false;

    }

    function exemptAll(address holder, bool exempt) external onlyOwner {
        require(holder != address(0), "Holder is the zero address");
        isFeeExempt[holder] = exempt;
        isTxLimitExempt[holder] = exempt;
        emit exemptFees(holder, exempt);
    }

    function setTxLimitExempt(address holder, bool exempt) external onlyOwner {
        require(holder != address(0), "Holder is the zero address");
        isTxLimitExempt[holder] = exempt;
        emit exemptTxLimit(holder, exempt);
    }

    function updateFees(uint256 _buyFee, uint256 _sellFee) external onlyOwner {
        require( _buyFee <= 20 && _sellFee <= 20, "Fees can not be more than 20%"); 
        buyFee = _buyFee;
        sellFee = _sellFee;
        emit feesUpdated(buyFee, sellFee);
    }

    function updateFeeWallets( address _marketingFeeReceiver, address _developmentFeeReceiver, address _reservesFeeReceiver) external onlyOwner {
        require(_marketingFeeReceiver != address(0) && _developmentFeeReceiver != address(0) && _reservesFeeReceiver != address(0), "Fee receiver cannot be zero address");
        marketingFeeReceiver = _marketingFeeReceiver;
        developmentFeeReceiver = _developmentFeeReceiver;
        reservesFeeReceiver = _reservesFeeReceiver;
        emit feesWalletsUpdated(marketingFeeReceiver, developmentFeeReceiver, reservesFeeReceiver);
    }

    function editSwapbackSettings(bool _enabled, uint256 _amount) external onlyOwner {
        require( _amount <= 5e5 && _amount >= 1e5, "Swap amount can not be more than 0.5% or less than 0.1%"); 
        swapEnabled = _enabled;
        swapThreshold = _amount * 10**_decimals;
        emit swapbackSettingsUpdated(_enabled, _amount);
    }
    
    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply - balanceOf(DEAD)- balanceOf(ZERO);
    }

}