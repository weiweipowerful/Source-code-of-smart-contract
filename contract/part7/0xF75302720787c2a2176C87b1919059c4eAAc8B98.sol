/**
 *Submitted for verification at Etherscan.io on 2025-01-01
*/

// SPDX-License-Identifier: MIT

/**

https://CFGI.io
https://linktr.ee/CFGI_io

*/

pragma solidity = 0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function getOwner() external view returns (address);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address _owner,
        address spender
    ) external view returns (uint256);

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
    event Burn(address indexed from, address indexed to, uint256 value);
}

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

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    address internal ZERO = 0x0000000000000000000000000000000000000000;

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(ZERO);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != ZERO, "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IDEXFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
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
    )
        external
        payable
        returns (uint amountToken, uint amountETH, uint liquidity);

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

contract CFGI is IERC20, Ownable {
    address private immutable WETH;
    address public immutable pair;
    IDEXRouter public constant router =
        IDEXRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    string private constant _name = "CFGI";
    string private constant _symbol = "CFGI";
    uint8 private constant _decimals = 18;
    uint256 private constant TOTAL_SUPPLY = 1 * 10 ** 10 * (10 ** _decimals);

    uint32 public launchedAt;
    address public marketingWallet = owner();

    bool public tradingOpen = false;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private isAuthorized;

    //Event Logs
    event MarketingWalletUpdated(address indexed _newWallet);
    event StuckETHCleared(uint256 _amount);
    event StuckTokensCleared(address _token, uint256 _amount);
    event LaunchSequenceStarted();
    event StuckETH(uint256 _amount);

    error InvalidAddress();
    error InvalidAmount();
    error Unavailable();
    error TransferFromZeroAddress();
    error TransferToZeroAddress();

    constructor() {
        WETH = router.WETH();

        pair = IDEXFactory(router.factory()).createPair(WETH, address(this));

        _allowances[address(this)][address(router)] = type(uint256).max;

        _balances[owner()] = TOTAL_SUPPLY;

        isAuthorized[owner()] = true;
        isAuthorized[marketingWallet] = true;

        emit Transfer(address(0), owner(), TOTAL_SUPPLY);
    }

    function launchSequence() external onlyOwner {
        if (launchedAt != 0) revert Unavailable();
        launchedAt = uint32(block.number);
        tradingOpen = true;
        emit LaunchSequenceStarted();
    }

    function getCirculatingSupply() external view returns (uint256) {
        return TOTAL_SUPPLY - balanceOf(DEAD) - balanceOf(ZERO);
    }

    function totalSupply() external pure override returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function decimals() external pure override returns (uint8) {
        return _decimals;
    }

    function symbol() external pure override returns (string memory) {
        return _symbol;
    }

    function name() external pure override returns (string memory) {
        return _name;
    }

    function getOwner() external view override returns (address) {
        return owner();
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function authorized(address account) public view returns (bool) {
        return isAuthorized[account];
    }

    function allowance(
        address holder,
        address spender
    ) external view override returns (uint256) {
        return _allowances[holder][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    //Transfer Functions

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        return _transfer(msg.sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] =
                _allowances[sender][msg.sender] -
                amount;
        }
        return _transfer(sender, recipient, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private returns (bool) {
        if (sender == address(0)) revert TransferFromZeroAddress();
        if (recipient == address(0)) revert TransferToZeroAddress();
        if (amount == 0) revert InvalidAmount();
        if (!tradingOpen && !isAuthorized[sender]) revert Unavailable();
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    // Update/Change Functions

    function setMarketingWallet(address newMarketingWallet) external onlyOwner {
        if (newMarketingWallet == address(0)) revert InvalidAddress();
        isAuthorized[marketingWallet] = false;
        marketingWallet = newMarketingWallet;
        isAuthorized[marketingWallet] = true;
        emit MarketingWalletUpdated(newMarketingWallet);
    }

    function setAuthorization(address _authorizedAddress, bool _access) external onlyOwner {
        if (_authorizedAddress == address(0)) revert InvalidAddress();
        if (_authorizedAddress == DEAD) revert InvalidAddress();
        isAuthorized[_authorizedAddress] = _access;
    }

    function clearStuckETH() external onlyOwner {
        uint256 contractETHBalance = address(this).balance;
        if (contractETHBalance == 0) revert InvalidAmount();
        _transferETHToMarketing(contractETHBalance);
        emit StuckETHCleared(contractETHBalance);
    }

    function clearStuckTokens(IERC20 token) external onlyOwner {
        if (address(token) == address(0)) revert InvalidAddress();
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) revert InvalidAmount();
        token.transfer(marketingWallet, balance);
        emit StuckTokensCleared(address(token), balance);
    }

    function _transferETHToMarketing(uint256 amount) private {
        (bool success, ) = marketingWallet.call{value: amount}("");
        if (!success) {
            /// @dev owner can claim ETH via clearStuckETH()
            emit StuckETH(amount);
        }
    }

    receive() external payable {}
}

/// Stop reading the contract and get using CFGI.io!