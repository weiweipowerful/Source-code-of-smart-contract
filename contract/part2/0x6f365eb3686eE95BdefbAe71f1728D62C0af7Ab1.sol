// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;


abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this;
        return msg.data;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
    unchecked {
        _approve(sender, _msgSender(), currentAllowance - amount);
    }

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
            unchecked {
                _approve(_msgSender(), spender, currentAllowance - subtractedValue);
            }
        }
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
    unchecked {
        _balances[sender] = senderBalance - amount;
    }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _createInitialSupply(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
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

interface IDexRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

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
}

interface IDexFactory {
    function createPair(address tokenA, address tokenB)
    external
    returns (address pair);
}

contract AITHER is ERC20, Ownable {

    uint256 public maxBuyAmount;
    uint256 public maxSellAmount;
    uint256 public maxWalletAmount;

    IDexFactory public immutable uniswapV2Factory;
    IDexRouter public immutable uniswapV2Router;
    address public uniswapV2Pair;
    address public immutable WETH;

    bool private swapping;
    uint256 public swapTokensAtAmount;
    uint256 public swapTokensMaxAmount;
    uint256 public swapTokensLastBlock;

    address public treasuryAddress;

    uint256 public tradingActiveBlock = 0; // 0 means trading is not active

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;
    bool public swapFeesOncePerBlock = true;

    address public sniperBotsGuard;
    mapping(address => bool) public isSniperBot;

    uint256 public buyFee;
    uint256 public sellFee;

    // exclude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;
    mapping (address => bool) public _isExcludedMaxTransactionAmount;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event EnabledTrading(bool tradingActive);
    event RemovedLimits();

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event UpdatedMaxBuyAmount(uint256 newAmount);

    event UpdatedMaxSellAmount(uint256 newAmount);

    event UpdatedMaxWalletAmount(uint256 newAmount);

    event UpdatedTreasuryAddress(address indexed newWallet);

    event MaxTransactionExclusion(address _address, bool excluded);

    event SwapFeeCollected(uint256 amount);
    event SwapBackResult(uint256 amountIn, uint256 amountOut);

    event TransferForeignToken(address token, uint256 amount);

    event IsSniperBotSet(address account, bool isSniper);
    event SniperBotsGuardSet(address account);

    event SwapTokensMaxAmountSet(uint256 newAmount);
    event SwapFeesOncePerBlockSet(bool newSetting);
    event SetSwapThreshold(uint256 newAmount);

    function setSwapTokensMaxAmountUnits(uint256 newAmount) external {
        require(
            msg.sender == treasuryAddress || msg.sender == owner(),
            "only treasuryAddress or owner can change swapTokensMaxAmount");
        swapTokensMaxAmount = newAmount * 10**18;
        emit SwapTokensMaxAmountSet(swapTokensMaxAmount);
    }

    function setSwapFeesOncePerBlock(bool newSetting) external {
        require(
            msg.sender == treasuryAddress || msg.sender == owner(),
            "only treasuryAddress or owner can change swapFeesOncePerBlock");
        swapFeesOncePerBlock = newSetting;
        emit SwapFeesOncePerBlockSet(newSetting);
    }

    function setSniperBot(address account, bool isSniper) external {
        require(
            msg.sender == sniperBotsGuard || msg.sender == owner(),
            "Only owner or sniperBotsGuard can set sniper bots");
        isSniperBot[account] = isSniper;
        emit IsSniperBotSet(account, isSniper);
    }

    function setSniperBotsGuard(address account) external {
        require(
            msg.sender == owner() || msg.sender == sniperBotsGuard,
            "Only owner or sniperBotsGuard can set sniper bots guard");
        sniperBotsGuard = account;
        emit SniperBotsGuardSet(account);
    }

    function _getDEXRouterAddress() internal view returns (address) {
        if (block.chainid == 1) {
            return 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;  // uniswap v2
        } else {
            revert("Chain ID not supported");
        }
    }

    constructor() ERC20("Aither Protocol", "$AITHER") {
        address newOwner = msg.sender;
        sniperBotsGuard = newOwner;

        IDexRouter _uniswapV2Router = IDexRouter(_getDEXRouterAddress());
        _excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Factory = IDexFactory(_uniswapV2Router.factory());
        WETH = _uniswapV2Router.WETH();
        uniswapV2Pair = uniswapV2Factory.createPair(address(this), WETH);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        uint256 totalSupply = 1_000_000_000 * 1e18;

        maxBuyAmount = totalSupply;
        maxSellAmount = totalSupply;
        maxWalletAmount = totalSupply;
        swapTokensAtAmount = totalSupply * 15 / 100_000;
        swapTokensMaxAmount = totalSupply / 100 * 5 / 100;  // 0.05% of total supply

        buyFee = 15;
        sellFee = 30;

        _excludeFromMaxTransaction(newOwner, true);
        _excludeFromMaxTransaction(address(this), true);
        _excludeFromMaxTransaction(address(0xdead), true);

        treasuryAddress = address(newOwner);

        excludeFromFees(newOwner, true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);
        excludeFromFees(treasuryAddress, true);

        _createInitialSupply(newOwner, totalSupply);
        transferOwnership(newOwner);
    }

    receive() external payable {}

    function getSwapThreshold() external view returns (uint256) {
        return swapTokensAtAmount;
    }

    function getTradingActiveBlock() external view returns (uint256) {
        return tradingActiveBlock;
    }

    function getTradingActive() external view returns (bool) {
        return tradingActive;
    }

    function updateMaxBuyAmount(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 1 / 1000) / 1e18, "Cannot set max buy amount lower than 0.1%");
        maxBuyAmount = newNum * (10**18);
        emit UpdatedMaxBuyAmount(maxBuyAmount);
    }

    function getFees() external view returns (uint256, uint256) {
        return (buyFee, sellFee);
    }

    function setFees(uint256 _buyFee, uint256 _sellFee) external onlyOwner {
        require(_buyFee <= 30, "Fees must be 30% or less");
        require(_sellFee <= 30, "Fees must be 30% or less");
        buyFee = _buyFee;
        sellFee = _sellFee;
    }

    function updateMaxSellAmount(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 1 / 1000) / 1e18, "Cannot set max sell amount lower than 0.1%");
        maxSellAmount = newNum * (10**18);
        emit UpdatedMaxSellAmount(maxSellAmount);
    }

    // remove limits after token is stable
    function removeLimits() external onlyOwner {
        limitsInEffect = false;
        emit RemovedLimits();
    }

    function _excludeFromMaxTransaction(address updAds, bool isExcluded) private {
        _isExcludedMaxTransactionAmount[updAds] = isExcluded;
        emit MaxTransactionExclusion(updAds, isExcluded);
    }

    function excludeFromMaxTransaction(address updAds, bool isEx) external onlyOwner {
        if(!isEx){
            require(updAds != uniswapV2Pair, "Cannot remove uniswap pair from max txn");
        }
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 3 / 1000) / 1e18, "Cannot set max wallet amount lower than 0.3%");
        maxWalletAmount = newNum * (10**18);
        emit UpdatedMaxWalletAmount(maxWalletAmount);
    }

    function setSwapThresholdUnits(uint256 newAmount) external {
        require(msg.sender == treasuryAddress || msg.sender == owner(),
            "only treasuryAddress or owner can change swapThreshold");
        swapTokensAtAmount = newAmount * 10**18;
        emit SetSwapThreshold(swapTokensAtAmount);
    }

    function updateSwapThreshold(uint256 newAmount) public  {
        require(msg.sender == treasuryAddress,
            "only treasuryAddress can change swapThreshold");
        swapTokensAtAmount = newAmount * (10**18);
        emit SetSwapThreshold(swapTokensAtAmount);
    }

    function transferForeignToken(address _token, address _to) public returns (bool _sent) {
        require(_token != address(0), "_token address cannot be 0");
        require(msg.sender == treasuryAddress,
            "only treasuryAddress can withdraw");
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        _sent = IERC20(_token).transfer(_to, _contractBalance);
        emit TransferForeignToken(_token, _contractBalance);
    }

    // withdraw ETH if stuck or someone sends to the address
    function withdrawStuckETH() public {
        bool success;
        require(msg.sender == treasuryAddress,"only treasuryAddress can withdraw");
        (success,) = address(msg.sender).call{value: address(this).balance}("");
    }

    address public feesController;
    event FeesControllerSet(address newController);
    function setFeesController(address _feesController) external {
        require(msg.sender == owner() || msg.sender == feesController,
            "Only owner or feesController can set feesController");
        feesController = _feesController;
        emit FeesControllerSet(_feesController);
    }

    function updateBuyFee(uint256 _fee) external {
        require(msg.sender == feesController || msg.sender == owner(),
            "Only owner or feesController can update buyFee");
        buyFee = _fee;
        require(buyFee <= 30, "Fees must be 30% or less");
    }

    function updateSellFee(uint256 _fee) external {
        require(msg.sender == feesController || msg.sender == owner(),
            "Only owner or feesController can update sellFee");
        sellFee = _fee;
        require(sellFee <= 30, "Fees must be 30% or less");
    }

    function updateBuysSellFees(
        uint256 _buyFee,
        uint256 _sellFee
    ) external {
        require(msg.sender == feesController || msg.sender == owner(),
            "Only owner or feesController can update buyFee");
        require(_buyFee <= 30, "Fees must be 30% or less");
        require(_sellFee <= 30, "Fees must be 30% or less");
        buyFee = _buyFee;
        sellFee = _sellFee;
    }

    function excludeFromFees(address account, bool excluded) public {
        require(msg.sender == owner() || msg.sender == feesController,
            "Only owner or feesController can exclude from fees");
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function _getBuyFee() public view returns (uint256) {
        if (tradingActiveBlock == 0) {
            return 50;  // sniper bots prevention
        } else if (
            (tradingActiveBlock < block.number)
            &&
            (block.number <= tradingActiveBlock + 3)
        ) {
            return 49;  // sniper bots prevention
        } else if (
            (tradingActiveBlock + 3 < block.number)
            &&
            (block.number <= tradingActiveBlock + 6)
        ){
            return 30;  // sniper bots prevention
        } else {
            return buyFee;
        }
    }

    function _getSellFee() public view returns (uint256) {
        if (tradingActiveBlock == 0) {
            return 50;  // sniper bots prevention
        } else if (
            (tradingActiveBlock < block.number)
            &&
            (block.number <= tradingActiveBlock + 3)
        ) {
            return 50;  // sniper bots prevention
        } else if (
            (tradingActiveBlock + 3 < block.number)
            &&
            (block.number <= tradingActiveBlock + (180/12))
        ) {
            return 40;  // sniper bots prevention
        } else {
            return sellFee;
        }
    }

    function _getBuyAndSellFee() public view returns (uint256, uint256) {
        return (_getBuyFee(), _getSellFee());
    }

    function _transfer(address from, address to, uint256 amount) internal override {

        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "amount must be greater than 0");

        require(!isSniperBot[from] && !isSniperBot[to], "Sniper bots are not allowed");

        if(limitsInEffect){
            if (from != owner() && to != owner() && to != address(0) && to != address(0xdead)){
                if(!tradingActive){
                    require(_isExcludedMaxTransactionAmount[from] || _isExcludedMaxTransactionAmount[to], "Trading is not active.");
                    require(from == owner(), "Trading is not enabled");
                }
                //when buy
                if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                    require(amount <= maxBuyAmount, "Buy transfer amount exceeds the max buy.");
                    require(amount + balanceOf(to) <= maxWalletAmount, "Cannot Exceed max wallet");
                }
                //when sell
                else if (automatedMarketMakerPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(amount <= maxSellAmount, "Sell transfer amount exceeds the max sell.");
                }
                else if (!_isExcludedMaxTransactionAmount[to] && !_isExcludedMaxTransactionAmount[from]){
                    require(amount + balanceOf(to) <= maxWalletAmount, "Cannot Exceed max wallet");
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if(
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;
            _swapBack();
            swapping = false;
        }

        bool takeFee = true;
        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        // only take fees on Trades, not on wallet transfers

        if(takeFee && tradingActiveBlock>0 && (block.number>=tradingActiveBlock)) {
            uint256 fees = 0;

            // on sell
            if (automatedMarketMakerPairs[to] && _getSellFee() > 0) {
                fees = amount * _getSellFee() / 100;
            }
            // on buy
            else if(automatedMarketMakerPairs[from] && _getBuyFee() > 0) {
                fees = amount * _getBuyFee() / 100;
            }

            if(fees > 0){
                super._transfer(from, address(this), fees);
            }

            amount -= fees;

            emit SwapFeeCollected(fees);
        }

        super._transfer(from, to, amount);
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        _approve(
            address(this), address(uniswapV2Router), tokenAmount);

        uint ethBalanceBeforeSwap = address(this).balance;

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        emit SwapBackResult(tokenAmount, address(this).balance - ethBalanceBeforeSwap);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != uniswapV2Pair,
            "The pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        _excludeFromMaxTransaction(pair, value);

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function createPool() public onlyOwner {
        uniswapV2Pair = uniswapV2Factory.createPair(address(this), WETH);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);
    }

    function setTreasuryAddress(address _TreasuryAddress) external onlyOwner {
        require(_TreasuryAddress != address(0),
            "_TreasuryAddress address cannot be 0");
        treasuryAddress = payable(_TreasuryAddress);
        emit UpdatedTreasuryAddress(_TreasuryAddress);
    }

    event SwapTokensLastBlockSet(uint256 newBlock);
    event SkipSwapBecauseOfBlock();

    function _swapBack() private {
        uint256 tokensToSwap = balanceOf(address(this));
        if(tokensToSwap == 0) {return;}

        if (swapFeesOncePerBlock && swapTokensLastBlock == block.number) {
            emit SkipSwapBecauseOfBlock();
            return;
        }
        swapTokensLastBlock = block.number;
        emit SwapTokensLastBlockSet(block.number);

        if (swapTokensMaxAmount > 0) {
            if (tokensToSwap > swapTokensMaxAmount) {
                tokensToSwap = swapTokensMaxAmount;
            }
        } else {
            if(tokensToSwap > swapTokensAtAmount * 5){
                tokensToSwap = swapTokensAtAmount * 5;
            }
        }

        bool success;

        _swapTokensForEth(tokensToSwap);

        uint256 ethBalance=address(this).balance;
        if (ethBalance > 0) {
            (success,) = address(treasuryAddress).call{value: ethBalance}("");
        }
    }

    function makeManualSwap() external {
        require(_msgSender() == treasuryAddress,
            "Only treasuryAddress can manually swap");
        uint256 tokenBalance = balanceOf(address(this));
        if(tokenBalance > 0){
            swapping = true;
            _swapBack();
            swapping = false;
        }
    }

    // once enabled, can never be turned off
    function enableTrading() external onlyOwner {
        require(!tradingActive, "Cannot re enable trading");
        tradingActive = true;
        swapEnabled = true;
        emit EnabledTrading(tradingActive);
        tradingActiveBlock = block.number;
    }
}