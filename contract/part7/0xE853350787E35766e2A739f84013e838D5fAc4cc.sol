// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {PortalToken} from "./PortalToken.sol";

/**
 * @title Portal Token Vesting Contract
 * @dev This contract handles the vesting of ERC20 tokens for a single beneficiary.
 * The vesting schedule is linear with configurable start and end timestamps.
 */
contract PortalTokenVesting is Ownable, ReentrancyGuard, Pausable {
    /// @notice Portal token contract
    PortalToken public immutable token;
    
    /// @notice Start timestamp of the vesting period
    uint256 public startTimestamp;
    
    /// @notice End timestamp of the vesting period
    uint256 public endTimestamp;
    
    /// @notice Beneficiary address that will receive the tokens
    address public beneficiary;

    /// @notice Total allocation of tokens to be vested
    uint256 public totalAllocation;
    
    /// @notice Amount of tokens claimed so far
    uint256 public claimed;

    /// @notice Event emitted when tokens are claimed
    event TokensClaimed(address indexed beneficiary, uint256 amount);
    
    /// @notice Event emitted when tokens are withdrawn in emergency
    event EmergencyWithdraw(address indexed owner, uint256 amount);
    
    /// @notice Event emitted when vesting schedule is updated
    event VestingScheduleUpdated(uint256 newStartTimestamp, uint256 newEndTimestamp);
    
    /// @notice Event emitted when total allocation is updated
    event TotalAllocationUpdated(uint256 newTotalAllocation);

    /**
     * @notice Initialize the contract with token, beneficiary, start and end timestamps
     * @param _token Address of the ERC20 token
     * @param _beneficiary Address of the beneficiary
     * @param _startTimestamp Start timestamp of the vesting period
     * @param _endTimestamp End timestamp of the vesting period
     * @param _totalAllocation Total amount of tokens to be vested
     */
    constructor(
        address _token, 
        address _beneficiary, 
        uint256 _startTimestamp, 
        uint256 _endTimestamp,
        uint256 _totalAllocation
    ) {
        require(_token != address(0), "Token address cannot be zero");
        require(_beneficiary != address(0), "Beneficiary address cannot be zero");
        require(_endTimestamp > _startTimestamp, "End timestamp must be after start timestamp");
        
        token = PortalToken(_token);
        beneficiary = _beneficiary;
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;
        
        totalAllocation = _totalAllocation;
    }

    /**
     * @notice Function for beneficiary to claim vested tokens
     */
    function claim() external nonReentrant whenNotPaused {
        require(msg.sender == beneficiary, "Only beneficiary can claim");
        
        uint256 amountToClaim = claimableAmount();
        require(amountToClaim > 0, "No tokens to claim");
        
        claimed += amountToClaim;
        bool success = token.transfer(beneficiary, amountToClaim);
        require(success, "Token transfer failed");
        
        emit TokensClaimed(beneficiary, amountToClaim);
    }

    /**
     * @notice Calculate the amount of tokens that can be claimed
     * @return Amount of tokens that can be claimed
     */
    function claimableAmount() public view returns (uint256) {
        return vestedAmount() - claimed;
    }

    /**
     * @notice Calculate the amount of tokens that have vested
     * @return Amount of tokens that have vested
     */
    function vestedAmount() public view returns (uint256) {
        if (block.timestamp < startTimestamp) {
            return 0;
        }
        
        if (block.timestamp >= endTimestamp) {
            return totalAllocation;
        }
        
        // Linear vesting
        uint256 elapsedTime = block.timestamp - startTimestamp;
        uint256 vestingDuration = endTimestamp - startTimestamp;
        
        return (totalAllocation * elapsedTime) / vestingDuration;
    }

    /**
     * @notice Update the beneficiary address
     * @param newBeneficiary address of the new beneficiary
     */
    function updateBeneficiary(address newBeneficiary) external onlyOwner {
        require(newBeneficiary != address(0), "Beneficiary address cannot be zero");
        beneficiary = newBeneficiary;
    }
    
    /**
     * @notice Update the vesting schedule
     * @param newStartTimestamp New start timestamp of the vesting period
     * @param newEndTimestamp New end timestamp of the vesting period
     */
    function updateVestingSchedule(uint256 newStartTimestamp, uint256 newEndTimestamp) external onlyOwner {
        require(newEndTimestamp > newStartTimestamp, "End timestamp must be after start timestamp");
        
        // If vesting has already started, we can only extend the end date or push back the start date
        if (block.timestamp >= startTimestamp) {
            require(newStartTimestamp <= block.timestamp, "Cannot move start time to the future after vesting has begun");
        }
        
        startTimestamp = newStartTimestamp;
        endTimestamp = newEndTimestamp;
        
        emit VestingScheduleUpdated(newStartTimestamp, newEndTimestamp);
    }
    
    /**
     * @notice Update the total allocation
     * @param newTotalAllocation New total allocation of tokens to be vested
     */
    function updateTotalAllocation(uint256 newTotalAllocation) external onlyOwner {
        require(newTotalAllocation >= claimed, "New allocation cannot be less than already claimed amount");
        
        totalAllocation = newTotalAllocation;
        
        emit TotalAllocationUpdated(newTotalAllocation);
    }

    /**
     * @notice Pause the contract to prevent claiming
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract to allow claiming
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw all tokens from the contract
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        
        bool success = token.transfer(owner(), balance);
        require(success, "Token transfer failed");
        
        emit EmergencyWithdraw(owner(), balance);
    }
}