// Web: https://trackerai.bot/
// Tg: https://t.me/TrackerAI_ERC
// X: https://twitter.com/TrackerAI_ERC

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable, Context} from "@openzeppelin/contracts/access/Ownable.sol";

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

    function name() external view virtual override returns (string memory) {
        return _name;
    }

    function symbol() external view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() external view virtual override returns (uint8) {
        return 9;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external virtual override returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            unchecked {
                _approve(sender, _msgSender(), currentAllowance - amount);
            }
        }

        _transfer(sender, recipient, amount);

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256 amountB);

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountOut);

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
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

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract TRACK is ERC20, Ownable {
    uint256 public feeOnBuy = 5;
    uint256 public feeOnSell = 5;
    address public marketingWallet = 0xF83B88408C202F740A6799EDbD24Bf69f9A190D2;
    address public devWallet = 0xC0F62C26fa3bf677D1509cF5232C952d713B9d4b;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    bool private swapping;
    uint256 public swapTokensAtAmount;
    uint256 public maxTxnAmount;
    uint256 public maxWalletSize;

    bool public isTradeOpen = false;
    bool public isSizeLimitsOpen;
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private _isLimitExempt;

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event FeesUpdated(uint256 feeOnBuy, uint256 feeOnSell);
    event MarketingWalletChanged(address indexed newMarketingWallet);

    event DevWalletChanged(address indexed newDevWallet);
    event SwapAndSendFee(uint256 tokensSwapped, uint256 bnbSend);
    event SwapTokensAtAmountChanged(uint256 newAmount);
    event SizesAtAmountChanged(uint256 _maxTxnAmount, uint256 _maxWalletSize, uint256 percent);
    event TransferForeignToken(address token, uint256 amount);

    constructor(address initialOwner, address _v2Router) ERC20("Tracker AI", "TRACK") Ownable(initialOwner) {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_v2Router);
        address _uniswapV2Pair =
            IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _approve(address(this), address(uniswapV2Router), type(uint256).max);

        isSizeLimitsOpen = true;
        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[DEAD] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[marketingWallet] = true;
        _isExcludedFromFees[devWallet] = true;

        _isLimitExempt[owner()] = true;

        _mint(owner(), 10 ** 8 * (10 ** 9));
        swapTokensAtAmount = totalSupply() / 5000;
        maxTxnAmount = (totalSupply() * 4) / 1000;
        maxWalletSize = (totalSupply() * 8) / 1000;
    }

    receive() external payable {}

    function sendBNB(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success,) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function enableTrade() external onlyOwner {
        require(isTradeOpen == false, "Trade is already open!");
        isTradeOpen = true;
    }

    function disableSizeLimits() public onlyOwner {
        isSizeLimitsOpen = false;
    }

    function excludeFromFees(address account, bool excluded) external onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function exemptFromLimit(address account, bool exempt) external onlyOwner {
        require(_isLimitExempt[account] != exempt, "Account is already the value of 'exempt'");
        _isLimitExempt[account] = exempt;
    }

    function isExcludedFromFees(address account) external view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function setFees(uint256 _feeOnBuy, uint256 _feeOnSell) external onlyOwner {
        feeOnBuy = _feeOnBuy;
        feeOnSell = _feeOnSell;
        emit FeesUpdated(feeOnBuy, feeOnSell);
    }

    function changeMarketingWallet(address _marketingWallet) external onlyOwner {
        require(_marketingWallet != marketingWallet, " wallet is already that address");
        require(_marketingWallet != address(0), " wallet cannot be the zero address");
        marketingWallet = _marketingWallet;
        _isExcludedFromFees[marketingWallet] = true;
        emit MarketingWalletChanged(marketingWallet);
    }

    function changeDevWallet(address _devWallet) external onlyOwner {
        require(_devWallet != devWallet, " wallet is already that address");
        require(_devWallet != address(0), " wallet cannot be the zero address");
        devWallet = _devWallet;
        _isExcludedFromFees[devWallet] = true;
        emit DevWalletChanged(_devWallet);
    }

    function setSizesAtAmount(uint256 _maxTxnAmount, uint256 _maxWalletSize, uint256 percent) public onlyOwner {
        maxTxnAmount = (_maxTxnAmount * totalSupply()) / percent;
        maxWalletSize = (_maxWalletSize * totalSupply()) / percent;
        emit SizesAtAmountChanged(_maxTxnAmount, _maxWalletSize, percent);
    }

    function setSwapTokensAtAmount(uint256 newAmount) external onlyOwner {
        require(newAmount > totalSupply() / 100000, "SwapTokensAtAmount must be greater than 0.001% of total supply");
        swapTokensAtAmount = newAmount;
        emit SwapTokensAtAmountChanged(newAmount);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(isTradeOpen || _isLimitExempt[from] || _isLimitExempt[to], "Trading is not open!");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (isSizeLimitsOpen) {
            if (from == uniswapV2Pair && !_isExcludedFromFees[to]) {
                require(amount <= maxTxnAmount, "Buy transfer amount exceeds the maxTransactionAmount.");
            } else if (to == uniswapV2Pair && !_isExcludedFromFees[from]) {
                require(amount <= maxTxnAmount, "Sell transfer amount exceeds the maxTransactionAmount.");
            }

            if (
                !_isExcludedFromFees[from] && to != address(uniswapV2Router) && to != address(uniswapV2Pair)
                    && !_isExcludedFromFees[to]
            ) {
                require(balanceOf(to) + amount <= maxWalletSize, "Transfer amount exceeds the maxWalletSize.");
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (canSwap && !swapping && to == uniswapV2Pair) {
            swapping = true;

            swapBack();

            swapping = false;
        }

        bool takeFee = !swapping;

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (takeFee) {
            uint256 fees;
            if (from == uniswapV2Pair) {
                fees = (amount * feeOnBuy) / 100;
            } else if (to == uniswapV2Pair) {
                fees = (amount * feeOnSell) / 100;
            } else {
                fees = 0;
            }
            amount -= fees;
            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }
        }

        super._transfer(from, to, amount);
    }

    function swapAndSendFee(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractTokenBalance = balanceOf(address(this));

        if (contractTokenBalance == 0) {
            return;
        }

        if (contractTokenBalance > swapTokensAtAmount * 20) {
            contractTokenBalance = swapTokensAtAmount * 20;
        }

        swapAndSendFee(contractTokenBalance);
        contractTokenBalance = address(this).balance;

        uint256 amountToMarketing = (contractTokenBalance * 8) / 10;
        uint256 amountToDev = (contractTokenBalance * 2) / 10;
        // uint256 amountToDev = newBalance;

        sendBNB(payable(marketingWallet), amountToMarketing);
        sendBNB(payable(devWallet), amountToDev);
    }

    function transferForeignToken(address _token) external returns (bool _sent) {
        require(_token != address(0), "_token address cannot be 0");
        require(_token != address(this), "_token address cannot be native token");
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        _sent = IERC20(_token).transfer(address(devWallet), _contractBalance);
        emit TransferForeignToken(_token, _contractBalance);
    }

    // withdraw in token contract ETH if stuck
    function withdrawStuckETH() external {
        bool success;
        (success,) = address(marketingWallet).call{value: address(this).balance}("");
    }
}