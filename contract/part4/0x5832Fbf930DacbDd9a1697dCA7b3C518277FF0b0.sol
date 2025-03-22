// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract Token is ERC20, Ownable {
    using SafeERC20 for IERC20;

    uint8 private immutable _decimals;

    uint256 public constant BUY_FEE = 2_10;
    uint256 public constant SELL_FEE = 2_10;
    uint256 public constant FEE_FACTOR = 100_00;

    address public feeRecipient;
    uint256 public thresholdAmountSell;
    uint256 public maxAmountSell;

    IUniswapV2Router02 public immutable router;
    address public immutable pair;
    address public immutable WETH;

    bool private _isStarted;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_,
        IUniswapV2Router02 router_
    ) ERC20(name_, symbol_) Ownable() {
        require(owner_ != address(0), 'Invalid owner');
        require(address(router_) != address(0), 'Invalid router');

        _decimals = decimals_;
        feeRecipient = owner_;
        router = router_;

        transferOwnership(owner_);
        _mint(owner_, totalSupply_);

        WETH = router_.WETH();
        IUniswapV2Factory factory = IUniswapV2Factory(router_.factory());
        pair = factory.createPair(address(this), WETH);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        uint256 fee_ = 0;
        bool isSell = false;

        if (from != address(this) && to == pair) {
            fee_ = SELL_FEE;
            isSell = true;
        } else if (from == pair && to != address(this)) {
            fee_ = BUY_FEE;
        }

        if (isSell && !_isStarted) {
            _isStarted = true;
            super._transfer(from, to, amount);
            return;
        } else if (!_isStarted) {
            super._transfer(from, to, amount);
            return;
        }

        uint256 feeAmount = (amount * fee_) / FEE_FACTOR;
        uint256 restAmount = amount - feeAmount;

        if (feeAmount > 0) {
            super._transfer(from, address(this), feeAmount);
        }
        if (isSell) {
            _sellTokens(restAmount);
        }

        super._transfer(from, to, restAmount);
    }

    // ADMIN functions

    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Invalid recipient');
        feeRecipient = recipient;
    }

    function withdrawTokens(IERC20 token, uint256 amount) external onlyOwner {
        require(address(token) != address(0), 'Invalid token');
        require(amount > 0, 'Invalid amount');

        uint256 balance = token.balanceOf(address(this));
        require(balance != 0, 'No tokens to withdraw');

        if (amount > balance) {
            amount = balance;
        }

        token.safeTransfer(msg.sender, amount);
    }

    function setThresholdAmountSell(
        uint256 thresholdAmountSell_
    ) external onlyOwner {
        thresholdAmountSell = thresholdAmountSell_;
    }

    function setMaxAmountSell(uint256 maxAmountSell_) external onlyOwner {
        maxAmountSell = maxAmountSell_;
    }

    // internal

    function _sellTokens(uint256 amount) internal {
        uint256 balance = balanceOf(address(this));
        if (balance < thresholdAmountSell) {
            return;
        }
        if (amount > maxAmountSell) {
            amount = maxAmountSell;
        }
        if (amount > balance) {
            amount = balance;
        }

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        _approve(address(this), address(router), amount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            feeRecipient,
            block.timestamp
        );
    }
}