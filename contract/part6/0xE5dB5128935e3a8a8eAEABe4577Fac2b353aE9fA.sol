/**
 *Submitted for verification at Etherscan.io on 2024-12-13
*/

// SPDX-License-Identifier: MIT
/*
   _____   ____ _____________ ____  __.
  /  _  \ |    |   \______   \    |/ _|
 /  /_\  \|    |   /|       _/      <  
/    |    \    |  / |    |   \    |  \ 
\____|__  /______/  |____|_  /____|__ \
  Website:  https://aurk.org/
  X:        https://x.com/aiaurk
  Telegram: https://t.me/aurkai
  Docs:     https://aurk.gitbook.io/aurk-whitepaper
*/

pragma solidity 0.8.20;

interface IERC20 {
    event Transfer(
        address indexed sender,
        address indexed recipient,
        uint256 amount
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

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
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

contract Ownable is Context {
    address private _contractOwner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * Constructor sets the deployer as the initial owner of the contract.
     */
    constructor() {
        address msgSender = _msgSender();
        _contractOwner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _contractOwner;
    }

    modifier onlyOwner() {
        require(
            _contractOwner == _msgSender(),
            "Ownable: caller is not the owner"
        );
        _;
    }

    /**
     * Transfers ownership to a new address.
     * newOwner cannot be a zero address.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _updateOwnership(newOwner);
    }

    function _updateOwnership(address newOwner) internal {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_contractOwner, newOwner);
        _contractOwner = newOwner;
    }

    /**
     * Renounces ownership, making the contract ownerless.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_contractOwner, address(0));
        _contractOwner = address(0);
    }
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 tokenAmount,
        uint256 minETHAmount,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 tokenDesired,
        uint256 tokenMin,
        uint256 ethMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 tokenAmount,
            uint256 ethAmount,
            uint256 liquidity
        );
}

contract AURK is Context, IERC20, Ownable {
    string private constant _tokenName = "Aurk AI";
    string private constant _tokenSymbol = "AURK";
    uint8 private constant _tokenDecimals = 18;
    uint256 private constant _totalSupply = 100000000 * 10**_tokenDecimals;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _excludedAccounts;

    uint256 private constant _minSwapTokens = 10000 * 10**_tokenDecimals; // Min. tokens to swap
    uint256 private _maxSwapTokens = 50000 * 10**_tokenDecimals; // Max tokens to swap
    uint256 private _lastSwapBlock;
    uint256 private _swapCount;

    uint256 public maxTxValue = 1500000 * 10**_tokenDecimals; // Max tx value
    uint256 public maxWalletHoldings = 1500000 * 10**_tokenDecimals; // Max wallet value

    uint256 private _launchBlock;
    uint256 buyFeeRate = 30; // Buy fee
    uint256 sellFeeRate = 30; // Sell fee

    IUniswapV2Router02 private _uniswapV2Router;
    address public uniswapV2Pair;

    address ProjectWallet; //Primary Fee Wallet
    address DevOps;
    address EcoWallet;
    address BDWallet;
    address CreatorWallet;
    address UserWallet;
    address TeamWallet;

    bool private _isTradingActive = false;

    //** Begin Constructor

    constructor() {
        // Define wallet addresses
        ProjectWallet = 0x1eA8f412DD2f17BE2048880c18f5Ee5C1d6DcA95;
        EcoWallet = 0xFDf7Ad778F7Bdf8F8e1B49F2067dC54523a0abC8;
        BDWallet = 0x23545ecDC9EACe9F93BB4006047c00cE047b91fE;
        CreatorWallet = 0x921b6bb12a25275A03fEA22e419c82f2b56F9a51;
        UserWallet = 0x9Ab15eb4665Ae4bE78BCB04FF09D30d6269838ce;
        TeamWallet = 0x4c6ae48AEcC3251e2De83b1098B7b866BF6b6DfB;
        DevOps = 0x81A19e3bC368F67cdEE79B48cD78B82c7AAE43AE;

        // Calculate token allocations
        uint256 dexLiquidityTokens = (_totalSupply * 65) / 100;
        uint256 projectTokens = (_totalSupply * 2) / 100;
        uint256 ecosystemTokens = (_totalSupply * 10) / 100;
        uint256 businessDevTokens = (_totalSupply * 5) / 100;
        uint256 creatorTokens = (_totalSupply * 5) / 100;
        uint256 userTokens = (_totalSupply * 8) / 100;
        uint256 teamTokens = (_totalSupply * 5) / 100;

        // Distribute tokens
        _balances[address(this)] = dexLiquidityTokens; // DEX Liquidity
        _balances[ProjectWallet] = projectTokens; // Project Reserve
        _balances[EcoWallet] = ecosystemTokens; // Listings & Ecosystem
        _balances[BDWallet] = businessDevTokens; // Partnerships & Business Development
        _balances[CreatorWallet] = creatorTokens; // Creator Incentives
        _balances[UserWallet] = userTokens; // User Incentives
        _balances[TeamWallet] = teamTokens; // Team & Advisors

        // Apply exclusions
        _excludedAccounts[msg.sender] = 1;
        _excludedAccounts[address(this)] = 1;
        _excludedAccounts[ProjectWallet] = 1;
        _excludedAccounts[EcoWallet] = 1;
        _excludedAccounts[BDWallet] = 1;
        _excludedAccounts[CreatorWallet] = 1;
        _excludedAccounts[UserWallet] = 1;
        _excludedAccounts[TeamWallet] = 1;

        // Initialize swap-related state variables
        _lastSwapBlock = 0;
        _swapCount = 0;

        // Emit transfer events
        emit Transfer(address(0), address(this), dexLiquidityTokens);
        emit Transfer(address(0), ProjectWallet, projectTokens);
        emit Transfer(address(0), EcoWallet, ecosystemTokens);
        emit Transfer(address(0), BDWallet, businessDevTokens);
        emit Transfer(address(0), CreatorWallet, creatorTokens);
        emit Transfer(address(0), UserWallet, userTokens);
        emit Transfer(address(0), TeamWallet, teamTokens);
    }

    function name() public pure returns (string memory) {
        return _tokenName;
    }

    function symbol() public pure returns (string memory) {
        return _tokenSymbol;
    }

    function decimals() public pure returns (uint8) {
        return _tokenDecimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _totalSupply;
    }

    //Return fee rate values
    function getFeeRates()
        external
        view
        returns (uint256 buyTax, uint256 sellTax)
    {
        buyTax = buyFeeRate;
        sellTax = sellFeeRate;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _executeTransfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _setAllowance(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _executeTransfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: transfer amount exceeds allowance"
            );
            unchecked {
                _setAllowance(sender, _msgSender(), currentAllowance - amount);
            }
        }
        return true;
    }

    function _setAllowance(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    //Enables trading and adds liquidity at once
    function startTrading() external onlyOwner {
        require(!_isTradingActive, "Trading is already enabled");
        _uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        _setAllowance(address(this), address(_uniswapV2Router), _totalSupply);

        _uniswapV2Router.addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            block.timestamp
        );

        IERC20(uniswapV2Pair).approve(
            address(_uniswapV2Router),
            type(uint256).max
        );
        _isTradingActive = true;
        _launchBlock = block.number;
    }

    //Include or Exclude from fees
    function setExcludedAccount(address account, uint256 value)
        external
        onlyOwner
    {
        _excludedAccounts[account] = value;
    }

    //Remove limits when stable
    function disableLimits() external onlyOwner {
        maxTxValue = _totalSupply;
        maxWalletHoldings = _totalSupply;
    }

    // Adjust tax rates
    function adjustTaxRates(uint256 newBuyTaxRate, uint256 newSellTaxRate)
        external
        onlyOwner
    {
        require(newBuyTaxRate <= 100, "Buy tax rate cannot exceed 100%");
        require(newSellTaxRate <= 100, "Sell tax rate cannot exceed 100%");

        buyFeeRate = newBuyTaxRate;
        sellFeeRate = newSellTaxRate;
    }

    // Handles transfer and applies tax

    function _executeTokenTransfer(
        address from,
        address to,
        uint256 amount,
        uint256 taxRate
    ) private {
        uint256 taxAmount = (amount * taxRate) / 100;
        uint256 transferAmount = amount - taxAmount;

        _balances[from] -= amount;
        _balances[to] += transferAmount;
        _balances[address(this)] += taxAmount;

        emit Transfer(from, to, transferAmount);
    }

    //Transfer function
    function _executeTransfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(amount > 0, "ERC20: transfer amount must be greater than zero");

        uint256 taxRate = 0;

        if (_excludedAccounts[from] == 0 && _excludedAccounts[to] == 0) {
            require(_isTradingActive, "Trading is not enabled yet");
            require(
                amount <= maxTxValue,
                "Transaction amount exceeds the maximum limit"
            );

            if (to != uniswapV2Pair && to != address(0xdead)) {
                require(
                    balanceOf(to) + amount <= maxWalletHoldings,
                    "Recipient wallet exceeds the maximum limit"
                );
            }

            if (block.number < _launchBlock + 3) {
                taxRate = (from == uniswapV2Pair) ? 30 : 30;
            } else {
                if (from == uniswapV2Pair) {
                    taxRate = buyFeeRate;
                } else if (to == uniswapV2Pair) {
                    uint256 contractTokenBalance = balanceOf(address(this));
                    if (contractTokenBalance > _minSwapTokens) {
                        uint256 swapAmount = _maxSwapTokens;
                        if (contractTokenBalance > amount)
                            contractTokenBalance = amount;
                        if (contractTokenBalance > swapAmount)
                            contractTokenBalance = swapAmount;
                        _exchangeTokensForEth(contractTokenBalance);
                    }
                    taxRate = sellFeeRate;
                }
            }
        }
        _executeTokenTransfer(from, to, amount, taxRate);
    }

    //Recovers stuck ETH
    function withdrawEth() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Rescue ETH failed");
    }

    //Recovers stuck tokens
    function recoverTokens() external onlyOwner {
        uint256 contractTokenBalance = balanceOf(address(this));
        require(contractTokenBalance > 0, "No tokens to rescue");

        _executeTokenTransfer(address(this), owner(), contractTokenBalance, 0);
    }

    //Force swapback
    function executeManualSwap(uint256 percent) external onlyOwner {
        uint256 contractTokenBalance = balanceOf(address(this));
        uint256 swapAmount = (percent * contractTokenBalance) / 100;
        _exchangeTokensForEth(swapAmount);
    }

    //Swapback logic
    function _exchangeTokensForEth(uint256 tokenAmount) private {
        // Check if it's the current block
        if (block.number == _lastSwapBlock) {
            // Allow a maximum of 2 swaps in the same block
            require(_swapCount < 2, "Maximum swaps per block reached");
            _swapCount++;
        } else {
            // Reset for a new block
            _lastSwapBlock = block.number;
            _swapCount = 1;
        }

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _uniswapV2Router.WETH();

        _setAllowance(address(this), address(_uniswapV2Router), tokenAmount);

        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 contractEthBalance = address(this).balance;

        // Calculate balances
        uint256 devOpsShare = (contractEthBalance * 10) / 100;
         uint256 projectShare = (contractEthBalance * 90) / 100;

        // Transfer to DevOps wallet
        (bool successDevOps, ) = DevOps.call{value: devOpsShare}("");
        require(successDevOps, "Transfer to DevOps failed");

        // Transfer to ProjectWallet
        (bool successProject, ) = ProjectWallet.call{value: projectShare}("");
        require(successProject, "Transfer to ProjectWallet failed");
    }

    receive() external payable {}
}