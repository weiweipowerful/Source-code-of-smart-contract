// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error UnsuccessfulFetchOfTokenBalance();

contract StakingRewards is Ownable {
	IERC20 public immutable stakingToken;
	IERC20 public immutable rewardsToken;

	// Duration of rewards to be paid out (in seconds)
	uint256 public duration;
	// Timestamp of when the rewards finish
	uint256 public finishAt;
	// Minimum of last updated time and reward finish time
	uint256 public updatedAt;
	// Reward to be paid out per second
	uint256 public rewardRate;
	// Sum of (reward rate * dt * 1e18 / total supply)
	uint256 public rewardPerTokenStored;
	// User address => rewardPerTokenStored
	mapping(address => uint256) public userRewardPerTokenPaid;
	// User address => rewards to be claimed
	mapping(address => uint256) public rewards;

	// Total staked
	uint256 public totalSupply;
	// User address => staked amount
	mapping(address => uint256) public balanceOf;

	event RewardAdded(uint256 reward);
	event Staked(address indexed user, uint256 amount);
	event Withdrawn(address indexed user, uint256 amount);
	event RewardPaid(address indexed user, uint256 reward);
	event RewardsDurationUpdated(uint256 newDuration);
	event Recovered(address token, uint256 amount);

	constructor(address _stakingToken, address _rewardToken, uint256 _duration) {
		stakingToken = IERC20(_stakingToken);
		rewardsToken = IERC20(_rewardToken);
		setRewardsDuration(_duration);
	}

	modifier updateReward(address _account) {
		rewardPerTokenStored = rewardPerToken();
		updatedAt = lastTimeRewardApplicable();

		if (_account != address(0)) {
			rewards[_account] = earned(_account);
			userRewardPerTokenPaid[_account] = rewardPerTokenStored;
		}

		_;
	}

	function lastTimeRewardApplicable() public view returns (uint256) {
		return _min(finishAt, block.timestamp);
	}

	function rewardPerToken() public view returns (uint256) {
		if (totalSupply == 0) {
			return rewardPerTokenStored;
		}

		return rewardPerTokenStored + (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) / totalSupply;
	}

	function stake(uint256 _amount) external updateReward(msg.sender) {
		require(_amount > 0, "Cannot stake 0");
		uint256 balance = getTokenBalance(address(stakingToken));
		stakingToken.transferFrom(msg.sender, address(this), _amount);
		uint256 transferredAmount = getTokenBalance(address(stakingToken)) - balance;
		balanceOf[msg.sender] += transferredAmount;
		totalSupply += transferredAmount;
		emit Staked(msg.sender, transferredAmount);
	}

	function withdraw(uint256 _amount) public updateReward(msg.sender) {
		require(_amount > 0, "Cannot withdraw 0");
		require(balanceOf[msg.sender] >= _amount, "Withdraw exceeds balance");
		balanceOf[msg.sender] -= _amount;
		totalSupply -= _amount;
		stakingToken.transfer(msg.sender, _amount);
		emit Withdrawn(msg.sender, _amount);
	}

	function getRewardForDuration() external view returns (uint256) {
		return rewardRate * duration;
	}

	function earned(address _account) public view returns (uint256) {
		return
			((balanceOf[_account] * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18) + rewards[_account];
	}

	function getReward() public updateReward(msg.sender) {
		uint256 reward = rewards[msg.sender];
		if (reward > 0) {
			rewards[msg.sender] = 0;
			rewardsToken.transfer(msg.sender, reward);
			emit RewardPaid(msg.sender, reward);
		}
	}

	function setRewardsDuration(uint256 _duration) public onlyOwner {
		require(
			block.timestamp > finishAt,
			"Previous rewards period must be complete before changing the duration for the new period"
		);
		duration = _duration;
		emit RewardsDurationUpdated(_duration);
	}

	function notifyRewardAmount(uint256 _amount) external onlyOwner updateReward(address(0)) {
		if (block.timestamp >= finishAt) {
			rewardRate = _amount / duration;
		} else {
			uint256 remainingRewards = (finishAt - block.timestamp) * rewardRate;
			rewardRate = (_amount + remainingRewards) / duration;
		}

		require(rewardRate > 0, "reward rate = 0");
		require(rewardRate * duration <= rewardsToken.balanceOf(address(this)), "Provided reward too high");

		finishAt = block.timestamp + duration;
		updatedAt = block.timestamp;
		emit RewardAdded(_amount);
	}

	function exit() external {
		withdraw(balanceOf[msg.sender]);
		getReward();
	}

	// Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
	function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
		require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");
		IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
		emit Recovered(tokenAddress, tokenAmount);
	}

	function getTokenBalance(address token) internal view returns (uint256) {
		(bool success, bytes memory encodedBalance) = token.staticcall(
			abi.encodeWithSelector(IERC20.balanceOf.selector, address(this))
		);

		if (success && encodedBalance.length >= 32) {
			return abi.decode(encodedBalance, (uint256));
		}
		revert UnsuccessfulFetchOfTokenBalance();
	}

	function _min(uint256 x, uint256 y) private pure returns (uint256) {
		return x <= y ? x : y;
	}
}