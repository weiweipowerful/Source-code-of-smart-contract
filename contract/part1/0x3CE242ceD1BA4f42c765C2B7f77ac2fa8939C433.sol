// SPDX-License-Identifier: BSD-3-Clause

pragma solidity = 0.8.28;

import "@openzeppelin/[email protected]/utils/Address.sol";
import "@openzeppelin/[email protected]/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/[email protected]/token/ERC20/IERC20.sol";
import "@openzeppelin/[email protected]/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/[email protected]/utils/ReentrancyGuard.sol";

interface gyrowinInternal {
    // IUniswapV2Router
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    // IUniswapV2Factory
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

/**
 * Welcome to Gyrowin,
 * Gyrowin is a cross-chain decentralized finance and gaming platform.
 * https://gyro.win
 */
contract Gyrowin is ReentrancyGuard {

    string public constant name = "Gyrowin";
    string public constant symbol = "GYROWIN";
    uint8 public constant decimals = 18;
    
    uint256 private constant TOTAL_SUPPLY = 1 * 10 ** (decimals + 9); // 1 billion GYROWIN

    address constant private WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    gyrowinInternal constant private UNISWAP_V2_ROUTER = gyrowinInternal(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    gyrowinInternal constant private UNISWAP_V2_FACTORY = gyrowinInternal(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event TransferSent(address indexed, address indexed, uint indexed);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event NewOwner(address newOwner);
    event NewMarketingWallet(address newWallet);
    // @notice An event thats emittied when users are able to trade token
    event TradingOpen(uint256 indexed openTime);

    // @notice Owner of the contract
    // @dev should be multisig address
    address private _admin;
    address public marketingWallet;

    bool private _initialize;

    // @notice Status of collecting marketing funds
    bool private _swapping;
    bool public clog;

    // @notice Status of trading
    bool public isTrading;
    bool private _preparedTrading;

    // @notice status of buy/sell fee
    uint256 public fee;
    bool private lockedFee;

    /**
     * @notice Construct GYROWIN token
     */
    function initialize(address _owner, address _marketingWallet) external {
        require(_owner == address(0x05803c32E393765a204e22fCF560421729cbCA42), "GYROWIN: not owner");
        require(_marketingWallet != address(0), "GYROWIN: can't be the zero address");
        require(!_initialize, "GYROWIN: initialized");
        _admin = _owner;
        marketingWallet = _marketingWallet;
        _balance[_msgSender()] = TOTAL_SUPPLY;
        clog = true;
        fee = 30;
        _initialize = true;
    }

    receive() payable external {}

    modifier onlyOwner() {
        require(_admin == _msgSender(), "GYROWIN: not owner"); _;
    }

    modifier lockSwap {
        _swapping = true;
        _;
        _swapping = false;
    }

    using SafeERC20 for IERC20;

    // @notice List token pair contract address
    mapping(address => bool) private _swapPair;

    // @notice Official record of token balances for each account
    mapping(address => uint256) private _balance;

    // @notice Allowance amounts on behalf of others
    mapping(address => mapping(address => uint256)) private _allowance;

    /**
     * @notice The totalSupply method denotes the total number of tokens created by Gyrowin
     * and does not reflect the circulating supply.
     */    
    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(_msgSender(), spender, amount);

        return true;
    }

    /**
     * @notice Get the number of tokens `spender` is approved to spend on behalf of `account`
     * @param _owner The address of the account holding the funds
     * @param spender The address of the account spending the funds
     * @return The number of tokens approved
     */
    function allowance(address _owner, address spender) external view returns (uint256) {
        return _allowance[_owner][spender];
    }

    // @notice Alternative to {approve} that can be used as a mitigation for problems described in {ERC20-approve}.
    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, _allowance[_msgSender()][spender] + (addedValue));

        return true;
    }

    // @notice Alternative to {approve} that can be used as a mitigation for problems described in {ERC20-approve}.
    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        uint256 currentAllowance = _allowance[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "GYROWIN: decreased allowance below zero");

        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

