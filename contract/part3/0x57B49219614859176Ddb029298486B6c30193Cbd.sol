// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import "./lib/IRouter02.sol";
import "./lib/IERC20.sol";
import "./lib/IFactoryV2.sol";
import "./lib/IV2Pair.sol";

contract Oracle is IERC20 {

    uint256 public constant maxBuyTaxes = 2500;    
    bool inSwap;
    uint256 public constant maxSellTaxes = 2500;
    uint256 public constant maxTransferTaxes = 2500;
    uint256 constant taxDivisor = 10000;
    uint256 internal _tSupply = 1000000000000000000000000000;
    address private _owner;
    uint256 private timeSinceLastPairCreated = 0;
    
    mapping(address => uint256) internal _tokenOwned;
    mapping(address => bool) allLiquidityPoolPairs;
    mapping(address => mapping(address => uint256)) internal _allowances;
    mapping(address => bool) internal _isExcludedFromFees;
    mapping(address => bool) internal _isExcludedFromLimits;
    mapping(address => bool) internal _liquidityHolders;

    Fees public _taxRates =
        Fees({buyFee: 500, sellFee: 1000, transferFee: 0});

    TaxPercentages public _taxPercentages =
        TaxPercentages({marketing: 70, dev: 30});

    uint256 internal lastSwap;

    uint256 internal _maxTxAmount = (_tSupply * 400) / 10000;
    uint256 internal _maxWalletSize = (_tSupply * 400) / 10000;
    TaxWallets public _taxWallets;

    bool public contractSwapEnabled = false;
    uint256 public contractSwapTimer = 0 seconds;
    uint256 public swapThreshold;

    bool public tradingEnabled = false;
    bool public _hasLiquidityBeenAdded = false;

    IRouter02 public dexRouter;
    address public lpPair;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    bool public liquidityPoolInitialized = false;

    struct Fees {
        uint16 buyFee;
        uint16 sellFee;
        uint16 transferFee;
    }

struct TaxPercentages {
        uint16 marketing;
        uint16 dev;
    }

    struct TaxWallets {
        address payable marketing;
        address payable dev;
    }

    event OwnershipTransferred(
        address indexed pastOwner,
        address indexed newOwner
    );
    event ContractSwapEnabledUpdated(bool enabled);
    event AutoLiquify(uint256 amountCurrency, uint256 amountTokens);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event TaxUpdated(uint256 buy, uint256 sell, uint256 transfer);
    event TaxDistributionPercentageUpdated(uint256 marketing, uint256 dev);
    event MaxTransactionAmountUpdated(uint256 amount);
    event SwapSettingsUpdated(uint256 threshold, uint256 time);


    modifier swapLock {
        inSwap = true;
        _;
        inSwap = false;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Caller must be the owner");
        _;
    }

    string internal _name = "Oracle AI";
    string internal _symbol = "ORACLE";
    uint8 internal _decimals = 18;

    constructor() payable {
        // Set the owner.
        _owner = address(msg.sender);

        _tokenOwned[msg.sender] = _tSupply;
        emit Transfer(address(0), msg.sender, _tSupply);

        // Multichain Token - Will need to rephrase
        dexRouter = IRouter02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _taxWallets.marketing=payable(0xE46638737702a8A0Ff41df055bF40cE9bE385c4B);
        _taxWallets.dev=payable(0x3F54800d28838A0AB7f25a007B1F9FcFEdC3cc67);

        _isExcludedFromFees[_owner] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[DEAD] = true;
        _isExcludedFromFees[_taxWallets.marketing] = true;
        _isExcludedFromFees[_taxWallets.dev] = true;
        _isExcludedFromFees[0xF041690D9cBE398d3D51F25C87902C1403AffE66] = true;
        _isExcludedFromFees[0xe6D5456Ac986A95b5d4D165ae1ed96c8a4E50BB2] = true;
        _isExcludedFromLimits[_taxWallets.marketing] = true;
        _isExcludedFromLimits[_taxWallets.dev] = true;
        _isExcludedFromLimits[0xF041690D9cBE398d3D51F25C87902C1403AffE66] = true;
        _isExcludedFromLimits[0xe6D5456Ac986A95b5d4D165ae1ed96c8a4E50BB2] = true;
        _liquidityHolders[_owner] = true;
    }

    function balanceOf(address account) public view override(IERC20)  returns (uint256) {
        return _tokenOwned[account];
    }
    
    function confirmLP(
    ) public onlyOwner{
        require(!liquidityPoolInitialized, 'LP already initited');
        lpPair = IFactoryV2(dexRouter.factory()).getPair(address(this), dexRouter.WETH());
        setLiquidityPoolPair(lpPair, true);
        liquidityPoolInitialized = true;
        _checkLiquidityAdd(msg.sender);
        allowTrading();
    }

    function setPairAddress (address pair
    ) public onlyOwner{
        require(pair!=address(0),'Invalid address');
        setLiquidityPoolPair(pair, true);
    }

    function isContract(address _addr) public view returns (bool){
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function preInitializeTransfer(
        address to,
        uint256 amount
    ) public onlyOwner {
        require(!liquidityPoolInitialized,'Liquidity pool must not be initialized');
        amount = amount * 10 ** _decimals;
        _finalizeTransfer(msg.sender, to, amount, false, false, false, true);
    }


    // Ownable removed as a lib and added here to allow for custom transfers and renouncements.
    // This allows for removal of ownership privileges from the owner once renounced or transferred.
    function transferOwner(address newOwner) external onlyOwner(){
        require(
            newOwner != address(0),
            "Call renounceOwnership to transfer owner to the zero address"
        );
        require(
            newOwner != DEAD,
            "Call renounceOwnership to transfer owner to the zero address"
        );
        setExcludedFromFees(_owner, false);
        setExcludedFromFees(newOwner, true);

        if (balanceOf(_owner) > 0) {
            _transfer(_owner, newOwner, balanceOf(_owner));
        }

        _owner = newOwner;
        emit OwnershipTransferred(_owner, newOwner);
    }

    function renounceOwnership() public onlyOwner {
        setExcludedFromFees(_owner, false);
        _owner = address(0);
        emit OwnershipTransferred(_owner, address(0));
    }

    //===============================================================================================================

    function totalSupply() external view override returns (uint256) {
        if (_tSupply == 0) {
            revert();
        }
        return _tSupply;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function getOwner() external view override returns (address) {
        return _owner;
    }

    function allowance(
        address holder,
        address spender
    ) external view override returns (uint256) {
        return _allowances[holder][spender];
    }

    
    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function approveContractContingency() public onlyOwner returns (bool) {
        _approve(address(this), address(dexRouter), type(uint256).max);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] -= amount;
        }

        return _transfer(sender, recipient, amount);
    }

    function setNewRouter(address newRouter) public onlyOwner {
        require(newRouter!=address(0),'Invalid address');
        IRouter02 _newRouter = IRouter02(newRouter);
        address get_pair = IFactoryV2(_newRouter.factory()).getPair(
            address(this),
            _newRouter.WETH()
        );
        if (get_pair == address(0)) {
            lpPair = IFactoryV2(_newRouter.factory()).createPair(
                address(this),
                _newRouter.WETH()
            );
        } else {
            lpPair = get_pair;
        }
        dexRouter = _newRouter;
        _approve(address(this), address(dexRouter), type(uint256).max);
    }

    function setLiquidityPoolPair(
        address pair,
        bool enabled
    ) public onlyOwner {
        require(pair!=address(0),'Invalid address');
        if (!enabled) {
            allLiquidityPoolPairs[pair] = false;
        } else {
            if (timeSinceLastPairCreated != 0) {
                require(
                    block.timestamp - timeSinceLastPairCreated > 3 days,
                    "3 Day cooldown.!"
                );
            }
            allLiquidityPoolPairs[pair] = true;
            timeSinceLastPairCreated = block.timestamp;
        }
    }
    
    function setTaxes(
        uint16 buyFee,
        uint16 sellFee,
        uint16 transferFee
    ) external onlyOwner {
        require(
            buyFee <= maxBuyTaxes &&
                sellFee <= maxSellTaxes &&
                transferFee <= maxTransferTaxes,
            "Cannot exceed maximum"
        );
        _taxRates.buyFee = buyFee;
        _taxRates.sellFee = sellFee;
        _taxRates.transferFee = transferFee;
        emit TaxUpdated(buyFee, sellFee, transferFee);
    }

    function setTaxPercentages(
        uint16 marketing
    ) external onlyOwner {
        require(marketing>=0 && marketing<=100,'Percentage should be between 0 - 100');
        _taxPercentages.marketing = marketing;
        _taxPercentages.dev = 100-marketing;
        emit TaxDistributionPercentageUpdated(marketing, _taxPercentages.dev);
    }

    function setMaxTxPercent(
        uint256 percent,
        uint256 divisor
    ) external onlyOwner {
        require(
            (_tSupply * percent) / divisor >= (_tSupply / 1000),
            "Max Transaction amount must be above 0.1% of total supply"
        );
        _maxTxAmount = (_tSupply * percent) / divisor;
        emit MaxTransactionAmountUpdated(_maxTxAmount);
    }


    function setSwapSettings(
        uint256 threshold,
        uint256 thresholdDivisor,
        uint256 time
    ) external onlyOwner {
        require(threshold > 0,'Threshold has to be higher than 0');
        require(thresholdDivisor%10 == 0 && thresholdDivisor > 0,'thresholdDivisor has to be higher than 0 and divisible by 10');
        swapThreshold = (_tSupply * threshold) / thresholdDivisor;
        contractSwapTimer = time;
        emit SwapSettingsUpdated(swapThreshold, time);
    }

    function setContractSwapEnabled(bool enabled) external onlyOwner {
        contractSwapEnabled = enabled;
        emit ContractSwapEnabledUpdated(enabled);
    }

    function setWallets(
        address payable marketing,
        address payable dev
    ) external onlyOwner {
        require(!isContract(marketing),'Cannot be a contract');
        require(!isContract(dev),'Cannot be a contract');
        _taxWallets.marketing = payable(marketing);
        _taxWallets.dev = payable(dev);
    }

    function preInitializeTransferMultiple(
        address[] memory accounts,
        uint256[] memory amounts
    ) external onlyOwner {
        require(accounts.length == amounts.length, "Accounts != Amounts");
        for (uint8 i = 0; i < accounts.length; i++) {
            require(balanceOf(msg.sender) >= amounts[i] * 10 ** _decimals,'Account have lower tokenb balance than needed');
            preInitializeTransfer(accounts[i], amounts[i]);
        }
    }




    function allowTrading() internal {
        require(!tradingEnabled, "Trading already enabled!");
        require(_hasLiquidityBeenAdded, "Liquidity must be added");
        tradingEnabled = true;
        swapThreshold = (_tSupply * 1) / 1000;

    }

    function takeTax(
        address from,
        bool buy,
        bool sell,
        uint256 amount
    ) internal returns (uint256) {
        uint256 currentFee;
        if (buy) {
            currentFee = _taxRates.buyFee;
        } else if (sell) {
            currentFee = _taxRates.sellFee;
        } else {
            currentFee = _taxRates.transferFee;
        }

        uint256 feeAmount = (amount * currentFee) / taxDivisor;

        _tokenOwned[address(this)] += feeAmount;
        emit Transfer(from, address(this), feeAmount);

        return amount - feeAmount;
    }


    function setMaxWalletSize(
        uint256 percent,
        uint256 divisor
    ) external onlyOwner {
        require(
            (_tSupply * percent) / divisor >= (_tSupply / 1000),
            "Max Wallet amount must be above 0.1% of total supply"
        );
        _maxWalletSize = (_tSupply * percent) / divisor;
    }

    function setExcludedFromLimits(
        address account,
        bool enabled
    ) external onlyOwner {
        _isExcludedFromLimits[account] = enabled;
    }


    function sweepContingency() external onlyOwner {
        require(!_hasLiquidityBeenAdded, "Cannot call after liquidity");
        payable(_owner).transfer(address(this).balance);
    }

    function contractSwap(uint256 contractTokenBalance) internal swapLock {

        TaxPercentages memory taxPercentages = _taxPercentages;

        if (
            _allowances[address(this)][address(dexRouter)] != type(uint256).max
        ) {
            _allowances[address(this)][address(dexRouter)] = type(uint256).max;
        }

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            contractTokenBalance,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amtBalance = address(this).balance;

        uint256 devBalance = (amtBalance * taxPercentages.dev) / 100;
        uint256 marketingBalance = amtBalance - devBalance;
        if (taxPercentages.dev > 0) {
            _taxWallets.dev.transfer(devBalance);
        }
        if (taxPercentages.marketing > 0) {
            _taxWallets.marketing.transfer(marketingBalance);
        }
    }

    function isExcludedFromLimits(address account) public view returns (bool) {
        return _isExcludedFromLimits[account];
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function setExcludedFromFees(
        address account,
        bool enabled
    ) public onlyOwner {
        _isExcludedFromFees[account] = enabled;
    }

    function getMaxTransaction() public view returns (uint256) {
        return _maxTxAmount / (10 ** _decimals);
    }

    function getMaxWallet() public view returns (uint256) {
        return _maxWalletSize / (10 ** _decimals);
    }

    function _finalizeTransfer(
        address from,
        address to,
        uint256 amount,
        bool takeFee,
        bool buy,
        bool sell,
        bool other
    ) internal returns (bool) {

        _tokenOwned[from] -= amount;
        uint256 amountReceived = (takeFee)
            ? takeTax(from, buy, sell, amount)
            : amount;
        _tokenOwned[to] += amountReceived;

        emit Transfer(from, to, amountReceived);
        return true;
    }

    function _hasLimits(address from, address to) internal view returns (bool) {
        return
            from != _owner &&
            to != _owner &&
            tx.origin != _owner &&
            !_liquidityHolders[to] &&
            !_liquidityHolders[from] &&
            to != DEAD &&
            to != address(0) &&
            from != address(this);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        // require(liquidityPoolInitialized, "LP must be intiialized first!");


        bool buy = false;
        bool sell = false;
        bool other = false;
        if (allLiquidityPoolPairs[from]) {
            buy = true;
        } else if (allLiquidityPoolPairs[to]) {
            sell = true;
        } else {
            other = true;
        }
        
        if (_hasLimits(from, to)) {
            if (!tradingEnabled) {
                revert("Trading not yet enabled!");
            }
            if (buy || sell) {
                if (
                    !_isExcludedFromLimits[from] && !_isExcludedFromLimits[to]
                ) {
                    require(
                        amount <= _maxTxAmount,
                        "Transfer amount exceeds the maxTransactionAmount"
                    );
                }
            }
            if (to != address(dexRouter) && !sell) {
                if (!_isExcludedFromLimits[to]) {
                    require(
                        balanceOf(to) + amount <= _maxWalletSize,
                        "Transfer amount exceeds the maxWalletSize."
                    );
                }
            }
        }

        bool takeFee = true;
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (sell) {
            if (!inSwap && contractSwapEnabled) {
                if (lastSwap + contractSwapTimer < block.timestamp) {
                    uint256 contractTokenBalance = balanceOf(address(this));
                    if (contractTokenBalance >= swapThreshold) {
                        contractTokenBalance = swapThreshold;
                        contractSwap(contractTokenBalance);
                        lastSwap = block.timestamp;
                    }
                }
            }
        }
        return _finalizeTransfer(from, to, amount, takeFee, buy, sell, other);
    }

    function distributeTax() public onlyOwner(){
         if (lastSwap + contractSwapTimer < block.timestamp) {
                    uint256 contractTokenBalance = balanceOf(address(this));
                    if (contractTokenBalance >= swapThreshold) {
                        contractTokenBalance = swapThreshold;
                        contractSwap(contractTokenBalance);
                        lastSwap = block.timestamp;
                    }
                }
    }

    function _approve(
        address sender,
        address spender,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: Zero Address");
        require(spender != address(0), "ERC20: Zero Address");

        _allowances[sender][spender] = amount;
        emit Approval(sender, spender, amount);
    }

    function _checkLiquidityAdd(address from) internal {
        require(!_hasLiquidityBeenAdded, "Liquidity already added and marked");
            _liquidityHolders[from] = true;
            _hasLiquidityBeenAdded = true;

            contractSwapEnabled = true;
            emit ContractSwapEnabledUpdated(true);
    }
    receive() payable external {}
}