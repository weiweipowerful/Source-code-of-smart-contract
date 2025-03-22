// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title The Wally Group Token
 * @dev ERC20 token with vesting, transaction limits, and tax mechanisms
 */
contract TWGToken is ERC20, Ownable {
    // Constants
    uint256 public constant TOTAL_SUPPLY = 10_000_000_000 * 10**18; // 10 billion tokens
    uint256 public constant MAX_TX_AMOUNT = 150_000_000 * 10**18;   // 1.5% of total supply
    uint256 public constant MIN_TX_AMOUNT = 1_000 * 10**18;         // 1,000 tokens
    uint256 public constant SELL_TAX_RATE = 30;                     // 30% sell tax initially
    
    // Time constants
    uint256 public constant TAX_DURATION = 24 hours;
    
    // State variables
    uint256 public tradingEnabledTimestamp;
    bool public tradingEnabled;
    address public taxCollector;
    mapping(address => bool) public isExcludedFromTax;
    mapping(address => bool) public isExcludedFromTxLimits;
    
    // Vesting related variables
    mapping(address => uint256) public vestedAmount;
    mapping(address => uint256) public vestingEndTime;
    mapping(address => uint256) public vestingStartTime;
    
    // Uniswap variables
    address public uniswapV2Pair;
    address public uniswapV2Router;
    
    // Events
    event TradingEnabled(uint256 timestamp);
    event AddedToTaxExclusion(address indexed account);
    event RemovedFromTaxExclusion(address indexed account);
    event AddedToTxLimitsExclusion(address indexed account);
    event RemovedFromTxLimitsExclusion(address indexed account);
    event TaxCollectorUpdated(address indexed newTaxCollector);
    event TokensVested(address indexed beneficiary, uint256 amount, uint256 endTime);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount);

    /**
     * @dev Constructor to initialize the token
     * @param _taxCollector Address where collected taxes will be sent
     */
    constructor(address _taxCollector) ERC20("The Wally Group Token", "TWG") Ownable() {
        require(_taxCollector != address(0), "Tax collector cannot be zero address");
        taxCollector = _taxCollector;
        
        // Mint total supply to contract itself for distribution
        _mint(address(this), TOTAL_SUPPLY);
        
        // Exclude owner and contract from tax
        isExcludedFromTax[owner()] = true;
        isExcludedFromTax[address(this)] = true;
        isExcludedFromTax[_taxCollector] = true;
        
        // Exclude from transaction limits
        isExcludedFromTxLimits[owner()] = true;
        isExcludedFromTxLimits[address(this)] = true;
        isExcludedFromTxLimits[_taxCollector] = true;
    }
    
    /**
     * @dev Transfer override to check restrictions and apply tax
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // Apply transaction limits if not excluded
        if (!isExcludedFromTxLimits[from] && !isExcludedFromTxLimits[to]) {
            require(amount >= MIN_TX_AMOUNT, "Transfer amount below minimum");
            require(amount <= MAX_TX_AMOUNT, "Transfer amount exceeds maximum");
        }
        
        // Check trading status
        if (!tradingEnabled) {
            require(
                isExcludedFromTxLimits[from] || isExcludedFromTxLimits[to],
                "Trading not yet enabled"
            );
        }
        
        // Apply sell tax if applicable
        if (
            to == uniswapV2Pair && // Sell to the pair
            tradingEnabled &&
            block.timestamp <= (tradingEnabledTimestamp + TAX_DURATION) && // Within tax period
            !isExcludedFromTax[from] // Not excluded from tax
        ) {
            uint256 taxAmount = (amount * SELL_TAX_RATE) / 100;
            uint256 transferAmount = amount - taxAmount;
            
            super._transfer(from, taxCollector, taxAmount);
            super._transfer(from, to, transferAmount);
        } else {
            super._transfer(from, to, amount);
        }
    }
    
    /**
     * @dev Calculate available vested tokens for an address
     * @param beneficiary Address to check vested tokens for
     * @return The amount of available vested tokens
     */
    function calculateAvailableVested(address beneficiary) public view returns (uint256) {
        if (block.timestamp < vestingStartTime[beneficiary]) {
            return 0;
        }
        
        if (block.timestamp >= vestingEndTime[beneficiary]) {
            return vestedAmount[beneficiary];
        }
        
        // Calculate linear vesting amount
        uint256 totalVestingDuration = vestingEndTime[beneficiary] - vestingStartTime[beneficiary];
        uint256 elapsedTime = block.timestamp - vestingStartTime[beneficiary];
        
        return (vestedAmount[beneficiary] * elapsedTime) / totalVestingDuration;
    }
    
    /**
     * @dev Release vested tokens to a beneficiary
     * @param beneficiary Address to release tokens to
     * @return The amount of tokens released
     */
    function releaseVestedTokens(address beneficiary) external returns (uint256) {
        uint256 available = calculateAvailableVested(beneficiary);
        require(available > 0, "No tokens available for release");
        
        // Update vested amount
        vestedAmount[beneficiary] = 0;
        
        // Transfer tokens to beneficiary
        _transfer(address(this), beneficiary, available);
        
        emit TokensReleased(beneficiary, available);
        return available;
    }
    
    /**
     * @dev Create a vesting schedule for a beneficiary
     * @param beneficiary Address to vest tokens for
     * @param amount Amount of tokens to vest
     * @param durationInDays Vesting duration in days
     */
    function createVesting(
        address beneficiary,
        uint256 amount,
        uint256 durationInDays
    ) external onlyOwner {
        require(beneficiary != address(0), "Beneficiary cannot be zero address");
        require(amount > 0, "Vesting amount must be greater than zero");
        require(durationInDays > 0, "Vesting duration must be greater than zero");
        
        // Set vesting details
        vestedAmount[beneficiary] = amount;
        vestingStartTime[beneficiary] = block.timestamp;
        vestingEndTime[beneficiary] = block.timestamp + (durationInDays * 1 days);
        
        emit TokensVested(beneficiary, amount, vestingEndTime[beneficiary]);
    }
    
    /**
     * @dev Enable trading and start the tax period
     */
    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "Trading already enabled");
        tradingEnabled = true;
        tradingEnabledTimestamp = block.timestamp;
        emit TradingEnabled(tradingEnabledTimestamp);
    }
    
    /**
     * @dev Set tax collector address
     * @param _taxCollector New tax collector address
     */
    function setTaxCollector(address _taxCollector) external onlyOwner {
        require(_taxCollector != address(0), "Tax collector cannot be zero address");
        taxCollector = _taxCollector;
        isExcludedFromTax[_taxCollector] = true;
        isExcludedFromTxLimits[_taxCollector] = true;
        emit TaxCollectorUpdated(_taxCollector);
    }
    
    /**
     * @dev Add an address to tax exclusion list
     * @param account Address to exclude from tax
     */
    function excludeFromTax(address account) external onlyOwner {
        require(!isExcludedFromTax[account], "Account already excluded from tax");
        isExcludedFromTax[account] = true;
        emit AddedToTaxExclusion(account);
    }
    
    /**
     * @dev Remove an address from tax exclusion list
     * @param account Address to include in tax
     */
    function includeInTax(address account) external onlyOwner {
        require(isExcludedFromTax[account], "Account already included in tax");
        isExcludedFromTax[account] = false;
        emit RemovedFromTaxExclusion(account);
    }
    
    /**
     * @dev Add an address to transaction limits exclusion list
     * @param account Address to exclude from transaction limits
     */
    function excludeFromTxLimits(address account) external onlyOwner {
        require(!isExcludedFromTxLimits[account], "Account already excluded from limits");
        isExcludedFromTxLimits[account] = true;
        emit AddedToTxLimitsExclusion(account);
    }
    
    /**
     * @dev Remove an address from transaction limits exclusion list
     * @param account Address to include in transaction limits
     */
    function includeInTxLimits(address account) external onlyOwner {
        require(isExcludedFromTxLimits[account], "Account already included in limits");
        isExcludedFromTxLimits[account] = false;
        emit RemovedFromTxLimitsExclusion(account);
    }
    
    /**
     * @dev Add liquidity to Uniswap
     * @param tokenAmount Amount of tokens to add to liquidity
     */
    function addLiquidity(uint256 tokenAmount, address _uniswapRouter) external payable onlyOwner {
        require(tokenAmount > 0, "Token amount must be greater than zero");
        require(msg.value > 0, "ETH amount must be greater than zero");
        require(uniswapV2Pair == address(0), "Liquidity already added");
        require(_uniswapRouter != address(0), "Router cannot be zero address");
        
        uniswapV2Router = _uniswapRouter;
        
        // Created via interface to avoid direct dependency
        // Interface of IERC20 transfer and approve functions
        (bool success,) = address(this).call(
            abi.encodeWithSignature(
                "approve(address,uint256)", 
                _uniswapRouter, 
                tokenAmount
            )
        );
        require(success, "Approve failed");
        
        // Add liquidity - minimal interface interaction to avoid dependencies
        (bool addSuccess,) = _uniswapRouter.call{value: msg.value}(
            abi.encodeWithSignature(
                "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)", 
                address(this), 
                tokenAmount,
                0,
                0,
                owner(),
                block.timestamp + 300
            )
        );
        require(addSuccess, "Add liquidity failed");
        
        // Get pair address from factory - minimal interface interaction
        (bool getPairSuccess, bytes memory data) = _uniswapRouter.call(
            abi.encodeWithSignature("factory()")
        );
        require(getPairSuccess, "Get factory failed");
        
        address factory = abi.decode(data, (address));
        
        (bool getPairSuccess2, bytes memory data2) = factory.call(
            abi.encodeWithSignature(
                "getPair(address,address)", 
                address(this),
                address(0) // WETH - placeholder, real implementation would get from router
            )
        );
        require(getPairSuccess2, "Get pair failed");
        
        uniswapV2Pair = abi.decode(data2, (address));
        
        emit LiquidityAdded(tokenAmount, msg.value);
    }
    
    /**
     * @dev Distribute tokens to multiple addresses
     * @param addresses Array of recipient addresses
     * @param amounts Array of token amounts
     */
    function distributeTokens(
        address[] calldata addresses,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(addresses.length == amounts.length, "Arrays must have same length");
        require(addresses.length > 0, "Must distribute to at least one address");
        
        for (uint256 i = 0; i < addresses.length; i++) {
            require(addresses[i] != address(0), "Cannot distribute to zero address");
            require(amounts[i] > 0, "Amount must be greater than zero");
            
            _transfer(address(this), addresses[i], amounts[i]);
        }
    }
    
    /**
     * @dev Emergency token recovery function
     * @param tokenAddress Address of token to recover
     * @param tokenAmount Amount of tokens to recover
     */
    function recoverTokens(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner {
        require(tokenAddress != address(this), "Cannot recover TWG tokens");
        
        // Created via interface to avoid direct dependency
        // Interface of IERC20 transfer function
        (bool success,) = tokenAddress.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)", 
                owner(), 
                tokenAmount
            )
        );
        require(success, "Transfer failed");
    }
}