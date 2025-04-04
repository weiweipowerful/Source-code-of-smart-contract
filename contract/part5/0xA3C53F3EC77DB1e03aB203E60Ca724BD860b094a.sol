// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardPool} from "src/interfaces/IRewardPool.sol";
import {IConvexBooster} from "src/interfaces/IConvexBooster.sol";
import {IVirtualBalanceRewardPool} from "src/interfaces/IVirtualBalanceRewardPool.sol";

// StakingWrapper interface for pools with pid 151+
interface IStakingWrapper {
    function token() external returns (address);
}

contract ConvexEscrowV2 {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error OnlyMarket();
    error OnlyBeneficiary();
    error OnlyBeneficiaryOrAllowlist();

    uint256 public immutable pid;

    IRewardPool public immutable rewardPool;
    IConvexBooster public immutable booster;
    IERC20 public immutable cvx;
    IERC20 public immutable crv;

    address public market;
    IERC20 public token;
    address public beneficiary;

    mapping(address => bool) public allowlist;

    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary) revert OnlyBeneficiary();
        _;
    }

    modifier onlyBeneficiaryOrAllowlist() {
        if (msg.sender != beneficiary && !allowlist[msg.sender])
            revert OnlyBeneficiaryOrAllowlist();
        _;
    }

    event AllowClaim(address indexed allowedAddress, bool allowed);

    constructor(
        address _rewardPool,
        address _booster,
        address _cvx,
        address _crv,
        uint256 _pid
    ) {
        rewardPool = IRewardPool(_rewardPool);
        booster = IConvexBooster(_booster);
        cvx = IERC20(_cvx);
        crv = IERC20(_crv);
        pid = _pid;
    }

    /**
    @notice Initialize escrow with a token
    @dev Must be called right after proxy is created.
    @param _token The IERC20 token representing the governance token
    @param _beneficiary The beneficiary who the token is staked on behalf
    */
    function initialize(IERC20 _token, address _beneficiary) public {
        if (market != address(0)) revert AlreadyInitialized();
        market = msg.sender;
        token = _token;
        token.approve(address(booster), type(uint).max);
        beneficiary = _beneficiary;
    }

    /**
    @notice Withdraws the wrapped token from the reward pool and transfers the associated ERC20 token to a recipient.
    @dev Will first try to pay from the escrow balance, if not enough or any, will try to pay the missing amount withdrawing from Convex
    @param recipient The address to receive payment from the escrow
    @param amount The amount of ERC20 token to be transferred.
    */
    function pay(address recipient, uint amount) public {
        if (msg.sender != market) revert OnlyMarket();
        uint256 tokenBal = token.balanceOf(address(this));

        if (tokenBal >= amount) {
            token.safeTransfer(recipient, amount);
            return;
        }

        uint256 missingAmount = amount - tokenBal;
        uint256 convexBalance = rewardPool.balanceOf(address(this));
        if (convexBalance > 0) {
            uint256 withdrawAmount = convexBalance > missingAmount
                ? missingAmount
                : convexBalance;
            missingAmount -= withdrawAmount;
            rewardPool.withdrawAndUnwrap(withdrawAmount, false);
        }

        token.safeTransfer(recipient, amount);
    }

    /**
    @notice Get the token balance of the escrow
    @return Uint representing the token balance of the escrow
    */
    function balance() public view returns (uint) {
        return
            rewardPool.balanceOf(address(this)) +
            token.balanceOf(address(this));
    }

    /**
    @notice Function called by market on deposit. Stakes deposited collateral into Convex reward pool
    @dev This function should remain callable by anyone to handle direct inbound transfers.
    */
    function onDeposit() public {
        uint256 tokenBal = token.balanceOf(address(this));
        if (tokenBal == 0) return;
        booster.deposit(pid, tokenBal, true);
    }

    /**
    @notice Claims reward tokens to the specified address. Only callable by beneficiary and allowlisted addresses
    @param to Address to send claimed rewards to
    */
    function claimTo(address to) public onlyBeneficiaryOrAllowlist {
        //Claim rewards
        rewardPool.getReward(address(this), true);
        //Send crv balance
        uint256 crvBal = crv.balanceOf(address(this));
        if (crvBal != 0) crv.safeTransfer(to, crvBal);
        //Send cvx balance
        uint256 cvxBal = cvx.balanceOf(address(this));
        if (cvxBal != 0) cvx.safeTransfer(to, cvxBal);

        //Send contract balance of extra rewards
        uint256 rewardLength = rewardPool.extraRewardsLength();
        if (rewardLength == 0) return;
        for (uint rewardIndex; rewardIndex < rewardLength; ++rewardIndex) {
            IVirtualBalanceRewardPool virtualReward = IVirtualBalanceRewardPool(
                rewardPool.extraRewards(rewardIndex)
            );
            IERC20 rewardToken;
            if (pid >= 151) {
                rewardToken = IERC20(
                    IStakingWrapper(address(virtualReward.rewardToken()))
                        .token()
                );
            } else {
                rewardToken = virtualReward.rewardToken();
            }

            uint rewardBal = rewardToken.balanceOf(address(this));
            if (rewardBal > 0) {
                //Use safe transfer in case bad reward token is added
                rewardToken.safeTransfer(to, rewardBal);
            }
        }
    }

    /**
    @notice Claims reward tokens to the message sender. Only callable by beneficiary and allowlisted addresses
    */
    function claim() external onlyBeneficiary {
        claimTo(msg.sender);
    }

    /**
    @notice Allow address to claim on behalf of the beneficiary to any address
    @param allowee Address that are allowed to claim on behalf of the beneficiary
    @dev Can be used to build contracts for auto-compounding cvxCrv, auto-buying DBR or auto-repaying loans
    */
    function allowClaimOnBehalf(address allowee) external onlyBeneficiary {
        allowlist[allowee] = true;
        emit AllowClaim(allowee, true);
    }

    /**
    @notice Disallow address to claim on behalf of the beneficiary to any address
    @param allowee Address that are disallowed to claim on behalf of the beneficiary
    */
    function disallowClaimOnBehalf(address allowee) external onlyBeneficiary {
        allowlist[allowee] = false;
        emit AllowClaim(allowee, false);
    }
}