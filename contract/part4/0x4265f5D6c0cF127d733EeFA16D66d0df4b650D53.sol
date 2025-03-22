// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {ElixirDeUSDCommits} from "src/ElixirDeUSDCommits.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ElixirDeposit} from "src/ElixirDeposit.sol";

/// @title Elixir withdraw contract
/// @author The Elixir Team
/// @notice This contract is used to withdraw funds
contract ElixirCommitsAndWithdraw is Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the ElixirDeposit contract
    ElixirDeposit public elixirDepositContract;

    /// @notice The address of the DepositContract.
    ElixirDeUSDCommits public deusdCommitsContract;

    /// @notice The address of the stETH token
    IERC20 public token;

    /// @notice Mapping of address to committed ETH to deUSD
    mapping(address user => uint256 withdrawn) public committedEth;

    /// @notice Mapping of address to withdrawn ETH
    mapping(address user => uint256 withdrawn) public withdrawn;

    /// @notice The pause status of commit
    bool public commitsPaused;

    /// @notice The pause status of withdrawals. True if withdrawals are paused.
    bool public withdrawalsPaused;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when user commits an amount
    /// @param caller The caller of the commit function.
    /// @param amount The token amount committed and transferred.
    event Commit(address indexed caller, uint256 indexed amount);

    /// @notice Emitted when a user withdraws funds.
    /// @param withdrawer The withdrawer.
    /// @param amount The amount withdrawn.
    event Withdraw(address indexed withdrawer, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when withdraws are paused.
    error WithdrawsPaused();

    /// @notice Emitted when a withdraw fails.
    error WithdrawFailed();

    /// @notice Emitted when the user doesn't have enough funds to withdraw.
    error InsufficientFunds();

    /// @notice Emitted when commits are paused.
    error CommitsPaused();

    /// @notice Emitted when commit exceeds current deposit balance.
    error CommitExceedsBalance();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when commits are paused.
    modifier whenCommitNotPaused() {
        if (commitsPaused) revert CommitsPaused();
        _;
    }

    /// @notice Reverts when withdraws are paused.
    modifier whenWithdrawNotPaused() {
        if (withdrawalsPaused) revert WithdrawsPaused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the settings and parameters
    /// @param _commitsContract The address of the commits contract
    /// @param _owner The address of the owner of the contract
    constructor(address _owner, address _depositContract, address _commitsContract, address _token) Ownable(_owner) {
        elixirDepositContract = ElixirDeposit(_depositContract);
        deusdCommitsContract = ElixirDeUSDCommits(_commitsContract);
        token = IERC20(_token);
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get user's unused balance from DeusdCommitsContract contract
    /// @param user The address of user with unused balance
    function committed(address user) public view returns (uint256 amount) {
        return deusdCommitsContract.committed(user) + committedEth[user];
    }

    /// @notice Get user's unused balance from DeusdCommitsContract contract
    /// @param user The address of user with unused balance
    function unusedBalance(address user) public view returns (uint256 amount) {
        return elixirDepositContract.deposits(user) - committed(user) - withdrawn[user];
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Commit elxETH to deUSD
    /// @param commitAmount amount of elxETH to commit to deUSD (18 decimals)
    function commitDeUSD(uint256 commitAmount) external whenCommitNotPaused {
        if (commitAmount > unusedBalance(msg.sender)) revert CommitExceedsBalance();
        committedEth[msg.sender] += commitAmount;
        token.safeTransferFrom(
            elixirDepositContract.controller(), deusdCommitsContract.commitsController(), commitAmount
        );
        emit Commit(msg.sender, commitAmount);
    }

    /// @notice Withdraw ETH that was deposited in the ElixirDeposit contract
    /// @param amount The amount of ETH to withdraw
    function withdrawEth(uint256 amount) external whenWithdrawNotPaused {
        if (amount > unusedBalance(msg.sender)) revert InsufficientFunds();

        withdrawn[msg.sender] += amount;

        (bool sent,) = msg.sender.call{value: amount}("");
        if (!sent) revert WithdrawFailed();

        emit Withdraw(msg.sender, amount);
    }

    /// @notice Withdraw unclaimed ETH
    /// @param amount The amount of ETH to withdraw
    function withdrawOwnerEth(uint256 amount) external onlyOwner {
        (bool sent,) = msg.sender.call{value: amount}("");
        if (!sent) revert WithdrawFailed();
    }

    /// @notice Pause withdraws, callable by the owner
    /// @param pauseWithdraw True if withdraws are to be paused, false if they are to be unpaused
    function pauseWithdraws(bool pauseWithdraw) external onlyOwner {
        withdrawalsPaused = pauseWithdraw;
    }

    /// @notice Pause commit, callable by the owner
    /// @param pauseCommit True if mints are to be paused, false if they are to be unpaused
    function pauseCommits(bool pauseCommit) external onlyOwner {
        commitsPaused = pauseCommit;
    }

    /// @notice Receive ether.
    receive() external payable {}
}