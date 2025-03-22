// Website: https://zktao.ai/ 
// Docs: https://docs.zktao.ai/
// X (Twitter): https://x.com/zkTAO_ai
// Telegram: https://t.me/zkTAO_ai

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";

contract ZkTAO is Ownable, ERC20 {
    using SafeMath for uint256;

    uint256 public MAX_SUPPLY = 210000000 * 10 ** 18;

    IUniswapV2Router02 public uniswapV2Router;
    address public pair;
    address public developmentFund;
    address public stakingAndNftHolderPool;

    struct Taxes {
        uint256 rewardStake;
        uint256 development;
    }

    Taxes public buyTaxes = Taxes(2, 3);
    Taxes public sellTaxes = Taxes(2, 3);

    uint256 public totalBuyFee = 5;
    uint256 public totalSellFee = 5;
    bool inSwap = false;

    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) private _isExcludedFromMaxWallet;

    uint256 public swapAtAmount = 150000 ether;
    uint256 public maxHolder = MAX_SUPPLY;
    uint256 public maxWalletTime;
    uint256 public tradingTime;
    uint256 private _maxBuy;

    bool public tradingEnabled;
    bool private swapAndLiquifyEnabled = true;

    constructor() ERC20("ZkTAO", "ZAO") {
        _mint(_msgSender(), MAX_SUPPLY);
        tradingEnabled = false;
        developmentFund = address(0xCDf2426fDc1660F002EFD9cbB95866Ce6E1962C4);
        stakingAndNftHolderPool = address(0x38b53406294ceBfcb62122ae71cDb112e2aD72ac);

        IUniswapV2Router02 _router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address _pair = IUniswapV2Factory(_router.factory()).createPair(
            address(this),
            _router.WETH()
        );
        uniswapV2Router = _router;
        pair = _pair;

        isExcludedFromFee[_msgSender()] = true;
        isExcludedFromFee[developmentFund] = true;
        isExcludedFromFee[stakingAndNftHolderPool] = true;
        isExcludedFromFee[address(this)] = true;

        excludeFromMaxWallet(_msgSender(), true);
        excludeFromMaxWallet(address(pair), true);
        excludeFromMaxWallet(address(this), true);
        excludeFromMaxWallet(address(uniswapV2Router), true);
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "Trading already enabled.");
        tradingEnabled = true;
        maxHolder = 3150000 ether;
        maxWalletTime = block.timestamp + 2 minutes;
        tradingTime = block.timestamp;
        _maxBuy = 525000 ether;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {

        uint256 taxFee;
        if (
            !isExcludedFromFee[from] && !isExcludedFromFee[to] && !inSwap
        ) {
            require(tradingEnabled, "Trading not yet enabled!");

            if (!_isExcludedFromMaxWallet[to] && block.timestamp <= maxWalletTime) {
                require(
                    amount + balanceOf(to) <= maxHolder,
                    "Unable to exceed Max Wallet"
                );
            }
            if(pair == from && block.timestamp <= tradingTime + 30 seconds) {
                require(amount <= _maxBuy, "Unable to exceed Max Buy");
            }
        }
        if (inSwap) {
            super._transfer(from, to, amount);
            return;
        }
        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapAtAmount && from !=pair;

        if (
            canSwap &&
            !inSwap &&
            swapAndLiquifyEnabled
        ) {
            inSwap = true;
            swapTokensForETH(swapAtAmount);
            inSwap = false;
        }
        if (!isExcludedFromFee[from] && pair == to) {
            taxFee = totalSellFee;
        } else if (!isExcludedFromFee[to] && pair == from) {
            taxFee = totalBuyFee;
        }

        if (taxFee > 0 && from != address(this) && to != address(this)) {
            uint256 _fee = amount.mul(taxFee).div(100);
            super._transfer(from, address(this), _fee);
            amount = amount.sub(_fee);
        }

        super._transfer(from, to, amount);
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETH(tokenAmount, 0, path, address(this), block.timestamp);
        uint currentETH = address(this).balance;
        uint developFundValue = currentETH.mul(sellTaxes.development).div(totalSellFee);
        uint stakingValue = currentETH.sub(developFundValue);
        payable(developmentFund).call{value: developFundValue}("");
        payable(stakingAndNftHolderPool).call{value: stakingValue}("");
    }

    function setExcludeFromFee(address _address, bool _status) external onlyOwner {
        require(_address != address(0), "0x is not accepted here");
        require(isExcludedFromFee[_address] != _status, "Status was set");
        isExcludedFromFee[_address] = _status;
    }

    function changeSwapAtAmount(uint256 _swapAtAmount) external onlyOwner {
        require(_swapAtAmount != 0, "_swapAtAmount value invalid");
        swapAtAmount = _swapAtAmount;
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(
            isExcludedFromFee[account] != excluded,
            "Account is already the value of 'excluded'"
        );
        isExcludedFromFee[account] = excluded;
    }

    function excludeFromMaxWallet(address account, bool excluded)
    public
    onlyOwner
    {
        _isExcludedFromMaxWallet[account] = excluded;
    }

    receive() external payable {}

}