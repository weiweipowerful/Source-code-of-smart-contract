// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract NeuralStaking is Ownable2Step {
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of reward tokens
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * accRewardPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws tokens. Here's what happens:
        //   1. The `accRewardPerShare` gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    IERC20 token; // Address of token contract.
    IERC20 rewardToken; // Address of reward token contract.
    uint256 lastRewardTimestamp; // Last block timestamp that reward tokens distribution occurs.
    uint256 accRewardPerShare; // Accumulated reward per share, times 1e18. See below.
    uint256 lastTotalRewardTokenAmount;
    uint256 lastDistributionRoundEndTime;

    // reward tokens created per second.
    uint256 public rewardPerSec;

    // Info of each user that stakes tokens.
    mapping(address => UserInfo) public userInfo;

    event Deposit(
        address indexed user,
        uint256 token_amount,
        uint256 reward_amount
    );
    event Withdraw(
        address indexed user,
        uint256 token_amount,
        uint256 reward_amount
    );
    event EmergencyWithdraw(address indexed user, uint256 token_amount);
    event DepositReward(uint256 period, uint256 reward_amount);
    event EmergencyWithdrawRewards(address indexed user, uint256 token_amount);

    constructor(
        IERC20 _token,
        IERC20 _rewardToken,
        address initialOwner
    ) Ownable(initialOwner) {
        token = _token;
        rewardToken = _rewardToken;
    }

    // View function to see pending rewards on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 supply = token.balanceOf(address(this));
        uint256 accPerShare = accRewardPerShare;
        if (block.timestamp > lastRewardTimestamp && supply != 0) {
            uint256 currentTimestamp = block.timestamp >
                lastDistributionRoundEndTime
                ? lastDistributionRoundEndTime
                : block.timestamp;
            uint256 reward = (currentTimestamp - lastRewardTimestamp) *
                rewardPerSec;
            accPerShare = accPerShare + (reward / supply);
        }
        return (user.amount * accPerShare) / 1e18 - user.rewardDebt;
    }

    // Update reward variables to be up-to-date.
    function updatePool() public {
        uint256 supply = token.balanceOf(address(this));
        if (supply == 0) {
            return;
        }
        uint256 currentTimestamp = block.timestamp >
            lastDistributionRoundEndTime
            ? lastDistributionRoundEndTime
            : block.timestamp;
        if (currentTimestamp < lastRewardTimestamp) {
            return;
        }
        uint256 reward = (currentTimestamp - lastRewardTimestamp) *
            rewardPerSec;
        accRewardPerShare = accRewardPerShare + (reward / supply);
        lastRewardTimestamp = currentTimestamp;
    }

    // Deposit tokens to MasterChef for reward token allocation.
    function deposit(uint256 _amount) external {
        uint256 supply = token.balanceOf(address(this));
        if (supply == 0) {
            lastRewardTimestamp = block.timestamp;
        }

        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        uint256 pending = (user.amount * accRewardPerShare) /
            1e18 -
            user.rewardDebt;
        user.amount = user.amount + _amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
        if (pending > 0) {
            lastTotalRewardTokenAmount -= pending;
            rewardToken.safeTransfer(msg.sender, pending);
        }
        token.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(msg.sender, _amount, pending);
    }

    // Withdraw tokens from MasterChef.
    function withdraw(uint256 _amount) external {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 pending = (user.amount * accRewardPerShare) /
            1e18 -
            user.rewardDebt;
        lastTotalRewardTokenAmount -= pending;
        user.amount = user.amount - _amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
        rewardToken.safeTransfer(msg.sender, pending);
        if (_amount > 0) {
            token.safeTransfer(msg.sender, _amount);
        }
        emit Withdraw(msg.sender, _amount, pending);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() external {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        token.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    // Call this function after reward token deposit
    // period unit is second, now it is normally 14~15 days
    function depositReward(uint256 period) external onlyOwner {
        updatePool();
        uint256 newRewardTokenAmount = rewardToken.balanceOf(address(this)) -
            lastTotalRewardTokenAmount;
        if (lastDistributionRoundEndTime > block.timestamp) {
            newRewardTokenAmount =
                newRewardTokenAmount +
                ((lastDistributionRoundEndTime - block.timestamp) *
                    rewardPerSec) /
                1e18;
        }
        rewardPerSec = (newRewardTokenAmount * 1e18) / period;
        lastTotalRewardTokenAmount = rewardToken.balanceOf(address(this));
        lastDistributionRoundEndTime = block.timestamp + period;
        lastRewardTimestamp = block.timestamp;
        emit DepositReward(period, newRewardTokenAmount);
    }

    // Withdraw reward tokens.
    function emergencyWithdrawRewards() external onlyOwner {
        rewardPerSec = 0;
        lastTotalRewardTokenAmount = 0;
        lastDistributionRoundEndTime = 0;
        lastRewardTimestamp = 0;
        uint256 amount = rewardToken.balanceOf(address(this));
        rewardToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdrawRewards(msg.sender, amount);
    }
}