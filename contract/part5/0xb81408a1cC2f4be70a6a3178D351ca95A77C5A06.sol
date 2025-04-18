/**
 *Submitted for verification at Etherscan.io on 2024-03-02
*/

/**
 *Submitted for verification at BscScan.com on 2023-05-18
*/

// SPDX Licence: Unlicenced

/*
 █████ █████    ███████    ██████████   ██████████ █████ █████
░░███ ░░███   ███░░░░░███ ░░███░░░░███ ░░███░░░░░█░░███ ░░███
 ░░███ ███   ███     ░░███ ░███   ░░███ ░███  █ ░  ░░███ ███
  ░░█████   ░███      ░███ ░███    ░███ ░██████     ░░█████
   ███░███  ░███      ░███ ░███    ░███ ░███░░█      ███░███
  ███ ░░███ ░░███     ███  ░███    ███  ░███ ░   █  ███ ░░███
 █████ █████ ░░░███████░   ██████████   ██████████ █████ █████
░░░░░ ░░░░░    ░░░░░░░    ░░░░░░░░░░   ░░░░░░░░░░ ░░░░░ ░░░░░

Website: https://www.xo-dex.com
Telegram: https://t.me/xodexofficialtg
Twitter: https://twitter.com/XODEXnetwork
Coin Market Cap: https://coinmarketcap.com/currencies/xodex/

*/

pragma solidity ^0.8.7;

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

library SafeMath {
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
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this;
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    // Set original owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = 0xb0B9D8873756cE7368B16fFDbf3fe58eE7Ea5690;
        emit OwnershipTransferred(address(0), _owner);
    }

    // Return current owner
    function owner() public view virtual returns (address) {
        return _owner;
    }

    // Restrict function to contract owner only
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    // Renounce ownership of the contract
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    // Transfer the contract to to a new owner
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
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

    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
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

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

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

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

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

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
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

