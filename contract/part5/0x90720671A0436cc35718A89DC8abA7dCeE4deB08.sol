// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**

 DEXLab AI - DXAI

 ░▒▓███████▓▒░░▒▓████████▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░       ░▒▓██████▓▒░░▒▓███████▓▒░        ░▒▓██████▓▒░░▒▓█▓▒░ 
 ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
 ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
 ░▒▓█▓▒░░▒▓█▓▒░▒▓██████▓▒░  ░▒▓██████▓▒░░▒▓█▓▒░      ░▒▓████████▓▒░▒▓███████▓▒░       ░▒▓████████▓▒░▒▓█▓▒░ 
 ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
 ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
 ░▒▓███████▓▒░░▒▓████████▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓████████▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓███████▓▒░       ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
                                                                                                           
 * https://dexlab.ai/
 * https://x.com/dexlabai
 * https://t.me/dexlabai
 *
 * @title DEXLab AI Token Contract
 * @dev Implements ERC20 functionality with sell tax.
 */
contract DEXLabAI is ERC20, Ownable {
    // Uniswap Router and Pair addresses for liquidity and handling tax.
    mapping(address => bool) public isPairAddress;
    IUniswapV2Router02 public uniswapRouter;

    // Uniswap V2 Router address on Ethereum Mainnet
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Token distribution
    uint256 private constant TOTAL_SUPPLY = 10_000_000_000 * 10 ** 18; // 10 billion tokens

    // Wallet allocations
    uint256 private constant TEAM_SUPPLY = (TOTAL_SUPPLY * 8) / 100; // 8%
    uint256 private constant CEX_SUPPLY = (TOTAL_SUPPLY * 8) / 100; // 8%
    uint256 private constant AIRDROP_SUPPLY = (TOTAL_SUPPLY * 3) / 100; // 3%
    uint256 private constant OLD_HOLDERS_SUPPLY = (TOTAL_SUPPLY * 4) / 100; // 4%

    // Team wallets (2 x 4%)
    address private constant TEAM_WALLET_1 = 0xCd6323E2AdD9823caDF0c3747FB0b93105D13ebe;
    address private constant TEAM_WALLET_2 = 0x606dA4091990bD450b0ace877F4124E3436b0B53;

    // CEX wallets (2 x 4%)
    address private constant CEX_WALLET_1 = 0x2Ff11DE5bF792D2E141A5568B8693a7989CB2f8A;
    address private constant CEX_WALLET_2 = 0xbf5EB23Ba9F3e1391bE5df95eED8CE615E3b2519;

    // Airdrop wallet
    address private constant AIRDROP_WALLET = 0xC2f8DFF853081892809E4cF5c1E88c3bade1f4a2;

    // Old holders wallet
    address private constant OLD_HOLDERS_WALLET = 0xE21431CE0cA911Ad92d67b4a7112bB1dF86873aE;

    // Tax wallets
    address private constant MARKETING_WALLET = 0x72bF6F8FF8c69b09CEe7b3F38Ebe823893e673F2;
    address private constant DEVELOPMENT_WALLET = 0x474A736c40A682c620d928FbBAe605E45A2ccB0C;

    // Fee rate (4% sell tax)
    uint256 private constant TAX_RATE = 4;

    // Events
    event TradingStarted(address indexed pairAddress);
    event SellTaxApplied(address indexed sender, uint256 amount, uint256 sellTaxAmount);

    /**
     * @dev Constructor that sets the token name and symbol, mints the total supply,
     * and allocates tokens to specified wallets.
     */
    constructor() ERC20("DEXLab AI", "DXAI") Ownable(msg.sender) {
        // Mint total supply to the contract owner
        _mint(msg.sender, TOTAL_SUPPLY);

        // Transfer allocations to respective wallets
        // Team wallets (2 x 4%)
        uint256 teamWalletAllocation = TEAM_SUPPLY / 2;
        _transfer(msg.sender, TEAM_WALLET_1, teamWalletAllocation);
        _transfer(msg.sender, TEAM_WALLET_2, teamWalletAllocation);

        // CEX wallets (2 x 4%)
        uint256 cexWalletAllocation = CEX_SUPPLY / 2;
        _transfer(msg.sender, CEX_WALLET_1, cexWalletAllocation);
        _transfer(msg.sender, CEX_WALLET_2, cexWalletAllocation);

        // Airdrop wallet
        _transfer(msg.sender, AIRDROP_WALLET, AIRDROP_SUPPLY);

        // Old holders wallet
        _transfer(msg.sender, OLD_HOLDERS_WALLET, OLD_HOLDERS_SUPPLY);
    }

    /**
     * @dev Start trading by creating a pair on Uniswap V2.
     */
    function startTrading() external onlyOwner {
        uniswapRouter = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        address pair = IUniswapV2Factory(uniswapRouter.factory()).getPair(address(this), uniswapRouter.WETH());

        // Create a pair if it doesn't exist
        if (pair == address(0)) {
            pair = IUniswapV2Factory(uniswapRouter.factory()).createPair(address(this), uniswapRouter.WETH());
            isPairAddress[pair] = true;
            emit TradingStarted(pair);
        }
    }

    /**
     * @dev Overridden _transfer function that applies a tax on sell transactions.
     * @param sender Address sending the tokens.
     * @param recipient Address receiving the tokens.
     * @param amount Amount of tokens to transfer.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        // Apply sell tax if applicable
        if (_shouldApplySellTax(sender, recipient)) {
            uint256 sellTaxAmount = _applySellTax(sender, amount);
            emit SellTaxApplied(sender, amount, sellTaxAmount);
            amount -= sellTaxAmount;
        }
        // Transfer tokens
        super._transfer(sender, recipient, amount);
    }

    /**
     * @dev Checks if sell tax should be applied for a transaction.
     * @param sender Address sending the tokens.
     * @param recipient Address receiving the tokens.
     * @return True if sell tax is applicable, false otherwise.
     */
    function _shouldApplySellTax(address sender, address recipient) private view returns (bool) {
        return sender != owner() && recipient != owner() && sender != MARKETING_WALLET && recipient != MARKETING_WALLET && sender != DEVELOPMENT_WALLET && recipient != DEVELOPMENT_WALLET && sender != address(this) && recipient != address(this) && isPairAddress[recipient];
    }

    /**
     * @dev Applies sell tax to a transaction.
     * @param sender Address sending the tokens.
     * @param amount Amount of tokens to transfer.
     * @return The total tax amount deducted.
     */
    function _applySellTax(address sender, uint256 amount) private returns (uint256) {
        // Calculate tax amount and transfer to contract
        uint256 totalTaxAmount = (amount * TAX_RATE) / 100;
        super._transfer(sender, address(this), totalTaxAmount);

        // Swap tokens for ETH and calculate tax amount in ETH
        uint256 contractBalanceBefore = address(this).balance;
        _swapTokensForETH(totalTaxAmount);
        uint256 contractBalanceAfter = address(this).balance;
        uint256 taxAmountEth = contractBalanceAfter - contractBalanceBefore;

        // Split ETH tax amount between Marketing and Development wallets
        uint256 halfTaxEth = taxAmountEth / 2;

        // Transfer ETH to Marketing wallet
        payable(MARKETING_WALLET).transfer(halfTaxEth);

        // Transfer remaining ETH to Development wallet
        payable(DEVELOPMENT_WALLET).transfer(taxAmountEth - halfTaxEth);

        return totalTaxAmount;
    }

    /**
     * @dev Swaps tokens for ETH via Uniswap V2 Router.
     * @param tokenAmount Amount of tokens to swap.
     */
    function _swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapRouter.WETH();

        _approve(address(this), UNISWAP_V2_ROUTER, tokenAmount); // Approve tokens for swap

        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    // Receive function to accept ETH from Uniswap swaps
    receive() external payable {}

    // Fallback function
    fallback() external payable {}
}