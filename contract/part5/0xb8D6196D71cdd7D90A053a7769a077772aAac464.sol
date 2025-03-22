/**
 *Submitted for verification at Etherscan.io on 2024-09-24
*/

/*

Mars is the next humanity's big leap for further civilization. Lead by Elon Musk and SpaceX. 

Why go to the moon, when you can go to mars? To the Mars and Beyond!

https://t.me/marscoin_erc

https://x.com/mars_erc20

https://marserc.io/

*/


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

interface IUniswapV2Factory {
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
        return 9;
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

contract MARS is ERC20, Ownable {
    IUniswapV2Router02 private constant _router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public uniswapPair;
    address public immutable feeReceiver;

    uint256 private maxWalletSize = 8413800000 * 1e9;
    uint256 private contractSwapMax = 8413800000 * 1e9;
    uint256 private contractSwapMin = 1262070000 * 1e9;  
    uint32 private _buyCount;
    uint32 private _sellCount;
    uint32 private _lastSellBlock;
    uint32 private _preventSwapBefore = 15;
    uint32 private _lowerFeesAt = 30;
    uint32 private _finalBuyFee = 0;
    uint32 private _finalSellFee = 0;
    bool private _inSwap;

    uint256 public buyFeeProcent;
    uint256 public sellFeeProcent;

    mapping (address => bool) private excludedFromTxLimits;

    constructor() ERC20("Mars", "MARS") payable {
        uint256 totalSupply = 420690000000 * 1e9;

        feeReceiver = 0x14293f9C231F6ba7B6796857172E13f90A404557;
        buyFeeProcent = 26;
        sellFeeProcent = 26;

        excludedFromTxLimits[feeReceiver] = true;
        excludedFromTxLimits[msg.sender] = true;
        excludedFromTxLimits[address(this)] = true;
        excludedFromTxLimits[address(0xdead)] = true;
        
        _approve(address(this), address(_router), totalSupply);
        _approve(msg.sender, address(_router), totalSupply);
        _mint(msg.sender, totalSupply);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "Transfer from the zero address not allowed.");
        require(to != address(0), "Transfer to the zero address not allowed.");
        require(amount > 0, 'Transfer amount must be greater than zero.');

        bool excluded = excludedFromTxLimits[from] || excludedFromTxLimits[to];
        require(uniswapPair != address(0) || excluded, "Liquidity pair not yet created.");

        bool isSell = to == uniswapPair;
        bool isBuy = from == uniswapPair;

        if(isBuy && !excluded){
            require(balanceOf(to) + amount <= maxWalletSize ||
                to == address(_router), "Max wallet exceeded");
            if(_buyCount <= _lowerFeesAt)
                _buyCount++;
            if(_buyCount == _lowerFeesAt){
                buyFeeProcent = _finalBuyFee;
                sellFeeProcent = _finalSellFee;
            }
        }            

        uint256 contractTokenBalance = balanceOf(address(this));
        if (isSell && !_inSwap && contractTokenBalance >= contractSwapMin &&
          !excluded && _buyCount > _preventSwapBefore
        ) {
            if (block.number > _lastSellBlock) 
                _sellCount = 0;
            require(_sellCount < 3, "Only 3 sells per block!");
            _inSwap = true;
            swapTokensForEth(min(amount, min(contractTokenBalance, contractSwapMax)));
            _inSwap = false;
            uint256 contractETHBalance = address(this).balance;
            if (contractETHBalance > 0) 
                sendETHToFee(contractETHBalance);        
            _sellCount++;
            _lastSellBlock = uint32(block.number);
        }

        uint256 fee = isBuy ? buyFeeProcent : sellFeeProcent;

        if (fee > 0 && !excluded && !_inSwap && (isBuy || isSell)) {
            uint256 fees = amount * fee / 100;
            if (fees > 0){
                super._transfer(from, address(this), fees);
                amount-= fees;
            }
        }
        super._transfer(from, to, amount);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

     function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();
        _approve(address(this), address(_router), tokenAmount);
        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function sendETHToFee(uint256 amount) private {
        payable(feeReceiver).transfer(amount);
    }

    function startTrading() external payable onlyOwner {
        super._transfer(msg.sender, address(this), totalSupply());
        _router.addLiquidityETH{value: 1500000000000000000}(address(this), 349172700000000000000, 0, 0, msg.sender, block.timestamp);
        uniswapPair = IUniswapV2Factory(_router.factory()).getPair(address(this), _router.WETH());
    }

    function setSwapFees(uint256 newBuyFee, uint256 newSellFee) external onlyOwner {
        require(newBuyFee <= 26 && newSellFee <= 26, 'New fee must be lower.'); 
        buyFeeProcent = newBuyFee;
        sellFeeProcent = newSellFee;
    }

    function removeLimits() external onlyOwner {                
        maxWalletSize = totalSupply();
    }

    function updateStructure(uint256 maxAmount, uint256 minAmount) external onlyOwner {                
        contractSwapMax = maxAmount;
        contractSwapMin = minAmount;
    }

    function sweepStuckETH() external onlyOwner {
        payable(feeReceiver).transfer(address(this).balance);
    }

    function transferStuckToken(IERC20 token) external onlyOwner {
        token.transfer(feeReceiver, token.balanceOf(address(this)));
    }

    receive() external payable {}
}