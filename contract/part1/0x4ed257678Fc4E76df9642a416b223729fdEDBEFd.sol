// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interface/ERC20.sol";
import "./interface/IDEXRouter.sol";
import "./interface/IDEXFactory.sol";

import "./library/Ownable.sol";
import "./utils/SafeMath.sol";

contract StrikeX is ERC20, Ownable {

    using SafeMath for uint256;
    address uniswapV2RouterAdress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address DEAD = 0x000000000000000000000000000000000000dEaD;

    string constant _name = "StrikeX";
    string constant _symbol = "STRX";
    uint8 constant _decimals = 18;

    uint256 public _totalSupply = 1_000_000_000 * (10**_decimals);
    uint256 public _maxWalletAmount = _totalSupply;

    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) _allowances;
    mapping(address => bool) isFeeExempt;
    mapping(address => bool) isTxLimitExempt;

    address public teamAddress;
    address public marketingAddress;
    address public buybackAddress;

    IDEXRouter public router;
    address public pair;

    bool public swapEnabled = true;
    bool public TradingOpen = false;

    bool public feesEnabled = true;
    uint256 public swapThreshold = (_totalSupply / 1000) * 2;
    bool inSwap;

    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() Ownable(msg.sender) {

        router = IDEXRouter(uniswapV2RouterAdress);
        pair = IDEXFactory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );
        _allowances[address(this)][address(router)] = type(uint256).max;

        address _owner = owner;
        
        teamAddress = payable(0xB68D389bf73Ee9fdACb0df1fbf69CD20151F1F41); 
        buybackAddress = payable(0x7E48d044C6D58F71bde05A9B7Af560a5EB99f27C);
        marketingAddress = payable(msg.sender);

        isFeeExempt[_owner] = true;
        isFeeExempt[teamAddress] = true;
        isFeeExempt[address(this)] = true;

        isTxLimitExempt[_owner] = true;
        isTxLimitExempt[pair] = true;
        isTxLimitExempt[teamAddress] = true;
        isTxLimitExempt[address(this)] = true;

        _balances[_owner] = _totalSupply;

        emit Transfer(address(0), _owner, _totalSupply);
    }

    function enableTrading() public onlyOwner {  
        require(!TradingOpen,"trading is already open");
        TradingOpen = true;
    }

    function updateTeamAddress(address newTeamAddress) public onlyOwner {  
        teamAddress = payable(newTeamAddress);
    }

    function updateBuyBackAddress(address newBuyBackAddress) public onlyOwner {  
        buybackAddress = payable(newBuyBackAddress);
    }
    
    function name() external pure override returns (string memory) {
        return _name;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function decimals() external pure override returns (uint8) {
        return _decimals;
    }

    function symbol() external pure override returns (string memory) {
        return _symbol;
    }

    function getOwner() external view override returns (address) {
        return owner;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            msg.sender != pair &&
            !inSwap &&
            swapEnabled &&
            _balances[address(this)] >= swapThreshold;
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function allowance(address holder, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[holder][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender]
                .sub(amount, "Insufficient Allowance");
        }

        return _transferFrom(sender, recipient, amount);
    }

    /**
        Internal functions
    **/

    function takeFee(address sender, address recipient, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 taxFee;

        if(recipient == pair) {
            taxFee = 3;
        }

        uint256 feeAmount = amount.mul(taxFee).div(100);
        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);
        return amount.sub(feeAmount);
    }

    function swapBack() internal swapping {
        uint256 contractTokenBalance = swapThreshold;
        uint256 amountToSwap = contractTokenBalance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountFees = address(this).balance;

        uint256 ethForMarketing = amountFees.div(2);
        payable(marketingAddress).transfer(ethForMarketing);

        uint256 ethForTeam = amountFees.div(3);
        payable(teamAddress).transfer(ethForTeam);

        uint256 ethForBuyBack = amountFees.div(6);
        payable(buybackAddress).transfer(ethForBuyBack);

    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {

        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }

        if(!isFeeExempt[sender] && !isFeeExempt[recipient]){
            require(TradingOpen,"Trading not open yet");
        }

        if (recipient != pair && recipient != DEAD) {
            require(
                isTxLimitExempt[recipient] ||
                    _balances[recipient] + amount <= _maxWalletAmount,
                "Transfer amount exceeds the bag size."
            );
        }

        if (shouldSwapBack()) {
            swapBack();
        }

        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );

        uint256 amountReceived = feesEnabled && shouldTakeFee(sender)
            ? takeFee(sender, recipient, amount)
            : amount;

        _balances[recipient] = _balances[recipient].add(amountReceived);

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }
    receive() external payable {}
}