contract XODEX is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _totalOwned;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public _isExcludedFromFee;
    mapping(address => bool) public _isBlacklisted;

    string constant _name = "XODEX";
    string constant _symbol = "XODEX";
    uint8 constant _decimals = 18;
    uint256 constant _tTotal = 10000000000 * 10**18;

    bool public isBlackList;

    address payable private Dev_Wallet = payable(0x8e0bFdef94F09b5108b86a737Bf97e9D5A3F5503);
    address payable constant Burn_Wallet = payable(0x000000000000000000000000000000000000dEaD);

    uint8 private txCount = 0;
    uint8 private swapTrigger = 10;

    uint256 constant maxFee = 25;
    uint256 private maxTransferFee = 10;
    uint256 public _maxToken = _tTotal.mul(2).div(100);
    uint256 private _prevMaxToken = _maxToken;
    uint256 public _maxTxAmount = _tTotal.mul(1).div(100);
    uint256 private _prevMaxTxAmount = _maxTxAmount;

    uint256 public _TransferFee = 10;
    uint256 public _buyFee = 10;
    uint256 public _sellFee = 10;
    uint256 public _TotalFee = _TransferFee;


    bool public noTransferFee = true;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    bool public isSwapping;
    bool public swapAndLiqEnabled = true;

    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);

    modifier lockSwap() {
        isSwapping = true;
        _;
        isSwapping = false;
    }

    constructor() {
        _totalOwned[owner()] = _tTotal;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            _uniswapV2Router.WETH()
        );
        uniswapV2Router = _uniswapV2Router;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[Dev_Wallet] = true;

        emit Transfer(address(0), owner(), _tTotal);
    }

    receive() external payable {}

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function blacklist_Wallets(address[] calldata addresses) external onlyOwner {
        uint256 startGas;
        uint256 gasUsed;

        for (uint256 i; i < addresses.length; ++i) {
            if (gasUsed < gasleft()) {
                startGas = gasleft();
                if (!_isBlacklisted[addresses[i]]) {
                    _isBlacklisted[addresses[i]] = true;
                }
                gasUsed = startGas - gasleft();
            }
        }
    }

    function blacklist_Toggle(bool true_or_false) public onlyOwner {
        isBlackList = true_or_false;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _totalOwned[account];
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero")
        );
        return true;
    }

    function Update__Dev_Wallet(address payable wallet) public onlyOwner {
        require(wallet != address(0), "ERR: zero address");
        Dev_Wallet = wallet;
        _isExcludedFromFee[Dev_Wallet] = true;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function excludeFromFee(address account) public onlyOwner {
        require(account != address(0), "ERR: zero address");
        _isExcludedFromFee[account] = true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function includeInFee(address account) public onlyOwner {
        require(account != address(0), "ERR: zero address");

        _isExcludedFromFee[account] = false;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function process_Tokens(uint256 percent_Of_Tokens_To_Process) public onlyOwner {
        // Do not trigger if already in swap
        require(!isSwapping, "Currently processing, try later.");
        if (percent_Of_Tokens_To_Process > 100) {
            percent_Of_Tokens_To_Process = 100;
        }
        uint256 tokensOnContract = balanceOf(address(this));
        uint256 sendTokens = (tokensOnContract * percent_Of_Tokens_To_Process) / 100;
        swapTokens(sendTokens);
    }

    function recover_Tokens(
        address Token_Address,
        address send_to_wallet,
        uint256 number_of_tokens
    ) public onlyOwner returns (bool _sent) {
        require(Token_Address != address(0) && send_to_wallet != address(0), "ERR: zero address");
        require(Token_Address != address(this), "Can not remove native token");


        uint256 randomBalance = IERC20(Token_Address).balanceOf(address(this));
        if (number_of_tokens > randomBalance) {
            number_of_tokens = randomBalance;
        }
        _sent = IERC20(Token_Address).transfer(send_to_wallet, number_of_tokens);
    }

    function removeFees() private {
        if (_TotalFee == 0) return;

        _TotalFee = 0;
    }

    function restoreFees() private {
        if (_TotalFee == _TransferFee) return;

        _TotalFee = _TransferFee;
    }

    function sendToWallet(address payable wallet, uint256 amount) private {
        wallet.transfer(amount);
    }

    function swapTokens(uint256 contractTokenBalance) private lockSwap {
        swapTokensForETH(contractTokenBalance);
        uint256 contractETH = address(this).balance;
        sendToWallet(Dev_Wallet, contractETH);
    }

    function swapTokensForETH(uint256 tokenAmount) private {
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

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function set_Swap_And_Liquify_Enabled(bool true_or_false) public onlyOwner {
        swapAndLiqEnabled = true_or_false;
        emit SwapAndLiquifyEnabledUpdated(true_or_false);
    }

    function set_Number_Of_Transactions_Before_Liquify_Trigger(uint8 number_of_transactions) public onlyOwner {
        require(number_of_transactions > 0, "Minimum must be greater than 0");

        swapTrigger = number_of_transactions;
    }

    function set_TransferFees(bool true_or_false) external onlyOwner {
        noTransferFee = true_or_false;
    }

    function set_Max_TX_Percent(uint256 maxTxPercent_x100) external onlyOwner {
        require(maxTxPercent_x100 > 0, "Minimum must be greater than 0");
        _maxTxAmount = (_tTotal * maxTxPercent_x100) / 10000;
    }

    function set_Max_Wal_Percent(uint256 maxWallPercent_x100) external onlyOwner {
        require(maxWallPercent_x100 > 0, "Minimum must be greater than 0");

        _maxToken = (_tTotal * maxWallPercent_x100) / 10000;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance")
        );
        return true;
    }

    function unBlacklist_Wallets(address[] calldata addresses) external onlyOwner {
        uint256 startGas;
        uint256 gasUsed;

        for (uint256 i; i < addresses.length; ++i) {
            if (gasUsed < gasleft()) {
                startGas = gasleft();
                if (_isBlacklisted[addresses[i]]) {
                    _isBlacklisted[addresses[i]] = false;
                }
                gasUsed = startGas - gasleft();
            }
        }
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0) && spender != address(0), "ERR: zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        if (
            to != owner() &&
            to != Dev_Wallet &&
            to != address(this) &&
            to != uniswapV2Pair &&
            to != Burn_Wallet &&
            from != owner()
        ) {
            uint256 heldTokens = balanceOf(to);
            require(
                (heldTokens + amount) <= _maxToken,
                "You are trying to buy too many tokens. You have reached the limit for one wallet."
            );
        }

        // Limit the maximum number of tokens that can be bought or sold in one transaction
        if (from != owner() && to != owner())
            require(amount <= _maxTxAmount, "You are trying to buy more than the max transaction limit.");

        if (isBlackList) {
            require(!_isBlacklisted[from] && !_isBlacklisted[to], "This address is blacklisted. Transaction reverted.");
        }

        require(from != address(0) && to != address(0), "ERR: Using 0 address!");
        require(amount > 0, "Token value must be higher than zero.");

        if (txCount >= swapTrigger && !isSwapping && from != uniswapV2Pair && swapAndLiqEnabled) {
            txCount = 0;
            uint256 contractTokenBalance = balanceOf(address(this));
            if (contractTokenBalance > _maxTxAmount) {
                contractTokenBalance = _maxTxAmount;
            }
            if (contractTokenBalance > 0) {
                swapTokens(contractTokenBalance);
            }
        }

        bool takeFee = true;

        if (
            _isExcludedFromFee[from] ||
            _isExcludedFromFee[to] ||
            (noTransferFee && from != uniswapV2Pair && to != uniswapV2Pair)
        ) {
            takeFee = false;
        } else if (from == uniswapV2Pair) {
            _TotalFee = _buyFee;
        } else if (to == uniswapV2Pair) {
            _TotalFee = _sellFee;
        }

        _tokenTransfer(from, to, amount, takeFee);
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) {
            removeFees();
        } else {
            txCount++;
        }
        _transferTokens(sender, recipient, amount);

        restoreFees();
    }

    function _transferTokens(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (uint256 tTransferAmount, uint256 tDev) = _getValues(tAmount);
        _totalOwned[sender] = _totalOwned[sender].sub(tAmount);
        _totalOwned[recipient] = _totalOwned[recipient].add(tTransferAmount);
        _totalOwned[address(this)] = _totalOwned[address(this)].add(tDev);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _getValues(uint256 tAmount) private view returns (uint256, uint256) {
        uint256 tDev = (tAmount * _TotalFee) / 100;
        uint256 tTransferAmount = tAmount.sub(tDev);
        return (tTransferAmount, tDev);
    }

    function _set_Fees(uint256 Buy_Fee, uint256 Sell_Fee) external onlyOwner {
        require((Buy_Fee + Sell_Fee) <= maxFee, "Fee is too high!");
        _sellFee = Sell_Fee;
        _buyFee = Buy_Fee;
    }

    function _set_Transfer_Fee(uint256 Transfer_Fee) external onlyOwner {
        require(Transfer_Fee <= maxTransferFee, "Fee is too high!");
        _TransferFee = Transfer_Fee;
    }
}
// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.7;




library Address {
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}