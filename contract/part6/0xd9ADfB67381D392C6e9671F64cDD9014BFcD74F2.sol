/**

Morra Games is a web3 studio that incorporates cutting-edge technology and a community-driven  
approach to redefine the future of the entertainment industry. It operates as a platform that offers  
diverse entertainment ecosystems, including Gaming, Comics, Augmented Reality, and Esport, with 
a focus on creating content that resonates with the community's interests and passions. 

Linktree: https://linktr.ee/morragames
Telegram (Portal): t.me/morragames
Twitter: twitter.com/morragames

*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
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

interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
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

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
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
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
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
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _createInitialSupply(address account, uint256 amount)
        internal
        virtual
    {
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

    function renounceOwnership(bool confirmRenounce)
        external
        virtual
        onlyOwner
    {
        require(confirmRenounce, "Please confirm renounce!");
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface ILpPair {
    function sync() external;
}

interface IDexRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

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

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);
}

interface IDexFactory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

contract Morra is ERC20, Ownable {
    uint256 public maxBuyAmount;
    uint256 public maxSellAmount;
    uint256 public maxWallet;

    IDexRouter public dexRouter;
    address public lpPair;

    bool private swapping;
    uint256 public swapTokensAtAmount;

    address public devAddress;
    address public marketingAddress;
    address public reservedAddress;

    uint256 public tradingActiveBlock = 0; // 0 means trading is not active
    uint256 public antiBotBlock;
    mapping(address => bool) public botsBuy;
    address[] public identifiedBots;
    uint256 public botsIdentified;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;

    // Anti-bot and anti-whale mappings and variables
    mapping(address => uint256) private _holderLastTransferTimestamp; // to hold last Transfers temporarily during launch
    bool public transferDelayEnabled = true;

    uint256 public buyTotalFees;
    uint256 public buyDevFee;
    uint256 public buyLiquidityFee;
    uint256 public buyMarketingfee;

    uint256 public sellTotalFees;
    uint256 public sellDevFee;
    uint256 public sellLiquidityFee;
    uint256 public sellMarketingfee;

    uint256 public tokensForDev;
    uint256 public tokensForLiquidity;
    uint256 public tokensForMarketing;
    bool public markBotsEnabled = true;
    bool private taxFree = false; 

    /******************/

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedMaxTransactionAmount;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event EnabledTrading();

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event UpdatedMaxBuyAmount(uint256 newAmount);

    event UpdatedMaxSellAmount(uint256 newAmount);

    event UpdatedMaxWalletAmount(uint256 newAmount);

    event UpdatedDevAddress(address indexed newWallet);

    event UpdatedMarketingAddress(address indexed newWallet);

    event UpdatedReservedAddress(address indexed newWallet);

    event MaxTransactionExclusion(address _address, bool excluded);

    event OwnerForcedSwapBack(uint256 timestamp);

    event BotBlocked(address sniper);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    event TransferForeignToken(address token, uint256 amount);

    event UpdatedPrivateMaxSell(uint256 amount);

    event EnabledSelling();

    constructor() payable ERC20("Morra", "MORRA") {
        address newOwner = msg.sender; 

        address _dexRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; 

        // initialize router
        dexRouter = IDexRouter(_dexRouter);

        // create pair
        lpPair = IDexFactory(dexRouter.factory()).createPair(
            address(this),
            dexRouter.WETH()
        );
        _excludeFromMaxTransaction(address(lpPair), true);
        _setAutomatedMarketMakerPair(address(lpPair), true);

        uint256 totalSupply = 500 * 1e6 * 1e18; // 500 million

        maxBuyAmount = (totalSupply * 10) / 100; // 10%
        maxSellAmount = (totalSupply * 10) / 100; // 10%
        maxWallet = (totalSupply * 10) / 100; // 10%
        swapTokensAtAmount = (totalSupply * 5) / 10000; // 0.05 %

        buyDevFee = 2;
        buyLiquidityFee = 1;
        buyMarketingfee = 2;
        buyTotalFees = buyDevFee + buyLiquidityFee + buyMarketingfee;

        sellDevFee = 3;
        sellLiquidityFee = 1;
        sellMarketingfee = 3;
        sellTotalFees = sellDevFee + sellLiquidityFee + sellMarketingfee;

        devAddress = address(msg.sender);
        marketingAddress = address(0x92e394743b6d710ec011Ab85A36C01E9a08543c7);
        reservedAddress = address(0x13cB8918f77c0D2b7C8FfC7283A6eBF7f605019d);

        _excludeFromMaxTransaction(newOwner, true);
        _excludeFromMaxTransaction(address(this), true);
        _excludeFromMaxTransaction(address(0xdead), true);
        _excludeFromMaxTransaction(address(devAddress), true);
        _excludeFromMaxTransaction(address(marketingAddress), true);
        _excludeFromMaxTransaction(address(reservedAddress), true);
        _excludeFromMaxTransaction(address(dexRouter), true);

        excludeFromFees(newOwner, true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);
        excludeFromFees(address(devAddress), true);
        excludeFromFees(address(marketingAddress), true);
        excludeFromFees(address(reservedAddress), true);
        excludeFromFees(address(dexRouter), true);

        _createInitialSupply(newOwner, totalSupply);

        transferOwnership(newOwner);
    }

    receive() external payable {}

    function enableTrading(uint256 blocksForPenalty) external onlyOwner {
        require(!tradingActive, "Cannot reenable trading");
        require(
            blocksForPenalty <= 10,
            "Cannot make penalty blocks more than 10"
        );
        tradingActive = true;
        swapEnabled = true;
        tradingActiveBlock = block.number;
        antiBotBlock = tradingActiveBlock + blocksForPenalty;
        emit EnabledTrading();
    }

    function bots() external view returns (address[] memory) {
        return identifiedBots;
    }

    function identifySniper(address wallet) external onlyOwner {
        require(
            markBotsEnabled,
            "Mark bot functionality has been disabled forever!"
        );
        require(!botsBuy[wallet], "Wallet is already flagged.");
        botsBuy[wallet] = true;
    }

    function removeSniper(address wallet) external onlyOwner {
        require(botsBuy[wallet], "Wallet is already not flagged.");
        botsBuy[wallet] = false;
    }

    function emergencySetRouter(address router, bool _swapEnabled) external onlyOwner {
        require(!tradingActive, "Cannot set after trading is functional");
        dexRouter = IDexRouter(router);
        swapEnabled = _swapEnabled; 
    }

    // disable Transfer delay - cannot be reenabled
    function disableTransferDelay() external onlyOwner {
        transferDelayEnabled = false;
    }

    function setTaxFree(bool set) external onlyOwner {
        taxFree = set; 
    }

    function setMaxBuyAmount(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 5) / 1000) / 1e18,
            "Cannot set max buy amount lower than 0.5%"
        );
        require(
            newNum <= ((totalSupply() * 10) / 100) / 1e18,
            "Cannot set max buy amount higher than 10%"
        );
        maxBuyAmount = newNum * (10**18);
        emit UpdatedMaxBuyAmount(maxBuyAmount);
    }

    function setMaxSellAmount(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 5) / 1000) / 1e18,
            "Cannot set max sell amount lower than 0.5%"
        );
        require(
            newNum <= ((totalSupply() * 10) / 100) / 1e18,
            "Cannot set max sell amount higher than 10%"
        );
        maxSellAmount = newNum * (10**18);
        emit UpdatedMaxSellAmount(maxSellAmount);
    }

    function setMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 5) / 1000) / 1e18,
            "Cannot set max wallet amount lower than 0.5%"
        );
        require(
            newNum <= ((totalSupply() * 10) / 100) / 1e18,
            "Cannot set max wallet amount higher than 10%"
        );
        maxWallet = newNum * (10**18);
        emit UpdatedMaxWalletAmount(maxWallet);
    }

    // change the minimum amount of tokens to sell from fees
    function setSwapTokensAtAmount(uint256 newAmount) external onlyOwner {
        require(
            newAmount >= (totalSupply() * 1) / 100000,
            "Swap amount cannot be lower than 0.001% total supply."
        );
        require(
            newAmount <= (totalSupply() * 1) / 1000,
            "Swap amount cannot be higher than 0.1% total supply."
        );
        swapTokensAtAmount = newAmount;
    }

    function _excludeFromMaxTransaction(address updAds, bool isExcluded)
        private
    {
        _isExcludedMaxTransactionAmount[updAds] = isExcluded;
        emit MaxTransactionExclusion(updAds, isExcluded);
    }

    function excludeFromMaxTransaction(address updAds, bool isEx)
        external
        onlyOwner
    {
        if (!isEx) {
            require(
                updAds != lpPair,
                "Cannot remove uniswap pair from max txn"
            );
        }
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        external
        onlyOwner
    {
        require(
            pair != lpPair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );
        _setAutomatedMarketMakerPair(pair, value);
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;
        _excludeFromMaxTransaction(pair, value);
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function setBuyFees(
        uint256 _operationsFee,
        uint256 _liquidityFee,
        uint256 _marketingfee
    ) external onlyOwner {
        buyDevFee = _operationsFee;
        buyLiquidityFee = _liquidityFee;
        buyMarketingfee = _marketingfee;
        buyTotalFees = buyDevFee + buyLiquidityFee + buyMarketingfee;
        require(buyTotalFees <= 20, "Must keep fees at 20% or less");
    }

    function setSellFees(
        uint256 _operationsFee,
        uint256 _liquidityFee,
        uint256 _marketingfee
    ) external onlyOwner {
        sellDevFee = _operationsFee;
        sellLiquidityFee = _liquidityFee;
        sellMarketingfee = _marketingfee;
        sellTotalFees = sellDevFee + sellLiquidityFee + sellMarketingfee;
        require(sellTotalFees <= 30, "Must keep fees at 30% or less");
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "amount must be greater than 0");

        if (!tradingActive) {
            require(
                _isExcludedFromFees[from] || _isExcludedFromFees[to],
                "Trading is not active."
            );
        }

        if (!antiBot() && tradingActive) {
            require(
                !botsBuy[from] || to == owner() || to == address(0xdead),
                "Bots cannot transfer tokens in or out except to owner or dead address."
            );
        }

        if (limitsInEffect) {
            if (
                from != owner() &&
                to != owner() &&
                to != address(0xdead) &&
                !_isExcludedFromFees[from] &&
                !_isExcludedFromFees[to]
            ) {
                if (transferDelayEnabled) {
                    if (to != address(dexRouter) && to != address(lpPair)) {
                        require(
                            _holderLastTransferTimestamp[tx.origin] <
                                block.number - 2 &&
                                _holderLastTransferTimestamp[to] <
                                block.number - 2,
                            "_transfer:: Transfer Delay enabled.  Try again later."
                        );
                        _holderLastTransferTimestamp[tx.origin] = block.number;
                        _holderLastTransferTimestamp[to] = block.number;
                    }
                }

                //when buy
                if (
                    automatedMarketMakerPairs[from] &&
                    !_isExcludedMaxTransactionAmount[to]
                ) {
                    require(
                        amount <= maxBuyAmount,
                        "Buy transfer amount exceeds the max buy."
                    );
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max Wallet Exceeded"
                    );
                }
                //when sell
                else if (
                    automatedMarketMakerPairs[to] &&
                    !_isExcludedMaxTransactionAmount[from]
                ) {
                    require(
                        amount <= maxSellAmount,
                        "Sell transfer amount exceeds the max sell."
                    );
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max Wallet Exceeded"
                    );
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap && swapEnabled && !swapping && automatedMarketMakerPairs[to]
        ) {
            swapping = true;
            swapBack();
            swapping = false;
        }

        bool takeFee = true;
        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            // bot/sniper penalty.
            if (
                (antiBot()) &&
                automatedMarketMakerPairs[from] &&
                !automatedMarketMakerPairs[to] &&
                !_isExcludedFromFees[to] &&
                buyTotalFees > 0
            ) {

                if (!botsBuy[to]) {
                    botsBuy[to] = true;
                    botsIdentified += 1;
                    identifiedBots.push(to);
                    emit BotBlocked(to);
                }

                fees = (amount * 80) / 100;
                tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFees;
                tokensForDev += (fees * buyDevFee) / buyTotalFees;
                tokensForMarketing += (fees * buyMarketingfee) / buyTotalFees;
            }

            // on sell
            else if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                fees = (amount * sellTotalFees) / 100;
                tokensForLiquidity += (fees * sellLiquidityFee) / sellTotalFees;
                tokensForDev +=
                    (fees * sellDevFee) /
                    sellTotalFees;
                tokensForMarketing += (fees * sellMarketingfee) / sellTotalFees;
            }
            // on buy
            else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                fees = (amount * buyTotalFees) / 100;
                tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFees;
                tokensForDev += (fees * buyDevFee) / buyTotalFees;
                tokensForMarketing += (fees * buyMarketingfee) / buyTotalFees;
            }
            
            if(!taxFree) {

                if (fees > 0) {
                    super._transfer(from, address(this), fees);
                }

                amount -= fees;
            }
        }

        super._transfer(from, to, amount);
    }

    function antiBot() public view returns (bool) {
        return block.number < antiBotBlock;
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        _approve(address(this), address(dexRouter), tokenAmount);

        // make the swap
        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(dexRouter), tokenAmount);

        // add the liquidity
        dexRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            reservedAddress,
            block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));

        uint256 totalTokensToSwap = tokensForLiquidity +
            tokensForDev +
            tokensForMarketing;

        uint256 trueTokensToSwap = contractBalance < totalTokensToSwap ? contractBalance : totalTokensToSwap; 

        if (trueTokensToSwap == 0) {
            return;
        }

        if (trueTokensToSwap > swapTokensAtAmount * 30) {
            trueTokensToSwap = swapTokensAtAmount * 30;
        }

        bool success;

        // Halve the amount of liquidity tokens
        uint256 liquidityTokens = (trueTokensToSwap * tokensForLiquidity) /
            totalTokensToSwap /
            2;

        swapTokensForEth(trueTokensToSwap - liquidityTokens);

        uint256 ethBalance = address(this).balance;
        uint256 ethForLiquidity = ethBalance;

        uint256 ethForDev = (ethBalance * tokensForDev) /
            (totalTokensToSwap - (tokensForLiquidity / 2));
        uint256 ethForMarketing = (ethBalance * tokensForMarketing) /
            (totalTokensToSwap - (tokensForLiquidity / 2));

        ethForLiquidity -= ethForDev + ethForMarketing;

        tokensForLiquidity = 0;
        tokensForDev = 0;
        tokensForMarketing = 0;

        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            addLiquidity(liquidityTokens, ethForLiquidity);
        }

        (success, ) = address(marketingAddress).call{value: ethForMarketing}("");
        (success, ) = address(devAddress).call{
            value: address(this).balance
        }("");
    }

    function withdrawForeignToken(address _token, address _to)
        external
        onlyOwner
        returns (bool _sent)
    {
        require(_token != address(0), "_token address cannot be 0");
        require(
            _token != address(this) || !tradingActive,
            "Can't withdraw native tokens while trading is active"
        );
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        _sent = IERC20(_token).transfer(_to, _contractBalance);
        emit TransferForeignToken(_token, _contractBalance);
    }

    // withdraw ETH if stuck or someone sends to the address
    function withdrawStuckETH() external onlyOwner {
        bool success;
        (success, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
    }

    function setDevAddress(address _devAddress)
        external
        onlyOwner
    {
        require(
            _devAddress != address(0),
            "_devAddress address cannot be 0"
        );
        devAddress = payable(_devAddress);
        emit UpdatedDevAddress(_devAddress);
    }

    function setMarketingAddress(address _marketingAddress) external onlyOwner {
        require(
            _marketingAddress != address(0),
            "_marketingAddress address cannot be 0"
        );
        marketingAddress = payable(_marketingAddress);
        emit UpdatedMarketingAddress(_marketingAddress);
    }

    function setReservedAddress(address _reservedAddress) external onlyOwner {
        require(
            _reservedAddress != address(0),
            "_reservedAddress address cannot be 0"
        );
        reservedAddress = payable(_reservedAddress);
        emit UpdatedReservedAddress(_reservedAddress);
    }

    // force Swap back if slippage issues.
    function forceSwapBack() external onlyOwner {
        require(
            balanceOf(address(this)) >= swapTokensAtAmount,
            "Can only swap when token amount is at or higher than restriction"
        );
        swapping = true;
        swapBack();
        swapping = false;
        emit OwnerForcedSwapBack(block.timestamp);
    }

    // remove limits after token is stable
    function removeLimits() external onlyOwner {
        limitsInEffect = false;
    }

    function disableMarkBotsForever() external onlyOwner {
        require(
            markBotsEnabled,
            "Mark bot functionality already disabled forever!!"
        );

        markBotsEnabled = false;
    }
}