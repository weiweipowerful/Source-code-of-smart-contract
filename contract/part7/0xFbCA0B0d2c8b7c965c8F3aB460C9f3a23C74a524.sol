// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface PortalStakingEvents {
    /// @notice Emitted when a user stakes tokens
    event Stake(address indexed user, uint256 amount, uint256 totalStaked);
    /// @notice Emitted when a user unstakes tokens
    event Unstake(address indexed user, uint256 amount, uint256 totalRemainingStaked);
}

/**
 * @title PortalStaking
 * @dev A staking contract that allows users to stake tokens and earn rewards.
 *  • Staking Smart Contract on Ethereum
 *  • Standard of token: ERC-20
 *  • 7 day cool-down period after each stake (no withdrawal during this time).
 *  • Pull Based.
 *  • Ability to withdraw non-project tokens from the staking contract
 *  • Staking Contract can be used by other Contracts and UI
 */
contract PortalStaking is Ownable2Step, PortalStakingEvents {
    using SafeERC20 for IERC20;

    /**
     * @dev Staker is a struct that represents a staker in the contract. It contains the following fields:
     * • amount: the number of tokens staked by the user
     * • lastDeposit: the timestamp of the last deposit made by the user
     */
    struct Staker {
        uint96 amount; // totalSupply = 1e9 ether = 90 bits
        uint64 lastDepositTime;
    }

    /**
     * @dev token is an instance of IERC20 token that users will be staking.
     */
    IERC20 public immutable token;

    /**
     * @dev Required totalSupply of token, confirmed in constructor().
     */
    uint256 private constant TOTAL_SUPPLY = 1e9 ether;

    /**
     * @dev Minimum duration between a call to withdraw() and the last call to
     * deposit().
     */
    uint256 private constant MIN_STAKING_PERIOD = 7 days;

    /**
     * @notice Total staked via `deposit()`, which may differ from `balanceOf(this)`.
     * @dev See `accountForExcessBalance()`.
     */
    uint256 public totalStaked;

    /**
     * @dev `stakers` is a mapping from an address (Ethereum account) to a `Staker` struct.
     * This mapping is public, so its getter function - `stakers(address) -> (uint, uint)`
     * can get staker details for any address.
     * It represents the set of all addresses that currently have an active stake.
     */
    mapping(address => Staker) public stakers;

    // Errors
    error TokensLockedUntil(address user, uint256 unlockTime);
    error InvalidAmount(uint256);
    error DepositNotSufficient(address user, uint256 staked, uint256 amount);
    error InsufficientExcessBalance(uint256 excess, uint256 amount);
    error InvalidAddressPassed();

    /**
     * @dev The constructor sets the `token` state variable to the provided `_token` parameter as well as the owner.
     * @param _token is the address of the already deployed token contract (of IERC20 interface)
     * @param owner is the address of the owner of the staking contract
     */
    constructor(IERC20 _token, address owner) {
        token = _token;

        assert(_token.totalSupply() == TOTAL_SUPPLY);
        assert(TOTAL_SUPPLY < type(uint96).max); // avoids the need for SafeCast when packing

        _transferOwnership(owner);
    }

    /**
     * @dev Reverts on 0 or greater than total supply (1e9 ether). Any amount
     * that passes this test can fit in a uint96.
     */
    modifier requireValidAmount(uint256 amount) {
        if (amount == 0 || amount > TOTAL_SUPPLY) {
            revert InvalidAmount(amount);
        }
        _;
    }

    /**
     * @notice Deposit (stake) tokens.
     *
     * @param amount Number of tokens to stake.
     */
    function deposit(uint256 amount) external requireValidAmount(amount) {
        address account = msg.sender;
        Staker storage $ = stakers[account];

        // NO CHECKS

        // EFFECTS

        // If total were to overflow 96 bits then the transfer would also have failed.
        // Use a stack variable to avoid another SLOAD when emitting the event.
        uint96 total = $.amount + uint96(amount); // guaranteed by requireValidAmount()
        $.amount = total;
        $.lastDepositTime = uint64(block.timestamp);
        totalStaked += amount;

        // INTERACTIONS
        token.safeTransferFrom(account, address(this), amount);

        emit Stake(account, amount, total);
    }

    /**
     * @notice Withdraw (unstake) tokens.
     * @param amount Number of tokens to unstake.
     */
    function withdraw(uint256 amount) external requireValidAmount(amount) {
        address account = msg.sender;
        Staker storage $ = stakers[account];

        // CHECKS
        if (block.timestamp - $.lastDepositTime < MIN_STAKING_PERIOD) {
            revert TokensLockedUntil(account, $.lastDepositTime + MIN_STAKING_PERIOD);
        }
        uint96 staked = $.amount;
        if (staked < amount) {
            revert DepositNotSufficient(account, staked, amount);
        }

        // EFFECTS
        staked -= uint96(amount);
        $.amount = staked;
        totalStaked -= amount;

        // INTERACTIONS
        token.safeTransfer(account, amount);

        emit Unstake(account, amount, staked);
    }

    /**
     * @notice If someone sends tokens to this contract (instead of calling `deposit()`) they won't be accounted for.
     * This function allows the owner to assign said tokens based on an inspection of transaction history. While
     * introducing a level of trust, it's better than having the tokens permanently locked, and proving a log history
     * would be over-engineering.
     * @param assignTo The address that will have its balance increase.
     * @param amount The amount by which to increase the balance. Reverts if this is greater than the difference betwen
     * this contract's balance and `totalStaked`.
     */
    function accountForExcessBalance(address assignTo, uint256 amount) external onlyOwner requireValidAmount(amount) {
        if (assignTo == address(0)) {
            revert InvalidAddressPassed();
        }
        
        uint256 excess = token.balanceOf(address(this)) - totalStaked;
        if (excess < amount) {
            revert InsufficientExcessBalance(excess, amount);
        }

        Staker storage $ = stakers[assignTo];
        uint96 total = $.amount + uint96(amount);
        $.amount = total;

        totalStaked += amount;

        emit Stake(assignTo, amount, total);
    }
}