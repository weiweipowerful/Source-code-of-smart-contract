// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IERC20Burnable.sol";
import "./interfaces/IWETH9.sol";
import "./lib/constants.sol";

/// @title Stax Buy & Burn Contract
contract StaxBuyBurn is Ownable2Step {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Burnable;

    // -------------------------- STATE VARIABLES -------------------------- //

    address immutable STAX;

    /// @notice Incentive fee amount, measured in basis points (100 bps = 1%).
    uint16 public incentiveFeeBps = 30;
    /// @notice The maximum amount of ELMNT that can be swapped per Buy & Burn.
    uint256 public capPerSwapE280;
    /// @notice The maximum amount of X28/E280 that can be swapped per Buy & Burn.
    uint256 public capPerSwapX28 = 3_000_000_000 ether;
    /// @notice The minimum amount of X28 tokens to trigger X28/ELMNT swap.
    uint256 public minSwapAmountX28 = 1_000_000_000 ether;
    /// @notice Cooldown for Buy & Burns in seconds.
    uint32 public buyBurnInterval = 1 hours;
    /// @notice Time of the last Buy & Burn in seconds.
    uint256 public lastBuyBurn;

    /// @notice Whitelisted addresses to run Buy & Burn.
    mapping(address account => bool) public whitelisted;

    // ------------------------------- EVENTS ------------------------------ //

    event BuyBurn();

    // ------------------------------- ERRORS ------------------------------ //

    error Prohibited();
    error Cooldown();
    error ZeroAddress();
    error NoAllocation();

    // ----------------------------- CONSTRUCTOR --------------------------- //

    constructor(address _owner, address _stax) Ownable(_owner) {
        if (_stax == address(0)) revert ZeroAddress();
        STAX = _stax;
    }

    // --------------------------- PUBLIC FUNCTIONS ------------------------ //

    /// @notice Buys and burns the Stax tokens using ELMNT and X28 balance.
    /// @param minStaxAmount The minimum amount out for ELMNT -> Stax swap.
    /// @param minE280Amount The minimum amount out for the X28 -> ELMNT swap (if applicalbe).
    /// @param deadline The deadline for the swaps.
    function buyAndBurn(uint256 minStaxAmount, uint256 minE280Amount, uint256 deadline) external {
        if (!whitelisted[msg.sender]) revert Prohibited();
        if (block.timestamp < lastBuyBurn + buyBurnInterval) revert Cooldown();

        lastBuyBurn = block.timestamp;
        uint256 e280Balance = IERC20(E280).balanceOf(address(this));
        bool additionalSwap;
        if (e280Balance < capPerSwapE280) {
            uint256 e280BalanceAfterSwap = _handleX28BalanceCheck(e280Balance, minE280Amount, deadline);
            additionalSwap = e280BalanceAfterSwap > e280Balance;
            e280Balance = e280BalanceAfterSwap;
        }
        if (e280Balance == 0) revert NoAllocation();
        uint256 amountToSwap = e280Balance > capPerSwapE280 ? capPerSwapE280 : e280Balance;
        amountToSwap = _processIncentiveFee(amountToSwap, additionalSwap);
        _swapE280toStax(amountToSwap, minStaxAmount, deadline);
        _handleStaxBurn();
        emit BuyBurn();
    }

    // ----------------------- ADMINISTRATIVE FUNCTIONS -------------------- //

    /// @notice Sets the incentive fee basis points (bps) for Buy & Burns.
    /// @param bps The incentive fee in basis points (0 - 1000), (100 bps = 1%).
    function setIncentiveFee(uint16 bps) external onlyOwner {
        if (bps > 1000) revert Prohibited();
        incentiveFeeBps = bps;
    }

    /// @notice Sets the Buy & Burn interval.
    /// @param limit The new interval in seconds.
    function setBuyBurnInterval(uint32 limit) external onlyOwner {
        if (limit == 0) revert Prohibited();
        buyBurnInterval = limit;
    }

    /// @notice Sets the cap per swap for ELMNT -> Stax swaps.
    /// @param limit The new cap limit in WEI applied to ELMNT balance.
    function setCapPerSwapE280(uint256 limit) external onlyOwner {
        capPerSwapE280 = limit;
    }

    /// @notice Sets the cap per swap for X28 -> ELMNT swaps.
    /// @param limit The new cap limit in WEI applied to X28 balance.
    function setCapPerSwapX28(uint256 limit) external onlyOwner {
        capPerSwapX28 = limit;
    }

    /// @notice Sets the new minimum threshold for triggering the X28/ELMNT swap.
    /// @param limit The new threshold in WEI applied to X28 balance.
    function setMinSwapAmountX28(uint256 limit) external onlyOwner {
        minSwapAmountX28 = limit;
    }

    /// @notice Sets the whitelist status for provided addresses for Buy & Burn.
    /// @param accounts List of wallets which status will be changed.
    /// @param isWhitelisted Status to be set.
    function setWhitelisted(address[] calldata accounts, bool isWhitelisted) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelisted[accounts[i]] = isWhitelisted;
        }
    }

    // ---------------------------- VIEW FUNCTIONS ------------------------- //

    /// @notice Get the Buy & Burn information for the next call.
    /// @return isX28SwapPossible Will the X28 swap be performed on the next call.
    /// @return nextE280Swap Amount of E280 used in the next call.
    /// @return nextX28Swap Amount of X28 used in the next call.
    /// @return nextBuyBurn Time when next Buy & Burn will be available (in seconds).
    function getBuyBurnParams()
        public
        view
        returns (bool isX28SwapPossible, uint256 nextE280Swap, uint256 nextX28Swap, uint256 nextBuyBurn)
    {
        uint256 e280Balance = IERC20(E280).balanceOf(address(this));
        uint256 x28Balance = IERC20(X28).balanceOf(address(this));
        isX28SwapPossible = e280Balance < capPerSwapE280 && x28Balance > minSwapAmountX28;
        nextE280Swap = e280Balance > capPerSwapE280 ? capPerSwapE280 : e280Balance;
        if (isX28SwapPossible) nextX28Swap = x28Balance > capPerSwapX28 ? capPerSwapX28 : x28Balance;
        nextBuyBurn = lastBuyBurn + buyBurnInterval;
    }

    // -------------------------- INTERNAL FUNCTIONS ----------------------- //

    function _handleX28BalanceCheck(uint256 currentE280Balance, uint256 minE280Amount, uint256 deadline)
        internal
        returns (uint256)
    {
        uint256 x28Balance = IERC20(X28).balanceOf(address(this));
        if (x28Balance < minSwapAmountX28) return currentE280Balance;
        uint256 amountToSwap = x28Balance > capPerSwapX28 ? capPerSwapX28 : x28Balance;
        uint256 swappedAmount = _swapX28toE280(amountToSwap, minE280Amount, deadline);
        return currentE280Balance + swappedAmount;
    }

    function _processIncentiveFee(uint256 e280Amount, bool additionalSwap) internal returns (uint256) {
        uint16 _incentiveFeeBps = additionalSwap ? (incentiveFeeBps * 150) / 100 : incentiveFeeBps;
        uint256 incentiveFee = e280Amount * _incentiveFeeBps / BPS_BASE;
        IERC20(E280).safeTransfer(msg.sender, incentiveFee);
        unchecked {
            return e280Amount - incentiveFee;
        }
    }

    function _handleStaxBurn() internal {
        IERC20Burnable stax = IERC20Burnable(STAX);
        uint256 amountToBurn = stax.balanceOf(address(this));
        stax.burn(amountToBurn);
    }

    function _swapE280toStax(uint256 amountIn, uint256 minAmountOut, uint256 deadline) internal {
        if (minAmountOut == 0) revert Prohibited();
        IERC20(E280).safeIncreaseAllowance(UNISWAP_V2_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = E280;
        path[1] = STAX;

        IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn, minAmountOut, path, address(this), deadline
        );
    }

    function _swapX28toE280(uint256 amountIn, uint256 minAmountOut, uint256 deadline) private returns (uint256) {
        if (minAmountOut == 0) revert Prohibited();
        IERC20(X28).safeIncreaseAllowance(UNISWAP_V2_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = X28;
        path[1] = E280;

        uint256[] memory amounts = IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn, minAmountOut, path, address(this), deadline
        );

        return amounts[1];
    }
}