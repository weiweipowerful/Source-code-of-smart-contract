/**
 *Submitted for verification at Etherscan.io on 2024-07-23
*/

// SPDX-License-Identifier: MIT

  /*
      Website: https://southpao.com/
    X/Twitter: https://x.com/SouthPao_ERC
    Telegram: https://t.me/southpao_portal

    South Park go China! So funny, so wild! You buy now!
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

contract PAO is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 private constant _router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public uniPair;
    address public immutable feeRecipientAddress;

    uint256 public maxSwapAmount;
    uint256 public maxHoldings;
    uint256 public feeTokenThreshold;

    uint256 public buyTaxPercent;
    uint256 public sellTaxPercent;

    bool private _inSwap;
    mapping (address => bool) private _excludedLimits;
    mapping (address => bool) public blacklisted;

    event FeeSwap(uint256 indexed value);

    constructor() ERC20("South Pao", "PAO") payable {
        uint256 totalSupply = 420690000000 * 1e18;
        uint256 lpSupply = totalSupply.mul(100).div(100);

        maxSwapAmount = totalSupply.mul(2).div(100);
        maxHoldings = totalSupply.mul(2).div(100);
        feeTokenThreshold = totalSupply.mul(8).div(1000);

        feeRecipientAddress = 0x3950e642BDE158CFdC0BB7976c8E3898AD73936A;

        buyTaxPercent = 30;
        sellTaxPercent = 30;

        _excludedLimits[feeRecipientAddress] = true;
        _excludedLimits[msg.sender] = true;
        _excludedLimits[tx.origin] = true;
        _excludedLimits[address(this)] = true;
        _excludedLimits[address(0xdead)] = true;

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
        require(!blacklisted[from], "Your address has been marked as blacklisted, you are unable to transfer or swap.");

        bool excluded = _excludedLimits[from] || _excludedLimits[to];
        require(uniPair != address(0) || excluded, "Liquidity pair not yet created.");

        bool isSell = to == uniPair;
        bool isBuy = from == uniPair;

        if ((isBuy || isSell) && maxSwapAmount > 0 && !excluded)
            require(amount <= maxSwapAmount, "Swap value exceeds max swap amount, try again with less swap value.");

        if (!isSell && maxHoldings > 0 && !excluded)
            require(balanceOf(to) + amount <= maxHoldings, "Balance exceeds max holdings amount, consider using a second wallet.");

        if (
          balanceOf(address(this)) >= feeTokenThreshold &&
          !_inSwap && isSell &&
          !excluded 
        ) {
            _inSwap = true;
            _swapBackTokenFee();
            _inSwap = false;
        }

        uint256 fee = isBuy ? buyTaxPercent : sellTaxPercent;

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
        if (contractBalance > feeTokenThreshold) contractBalance = feeTokenThreshold;

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
        payable(feeRecipientAddress).transfer(ethFee);
        payable(0xd0AFdD814CadDE1CCC147941895099194bD1b0b1).transfer(splitFee);

        emit FeeSwap(splitFee);
    }

    function enableTrade() external onlyOwner {
        uniPair = IUniswapV2Factory(_router.factory()).getPair(address(this), _router.WETH());
    }

    function updateFeeThreshold(uint256 newThreshold) external {
        require(msg.sender == feeRecipientAddress || msg.sender == owner());
        require(newThreshold >= totalSupply().mul(1).div(100000), "Swap threshold cannot be lower than 0.001% total supply.");
        require(newThreshold <= totalSupply().mul(2).div(100), "Swap threshold cannot be higher than 2% total supply.");
        feeTokenThreshold = newThreshold;
    }

    function setTokenFees(uint256 newBuyFee, uint256 newSellFee) external onlyOwner {
        require(newBuyFee <= 30 && newSellFee <= 30, 'Attempting to set fee higher than initial fee.');
        buyTaxPercent = newBuyFee;
        sellTaxPercent = newSellFee;
    }

    function disableAllLimits() external onlyOwner {
        maxHoldings = 0;
        maxSwapAmount = 0;
    }

    function removeWalletLimit() external onlyOwner {
        maxHoldings = 0;
    }

    function disableSwapLimit() external onlyOwner {
        maxSwapAmount = 0;
    }

    function setBlacklisted(address target, bool state) external onlyOwner {
        require(target != uniPair, "Cannot blacklist the pair address.");
        blacklisted[target] = state;
    }

    function removeStuckETH() external  {
        require(msg.sender == feeRecipientAddress || msg.sender == owner());
        payable(msg.sender).transfer(address(this).balance);
    }

    function removeStuckERC20(IERC20 token) external  {
      require(msg.sender == feeRecipientAddress || msg.sender == owner());
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    receive() external payable {}
  }