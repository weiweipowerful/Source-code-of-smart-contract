// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
       _status = _NOT_ENTERED;
    }
	
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        _status = _ENTERED;

        _;
		
        _status = _NOT_ENTERED;
    }
}

contract BubsyStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
	
    address public BUBSY;
	uint256 public precisionFactor;
	uint256 public undistributedReward;
	
	bool public contractStatus;
	bool public rewardStatus;
	
	uint256[3] public poolDuration;
	uint256[3] public poolMultiplier;
	uint256[3] public BUBSYStaked;
	uint256[3] public minStaking;
	uint256[3] public rewardPerShare;
	uint256[3] public rewardDistributedPerPool;
	
	struct StakingInfo {
	  uint256 stakedBUBSY; 
	  uint256 startTime;
	  uint256 endTime;
	  bool unstaked;
	  uint256 pool;
	  uint256 rewardClaimed;
	  uint256 claimedETH;
	  uint256 rewardUnclaimed;
    }
	
	mapping(address => mapping(uint256 => StakingInfo)) public mapStakingInfo;
	mapping(address => uint256) public stakingCount;
	mapping(address => bool) public isWhitelistForSendFund;
	
	event Staked(address staker, uint256 amount);
	event Unstaked(address staker, uint256 amount, uint256 reward);
	event PoolUpdated(uint256 amount);
	event RewardClaimed(address staker, uint256 amount);
	event ContractStatusUpdated(bool status);
	event RewardStatusUpdated(bool status);
	event PoolDurationUpdated(uint256 pool1, uint256 pool2, uint256 pool3);
	event PoolMultiplierUpdated(uint256 pool1Multiplier, uint256 pool2Multiplier, uint256 pool3Multiplier);
	event WhitelistStatusUpdated(address wallet, bool status);
	event ETHRescueFromContract(address receiver, uint256 amount);
	
    constructor(address _owner) {
	   require(_owner != address(0), "Owner:: zero address");
	   
	   minStaking = [1 * 10**18, 1 * 10**18, 1 * 10**18];
	   poolDuration = [15 days, 90 days, 365 days];
	   poolMultiplier = [100, 125, 200];
	   
	   BUBSY = address(0xD699B83e43415B774B6ed4ce9999680F049aF2ab);
       precisionFactor = 1 * 10**18;
	   _transferOwnership(address(_owner));
    }
	
	receive() external payable {}
	
	function updateContractStatus(bool status) external onlyOwner {
	    require(contractStatus != status, "Same status already active");
		
		contractStatus = status;
		emit ContractStatusUpdated(status);
  	}
	
	function updateRewardStatus(bool status) external onlyOwner {
	    require(rewardStatus != status, "Same status already active");
		
		rewardStatus = status;
		if(rewardStatus && undistributedReward > 0)
		{
		   _distributeReward(undistributedReward);
		   undistributedReward = 0;
		}
		emit RewardStatusUpdated(status);
  	}
	
	function updatePoolDuration(uint256[3] calldata newPoolDuration) external onlyOwner {
	    require(newPoolDuration[0] > 0 && newPoolDuration[1] > 0 && newPoolDuration[2] > 0, "Staking duration is not correct");
		
		poolDuration[0] = newPoolDuration[0];
		poolDuration[1] = newPoolDuration[1];
		poolDuration[2] = newPoolDuration[2];
        emit PoolDurationUpdated(newPoolDuration[0], newPoolDuration[1], newPoolDuration[2]);
    }
	
	function updatePoolMultiplier(uint256[3] calldata newMultiplier) external onlyOwner {
	    require(newMultiplier[0] > 0 && newMultiplier[1] > 0 && newMultiplier[2] > 0, "Pool multiplier amount is not correct");
		
		poolMultiplier[0] = newMultiplier[0];
		poolMultiplier[1] = newMultiplier[1];
		poolMultiplier[2] = newMultiplier[2];
        emit PoolMultiplierUpdated(newMultiplier[0], newMultiplier[1], newMultiplier[2]);
    }
	
	function whitelistFundWallet(address wallet, bool status) external onlyOwner {
	   require(address(wallet) != address(0), "Zero address");
	   require(isWhitelistForSendFund[address(wallet)] != status, "Wallet is already the value of 'status'");
	   
	   isWhitelistForSendFund[address(wallet)] = status;
	   emit WhitelistStatusUpdated(address(wallet), status);
    }
	
	function rescueETH(address receiver, uint256 amount) external onlyOwner {
	   require(address(receiver) != address(0), "Zero address");
	   require(address(this).balance >= amount, "Insufficient ETH balance in contract");
	   
	   payable(address(receiver)).transfer(amount);
	   emit ETHRescueFromContract(address(receiver), amount);
    }
	
	function stake(uint256 amount, uint256 pool) external {
	    require(contractStatus, "Contract is not enabled");
		require(IERC20(BUBSY).balanceOf(address(msg.sender)) >= amount, "Balance not available for staking");
		require(poolDuration.length > pool, "Staking pool is not correct");
		require(amount >= minStaking[pool], "Stake amount is less than required amount");
		
		uint256 count = stakingCount[address(msg.sender)];
		
		IERC20(BUBSY).safeTransferFrom(address(msg.sender), address(this), amount);
		BUBSYStaked[pool] += amount;
		stakingCount[address(msg.sender)] += 1;
		
		mapStakingInfo[address(msg.sender)][count].stakedBUBSY = amount;
		mapStakingInfo[address(msg.sender)][count].startTime = block.timestamp;
		mapStakingInfo[address(msg.sender)][count].endTime = block.timestamp + poolDuration[pool];
		mapStakingInfo[address(msg.sender)][count].pool = pool;
		mapStakingInfo[address(msg.sender)][count].rewardClaimed = (amount * rewardPerShare[pool]) / precisionFactor;
        emit Staked(address(msg.sender), amount);
    }
	
	function unstake(address staker, uint256 count) external onlyOwner nonReentrant {
		require(mapStakingInfo[address(staker)][count].unstaked == false, "Staking already unstaked");
		require(stakingCount[address(staker)] > count, "Staking not found");
		
        uint256 pending = pendingReward(address(msg.sender), count);
		uint256 amount = mapStakingInfo[address(msg.sender)][count].stakedBUBSY;
		uint256 pool = mapStakingInfo[address(msg.sender)][count].pool;
		
		BUBSYStaked[pool] -= amount; 
		mapStakingInfo[address(msg.sender)][count].unstaked = true;
		mapStakingInfo[address(msg.sender)][count].rewardUnclaimed = pending;
		
		IERC20(BUBSY).safeTransfer(address(msg.sender), amount);
		emit Unstaked(address(msg.sender), amount, pending);
    }
	
	function unstake(uint256 count) external nonReentrant {
	    require(contractStatus, "Contract is not enabled");
		require(mapStakingInfo[address(msg.sender)][count].unstaked == false, "Staking already unstaked");
		require(mapStakingInfo[address(msg.sender)][count].endTime <= block.timestamp, "Staking time is not over");
		require(stakingCount[address(msg.sender)] > count, "Staking not found");
		
        uint256 pending = pendingReward(address(msg.sender), count);
		uint256 amount = mapStakingInfo[address(msg.sender)][count].stakedBUBSY;
		uint256 pool = mapStakingInfo[address(msg.sender)][count].pool;
		
		BUBSYStaked[pool] -= amount; 
		mapStakingInfo[address(msg.sender)][count].unstaked = true;
		
		if(pending > 0 && address(this).balance >= pending)
		{
		   payable(address(msg.sender)).transfer(pending);
		   mapStakingInfo[address(msg.sender)][count].claimedETH += pending;
		}
		IERC20(BUBSY).safeTransfer(address(msg.sender), amount);
		emit Unstaked(address(msg.sender), amount, pending);
    }
	
	function claimReward(uint256 count) external nonReentrant{
	    require(stakingCount[address(msg.sender)] > count, "Staking not found");
		require(contractStatus, "Contract is not enabled");
		
	    uint256 pending = pendingReward(address(msg.sender), count);
		if(pending > 0 && address(this).balance >= pending) 
		{
			payable(address(msg.sender)).transfer(pending);
			
			uint256 pool = mapStakingInfo[address(msg.sender)][count].pool;
		    uint256 amount = mapStakingInfo[address(msg.sender)][count].stakedBUBSY;
			mapStakingInfo[address(msg.sender)][count].rewardClaimed = (amount * rewardPerShare[pool]) / precisionFactor;
			mapStakingInfo[address(msg.sender)][count].claimedETH += pending;
			emit RewardClaimed(address(msg.sender), pending);
		}
    }
	
	function pendingReward(address staker, uint256 count) public view returns (uint256) {
	
	   if(mapStakingInfo[address(staker)][count].stakedBUBSY > 0 && !mapStakingInfo[address(staker)][count].unstaked && stakingCount[address(staker)] > count)
	   {
		   uint256 pool = mapStakingInfo[address(staker)][count].pool;
		   uint256 amount = mapStakingInfo[address(staker)][count].stakedBUBSY;
		   uint256 claimed = mapStakingInfo[address(staker)][count].rewardClaimed;
		   
		   uint256 pending = ((amount * rewardPerShare[pool]) / precisionFactor) - (claimed);
		   return pending;
       } 
	   else 
	   {
		   return 0;
	   }
    }
	
	function updatePool() external payable nonReentrant {
	   require(isWhitelistForSendFund[address(msg.sender)], "Sender is not whitelisted for add fund");
	   
	   if(rewardStatus)
	   {
	       _distributeReward(msg.value);
	   }
	   else
	   {
	       undistributedReward += msg.value;
	   }
	   emit PoolUpdated(msg.value);
    }
	
	function _distributeReward(uint256 amount) internal {	
	   
	   uint256 pool0StakedBUBSY = ((BUBSYStaked[0] * poolMultiplier[0]) / 100);
	   uint256 pool1StakedBUBSY = ((BUBSYStaked[1] * poolMultiplier[1]) / 100);
	   uint256 pool2StakedBUBSY = ((BUBSYStaked[2] * poolMultiplier[2]) / 100);
	   uint256 totalStakedBUBSY = (pool0StakedBUBSY + pool1StakedBUBSY + pool2StakedBUBSY);
	   
	   if(totalStakedBUBSY > 0)
	   {
	      uint256 pool0Share = ((amount * pool0StakedBUBSY) / totalStakedBUBSY);
		  uint256 pool1Share = ((amount * pool1StakedBUBSY) / totalStakedBUBSY);
		  uint256 pool2Share = amount - pool0Share - pool1Share;
		  
		  rewardPerShare[0] += ((pool0Share * precisionFactor) / BUBSYStaked[0]);
		  rewardPerShare[1] += ((pool1Share * precisionFactor) / BUBSYStaked[1]);
		  rewardPerShare[2] += ((pool2Share * precisionFactor) / BUBSYStaked[2]);
		  
		  rewardDistributedPerPool[0] += pool0Share;
		  rewardDistributedPerPool[1] += pool1Share;
		  rewardDistributedPerPool[2] += pool2Share;
	   }
	   else
	   {
	      undistributedReward += amount;
	   }
	}
}