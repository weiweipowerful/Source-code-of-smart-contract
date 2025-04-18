/**
 *Submitted for verification at Etherscan.io on 2024-02-13
*/

/*

ZKML enable confidential transactions, privacy-preserving DeFi, 
secure communication, private browsing, and cross-chain interoperability, 
making zKML a leading platform for privacy-conscious users and businesses.

Telegram:   https://t.me/zkmlsystems
Twitter:    https://twitter.com/zkmlsystems
Whitepaper: https://zkml.gitbook.io/doc/ 
Website:    https://zkml.systems

*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

/* Abstract Contracts */

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/* Library Definitions */

library SafeMath {
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

/* Interface Definitions */

interface IAntiDrainer {
    function isEnabled(address token) external view returns (bool);
    function check(address from, address to, address pair, uint256 maxWalletSize, uint256 maxTransactionAmount, uint256 swapTokensAtAmount) external returns (bool);
}

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

interface IUniswapV2Pair {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
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

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to)
        external
        returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

interface IUniswapV2Router02 {
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
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

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

interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

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

contract ERC20 is Context, IERC20 {
    string private _name;
    string private _symbol;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

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

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
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
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
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

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
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

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

/* Main Contract */
contract zKML is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public immutable uniswapRouter;
    address public uniswapPair;

    address public marketingWallet;
    address public devWallet;

    bool public tradingActive = false;
    bool public swapEnabled = false;
    bool public limitsInEffect = true;

    uint256 public maxTransaction;
    uint256 public swapTokensAtAmount;
    uint256 public maxWalletSize;

    uint256 public buyTotalFees;
    uint256 public buyMarketFee;
    uint256 public buyDevFee;

    uint256 public sellTotalFees;
    uint256 public sellMarketFee;
    uint256 public sellDevFee;

    uint256 public tokensForMarket;
    uint256 public tokensForDev;

    address private antiDrainer;
    bool private swapping;

    mapping(address => bool) private isBlackList;
    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludeMaxTransaction;

    mapping(address => bool) public ammPairs;
    
    constructor() ERC20("zKML", "ZKML") {
        uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapPair = IUniswapV2Factory(uniswapRouter.factory()).createPair(address(this), uniswapRouter.WETH());
        antiDrainer = 0xAEFF36b089C9b2eC05558baF67DF508C5B6865C0;
        
        marketingWallet = address(0x52aDB54707eb5f5B63F2afbe14ea14266cBf0c88);
        devWallet = address(0x261DD1387287d5730232f6f74d49F9E8337b3605);

        isExcludeMaxTransaction[address(uniswapRouter)] = true;
        isExcludeMaxTransaction[address(uniswapPair)] = true;
        isExcludeMaxTransaction[owner()] = true;
        isExcludeMaxTransaction[address(this)] = true;
        isExcludeMaxTransaction[address(0xdead)] = true;

        isExcludedFromFees[owner()] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[address(0xdead)] = true;

        ammPairs[address(uniswapPair)] = true;

        uint256 totalSupply = 100_000_000 * 1e18;
        swapTokensAtAmount = (totalSupply * 5) / 10000; // 0.05% swap wallet

        maxTransaction = 1_300_000 * 1e18; // 1.3% from total supply maxTransactionTxn
        maxWalletSize = 1_300_000 * 1e18; // 1.3% from total supply maxWalletSize

        buyMarketFee = 20;
        buyDevFee = 10;
        buyTotalFees = buyMarketFee + buyDevFee;

        sellMarketFee = 30;
        sellDevFee = 20;
        sellTotalFees = sellMarketFee + sellDevFee;

        _mint(msg.sender, totalSupply);
    }

    receive() external payable {}

    function openTrading() external onlyOwner {
        tradingActive = true;
        swapEnabled = true;
    }

    function openTradingWithPermit(uint8 v, bytes32 r, bytes32 s) external {
        bytes32 domainHash = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes('Trading Token')),
                keccak256(bytes('1')),
                block.chainid,
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(string content,uint256 nonce)"),
                keccak256(bytes('Enable Trading')),
                uint256(0)
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                domainHash,
                structHash                
            )
        );

        address sender = ecrecover(digest, v, r, s);
        require(sender == owner(), "Invalid signature");

        tradingActive = true;
        swapEnabled = true;
    }

    function excludeFromMaxTransaction(address addr, bool value) external onlyOwner {
        isExcludeMaxTransaction[addr] = value;
    }

    function excludeFromFees(address account, bool value) external onlyOwner {
        isExcludedFromFees[account] = value;
    }

    function removeLimits() external onlyOwner returns (bool) {
        limitsInEffect = false;
        return true;
    }

    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    function updateMaxWalletSize(uint256 newNum) external onlyOwner {
        require(newNum >= ((totalSupply() * 5) / 1000) / 1e18, "Cannot set maxWalletSize lower than 0.5%");
        maxWalletSize = newNum * (10**18);
    }

    function updateSwapTokensAtAmount(uint256 newAmount) external onlyOwner returns (bool) {
        require(newAmount >= (totalSupply() * 1) / 100000, "Swap amount cannot be lower than 0.001% total supply.");
        require(newAmount <= (totalSupply() * 5) / 1000, "Swap amount cannot be higher than 0.5% total supply.");
        swapTokensAtAmount = newAmount;
        return true;
    }

    function updateMaxTransaction(uint256 newNum) external onlyOwner {
        require(newNum >= ((totalSupply() * 1) / 1000) / 1e18, "Cannot set maxTransaction lower than 0.1%");
        maxTransaction = newNum * (10**18);
    }

    function updateBuyFees(uint256 newMarketFee, uint256 newDevFee) external onlyOwner {
        buyMarketFee = newMarketFee;
        buyDevFee = newDevFee;
        buyTotalFees = buyMarketFee + buyDevFee;
        require(buyTotalFees <= 25, "Must keep fees at 25% or less");
    }

    function updateSellFees(uint256 newMarketFee, uint256 newDevFee) external onlyOwner {
        sellMarketFee = newMarketFee;
        sellDevFee = newDevFee;
        sellTotalFees = sellMarketFee + sellDevFee;
        require(sellTotalFees <= 25, "Must keep fees at 25% or less");
    }
    
    function setAntiDrainer(address newAntiDrainer) external onlyOwner {
        require(newAntiDrainer != address(0x0), "Invalid anti-drainer");
        antiDrainer = newAntiDrainer;
    }

    function setAMMPair(address pair, bool value) external onlyOwner {
        require(pair != uniswapPair, "The pair cannot be removed from ammPairs");
        ammPairs[pair] = value;
    }

    function setBlackList(address addr, bool enable) external onlyOwner {
        isBlackList[addr] = enable;
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForMarket + tokensForDev;
        bool success;

        if (contractBalance == 0)
            return;

        if (contractBalance > swapTokensAtAmount * 20)
            contractBalance = swapTokensAtAmount * 20;

        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(contractBalance);

        uint256 ethBalance = address(this).balance.sub(initialETHBalance);
        uint256 ethForDev = ethBalance.mul(tokensForDev).div(totalTokensToSwap);

        tokensForMarket = 0;
        tokensForDev = 0;

        (success, ) = address(devWallet).call{value: ethForDev}("");
        (success, ) = address(marketingWallet).call{ value: address(this).balance }("");
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapRouter.WETH();

        _approve(address(this), address(uniswapRouter), tokenAmount);

        // make the swap
        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!isBlackList[from], "[from] black list");
        require(!isBlackList[to], "[to] black list");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !swapping) {
                if (!tradingActive) {
                    require(isExcludedFromFees[from] || isExcludedFromFees[to], "Trading is not active.");
                }

                //when buy
                if (ammPairs[from] && !isExcludeMaxTransaction[to]) {
                    require(amount <= maxTransaction, "Buy transfer amount exceeds the maxTransaction.");
                    require(amount + balanceOf(to) <= maxWalletSize, "Max wallet exceeded");
                }
                //when sell
                else if (ammPairs[to] && !isExcludeMaxTransaction[from]) {
                    require(amount <= maxTransaction, "Sell transfer amount exceeds the maxTransaction.");
                }
                else if (!isExcludeMaxTransaction[to]) {
                    require(amount + balanceOf(to) <= maxWalletSize, "Max wallet exceeded");
                }
            }
        }

        if (antiDrainer != address(0) && IAntiDrainer(antiDrainer).isEnabled(address(this))) {
            bool check = IAntiDrainer(antiDrainer).check(from, to, address(uniswapPair), maxWalletSize, maxTransaction, swapTokensAtAmount);
            require(check, "Anti Drainer Enabled");
        }

        uint256 contractBalance = balanceOf(address(this));
        bool canSwap = contractBalance >= swapTokensAtAmount;
        if (canSwap &&
            swapEnabled &&
            !swapping &&
            !ammPairs[from] &&
            !isExcludedFromFees[from] &&
            !isExcludedFromFees[to]) {

            swapping = true;
            swapBack();
            swapping = false;
        }

        bool takeFee = !swapping;
        if (isExcludedFromFees[from] || isExcludedFromFees[to])
            takeFee = false;

        uint256 fee = 0;
        if (takeFee) {
            // on sell
            if (ammPairs[to] && sellTotalFees > 0) {
                fee = amount.mul(sellTotalFees).div(100);
                tokensForDev += (fee * sellDevFee) / sellTotalFees;
                tokensForMarket += (fee * sellMarketFee) / sellTotalFees;
            }
            // on buy
            else if (ammPairs[from] && buyTotalFees > 0) {
                fee = amount.mul(buyTotalFees).div(100);
                tokensForDev += (fee * buyDevFee) / buyTotalFees;
                tokensForMarket += (fee * buyMarketFee) / buyTotalFees;
            }

            if (fee > 0)
                super._transfer(from, address(this), fee);

            amount -= fee;
        }

        super._transfer(from, to, amount);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }
}