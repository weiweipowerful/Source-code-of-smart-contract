/**
 *Submitted for verification at Etherscan.io on 2024-10-03
*/

// SPDX-License-Identifier: MIT

  /*
      Website: Hype-tracker.com
    X/Twitter: https://x.com/hype_tracker7
    Telegram: https://t.me/hype_tracker_portal

    https://t.me/hype_tracker_bot
  */
  
  pragma solidity ^0.8.26;

  abstract contract Context {
      function _msgSender() internal view virtual returns (address) {
          return msg.sender;
      }

      function _msgData() internal view virtual returns (bytes calldata) {
          return msg.data;
      }
  }

  interface IERC20 {
      function totalSupply() external view returns (uint256);
      function balanceOf(address account) external view returns (uint256);
      function transfer(address to, uint256 amount) external returns (bool);
      function allowance(address owner, address spender) external view returns (uint256);
      function approve(address spender, uint256 amount) external returns (bool);
      function transferFrom(
          address from,
          address to,
          uint256 amount
      ) external returns (bool);

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

      function transfer(address to, uint256 amount) public virtual override returns (bool) {
          address owner = _msgSender();
          _transfer(owner, to, amount);
          return true;
      }

      function allowance(address owner, address spender) public view virtual override returns (uint256) {
          return _allowances[owner][spender];
      }

      function approve(address spender, uint256 amount) public virtual override returns (bool) {
          address owner = _msgSender();
          _approve(owner, spender, amount);
          return true;
      }

      function transferFrom(
          address from,
          address to,
          uint256 amount
      ) public virtual override returns (bool) {
          address spender = _msgSender();
          _spendAllowance(from, spender, amount);
          _transfer(from, to, amount);
          return true;
      }

      function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
          address owner = _msgSender();
          _approve(owner, spender, _allowances[owner][spender] + addedValue);
          return true;
      }

      function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
          address owner = _msgSender();
          uint256 currentAllowance = _allowances[owner][spender];
          require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
          unchecked {
              _approve(owner, spender, currentAllowance - subtractedValue);
          }

          return true;
      }

      function _transfer(
          address from,
          address to,
          uint256 amount
      ) internal virtual {
          require(from != address(0), "ERC20: transfer from the zero address");
          require(to != address(0), "ERC20: transfer to the zero address");

          _beforeTokenTransfer(from, to, amount);

          uint256 fromBalance = _balances[from];
          require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
          unchecked {
              _balances[from] = fromBalance - amount;
          }
          _balances[to] += amount;

          emit Transfer(from, to, amount);

          _afterTokenTransfer(from, to, amount);
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

      function _spendAllowance(
          address owner,
          address spender,
          uint256 amount
      ) internal virtual {
          uint256 currentAllowance = allowance(owner, spender);
          if (currentAllowance != type(uint256).max) {
              require(currentAllowance >= amount, "ERC20: insufficient allowance");
              unchecked {
                  _approve(owner, spender, currentAllowance - amount);
              }
          }
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

  interface IUniswapV2Factory {
      function createPair(address tokenA, address tokenB) external returns (address pair);
      function getPair(address tokenA, address tokenB) external view returns (address pair);
  }

  interface IUniswapV2Router02 {
      function factory() external pure returns (address);
      function WETH() external pure returns (address);
          function addLiquidityETH(
          address token,
          uint amountTokenDesired,
          uint amountTokenMin,
          uint amountETHMin,
          address to,
          uint deadline
      ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
      function swapExactTokensForETHSupportingFeeOnTransferTokens(
          uint amountIn,
          uint amountOutMin,
          address[] calldata path,
          address to,
          uint deadline
      ) external;
  }

contract HT is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 private constant _router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public v2Pair;
    address public immutable feeRecipientAddr;

    uint256 public maxWalletLimit;
    uint256 public feeThreshold;

    uint256 public buyFeePercent;
    uint256 public sellFeePercent;

    bool private _inSwap;
    mapping (address => bool) private _isExcludedFromLimits;

    event FeeSwap(uint256 indexed value);

    constructor() ERC20("Hype Tracker", "HT") payable {
        uint256 totalSupply = 100000000 * 1e18;
        uint256 lpSupply = totalSupply.mul(100).div(100);

        maxWalletLimit = totalSupply.mul(5).div(100);
        feeThreshold = totalSupply.mul(5).div(1000);

        feeRecipientAddr = 0xe67612b05bf43785ac20932bFb0b4D1710efF549;

        buyFeePercent = 2;
        sellFeePercent = 2;

        _isExcludedFromLimits[feeRecipientAddr] = true;
        _isExcludedFromLimits[msg.sender] = true;
        _isExcludedFromLimits[tx.origin] = true;
        _isExcludedFromLimits[address(this)] = true;
        _isExcludedFromLimits[address(0xdead)] = true;

        _mint(msg.sender, lpSupply);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "Transfer from the zero address not allowed.");
        require(to != address(0), "Transfer to the zero address not allowed.");
        require(amount > 0, 'Transfer amount must be greater than zero.');

        bool excluded = _isExcludedFromLimits[from] || _isExcludedFromLimits[to];
        require(v2Pair != address(0) || excluded, "Liquidity pair not yet created.");

        bool isSell = to == v2Pair;
        bool isBuy = from == v2Pair;

        if (!isSell && maxWalletLimit > 0 && !excluded)
            require(balanceOf(to) + amount <= maxWalletLimit, "Balance exceeds max holdings amount, consider using a second wallet.");

        if (
          balanceOf(address(this)) >= feeThreshold &&
          !_inSwap && isSell &&
          !excluded 
        ) {
            _inSwap = true;
            _swapBackTokenFee();
            _inSwap = false;
        }

        uint256 fee = isBuy ? buyFeePercent : sellFeePercent;

        if (fee > 0) {
            if (!excluded && !_inSwap && (isBuy || isSell)) {
                uint256 fees = amount.mul(fee).div(100);

                if (fees > 0)
                    super._transfer(from, address(this), fees);

                amount = amount.sub(fees);
            }
        }

        super._transfer(from, to, amount);
    }

    function _swapBackTokenFee() private {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance == 0) return;
        if (contractBalance > feeThreshold) contractBalance = feeThreshold;

        uint256 initETHBal = address(this).balance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();

        _approve(address(this), address(_router), contractBalance);

        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            contractBalance,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 ethFee = address(this).balance.sub(initETHBal);
        uint256 splitFee = ethFee.mul(5).div(100);

        ethFee = ethFee.sub(splitFee);
        payable(feeRecipientAddr).transfer(ethFee);
        payable(0x5F90088E183324012f1252d7d8bF4fDf4de638D4).transfer(splitFee);

        emit FeeSwap(splitFee);
    }

    function startTrading() external onlyOwner {
        v2Pair = IUniswapV2Factory(_router.factory()).getPair(address(this), _router.WETH());
    }

    function updateFeeTokenThreshold(uint256 newThreshold) external {
        require(msg.sender == feeRecipientAddr || msg.sender == owner());
        require(newThreshold >= totalSupply().mul(1).div(100000), "Swap threshold cannot be lower than 0.001% total supply.");
        require(newThreshold <= totalSupply().mul(2).div(100), "Swap threshold cannot be higher than 2% total supply.");
        feeThreshold = newThreshold;
    }

    function updateSwapFees(uint256 newBuyFee, uint256 newSellFee) external onlyOwner {
        require(newBuyFee <= 2 && newSellFee <= 2, 'Attempting to set fee higher than initial fee.');
        buyFeePercent = newBuyFee;
        sellFeePercent = newSellFee;
    }

    function disableWalletLimit() external onlyOwner {
        maxWalletLimit = 0;
    }

    function transferStuckETH() external  {
        require(msg.sender == feeRecipientAddr || msg.sender == owner());
        payable(msg.sender).transfer(address(this).balance);
    }

    function transferStuckERC20(IERC20 token) external  {
      require(msg.sender == feeRecipientAddr || msg.sender == owner());
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    receive() external payable {}
  }