     /**
     * @notice Transfer `amount` tokens from `sender` to `recepient'
     * @param recipient The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address recipient, uint256 amount) external returns (bool) {
        _transfer(_msgSender(), recipient, amount);

        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param sender The address of the source account
     * @param recipient The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(recipient != address(0), "GYROWIN: can't transfer to the zero address");
        require(sender != address(0), "GYROWIN: can't transfer from the zero address");
        
        _spendAllowance(sender, _msgSender(), amount);
        _transfer(sender, recipient, amount);

        return true;
    }

    /**
     * @notice Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balance[account];
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `_owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address _owner, address spender, uint256 amount) internal {
        require(_owner != address(0), "GYROWIN: can't approve to the zero address");
        require(spender != address(0), "GYROWIN: can't approve to the zero address");

        _allowance[_owner][spender] = amount;
        emit Approval(_owner, spender, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(_balance[sender] >= amount, "GYROWIN: balance is insufficient");

        if (isTrading == true) {
            // on buy
            if (_swapPair[sender]) {
                if (clog) {
                    uint256 taxAmount = amount * fee / 100;
                    // tax distribute to MK wallet
                    transferToken(sender, marketingWallet, taxAmount);
                    amount = amount - taxAmount;
                }
                transferToken(sender, recipient, amount);
            // on sell
            } else if (_swapPair[recipient]) {
                if (!_swapping && clog) {
                    uint256 taxAmount = amount * fee / 100;
                    // tax distribute to MK wallet
                    transferToken(sender, marketingWallet, taxAmount);
                    _swapFee(amount);
                    amount = amount - taxAmount;
                }
                transferToken(sender, recipient, amount);
            } else {
                transferToken(sender, recipient, amount); 
            }
        } else {
            if (sender != _admin && sender != address(this)) {
                if (_swapPair[sender] || _swapPair[recipient]) revert("GYROWIN: trading has not opened yet");
            } 
            transferToken(sender, recipient, amount); 
        }
    }

    // @notice Normal token transfer
    function transferToken(address sender, address recipient, uint256 amount) internal {
        unchecked {
            _balance[sender] -= amount;
            _balance[recipient] += amount;
        }

        emit Transfer(sender, recipient, amount);
    }

    // @notice Collecting marketing funds from early sellers to prevent a collapse caused by snipers
    function _swapFee(uint256 amount) internal lockSwap {
        if (amount > IERC20(address(this)).balanceOf(address(this))) return;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        _approve(address(this), address(UNISWAP_V2_ROUTER), amount);
        UNISWAP_V2_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            marketingWallet,
            block.timestamp
        );
    }   

    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function renounceOwnership(address zero) external onlyOwner() {
        require(zero == address(0), "GYROWIN: invalid address");
        _admin = address(0);

        emit NewOwner(_admin);
    }

    /**
     * @notice change the owner of the contract
     * @dev only callable by the owner
     * @param account new owner address
     */
    function updateOwner(address account) external onlyOwner() {
        require(account != address(0),"GYROWIN: invalid owner address");
        _admin = account;

        emit NewOwner(_admin);
    }

    /// update marketing wallet account
    /// @dev only callable by the owner
    function updateMarketingWallet(address account) external onlyOwner() {
        require(account != address(0), "GYROWIN: can't be zero address");
        marketingWallet = account;

        emit NewMarketingWallet(marketingWallet);
    }

    /// @dev call by the owner modifier
    function owner() external view returns (address) {
        return _admin;
    }

    /**
     * @notice set pair token address
     * @dev only callable by the owner
     * @param account address of the pair
     * @param isPair check 
     */
    function setSwapPair(address account, bool isPair) external onlyOwner() {
        require(account != address(0), "GYROWIN: can't be zero address");
        if (isPair) {
            require(!_swapPair[account], "GYROWIN: already listed");
        }
        _swapPair[account] = isPair;
    }

    /**
     * @notice check if the address is right pair address
     * @param account address of the swap pair
     * @return Account is valid pair or not
     */
    function isSwapPair(address account) external view returns (bool) {
        return _swapPair[account];
    }

    function renounceClog(bool status) external onlyOwner {
        require(clog, "GYROWIN: clog done");
        clog = status;
    }

    /**
     * @notice set fees
     * @dev only callable by the owner
     * @param newFee buy and sell fee for the token
     */
    function setFee(uint256 newFee) public onlyOwner {
        require(!lockedFee, "GYROWIN: fee renounced with zero");
        require(newFee <= 30, "GYROWIN: limit the max. fee");
        fee = newFee;
        if (fee == 0) {
            // fee to zero forever
            lockedFee = true;
        }
    }

    /**
     * @dev Set when to open trading
     * @dev isTrading cannot be set false after it started
     */
    function openTrading(bool status) external onlyOwner() {
        require(!isTrading, "GYROWIN: not allowed");
        isTrading = status;

        emit TradingOpen(block.timestamp);
    }

    function prepareTrading(uint256 amountOfGYROWIN) external payable onlyOwner {
        require(!_preparedTrading, "GYROWIN: not allowed");
        require((amountOfGYROWIN <= IERC20(address(this)).balanceOf(address(this))), "GYROWIN: insufficient balance");
        _approve(address(this), address(UNISWAP_V2_ROUTER), amountOfGYROWIN);

        address pair = UNISWAP_V2_FACTORY.createPair(address(this), WETH);
        _swapPair[pair] = true;

        UNISWAP_V2_ROUTER.addLiquidityETH{value: address(this).balance}(address(this), amountOfGYROWIN, 0, 0, msg.sender, block.timestamp);

        IERC20(pair).approve(address(UNISWAP_V2_ROUTER), type(uint256).max);

        _preparedTrading = true;
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(address _owner, address spender, uint256 value) internal {
        uint256 currentAllowance = this.allowance(_owner, spender);
        if (currentAllowance != type(uint256).max) {

            require(currentAllowance >= value, "GYROWIN: insufficent allowance");

            unchecked {
                _approve(_owner, spender, currentAllowance - value);
            }
        }
    }

    /**
     * @notice rescue ETH sent to the address
     * @param amount to be retrieved from the contract
     * @param to address of the destination account
     */
    function rescueETH(uint256 amount, address payable to) external nonReentrant {
        require(to == _admin || to == marketingWallet, "not recipient");
        require(amount <= address(this).balance, "exceed amount input");
        (bool sent,) = payable(to).call{value: amount}("");
        require(sent, "Failed to send");
        emit TransferSent(address(this), to, amount);
    }

    /**
     * @notice rescue ERC20 token sent to the address
     * @param amount to be retrieved for ERC20 contract
     * @param to address of the destination account
     */
    function rescusERC20Token(address token, address to, uint256 amount) external payable nonReentrant {
        require(to == _admin || to == marketingWallet, "not recipient");
        require(amount <= IERC20(token).balanceOf(address(this)), "exceed amount input");
        IERC20(token).safeTransfer(to, amount);
        emit TransferSent(address(this), to, amount);
    }
}