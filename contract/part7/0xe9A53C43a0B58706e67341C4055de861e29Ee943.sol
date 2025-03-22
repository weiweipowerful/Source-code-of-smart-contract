// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/IElementNFT.sol";
import "./interfaces/ITITANX.sol";
import "./interfaces/IWETH9.sol";
import "./lib/constants.sol";

/// @title Element 280 Token Contract
contract Element280 is ERC20, Ownable2Step, IERC165 {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    // --------------------------- STATE VARIABLES --------------------------- //

    struct UserPurchase {
        uint256 timestamp;
        uint256 amount;
    }

    address public treasury;
    address public devWallet;
    address public E280NFT;
    address public HOLDER_VAULT;
    address public BUY_AND_BURN;

    /// @notice Total number of liqudity pools created for Element 280 protocol tokens
    uint8 public totalLPsCreated;

    /// @notice Purchases of ecosystem tokens are in progress
    bool public lpPurchaseStarted;

    /// @notice Purchases of ecosystem tokens are done
    bool public lpPurchaseFinished;

    /// @notice Trading is disabled until all LPs are created. Enables automatically with the creation of the last LP.
    bool public tradingEnabled;

    /// @notice TitanX tokens designated for ecosystem token purchases.
    uint256 public lpPool;

    /// @notice TitanX tokens used for ecosystem token purchases.
    uint256 public totalLpPoolUsed;

    /// @notice Total ELMT tokens burned to date.
    uint256 public totalBurned;

    /// @notice Timestamp in seconds of the presale end date.
    uint256 public presaleEnd;
    uint256 private _currentPurchaseId;

    /// @notice Purchase information for a specific purchase ID.
    /// @return timestamp The time when the purchase was made (as a Unix timestamp).
    /// @return amount The amount of Element 280 toknes of the purchase.
    mapping(uint256 purchaseId => UserPurchase) public purchases;

    /// @notice Returns the total amount of ecosystem tokens purchased for LP creation for a specific token.
    /// @return The total amount of the specified token allocated to the LP pool (in WEI).
    mapping(address token => uint256) public tokenPool;

    /// @notice Percent of the lpPool to calculate the allocation per ecosystem token purchases.
    mapping(address token => uint8) public tokenLpPercent;

    /// @notice Are transcations to provided address whitelisted.
    mapping(address => bool) public whitelistTo;

    /// @notice Are transcations from provided address whitelisted.
    mapping(address => bool) public whitelistFrom;

    /// @notice Total number of purchases per each ecosystem token. 5 per token is required.
    mapping(address token => uint8) public lpPurchases;

    mapping(address user => EnumerableSet.UintSet) private _userPurchases;

    // --------------------------- EVENTS & MODIFIERS --------------------------- //

    event PresaleStarted();

    modifier onlyPresale() {
        require(isPresaleActive(), "Presale not active");
        _;
    }

    modifier onlyNftContract() {
        require(msg.sender == E280NFT, "Unauthorized");
        _;
    }

    // --------------------------- CONSTRUCTOR --------------------------- //
    constructor(
        address _owner,
        address _devWallet,
        address _treasury,
        address[] memory _ecosystemTokens,
        uint8[] memory _lpPercentages
    ) ERC20("Element 280", "ELMNT") Ownable(_owner) {
        require(_ecosystemTokens.length == NUM_ECOSYSTEM_TOKENS, "Incorrect number of tokens");
        require(_lpPercentages.length == NUM_ECOSYSTEM_TOKENS, "Incorrect number of tokens");
        require(_owner != address(0), "Owner wallet not provided");
        require(_devWallet != address(0), "Dev wallet address not provided");
        require(_treasury != address(0), "Treasury address not provided");

        devWallet = _devWallet;
        treasury = _treasury;

        whitelistFrom[address(0)] = true;
        whitelistTo[address(0)] = true;

        uint8 totalPercentage;
        for (uint256 i = 0; i < _ecosystemTokens.length; i++) {
            address token = _ecosystemTokens[i];
            uint8 allocation = _lpPercentages[i];
            require(token != address(0), "Incorrect token address");
            require(allocation > 0, "Incorrect percentage value");
            require(tokenLpPercent[token] == 0, "Duplicate token");
            tokenLpPercent[token] = allocation;
            totalPercentage += allocation;
        }
        require(totalPercentage == 100, "Percentages do not add to 100");
    }

    // --------------------------- PUBLIC FUNCTIONS --------------------------- //

    /// @notice Allows users to purchase tokens during the presale using TitanX tokens.
    /// @param amount The amount of TitanX tokens to spend.
    function purchaseWithTitanX(uint256 amount) external onlyPresale {
        require(amount > 0, "Cannot purchase 0 tokens");
        IERC20(TITANX).safeTransferFrom(msg.sender, address(this), amount);
        _writePurchaseData(amount, msg.sender);
    }

    /// @notice Allows users to purchase tokens during the presale using ETH.
    /// @param minAmount The minimum amount of Element 280 tokens to purchase.
    function purchaseWithETH(uint256 minAmount, uint256 deadline) external payable onlyPresale {
        require(minAmount > 0, "Cannot purchase 0 tokens");
        uint256 swappedAmount = _swapETHForTitanX(minAmount, deadline);
        _writePurchaseData(swappedAmount, msg.sender);
    }

    /// @notice Allows users to claim their purchased tokens after the cooldown period.
    /// @param purchaseId The ID of the purchase to claim.
    function claimPurchase(uint256 purchaseId) external {
        require(_userPurchases[msg.sender].contains(purchaseId), "Cannot claim");
        UserPurchase memory purchase = purchases[purchaseId];
        require(purchase.timestamp + COOLDOWN_PERIOD < block.timestamp, "Cooldown is active");
        _userPurchases[msg.sender].remove(purchaseId);
        _mint(msg.sender, purchase.amount);
    }

    /// @notice Transfers TitanX allocation to Element 280 Buy&Burn contract.
    /// @dev Can only be called when there is an allocation for buy and burn.
    function distributeBuyAndBurn() external {
        uint256 allocation = getBuyBurnAllocation();
        require(allocation > 0, "Nothing to distribute");
        IERC20(TITANX).safeTransfer(BUY_AND_BURN, allocation);
    }

    /// @notice Burns the specified amount of tokens from the user's balance.
    /// @param value The amount of tokens in wei.
    function burn(uint256 value) public virtual {
        totalBurned += value;
        _burn(_msgSender(), value);
    }

    // --------------------------- PRESALE MANAGEMENT FUNCTIONS --------------------------- //

    /// @notice Starts the presale for the token.
    function startPresale() external onlyOwner {
        require(E280NFT != address(0), "NFT not set");
        require(presaleEnd == 0, "Can only be done once");
        unchecked {
            presaleEnd = block.timestamp + PRESALE_LENGTH;
        }
        IElementNFT(E280NFT).startPresale(presaleEnd);
        emit PresaleStarted();
    }

    /// @notice Begins the liquidity pool creation process after the presale has either ended or accumulated more than 200B TitanX.
    function startLpPurchases() external onlyOwner {
        require(presaleEnd != 0, "Presale not started yet");
        require(!lpPurchaseStarted, "LP creation already started");
        uint256 availableBalance = IERC20(TITANX).balanceOf(address(this));
        require(availableBalance > 0, "No TitanX available");
        if (availableBalance < LP_POOL_SIZE) {
            require(block.timestamp >= presaleEnd, "Presale not finished yet");
            _registerLPPool(availableBalance);
        } else {
            _registerLPPool(LP_POOL_SIZE);
        }
        lpPurchaseStarted = true;
    }

    /// @notice Executes token purchase of the ecosystem tokens for the liquidity pool based on the allocation.
    /// @param target The target token to purchase.
    /// @param minAmountOut Minimum amout to be received after swap.
    /// @dev Can only be called by the contract owner during the LP purchase phase.
    function purchaseTokenForLP(address target, uint256 minAmountOut, uint256 deadline) external onlyOwner {
        require(lpPurchaseStarted && !lpPurchaseFinished, "LP phase not active");
        require(lpPurchases[target] < 5, "All purchases have been made for target token");
        uint8 allocation = tokenLpPercent[target];
        require(allocation > 0, "Incorrect target token");
        uint256 amount = lpPool * allocation / 500;
        totalLpPoolUsed += amount;
        uint256 swappedAmount = _swapTitanXToToken(target, amount, minAmountOut, deadline);
        unchecked {
            tokenPool[target] += swappedAmount;
            lpPurchases[target]++;
            // account for rounding error
            if (totalLpPoolUsed >= lpPool - NUM_ECOSYSTEM_TOKENS * 5) lpPurchaseFinished = true;
        }
    }

    /// @notice Deploys the liquidity pool for a specific ecosystem token.
    /// @param target The token for which the liquidity pool will be deployed.
    /// @dev Can only be called by the contract owner after the LP phase has completed.
    function deployLP(address target, uint256 minTokenAmount, uint256 minE280Amount) external onlyOwner {
        require(lpPurchaseFinished, "Not all tokens have been purchased");
        uint8 allocation = tokenLpPercent[target];
        require(allocation > 0, "Incorrect target token");
        uint256 e280Amount = lpPool * allocation / 100;
        uint256 tokenAmount = tokenPool[target];
        require(tokenAmount > 0, "Pool already deployed");
        _deployLiqudityPool(target, tokenAmount, e280Amount, minTokenAmount, minE280Amount);
        unchecked {
            totalLPsCreated++;
        }
        if (totalLPsCreated == NUM_ECOSYSTEM_TOKENS) _enableTrading();
    }

    // --------------------------- ADMINISTRATIVE FUNCTIONS --------------------------- //

    /// @notice Sets the required addresses for the Element 280 protocol.
    /// @param nftAddress The address of the Element 280 NFT contract.
    /// @param vaultAddress The address of the Element 280 Holder Vault contract.
    /// @param buyAndBurn The address of the Element 280 Buy&Burn contract.
    /// @dev Can only be set once and can only be called by the owner.
    function setProtocolAddresses(address nftAddress, address vaultAddress, address buyAndBurn) external onlyOwner {
        require(E280NFT == address(0), "Can only be done once");
        require(nftAddress != address(0), "NFT address not provided");
        require(vaultAddress != address(0), "Holder Vault address not provided");
        require(buyAndBurn != address(0), "Buy&Burn address not provided");
        E280NFT = nftAddress;
        HOLDER_VAULT = vaultAddress;
        BUY_AND_BURN = buyAndBurn;
        whitelistFrom[HOLDER_VAULT] = true;
        whitelistTo[BUY_AND_BURN] = true;
    }

    /// @notice Sets the treasury address.
    /// @param _address The address of the treasury.
    /// @dev Can only be called by the owner.
    function setTreasury(address _address) external onlyOwner {
        require(_address != address(0), "Treasury address not provided");
        treasury = _address;
    }

    /// @notice Sets the whitelist status for transfers to a specified address.
    /// @param _address The address which whitelist status will be modified.
    /// @param enabled Will the address be whitelisted.
    /// @dev Can only be called by the owner.
    function setWhitelistTo(address _address, bool enabled) external onlyOwner {
        whitelistTo[_address] = enabled;
    }

    /// @notice Sets the whitelist status for transfers from a specified address.
    /// @param _address The address which whitelist status will be modified.
    /// @param enabled Will the address be whitelisted.
    /// @dev Can only be called by the owner.
    function setWhitelistFrom(address _address, bool enabled) external onlyOwner {
        whitelistFrom[_address] = enabled;
    }

    // --------------------------- VIEW FUNCTIONS --------------------------- //

    /// @notice Checks if the presale is currently active.
    /// @return A boolean indicating whether the presale is still active.
    function isPresaleActive() public view returns (bool) {
        return presaleEnd > block.timestamp;
    }

    /// @notice Returns all purchase IDs associated with a specific user.
    /// @param account The address of the user.
    /// @return An array of purchase IDs owned by the user.
    function getUserPurchaseIds(address account) external view returns (uint256[] memory) {
        return _userPurchases[account].values();
    }

    /// @notice Returns the available TitanX tokens for Element 280 Buy&Burn contract.
    /// @return The amount of TitanX tokens allocated (in WEI).
    /// @dev Requires that trading has been enabled.
    function getBuyBurnAllocation() public view returns (uint256) {
        require(tradingEnabled, "Trading is not enabled yet");
        return IERC20(TITANX).balanceOf(address(this));
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == INTERFACE_ID_ERC165 || interfaceId == INTERFACE_ID_ERC20;
    }

    // --------------------------- INTERNAL FUNCTIONS --------------------------- //

    /// @notice Handles the redemption process, applying tax and distributing the remaining amount.
    /// @param amount The amount to redeem.
    /// @param receiver The address to receive the redeemed amount after tax.
    /// @dev This function is only callable by the NFT contract.
    function handleRedeem(uint256 amount, address receiver) external onlyNftContract {
        (uint256 taxAmount, uint256 amountAfterTax) = _processTax(amount, NFT_REDEEM_TAX_PERCENTAGE);
        _mint(HOLDER_VAULT, taxAmount);
        _mint(receiver, amountAfterTax);
    }

    function _enableTrading() internal {
        tradingEnabled = true;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (!tradingEnabled) {
            if (from == address(this) || from == address(0)) {
                super._update(from, to, amount);
            } else {
                revert("Trading is disabled");
            }
        } else {
            if (whitelistTo[to] || whitelistFrom[from]) {
                super._update(from, to, amount);
            } else {
                uint256 taxPercentage = isPresaleActive() ? PRESALE_TRANSFER_TAX_PERCENTAGE : TRANSFER_TAX_PERCENTAGE;
                (uint256 taxAmount, uint256 amountAfterTax) = _processTax(amount, taxPercentage);
                super._update(from, HOLDER_VAULT, taxAmount);
                super._update(from, to, amountAfterTax);
            }
        }
    }

    function _writePurchaseData(uint256 amount, address to) internal {
        purchases[_currentPurchaseId] = UserPurchase(block.timestamp, amount);
        _userPurchases[to].add(_currentPurchaseId);
        unchecked {
            _currentPurchaseId++;
        }
    }

    function _processTax(uint256 amount, uint256 percentage)
        internal
        pure
        returns (uint256 taxAmount, uint256 amountAfterTax)
    {
        unchecked {
            taxAmount = (amount * percentage) / 100;
            amountAfterTax = amount - taxAmount;
        }
    }

    function _registerLPPool(uint256 amount) internal {
        uint256 devAmount = amount * DEV_PERCENT / 100;
        uint256 treasuryAmount = amount * TREASURY_PERCENT / 100;
        IERC20(TITANX).safeTransfer(devWallet, devAmount);
        IERC20(TITANX).safeTransfer(treasury, treasuryAmount);
        lpPool = amount - devAmount - treasuryAmount;
        lpPurchases[TITANX] = 5;
        uint256 titanXPool = lpPool * tokenLpPercent[TITANX] / 100;
        tokenPool[TITANX] = titanXPool;
        totalLpPoolUsed += titanXPool;
    }

    function _deployLiqudityPool(address tokenAddress, uint256 tokenAmount, uint256 e280Amount, uint256 minTokenAmount, uint256 minE280Amount) internal {
        (uint256 pairBalance, address pairAddress) = _checkPoolValidity(tokenAddress);
        if (pairBalance > 0) _fixPool(pairAddress, tokenAmount, e280Amount, pairBalance);
        _mint(address(this), e280Amount);
        IERC20(address(this)).safeIncreaseAllowance(UNISWAP_V2_ROUTER, e280Amount);
        IERC20(tokenAddress).safeIncreaseAllowance(UNISWAP_V2_ROUTER, tokenAmount);
        IUniswapV2Router02(UNISWAP_V2_ROUTER).addLiquidity(
            address(this),
            tokenAddress,
            e280Amount,
            tokenAmount,
            minE280Amount,
            minTokenAmount,
            address(0), //send governance tokens directly to zero address
            block.timestamp
        );
        tokenPool[tokenAddress] = 0;
    }

    function _checkPoolValidity(address target) internal view returns (uint256, address) {
        address pairAddress = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(address(this), target);
        if (pairAddress == address(0)) return (0, pairAddress);
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        if (reserve0 != 0) return (reserve0, pairAddress);
        if (reserve1 != 0) return (reserve1, pairAddress);
        return (0, pairAddress);
    }

    function _fixPool(address pairAddress, uint256 tokenAmount, uint256 e280Amount, uint256 currentBalance) internal {
        uint256 requiredE280 = currentBalance * e280Amount / tokenAmount;
        _mint(pairAddress, requiredE280);
        IUniswapV2Pair(pairAddress).sync();
    }

    function _swapETHForTitanX(uint256 minAmountOut, uint256 deadline) internal returns (uint256) {
        IWETH9(WETH9).deposit{value: msg.value}();

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH9,
            tokenOut: TITANX,
            fee: POOL_FEE_1PERCENT,
            recipient: address(this),
            deadline: deadline,
            amountIn: msg.value,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });
        IERC20(WETH9).safeIncreaseAllowance(UNISWAP_V3_ROUTER, msg.value);
        uint256 amountOut = ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(params);
        return amountOut;
    }

    function _swapTitanXToToken(address outputToken, uint256 amount, uint256 minAmountOut, uint256 deadline)
        internal
        returns (uint256)
    {
        if (outputToken == BLAZE_ADDRESS) return _swapUniswapV2Pool(outputToken, amount, minAmountOut, deadline);
        if (outputToken == BDX_ADDRESS || outputToken == HYDRA_ADDRESS || outputToken == AWESOMEX_ADDRESS) {
            return _swapMultihop(outputToken, DRAGONX_ADDRESS, amount, minAmountOut, deadline);
        }
        if (outputToken == FLUX_ADDRESS) {
            return _swapMultihop(outputToken, INFERNO_ADDRESS, amount, minAmountOut, deadline);
        }
        return _swapUniswapV3Pool(outputToken, amount, minAmountOut, deadline);
    }

    function _swapUniswapV3Pool(address outputToken, uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        internal
        returns (uint256)
    {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: TITANX,
            tokenOut: outputToken,
            fee: POOL_FEE_1PERCENT,
            recipient: address(this),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });
        IERC20(TITANX).safeIncreaseAllowance(UNISWAP_V3_ROUTER, amountIn);
        uint256 amountOut = ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(params);
        return amountOut;
    }

    function _swapUniswapV2Pool(address outputToken, uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        internal
        returns (uint256)
    {
        require(minAmountOut > 0, "minAmountOut not provided");
        IERC20(TITANX).safeIncreaseAllowance(UNISWAP_V2_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = TITANX;
        path[1] = outputToken;

        uint256[] memory amounts = IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn, minAmountOut, path, address(this), deadline
        );

        return amounts[1];
    }

    function _swapMultihop(
        address outputToken,
        address midToken,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) internal returns (uint256) {
        bytes memory path = abi.encodePacked(TITANX, POOL_FEE_1PERCENT, midToken, POOL_FEE_1PERCENT, outputToken);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(this),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });
        IERC20(TITANX).safeIncreaseAllowance(UNISWAP_V3_ROUTER, amountIn);
        uint256 amoutOut = ISwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
        return amoutOut;
    }
}