/* Quantum Cloak - QTC

Website: http://www.quantumcloak.network/
Telegram: https://t.me/Quantum_Cloak
*/
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IERC20.sol";
import "./ownable.sol";
import "./UniswapV2.sol";

contract QuantumCloak is Context, IERC20, Ownable {

    string private constant _name = "Quantum Cloak";
    string private constant _symbol = "QTC";
    uint8 private constant _decimals = 18;
    uint256 private constant _totalSupply = 180000000 * 10**_decimals;

    mapping(address => uint256) private _balance;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _ExcludedWallets;

    uint256 private constant onePercent = (_totalSupply)/100;
    uint256 private constant minimumSwapAmount = onePercent/20;

    uint256 private maxSwap = onePercent / 2;

    uint256 public MaxTX = onePercent;
    uint256 public MaxWallet = onePercent;

    uint256 private InitialBlockNo;

    uint256 public buyTax = 30;
    uint256 public sellTax = 55;

    IUniswapV2Router02 private uniswapV2Router;
    address public uniswapV2Pair;
    address public DevWallet;
    address public OperationWallet;
    address public MarketingWallet;

    bool private launch = false;

    constructor() {
        DevWallet  = 0x8196AcA069A180069c39313F61C1C0c8E5B3039E; //58
        OperationWallet = 0xF97bf6D3B02D1fC1Fa38835bf65268C3d0DedF39; //37
        MarketingWallet = 0x01Ec1626933f684B931e750396dEe4e78014B199; //5

        _balance[msg.sender] = _totalSupply;

        _ExcludedWallets[msg.sender] = 1;
        _ExcludedWallets[address(this)] = 1;

        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balance[account];
    }

    function transfer(address recipient, uint256 amount)public override returns (bool){
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256){
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool){
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if(currentAllowance != type(uint256).max) { 
            require(
                currentAllowance >= amount,
                "ERC20: transfer amount exceeds allowance"
            );
            unchecked {
                _approve(sender, _msgSender(), currentAllowance - amount);
            }
        }
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }


    function EnableTrading() external onlyOwner {
        require(!launch,"trading is already open");
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        _approve(address(this), address(uniswapV2Router), _totalSupply);
        
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        launch = true;
        InitialBlockNo = block.number;
    }

    function _ExcludedWallet(address wallet, uint256 value) external onlyOwner {
        _ExcludedWallets[wallet] = value;
    }

    function ChangeTaxWallet(address NewDevWallet, address NewOperationWallet, address NewMarketWallet) external onlyOwner {
        DevWallet = NewDevWallet;
        OperationWallet = NewOperationWallet;
        MarketingWallet = NewMarketWallet;
    }

    function RemoveLimits() external onlyOwner {
        MaxTX = _totalSupply;
        MaxWallet = _totalSupply;
    }

    function EditTaxes(uint256 newBuyTax, uint256 newSellTax) external onlyOwner {
        require(newBuyTax <= buyTax && newSellTax <= sellTax, "Tax cannot be increased");
        buyTax = newBuyTax;
        sellTax = newSellTax;
    }

    function ChangeSettings(uint256 newMaxWalletX10, uint256 newMaxTrxX10, uint256 newMaxSwapX10) external onlyOwner {
        require(newMaxSwapX10 <= 30, "can't be more than 3%");

        MaxWallet = newMaxWalletX10*(onePercent/10); //type 10 if 1%
        MaxTX = newMaxTrxX10*(onePercent/10);
        maxSwap = newMaxSwapX10*(onePercent/10);
    }

    function _tokenTransfer(address from, address to, uint256 amount, uint256 _tax) private {
        uint256 taxTokens = (amount * _tax) / 100;
        uint256 transferAmount = amount - taxTokens;

        _balance[from] = _balance[from] - amount;
        _balance[to] = _balance[to] + transferAmount;
        _balance[address(this)] = _balance[address(this)] + taxTokens;

        emit Transfer(from, to, transferAmount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(amount > 0, "ERC20: no tokens transferred");
        uint256 _tax = 0;
        if (_ExcludedWallets[from] == 0 && _ExcludedWallets[to] == 0)
        {
            require(launch, "Trading not open");
            require(amount <= MaxTX, "MaxTx Enabled at launch");
            if (to != uniswapV2Pair && to != address(0xdead)) require(balanceOf(to) + amount <= MaxWallet, "MaxWallet Enabled at launch");
            if (block.number < InitialBlockNo + 3) {
                _tax = (from == uniswapV2Pair) ? 30 : 55;
            } else {
                if (from == uniswapV2Pair) {
                    _tax = buyTax;
                } else if (to == uniswapV2Pair) {
                    uint256 tokensToSwap = balanceOf(address(this));
                    if (tokensToSwap > minimumSwapAmount) { 
                        uint256 mxSw = maxSwap;
                        if (tokensToSwap > amount) tokensToSwap = amount;
                        if (tokensToSwap > mxSw) tokensToSwap = mxSw;
                        swapTokensForEth(tokensToSwap);
                    }
                    _tax = sellTax;
                }
            }
        }
        _tokenTransfer(from, to, amount, _tax);
    }

    function RescueETH() external onlyOwner {
        bool success;
        (success, ) = owner().call{value: address(this).balance}("");
    } 

    function ManualSwap(uint256 percent) external onlyOwner {
        uint256 contractBalance = balanceOf(address(this));
        uint256 amtswap = (percent*contractBalance)/100;
        swapTokensForEth(amtswap);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
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
        bool success;

        uint256 devtax = address(this).balance *58/100;
        uint256 operationtax = address(this).balance *37/100;
        uint256 markettax = address(this).balance *5/100;

        (success, ) = DevWallet.call{value: devtax}("");
        (success, ) = OperationWallet.call{value: operationtax}("");
        (success, ) =  MarketingWallet.call{value: markettax}("");
    }
    receive() external payable {}
}