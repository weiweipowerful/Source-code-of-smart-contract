// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./BaseStaking.sol";
import '../util/TimeLock.sol';

/**
 * @title FlexiStaking Contract
 * @author Challenge.GG
 * @dev Extends BaseStaking with flexible unstake fee settings governed by a TimeLock contract.
 * Allows for secure, time-locked updates to unstake fee percentages, providing an additional layer of governance.
 * Stakers can stake and unstake tokens, with the unstake fee subject to scheduled changes approved through the TimeLock.
 * @notice Flexibel staking contract with no vesting schedules. Staking and unstaking can be done at any time. 
 * Unstaking is subject to a fee, which can be changed through the TimeLock contract.
 */
contract FlexiStaking is BaseStaking{

    TimeLock public timeLock; // TimeLock contract for unstake fee change

    /**
     * @dev Initializes the FlexiStaking contract linking staking logic with a TimeLock contract for governance.
     * Inherits initial settings from BaseStaking and sets the TimeLock contract used for managing unstake fee changes.
     * @param _multisigAdmin Address of the multisig admin with privileged control.
     * @param _rewardsToken Address of the ERC20 token used for rewards.
     * @param _stakingToken Address of the ERC20 token accepted for staking.
     * @param _timeLockContract Address of the TimeLock contract for governance actions.
     */
    constructor(
        address _multisigAdmin,
        address _rewardsToken,
        address _stakingToken,
        address _timeLockContract
    ) BaseStaking(_multisigAdmin,_rewardsToken,_stakingToken, 5) {
        require(_timeLockContract != address(0), "TimeLock address is the zero address");

        timeLock = TimeLock(_timeLockContract); 
    }
    
    /**
     * @notice Sets a new unstake fee percentage after a delay, governed by the TimeLock contract.
     * Can only be executed if the action has been scheduled in the TimeLock contract and the waiting period has passed.
     * Validates the actionId to ensure the action corresponds to the intended parameter change.
     * @dev Requires admin privileges. Ensures the actionId matches the scheduled change and the execution time has passed.
     * @param _unstakeFeePercentage New unstake fee percentage to be set.
     * @param actionId Unique identifier for the scheduled action in the TimeLock contract.
     */
    function setUnstakeFee(uint256 _unstakeFeePercentage,bytes32 actionId) external onlyAdmin{
        require(timeLock.getExecutionTime(actionId) != 0, "Action not scheduled");
        require(block.timestamp >= timeLock.getExecutionTime(actionId), "Action not ready");
        require(actionId == timeLock.generateActionId("setUnstakeFee", abi.encode(_unstakeFeePercentage), address(this)), "Invalid actionId");

        _setUnstakeFee(_unstakeFeePercentage);
         timeLock.clearAction(actionId);
    }
    
    /**
     * @notice Allows a user to stake a specified amount of the staking token.
     * @dev Stakes tokens for msg.sender, adhering to the BaseStaking implementation and nonReentrancy guard.
     * @param amount Amount of the staking token to stake.
     */
    function stake(uint256 amount) external override nonReentrant whenNotPaused  {
        _stake(amount,msg.sender,msg.sender);
    }    

    /**
     * @notice Allows a user to unstake a specified amount of the staking token.
     * @dev Unstakes tokens for msg.sender, adhering to the BaseStaking implementation and nonReentrancy guard.
     * @param amount Amount of the staking token to unstake.
     */
    function unstake(uint amount) public override nonReentrant{
         _unstake(amount,msg.sender);
    }    

   
}