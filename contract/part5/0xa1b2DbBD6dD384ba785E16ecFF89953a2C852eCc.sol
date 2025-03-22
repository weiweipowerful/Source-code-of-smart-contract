// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/utils/math/Math.sol";
import {AccessControlEnumerable} from "openzeppelin/access/extensions/AccessControlEnumerable.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/LSP/IStaking.sol";

/// @title Topupper
/// @notice This is a Mantle internal tool used to calculate and execute daily topups to achieve a
/// boosted APY on METH (Mantle ETH). The contract manages the distribution of additional rewards
/// to METH stakers through automated topup operations.
/// @dev Implements AccessControlEnumerable for role-based access control with RISKMANAGER_ROLE
/// and OPERATOR_ROLE permissions
contract Topupper is AccessControlEnumerable {
    using SafeERC20 for IERC20;

    // Errors.
    error DoesNotReceiveETH();

    // Constants.
    bytes32 public constant RISKMANAGER_ROLE = keccak256("RISKMANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 private constant BPS_DENOMINATOR = 10000;
    uint256 private constant SECONDS_IN_A_DAY = 86400;
    uint256 private constant DAYS_IN_YEAR = 365;
    uint256 private constant YEARLY_DENOMINATOR = BPS_DENOMINATOR * DAYS_IN_YEAR;

    // State variables.
    /// @notice Core state variables for topup calculations and tracking
    /// @dev checkpointTime - Timestamp of contract deployment, used as reference for topup calculations
    /// @dev targetTopupAPYinBPS - Target annual percentage yield in basis points (default: 20 BPS = 0.2%)
    /// @dev topupCounter - Tracks number of successful topups, manageable by risk manager
    /// @dev cumulativeTopupAmt - Total amount of ETH used for topups since deployment
    address public methStaking;
    address public defundTreasuryAddress;

    uint256 public currentPeriodStartTime;
    uint256 public currentPeriodRemainingTopups;
    uint256 public currentPeriodTopupCounter;
    uint256 public currentPeriodTopupAmt;
    uint256 public totalTopupCount;
    uint256 public cumulativeTopupAmt;

    uint256 public targetTopupAPYinBPS;

    // Constructor
    constructor(address staking, address MTreasuryL1_SC, address MTreasuryL1_FF, address TreasuryEOA) {
        require(staking != address(0), "Invalid staking address");
        require(MTreasuryL1_SC != address(0), "Invalid treasury SC address");
        require(MTreasuryL1_FF != address(0), "Invalid treasury FF address");
        require(TreasuryEOA != address(0), "Invalid treasury EOA address");
        methStaking = staking;
        defundTreasuryAddress = MTreasuryL1_FF;

        _setRoleAdmin(RISKMANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, RISKMANAGER_ROLE);

        // operator role ot be granted to engineering node later; or we can enable topup_byanyone"
        _grantRole(DEFAULT_ADMIN_ROLE, MTreasuryL1_SC); // MTreasuryL1-SC
        _grantRole(OPERATOR_ROLE, TreasuryEOA); // TreasuryEOA-M
        _grantRole(RISKMANAGER_ROLE, TreasuryEOA); // TreasuryEOA-M

        currentPeriodStartTime = block.timestamp - (block.timestamp % SECONDS_IN_A_DAY);  // Round down to start of day
        currentPeriodRemainingTopups = 1;
        currentPeriodTopupCounter = 0;
        currentPeriodTopupAmt = 0;
        totalTopupCount = 0;
        targetTopupAPYinBPS = 20;
    }

    /// @notice Executes an automatic topup if conditions are met
    /// @dev Checks operator authorization and ensures proper time has passed since last topup
    /// If no operators are assigned, anyone can call this function
    function autoTopUp() external {
        uint256 operatorCount = getRoleMemberCount(OPERATOR_ROLE);
        if (operatorCount > 0) {
            require(hasRole(OPERATOR_ROLE, msg.sender), "Caller must be operator");
        }
        require(currentPeriodRemainingTopups > 0, "Remaining topup is zero");

        uint256 dayCount = getCountByDays();
        require(dayCount >= currentPeriodTopupCounter, "Too early for topup");
        
        uint256 maxTopups = 1 + dayCount - currentPeriodTopupCounter;
        require(maxTopups > 0, "Max topup is zero");

        for (uint256 i = 0; i < maxTopups;) {
            if (currentPeriodRemainingTopups == 0) break;
            
            uint256 topupAmt = getTopupAmt();
            if (topupAmt > 0) {
                currentPeriodRemainingTopups--;
                currentPeriodTopupCounter++;
                currentPeriodTopupAmt += topupAmt;
                totalTopupCount++;
                cumulativeTopupAmt += topupAmt;
                _wrapTopup(topupAmt);
            }
            unchecked { ++i; }
        }
    }

    // Helper Functions
    function getCountByDays() public view returns (uint256) {
        unchecked {
            return (block.timestamp >= currentPeriodStartTime) 
                ? (block.timestamp - currentPeriodStartTime) / SECONDS_IN_A_DAY 
                : 0;
        }
    }

    function getTopupAmt() public view returns (uint256) {
        uint256 controlled = getTotalControlled();
        if (controlled == 0 || targetTopupAPYinBPS == 0) return 0;
        return Math.mulDiv(controlled, targetTopupAPYinBPS, YEARLY_DENOMINATOR);
    }

    function getTotalControlled() public view returns (uint256) {
        return IStaking(methStaking).totalControlled();
    }

    function _wrapTopup(uint256 _amount) internal {
        require(address(this).balance >= _amount, "Insufficient balance");
        IStaking(methStaking).topUp{value: _amount}();
    }

    // Risk Manager Config
    /// @notice Sets the target APY for topups in basis points
    /// @dev Only callable by RISKMANAGER_ROLE
    /// @param _newTargetTopupAPYinBPS New target APY in basis points (1 BPS = 0.01%)
    /// Must be between 0 and 400 (0% to 4% per year)
    function setTargetTopupAPYinBPS(uint256 _newTargetTopupAPYinBPS) external onlyRole(RISKMANAGER_ROLE) {
        require(_newTargetTopupAPYinBPS >= 0 && _newTargetTopupAPYinBPS <= 400, "Apy in bps out of range");

        targetTopupAPYinBPS = _newTargetTopupAPYinBPS;
    }

    /// @notice Sets the checkpoint time for topup calculations
    /// @dev Only callable by RISKMANAGER_ROLE
    /// @param _newStartTime New checkpoint time in seconds
    function setNewPeriod(uint256 _newStartTime, uint256 _newCount) external onlyRole(RISKMANAGER_ROLE) {
        currentPeriodStartTime = _newStartTime - (_newStartTime % SECONDS_IN_A_DAY);
        currentPeriodTopupCounter = 0;
        currentPeriodTopupAmt = 0;
        currentPeriodRemainingTopups = _newCount;
    }

    /// @notice Sets the topup counter value
    /// @dev Only callable by RISKMANAGER_ROLE
    /// @param _newCounter New value for the topup counter
    function setCurrentPeriodTopupCounter(uint256 _newCounter) external onlyRole(RISKMANAGER_ROLE) {
        currentPeriodTopupCounter = _newCounter;
    }

    /// @notice Sets the remaining topups for the current period
    /// @dev Only callable by RISKMANAGER_ROLE
    /// @param _newCount New value for the remaining topups counter
    function setCurrentPeriodRemainingTopups(uint256 _newCount) external onlyRole(RISKMANAGER_ROLE) {
        currentPeriodRemainingTopups = _newCount;
    }

    /// @notice Updates the treasury address where defunded assets will be sent
    /// @dev Only callable by RISKMANAGER_ROLE
    /// @param _newTreasuryAddress Address of the new treasury that will receive defunded assets
    function setDefundTreasuryAddress(address _newTreasuryAddress) external onlyRole(RISKMANAGER_ROLE) {
        require(_newTreasuryAddress != address(0), "Invalid treasury address");
        defundTreasuryAddress = _newTreasuryAddress;
    }

    /// @notice Allows the contract to receive ETH for topup operations
    /// @dev Direct ETH transfers through receive() are disabled
    function fundETH() external payable {
        // no need for implementation if just receiving ETH
        // usging transaction value to trace deposit history
    }

    /// @notice Withdraws ETH from the contract to the treasury
    /// @dev Only callable by RISKMANAGER_ROLE
    /// @param amount Amount of ETH to withdraw in wei
    function defundETH(uint256 amount) external onlyRole(RISKMANAGER_ROLE) {
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success,) = payable(defundTreasuryAddress).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /// @notice Recovers any ERC20 tokens accidentally sent to the contract
    /// @dev Only callable by RISKMANAGER_ROLE
    /// @param token Address of the ERC20 token to recover
    /// @param amount Amount of tokens to recover
    function rescueERC20(address token, uint256 amount) external onlyRole(RISKMANAGER_ROLE) {
        require(token != address(0), "Invalid token");
        IERC20(token).safeTransfer(defundTreasuryAddress, amount);
    }

    // Quality of life functions
    receive() external payable {
        revert DoesNotReceiveETH();
    }

    fallback() external payable {
        revert DoesNotReceiveETH();
    }
}