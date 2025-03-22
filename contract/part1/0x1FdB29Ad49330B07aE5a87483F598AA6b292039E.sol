// SPDX-License-Identifier: None

pragma solidity ^0.8.26;

// Importing required contracts and interfaces from OpenZeppelin and Uniswap
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

// Custom errors for better error handling
error InvalidTransfer(address from, address to);
error InvalidConfiguration();
error TradingNotEnabled();

// Custom events for reporting
event FeesProcessed(uint256 swapTokensAtAmount);
event FeesChanged(uint256 buy, uint256 sell);
event SwapThresholdAdjusted(uint256 amount);
event TradingStatus(bool enable);

// Main contract
contract LivingTheDream is ERC20, ERC20Burnable, Ownable {

// Struct for storing user information
    struct UserInfo {
        bool isFeeExempt; // If true, the user doesn't have to pay fees
        bool isBlacklisted; // If true, the user is blacklisted and cannot perform transactions
        bool isAMM; // If true, the user is an Automated Market Maker
    }

    // Maximum supply of the token
    uint256 public constant MAX_SUPPLY = 333_333_333_333 * 10**18;

    // Uniswap router and pair for dex functions
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable pair;

    // Wallet where the treasury funds are stored
    address payable public treasuryWallet;

    // If true, trading is enabled. Default is false.
    bool public isTradingEnabled;

    // Variables for swapping mechanism. Enabled/disabled and threshold amount / amount to swap.
    uint256 public swapping;
    uint256 public swapTokensAtAmount = 41666666666625 * 10**13; // 0.125% of total supply

    // Variables for fee mechanism. Total fee tokens current held and buy/sell fees.
    uint256 public totalFeeTokens;
    uint256 public buyFee = 10;
    uint256 public sellFee = 7;

    // Mapping to store user privlages/permissions (see struct UserInfo)
    mapping (address => UserInfo) public userInfo;

    // Ran on deployment to set up the contract. Pass in the treasury wallet and the router address.
    constructor(
        address _treasuryWallet,
        address _router
    ) ERC20("LivingTheDream", "LTD") Ownable(msg.sender) payable {

        // Set the Uniswap router and give it approval to spend the contract's tokens
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_router);
        uniswapV2Router = _uniswapV2Router;
        _approve(address(this), address(uniswapV2Router), type(uint256).max);

        // Create a Uniswap pair for the token
        pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        // Set the treasury wallet to the address passed in
        treasuryWallet = payable(_treasuryWallet);

        // Set this contract as the fee exempt and set the AMM flag for the pair
        userInfo[address(this)].isFeeExempt = true;
        userInfo[pair].isAMM = true;

        // Mint the total supply to the owner
        super._update(address(0), owner(), MAX_SUPPLY);
    }

    // Internal transfer logic (run on each transfer)
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        UserInfo storage sender = userInfo[from];
        UserInfo storage recipient = userInfo[to];
        if (sender.isBlacklisted || recipient.isBlacklisted) {
            revert InvalidTransfer(from, to);
        }

        if (swapping == 2 || from == owner() || to == owner() || amount == 0) {
            super._update(from, to, amount);
            return;
        }
        // Dissallow transfers if trading is not enabled.
        if (!isTradingEnabled) {
            revert TradingNotEnabled(); 
        }
        // Determine if we have reached the swapping threshold and swap if we have (unless we are already swapping)
        if (totalFeeTokens >= swapTokensAtAmount && !sender.isAMM) {
            swapping = 2;
            swapAndSend(swapTokensAtAmount);
            totalFeeTokens -= swapTokensAtAmount;
            emit FeesProcessed(swapTokensAtAmount);
            swapping = 1;
        }
        // Calculate fees and update balances, assuming the sender and recipient are not fee exempt
        if (!sender.isFeeExempt && !recipient.isFeeExempt) {

            uint256 fees;
            if (recipient.isAMM) { //sell
                fees = amount * sellFee / 100;
            } else if (sender.isAMM) { //buy
                fees = amount * buyFee / 100;
            }
            if (fees != 0) { 
                totalFeeTokens += fees;
                amount -= fees;
                super._update(from, address(this), fees);  // Transfer fees 
            }
        }
        // Transfer the remaining amount (full amount if a fee-exempt transfer)
        super._update(from, to, amount); 

    }

    // Function to swap tokens for ETH and send them to the treasury wallet
    function swapAndSend(uint256 tokenAmount) internal {
        // Generate the Uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        // Swap tokens for ETH, depositing resulting ETH to the treasury wallet
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            treasuryWallet,
            block.timestamp
        );
    }

    // Admin function to change buy and sell fees up to 10% maximum
    function changeFees(uint256 buy, uint256 sell) external onlyOwner {
        if (buy > 10 || sell > 10) {
            revert InvalidConfiguration();
        }
        buyFee = buy;
        sellFee = sell;

        emit FeesChanged(buy, sell);
    }

    // Admin function to set a single address as fee exempt
    function setFeeExempt(address account, bool value) public onlyOwner {
        userInfo[account].isFeeExempt = value;
    }

    // Admin function to set many addresses as fee exempt
    function setFeeExemptMany(address[] memory accounts) public onlyOwner {
        uint256 len = accounts.length;
        for (uint256 i; i < len; ++i) { 
            userInfo[accounts[i]].isFeeExempt = true;
        }
    }

    // Admin function to set aa single address as blacklisted
    function setBlacklisted(address account, bool value) external onlyOwner {
        userInfo[account].isBlacklisted = value;
    }

    // Admin function to set many addresses as blacklisted
    function setBlacklistedMany(address[] memory accounts) external onlyOwner {
        uint256 len = accounts.length;
        for (uint256 i = 0; i < len; ++i) { 
            userInfo[accounts[i]].isBlacklisted = true;
        }
    }

    // Admin function to set a single address as an AMM
    function setAMM(address account, bool value) external onlyOwner {
        userInfo[account].isAMM = value;
    }

    // Admin function to update the treasury wallet address
    function setTreasuryWallet(address newWallet) external onlyOwner {
        treasuryWallet = payable(newWallet);
    }

    // Admin function to update the swapping threshold
    function setSwapAtAmount(uint256 amount) external onlyOwner {
        swapTokensAtAmount = amount;
        emit SwapThresholdAdjusted(amount);
    }

    // Admin function to enable trading (no option to disable trading once enabled)
    function enableTrading(bool enable) external onlyOwner {
        isTradingEnabled = enable;
        emit TradingStatus(enable);
    }

    // Admin function to withdraw stuck tokens (excluding fee tokens)
    function withdrawStuckTokens(address token) external onlyOwner {
        if (token == address(this)) {
            super._update(address(this), _msgSender(), balanceOf(address(this)) - totalFeeTokens);
        } else {
            // bytes4(keccak256(bytes('transfer(address,uint256)')));
            (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, _msgSender(), IERC20(token).balanceOf(address(this))));
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
                revert InvalidTransfer(address(this), _msgSender());
            }
        }
    }

    // Public function to get the circulating supply. Subtracts tokens in the 0xdead burn address.
    function getCirculatingSupply() external view returns (uint256) {
        return totalSupply() - balanceOf(address(0xdead));
    }

}