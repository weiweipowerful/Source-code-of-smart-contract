// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IAutopool } from "src/interfaces/vault/IAutopilotRouter.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IAsyncSwapper, SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { Address } from "openzeppelin-contracts/utils/Address.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

// slither-disable-start cyclomatic-complexity

/// @notice Allows an off-chain process to regularly redeem fees/tokens held by other wallets
/// @dev Only supports rebasing tokens as a token to liquidate through liquidate() fn
contract FeeRedeemer is SystemComponent, SecurityBase {
    using Address for address;
    using SafeERC20 for IERC20;

    /// =====================================================
    /// Constant Vars
    /// =====================================================

    uint256 private constant MAX_WEIGHT = 10_000;

    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Receiver of assets from redeeming shares
    address public immutable rewardContract;

    /// @notice Token that will swapped to and sent to the rewarder
    address public immutable rewardToken;

    /// =====================================================
    /// Events
    /// =====================================================

    event AccRewardRedemption(
        address indexed attributedTo, address liquidatedToken, uint256 liquidatedAmount, uint256 rewardTokenAmount
    );
    event Recovered(address[] tokens, uint256[] amounts, address[] destinations);
    event TokenConfigured(
        address tokenToLiquidate,
        string tokenType,
        address fromWallet,
        uint256 pctToLiquidate,
        uint256 currentTokenBalance
    );

    /// =====================================================
    /// Errors
    /// =====================================================

    error MinAmountNotReceived(
        address autopool, address from, uint256 shareAmount, uint256 minAmount, uint256 assetsReceived
    );
    error ArrayLengthMismatch();
    error SwapperRequired();
    error RecoverFailed();

    /// =====================================================
    /// Structs
    /// =====================================================

    /// @param autopool Autopool share to liquidate
    /// @param from Current holder of the token.
    /// @param tokenAmount Amount of token to liquidate
    /// @param minAmount Minimum expected amount of assets to receive
    /// @param distributeAutopools Autopool(s) to distribute reward amount to
    /// @param distributeWeights Weights to used to distribute reward
    struct Redemptions {
        address autopool;
        address from;
        uint256 tokenAmount;
        uint256 minAmount;
        address[] distributeAutopools;
        uint256[] distributeWeights;
    }

    /// @param token The token to liquidate
    /// @param from The wallet to pull the token from
    /// @param amount The amount of token to liquidate
    /// @param minAmountReward The minimum amount of reward token to accept from the swap
    /// @param distributeAutopools Autopool(s) to distribute reward amount to
    /// @param distributeWeights Weights to used to distribute reward
    /// @param swapper The swapper contract to use for the swap
    /// @param swapParams The parameters to use for the swap
    struct Liquidation {
        address token;
        address from;
        uint256 amount;
        uint256 minAmountReward;
        address[] distributeAutopools;
        uint256[] distributeWeights;
        address swapper;
        SwapParams swapParams;
    }

    /// @notice Used for managing state in the redeem() fn
    struct RedeemState {
        uint256 redemptionLength;
        uint256[] redemptionAmounts;
        uint256[][] redemptionsBreakup;
        uint256 totalAssetsRedeemed;
        address baseAsset;
        uint256 initialRewardBalance;
    }

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry,
        address _rewardContract,
        address _rewardToken
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        Errors.verifyNotZero(_rewardContract, "_rewardContract");
        Errors.verifyNotZero(_rewardToken, "_rewardToken");

        // slither-disable-next-line missing-zero-check
        rewardContract = _rewardContract;

        // slither-disable-next-line missing-zero-check
        rewardToken = _rewardToken;
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Distribute the balance of rewardToken according to the specified weights
    /// @dev Tracking of breakup is via events only for the subgraph
    /// @param amount The amount of reward token being distributed
    /// @param autopools Autopools to distribute the rewardToken to
    /// @param weights Weights to distribute by
    function distribute(
        uint256 amount,
        address[] memory autopools,
        uint256[] memory weights
    ) external hasRole(Roles.FEE_REDEMPTION_EXECUTOR) {
        _distribute(rewardToken, amount, amount, autopools, weights);
    }

    /// @notice Swaps token to reward token and distributes based on provided weights
    /// @dev Tracking of breakup is via events only for the subgraph
    /// @dev Tokens are NOT checked against config. This is up to backend
    /// @param params Details of the liquidation
    function liquidate(
        Liquidation memory params
    ) external hasRole(Roles.FEE_REDEMPTION_EXECUTOR) {
        Errors.verifyNotZero(params.token, "token");
        Errors.verifyNotZero(params.amount, "amount");
        Errors.verifyNotZero(params.minAmountReward, "minAmountReward");
        Errors.verifyNotZero(params.swapper, "swapper");
        systemRegistry.asyncSwapperRegistry().verifyIsRegistered(params.swapper);

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(params.token).safeTransferFrom(params.from, address(this), params.amount);

        uint256 balanceBefore = IERC20(rewardToken).balanceOf(address(this));

        params.swapParams.buyTokenAddress = rewardToken;
        // slither-disable-next-line unused-return
        address(params.swapper).functionDelegateCall(
            abi.encodeCall(IAsyncSwapper.swap, params.swapParams), "SwapFailed"
        );

        uint256 rewardTokenAmount = IERC20(rewardToken).balanceOf(address(this)) - balanceBefore;

        _distribute(
            params.token, params.amount, rewardTokenAmount, params.distributeAutopools, params.distributeWeights
        );
    }

    /// @notice Cashes in Autopool shares, swaps to reward token, and distributes based on provided weights
    /// @dev Tracking of breakup is via events only for the subgraph
    /// @param redemptions Details of the Autopools to redeem for
    function redeem(
        Redemptions[] memory redemptions,
        address swapper,
        SwapParams memory swapParams
    ) external hasRole(Roles.FEE_REDEMPTION_EXECUTOR) {
        // slither-disable-next-line uninitialized-local
        RedeemState memory state;
        state.redemptionLength = redemptions.length;

        IERC20 reward = IERC20(rewardToken);
        state.initialRewardBalance = reward.balanceOf(address(this));

        Errors.verifyNotZero(state.redemptionLength, "redemptionLen");
        Errors.verifyNotZero(swapper, "swapper");
        systemRegistry.asyncSwapperRegistry().verifyIsRegistered(swapper);

        state.redemptionAmounts = new uint256[](state.redemptionLength);
        state.redemptionsBreakup = new uint256[][](state.redemptionLength);
        state.baseAsset = IAutopool(redemptions[0].autopool).asset();

        for (uint256 x = 0; x < state.redemptionLength;) {
            // We do want to make sure we have matching base assets though or
            // our totals will be off
            if (x > 0 && state.baseAsset != IAutopool(redemptions[x].autopool).asset()) {
                revert Errors.InvalidParam("baseAsset");
            }

            Errors.verifyNotZero(redemptions[x].tokenAmount, "tokenAmount");

            uint256 assetsRedeemed = _redeem(redemptions[x]);
            state.redemptionAmounts[x] = assetsRedeemed;
            state.totalAssetsRedeemed += assetsRedeemed;

            uint256 breakupLen = redemptions[x].distributeAutopools.length;
            Errors.verifyNotZero(breakupLen, "breakupLen");
            Errors.verifyArrayLengths(breakupLen, redemptions[x].distributeWeights.length, "breakupLen");

            state.redemptionsBreakup[x] = new uint256[](breakupLen);

            if (assetsRedeemed > 0) {
                // Break up the amount of assets redeemed amongst the provided autopools
                uint256 remaining = assetsRedeemed;
                uint256 utilizedWeights = 0;
                for (uint256 i = 0; i < breakupLen;) {
                    uint256 amt = remaining;
                    if (i < breakupLen - 1) {
                        // Unless its the item, breakup by the weight
                        // Last one gets the remainder
                        amt = assetsRedeemed * redemptions[x].distributeWeights[i] / MAX_WEIGHT;
                        remaining -= amt;
                    }

                    state.redemptionsBreakup[x][i] = amt;
                    utilizedWeights += redemptions[x].distributeWeights[i];

                    unchecked {
                        ++i;
                    }
                }

                if (utilizedWeights != MAX_WEIGHT) {
                    revert Errors.InvalidParam("utilizedWeight");
                }
            }

            unchecked {
                ++x;
            }
        }

        swapParams.sellAmount = state.totalAssetsRedeemed;
        swapParams.sellTokenAddress = state.baseAsset;
        swapParams.buyTokenAddress = rewardToken;
        // slither-disable-next-line unused-return
        address(swapper).functionDelegateCall(abi.encodeCall(IAsyncSwapper.swap, swapParams), "SwapFailed");

        uint256 amountDistributed = reward.balanceOf(address(this)) - state.initialRewardBalance;
        reward.safeTransfer(rewardContract, amountDistributed);

        uint256 totalRewardTokenRemaining = amountDistributed;
        for (uint256 x = 0; x < state.redemptionLength;) {
            uint256 breakupLen = redemptions[x].distributeAutopools.length;

            uint256 redemptionRewardAmount = totalRewardTokenRemaining;
            if (x < state.redemptionLength - 1) {
                redemptionRewardAmount = amountDistributed * state.redemptionAmounts[x] / state.totalAssetsRedeemed;
                totalRewardTokenRemaining -= redemptionRewardAmount;
            }

            uint256 redemptionRewardAmountRemaining = redemptionRewardAmount;
            for (uint256 i = 0; i < breakupLen;) {
                uint256 rewardAmt = redemptionRewardAmountRemaining;
                if (i < breakupLen - 1) {
                    rewardAmt = redemptionRewardAmount * redemptions[x].distributeWeights[i] / MAX_WEIGHT;
                    redemptionRewardAmountRemaining -= rewardAmt;
                }

                Errors.verifyNotZero(redemptions[x].distributeAutopools[i], "autopools");
                // slither-disable-next-line reentrancy-events
                emit AccRewardRedemption(
                    redemptions[x].distributeAutopools[i],
                    redemptions[x].autopool,
                    state.redemptionsBreakup[x][i],
                    rewardAmt
                );

                unchecked {
                    ++i;
                }
            }

            unchecked {
                ++x;
            }
        }
    }

    function configToken(
        address tokenToLiquidate,
        string memory tokenType,
        address fromWallet,
        uint256 pctToLiquidate
    ) external hasRole(Roles.FEE_REDEMPTION_MANAGER) {
        // Intentionally only emits an event and has no validation
        // Tracked by the subgraph for processing rewards
        emit TokenConfigured(
            tokenToLiquidate, tokenType, fromWallet, pctToLiquidate, IERC20(tokenToLiquidate).balanceOf(fromWallet)
        );
    }

    /// @notice Transfer out ETH or tokens
    function recover(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address[] calldata destinations
    ) external hasRole(Roles.TOKEN_RECOVERY_MANAGER) {
        uint256 length = tokens.length;
        Errors.verifyNotZero(length, "len");
        Errors.verifyArrayLengths(length, amounts.length, "amounts");
        Errors.verifyArrayLengths(length, destinations.length, "destinations");

        emit Recovered(tokens, amounts, destinations);

        for (uint256 i = 0; i < tokens.length; ++i) {
            // slither-disable-next-line missing-zero-check
            (address tokenAddress, uint256 amount, address destination) = (tokens[i], amounts[i], destinations[i]);

            Errors.verifyNotZero(tokenAddress, "tokenAddress");
            Errors.verifyNotZero(amount, "amount");
            Errors.verifyNotZero(destination, "destination");

            if (tokenAddress != 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
                IERC20(tokenAddress).safeTransfer(destination, amount);
            } else {
                // solhint-disable-next-line avoid-low-level-calls
                // slither-disable-next-line arbitrary-send-eth,low-level-calls
                (bool success,) = payable(destination).call{ value: amount }("");
                if (!success) {
                    revert RecoverFailed();
                }
            }
        }
    }

    /// =====================================================
    /// Functions - Private
    /// =====================================================

    /// @notice Distribute the amount of rewardToken according to the specified weights
    /// @dev Tracking of breakup is via events only for the subgraph
    /// @param fromToken The token that was swapped from to initiate the distribution
    /// @param fromTokenAmount The token amount that was swapped from to initiate the distribution
    /// @param rewardTokenAmount The amount of reward token being distributed
    /// @param autopools Autopools to distribute the rewardToken to
    /// @param weights Weights to distribute by
    function _distribute(
        address fromToken,
        uint256 fromTokenAmount,
        uint256 rewardTokenAmount,
        address[] memory autopools,
        uint256[] memory weights
    ) private {
        uint256 len = autopools.length;

        Errors.verifyNotZero(len, "autopoolLen");
        Errors.verifyArrayLengths(len, weights.length, "arrayLengths");
        Errors.verifyNotZero(rewardTokenAmount, "amount");

        IERC20 reward = IERC20(rewardToken);
        uint256 balance = reward.balanceOf(address(this));

        if (balance < rewardTokenAmount) {
            revert Errors.InvalidParam("rewardTokenBalance");
        }

        // Transfer reward token to the reward contract
        reward.safeTransfer(rewardContract, rewardTokenAmount);

        // Breakup the balance of the reward token across the provided Autopools
        uint256 fromTokenRemaining = fromTokenAmount;
        uint256 rewardTokenRemaining = rewardTokenAmount;
        uint256 utilizedWeights = 0;
        for (uint256 x = 0; x < len;) {
            uint256 rewardAmt = rewardTokenRemaining;
            uint256 fromAmt = fromTokenRemaining;
            if (x < len - 1) {
                // Unless its the item, breakup by the weight
                // Last one gets the remainder
                rewardAmt = rewardTokenAmount * weights[x] / MAX_WEIGHT;
                rewardTokenRemaining -= rewardAmt;

                fromAmt = fromTokenAmount * weights[x] / MAX_WEIGHT;
                fromTokenRemaining -= fromAmt;
            }
            utilizedWeights += weights[x];

            Errors.verifyNotZero(autopools[x], "autopools");

            // slither-disable-next-line reentrancy-events
            emit AccRewardRedemption(autopools[x], fromToken, fromAmt, rewardAmt);

            unchecked {
                ++x;
            }
        }

        if (utilizedWeights != MAX_WEIGHT) {
            revert Errors.InvalidParam("weights");
        }
    }

    /// @notice Perform individual redemption and return asset amount
    function _redeem(
        Redemptions memory redemption
    ) private returns (uint256) {
        Errors.verifyNotZero(redemption.minAmount, "redeemMinAmount");

        // From is expected to have already given adequate allowance
        uint256 assetsReceived =
            IAutopool(redemption.autopool).redeem(redemption.tokenAmount, address(this), redemption.from);

        // We're not going through the Router where this would normally occur so we have to do it manually
        if (assetsReceived < redemption.minAmount) {
            revert MinAmountNotReceived(
                redemption.autopool, redemption.from, redemption.tokenAmount, redemption.minAmount, assetsReceived
            );
        }

        return assetsReceived;
    }
}

// slither-disable-end cyclomatic-complexity