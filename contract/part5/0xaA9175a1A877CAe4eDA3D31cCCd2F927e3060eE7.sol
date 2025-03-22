// SPDX-License-Identifier: MIT

// 0xBID - is a transparent decentralized autonomous gambling platform that turns players into partners.
// With every bid, you earn a share of $0xBID supply. Bid, stake, and win together.

// WEBSITE: https://0xbid.app/
// X (Twitter): https://x.com/0xBIDai
// Telegram: https://t.me/bid_portal

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";

contract BIDTOKEN is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
    address public router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    bool private swapping;

    address private operationsWallet;
    address public stakingWallet;

    uint256 public maxTransaction;
    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;

    mapping(address => uint256) private _holderLastTransferBlock;
    bool public transferDelayEnabled = true;
    uint256 public launchBlockNumber;

    uint256 public buyFees;
    uint256 public sellFees;
    uint256 private _maxSwapableTokens;

    uint256 public _preventSwapBefore = 20;
    uint256 public _removeLimitsAt = 25;
    uint256 public _totalBuys = 0;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedmaxTransaction;
    mapping(address => bool) public automatedMarketMakerPairs;

    event UpdateUniswapV2Router(
        address indexed newAddress,
        address indexed oldAddress
    );

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event operationsWalletUpdated(
        address indexed newWallet,
        address indexed oldWallet
    );

    event StakingWalletUpdated(
        address indexed newStakingWallet,
        address indexed oldStakingWallet
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    constructor(
        address _operationsWallet,
        address _stakingWallet
    ) ERC20("0xBID AI", "0xBID", 8) {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(router);

        excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Router = _uniswapV2Router;

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        uint256 totalSupply = 10_000_000 * 10 ** decimals();

        maxTransaction = (totalSupply * 150) / 10_000; // 1.5% max transaction at launch
        maxWallet = (totalSupply * 150) / 10_000; // 1.5% max wallet at launch
        swapTokensAtAmount = (totalSupply * 50) / 10_000; // 0.5%
        _maxSwapableTokens = (totalSupply * 100) / 10_000; // 1%

        buyFees = 2_500; // INITIAL BUY FEES
        sellFees = 2_500; // INITIAL SELL FEES

        operationsWallet = _operationsWallet;
        stakingWallet = _stakingWallet;

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);

        excludeFromMaxTransaction(owner(), true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);

        _mint(msg.sender, totalSupply);
    }

    receive() external payable {}

    function enableTrading() external onlyOwner {
        require(!tradingActive, "Token launched");
        tradingActive = true;
        launchBlockNumber = block.number;
        swapEnabled = true;
    }

    function removeLimits() internal returns (bool) {
        limitsInEffect = false;
        buyFees = 400;
        sellFees = 400;
        return true;
    }

    // disable Transfer delay - cannot be reenabled
    function disableTransferDelay() external onlyOwner returns (bool) {
        transferDelayEnabled = false;
        return true;
    }

    function updateSwapTokensAtAmount(
        uint256 newAmount
    ) external onlyOwner returns (bool) {
        require(
            newAmount >= (totalSupply() * 1) / 100_000,
            "Swap amount cannot be lower than 0.001% total supply."
        );
        require(
            newAmount <= (totalSupply() * 100) / 10_000,
            "Swap amount cannot be higher than 1% total supply."
        );
        swapTokensAtAmount = newAmount;
        return true;
    }

    function updateMaxTransaction(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 10) / 10_000),
            "Cannot set maxTransaction lower than 0.1%"
        );
        maxTransaction = newNum * (10 ** decimals());
    }

    function updateMaxWallet(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 50) / 10_000),
            "Cannot set maxWallet lower than 0.5%"
        );
        maxWallet = newNum * (10 ** decimals());
    }

    function excludeFromMaxTransaction(
        address updAds,
        bool isEx
    ) public onlyOwner {
        _isExcludedmaxTransaction[updAds] = isEx;
    }

    // only use to disable contract sales if absolutely necessary (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    function updateBuyFee(uint256 _newOperationsFee) external onlyOwner {
        buyFees = _newOperationsFee;
        require(buyFees <= 2_000);
    }

    function updateSellFee(uint256 _newOperationsFee) external onlyOwner {
        sellFees = _newOperationsFee;
        require(sellFees <= 2_000);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setAutomatedMarketMakerPair(
        address pair,
        bool value
    ) public onlyOwner {
        require(
            pair != uniswapV2Pair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateOperationsWallet(
        address newOperationsWallet
    ) external onlyOwner {
        emit operationsWalletUpdated(newOperationsWallet, operationsWallet);
        operationsWallet = newOperationsWallet;
    }

    function updateStakingWallet(address newStakingWallet) external onlyOwner {
        emit StakingWalletUpdated(newStakingWallet, stakingWallet);
        stakingWallet = newStakingWallet;
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (
                from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !swapping
            ) {
                if (!tradingActive) {
                    require(
                        _isExcludedFromFees[from] || _isExcludedFromFees[to],
                        "Trading is not active."
                    );
                }

                if (transferDelayEnabled) {
                    if (
                        to != owner() &&
                        to != address(uniswapV2Router) &&
                        to != address(uniswapV2Pair)
                    ) {
                        require(
                            _holderLastTransferBlock[tx.origin] < block.number,
                            "_transfer:: Transfer Delay enabled.  Only one purchase per block allowed."
                        );
                        _holderLastTransferBlock[tx.origin] = block.number;
                    }
                }

                //when buy
                if (
                    automatedMarketMakerPairs[from] &&
                    !_isExcludedmaxTransaction[to]
                ) {
                    require(
                        amount <= maxTransaction,
                        "Buy transfer amount exceeds the maxTransaction."
                    );
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded"
                    );
                }
                //when sell
                else if (
                    automatedMarketMakerPairs[to] &&
                    !_isExcludedmaxTransaction[from]
                ) {
                    require(
                        amount <= maxTransaction,
                        "Sell transfer amount exceeds the maxTransaction."
                    );
                } else if (!_isExcludedmaxTransaction[to]) {
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded"
                    );
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to] &&
            _totalBuys > _preventSwapBefore
        ) {
            swapping = true;
            swapBack(min(contractTokenBalance, _maxSwapableTokens));
            swapping = false;
        }

        bool takeFee = !swapping;

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;

        if (takeFee) {
            // on sell
            if (automatedMarketMakerPairs[to] && sellFees > 0) {
                fees = amount.mul(sellFees).div(10_000);
            }
            // on buy
            else if (automatedMarketMakerPairs[from] && buyFees > 0) {
                fees = amount.mul(buyFees).div(10_000);
                _totalBuys++;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);

        if (_totalBuys >= _removeLimitsAt && limitsInEffect) {
            removeLimits();
        }
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function swapTokensForEth(uint256 tokenAmount) private {
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

    function swapBack(uint256 amount) private {
        bool success;

        if (amount == 0) {
            return;
        }

        uint256 amountToSwapForETH = amount;

        swapTokensForEth(amountToSwapForETH);

        uint256 ethBalance = address(this).balance;

        uint256 operationsPart = ethBalance.mul(8_500).div(10_000); // 85% to operations
        uint256 stakingPart = ethBalance.mul(1_500).div(10_000); // 15% to staking

        (success, ) = address(operationsWallet).call{value: operationsPart}("");
        require(success, "Failed to send ETH to operations wallet");

        (success, ) = address(stakingWallet).call{value: stakingPart}("");
        require(success, "Failed to send ETH to staking wallet");
    }
}