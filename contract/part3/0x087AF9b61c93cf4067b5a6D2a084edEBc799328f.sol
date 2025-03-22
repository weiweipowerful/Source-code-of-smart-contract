// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {MasaStaking as MasaStakingV1} from "./MasaStaking.sol";

/**
 * @dev Implementation of a staking contract V2 for MasaToken. This contract allows
 * users to stake their MasaTokens for a specified period and earn interest
 * based on the staking period. The contract includes functionalities for
 * staking, unstaking, and querying staked balances and earned interest.
 *
 * Provides backward compatibility to query pre-migration stakes from MasaStakingV1.
 * Supports new stakes after migration and a query function for historical stakes
 * based on the pause timestamp of V1 contract.
 */
contract MasaStakingV2 is ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    /**
     * @dev Struct to store information about each stake including amount,
     * start timestamp, period, and interest rate.
     */
    struct Stake {
        uint256 amount; // The amount of tokens staked.
        uint256 startTime; // The timestamp when the stake was initiated.
        uint256 unlockTime; // The timestamp when the stake was unlocked.
        uint256 period; // The period of the stake.
        uint256 interestRate; // The interest rate applicable to the stake.
        bool imported; // Flag to indicate if the stake was imported from V1.
        uint256 importedIndex; // Index of the stake in V1.
    }

    /**
     * @dev Struct to store details about each stake including amount,
     * start timestamp, unlock timestamp, period, interest rate, and eligibility
     * for unlocking and claiming. Used for querying stake details.
     */
    struct StakeDetails {
        Stake stake;
        bool canUnlock;
        bool canClaim;
    }

    /* ========== STATE VARIABLES =========================================== */

    uint256 public constant INTEREST_PRECISSION = 1_000_000;

    IERC20 public immutable masaToken;
    uint256 public immutable secondsForPeriod; // seconds for each period

    uint256 public cooldownPeriod; // period for unstaking

    mapping(address => Stake[]) public stakes;
    mapping(uint256 => uint256) public interestRates; // period => interest rate
    // array with all the periods
    uint256[] public periods;

    uint256 public rewardsReserved; // rewards reserved for staking (not yet claimed)
    uint256 public totalStaked;
    mapping(uint256 => uint256) public totalStakedForPeriod;

    /// @dev State variable to control the availability of staking functionality.
    bool public stakingEnabled;

    // Reference to the old MasaStakingV1 contract
    MasaStakingV1 public masaStakingV1;
    // Timestamp when V1 is considered outdated
    uint256 public stakingV1Timestamp;
    // Imported stake indexes from V1
    mapping(address => mapping(uint256 => bool)) public importedStakes;

    /* ========== EVENTS ==================================================== */

    event StakingEnabled(address indexed by);
    event StakingDisabled(address indexed by);
    event InterestRateUpdated(address indexed by, uint256 period, uint256 rate);
    event CooldownPeriodUpdated(address indexed by, uint256 cooldownPeriod);
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 startTime,
        uint256 period,
        uint256 interestRate,
        uint256 index
    );
    event Unlocked(address indexed user, uint256 amount, uint256 index);
    event Claimed(
        address indexed user,
        uint256 amount,
        uint256 reward,
        uint256 index
    );

    /* ========== INITIALIZE ================================================ */

    /**
     * @dev Sets the initial values for the MasaToken address and initializes
     * roles and default interest rates for different periods.
     * @param _masaTokenAddress The address of the MasaToken contract.
     * @param _admin The address of the admin account.
     * @param _secondsForPeriod The number of seconds for each staking period.
     * @param _cooldownPeriod The period for unstaking in seconds.
     * @param _masaStakingV1 The address of the MasaStakingV1 contract.
     * @param _stakingV1Timestamp The timestamp when V1 is considered outdated.
     * @param _rewardsReserved The rewards reserved for staking.
     * @param _totalStaked The total staked amount.
     * @param _periods An array of periods for which interest rates are set.
     * @param _totalStakedForPeriod An array of total staked amounts for each period.
     */
    constructor(
        address _masaTokenAddress,
        address _admin,
        uint256 _secondsForPeriod,
        uint256 _cooldownPeriod,
        address _masaStakingV1,
        uint256 _stakingV1Timestamp,
        uint256 _rewardsReserved,
        uint256 _totalStaked,
        uint256[] memory _periods,
        uint256[] memory _totalStakedForPeriod
    ) {
        require(_secondsForPeriod > 0, "Invalid seconds for period");
        require(
            _periods.length == _totalStakedForPeriod.length,
            "Invalid periods"
        );

        masaToken = IERC20(_masaTokenAddress);
        secondsForPeriod = _secondsForPeriod;
        cooldownPeriod = _cooldownPeriod;
        masaStakingV1 = MasaStakingV1(_masaStakingV1);
        if (_masaStakingV1 != address(0)) {
            stakingV1Timestamp = _stakingV1Timestamp;
            rewardsReserved = _rewardsReserved;
            totalStaked = _totalStaked;
            for (uint256 i = 0; i < _periods.length; i++) {
                totalStakedForPeriod[_periods[i]] = _totalStakedForPeriod[i];
            }
        }

        // set staking enabled default
        stakingEnabled = true;

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /* ========== RESTRICTED FUNCTIONS ====================================== */

    /**
     * @notice Disables the staking functionality.
     * @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE.
     * It sets the `stakingEnabled` state variable to false.
     */
    function disableStaking() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakingEnabled, "Staking is already disabled");
        stakingEnabled = false;
        emit StakingDisabled(msg.sender);
    }

    /**
     * @notice Enables the staking functionality.
     * @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE.
     * It sets the `stakingEnabled` state variable to true.
     */
    function enableStaking() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!stakingEnabled, "Staking is already enabled");
        stakingEnabled = true;
        emit StakingEnabled(msg.sender);
    }

    /**
     * @dev Pauses all staking and unstaking functions. Only callable by accounts
     * with the DEFAULT_ADMIN_ROLE.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
        emit Paused(msg.sender);
    }

    /**
     * @dev Unpauses all staking and unstaking functions. Only callable by accounts
     * with the DEFAULT_ADMIN_ROLE.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Updates the interest rate for a specific staking period.
     * Only callable by accounts with the DEFAULT_ADMIN_ROLE.
     * @param _period The staking period to update the interest rate for.
     * @param _rate The new interest rate for the specified staking period.
     */
    function setInterestRate(
        uint256 _period,
        uint256 _rate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(interestRates[_period] != _rate, "Rate is the same");
        require(_period > 0, "Invalid period");
        interestRates[_period] = _rate;

        // Add the period to the periods array if it doesn't already exist
        bool periodExists = false;

        uint periodsLength = periods.length;
        for (uint256 i = 0; i < periodsLength; i++) {
            if (periods[i] == _period) {
                periodExists = true;
                break;
            }
        }
        if (!periodExists) {
            periods.push(_period);
        }

        emit InterestRateUpdated(msg.sender, _period, _rate);
    }

    /**
     * @dev Updates the cooldown period for unstaking.
     * Only callable by accounts with the DEFAULT_ADMIN_ROLE.
     * @param _cooldownPeriod The new cooldown period in seconds.
     */
    function setCooldownPeriod(
        uint256 _cooldownPeriod
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            cooldownPeriod != _cooldownPeriod,
            "Cooldown period is the same"
        );
        cooldownPeriod = _cooldownPeriod;
        emit CooldownPeriodUpdated(msg.sender, _cooldownPeriod);
    }

    /**
     * @dev Updates the reference to the MasaStakingV1 contract and the paused timestamp.
     * Only callable by accounts with the DEFAULT_ADMIN_ROLE.
     * @param _masaStakingV1 The address of the MasaStakingV1 contract.
     * @param _stakingV1Timestamp The timestamp when V1 is considered outdated
     */
    function setMasaStakingV1(
        address _masaStakingV1,
        uint256 _stakingV1Timestamp
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        masaStakingV1 = MasaStakingV1(_masaStakingV1);
        stakingV1Timestamp = _stakingV1Timestamp;
    }

    /* ========== MUTATIVE FUNCTIONS ======================================== */

    /**
     * @dev Allows users to stake a specified amount of MasaToken for a specified period. Stakes are recorded
     * in the stakes mapping, and users are added to the allStakers array if they haven't staked before.
     * @param _amount The amount of MasaToken to be staked.
     * @param _period The period for which the MasaToken is staked, in months.
     */
    function stake(
        uint256 _amount,
        uint256 _period
    ) external nonReentrant whenNotPaused {
        require(stakingEnabled, "Staking is currently disabled");
        require(interestRates[_period] > 0, "Invalid staking period");
        require(_amount > 0, "Invalid amount");

        // Calculate the reward based on the staked amount and the interest rate
        uint256 reward = (_amount * interestRates[_period]) /
            (100 * INTEREST_PRECISSION);

        require(
            rewardsNotReserved() >= reward,
            "Not enough rewards to reserve for staking"
        );

        totalStaked += _amount;
        totalStakedForPeriod[_period] += _amount;

        // increase the rewards reserved for staking
        rewardsReserved += reward;

        stakes[msg.sender].push(
            Stake({
                amount: _amount,
                startTime: block.timestamp,
                unlockTime: 0,
                period: _period,
                interestRate: interestRates[_period],
                imported: false,
                importedIndex: 0
            })
        );

        masaToken.safeTransferFrom(msg.sender, address(this), _amount);

        emit Staked(
            msg.sender,
            _amount,
            block.timestamp,
            _period,
            interestRates[_period],
            stakes[msg.sender].length - 1
        );
    }

    /**
     * @dev Allows users to unlock a specific stake identified by its index after the staking period has fully elapsed.
     * @param _index The index of the stake within the user's array of stakes to be unlocked.
     */
    function unlock(uint256 _index) external nonReentrant whenNotPaused {
        require(_index < getUserStakeCount(msg.sender), "Invalid index");
        Stake[] memory userStakes = getUserStakes(msg.sender);
        Stake memory stakeData = userStakes[_index];

        // Ensure the current timestamp is beyond the unlock timestamp
        require(
            canUnlockStake(msg.sender, _index),
            "Staking period has not yet elapsed"
        );

        if (!stakeData.imported) {
            // index is the same as in stakes array because stake array is returned
            // first in the function getUserStakes
            stakes[msg.sender][_index].unlockTime = block.timestamp;
        } else {
            // we need to import the stake from V1
            stakes[msg.sender].push(
                Stake({
                    amount: stakeData.amount,
                    startTime: stakeData.startTime,
                    unlockTime: block.timestamp,
                    period: stakeData.period,
                    interestRate: stakeData.interestRate,
                    imported: stakeData.imported,
                    importedIndex: stakeData.importedIndex
                })
            );
            // mark the stake as imported
            importedStakes[msg.sender][stakeData.importedIndex] = true;
        }

        emit Unlocked(msg.sender, stakeData.amount, _index);
    }

    /**
     * @dev Allows users to claim a specific stake identified by its index after the cooldown period has fully elapsed.
     * @param _index The index of the stake within the user's array of stakes to be claimed.
     */
    function claim(uint256 _index) external nonReentrant whenNotPaused {
        require(_index < getUserStakeCount(msg.sender), "Invalid index");
        Stake[] memory userStakes = getUserStakes(msg.sender);
        Stake memory stakeData = userStakes[_index];

        // Ensure the current timestamp is beyond the cooldown period
        require(
            canClaimStake(msg.sender, _index),
            "Cooldown period has not yet elapsed"
        );

        // Calculate the reward based on the staked amount and the interest rate
        uint256 reward = (stakeData.amount * stakeData.interestRate) /
            (100 * INTEREST_PRECISSION);

        // Remove the stake from the user's stakes array.
        // Index is the same as in stakes array because stake array is returned
        // first in the function getUserStakes
        if (_index < stakes[msg.sender].length) {
            _removeStake(msg.sender, _index);
        }

        totalStaked -= stakeData.amount;
        totalStakedForPeriod[stakeData.period] -= stakeData.amount;

        if (stakeData.imported) {
            // mark the stake as imported.
            // With this, this stake can't be claimed again
            importedStakes[msg.sender][stakeData.importedIndex] = true;
        }

        // decrease the rewards reserved for staking
        rewardsReserved -= reward;

        // Transfer the staked amount plus the reward back to the user
        masaToken.safeTransfer(msg.sender, stakeData.amount + reward);

        emit Claimed(msg.sender, stakeData.amount, reward, _index);
    }

    /* ========== VIEWS ===================================================== */

    /**
     * @dev Returns the periods for which interest rates have been set.
     * @return An array of periods.
     */
    function getPeriods() external view returns (uint256[] memory) {
        return periods;
    }

    /**
     * @dev Returns the stakes of a user.
     * @param _user The address of the user.
     * @return An array of stakes.
     */
    function getUserStakes(address _user) public view returns (Stake[] memory) {
        if (address(masaStakingV1) == address(0) || !masaStakingV1.paused()) {
            return stakes[_user];
        } else {
            // get number of stakes in v2
            uint256 numStakes = stakes[_user].length;
            // get number of stakes in v1
            uint256 userStakeCount = masaStakingV1.getUserStakeCount(_user);
            for (uint256 i = 0; i < userStakeCount; i++) {
                MasaStakingV1.StakeDetails memory stakeDetails = masaStakingV1
                    .getUserStake(_user, i);
                // check if stake is before migration
                // and stake is not imported
                if (
                    stakeDetails.stake.startTime < stakingV1Timestamp &&
                    !importedStakes[_user][i]
                ) {
                    numStakes++;
                }
            }

            Stake[] memory userStakes = new Stake[](numStakes);

            uint256 index = 0;
            // get stakes in v2
            for (uint256 i = 0; i < stakes[_user].length; i++) {
                userStakes[index] = stakes[_user][i];
                index++;
            }
            // get stakes in v1
            for (uint256 i = 0; i < userStakeCount; i++) {
                MasaStakingV1.StakeDetails memory stakeDetails = masaStakingV1
                    .getUserStake(_user, i);
                // check if stake is before migration
                // and stake is not imported
                if (
                    stakeDetails.stake.startTime < stakingV1Timestamp &&
                    !importedStakes[_user][i]
                ) {
                    userStakes[index] = Stake({
                        amount: stakeDetails.stake.amount,
                        startTime: stakeDetails.stake.startTime,
                        unlockTime: stakeDetails.stake.unlockTime,
                        period: stakeDetails.stake.period,
                        interestRate: stakeDetails.stake.interestRate,
                        imported: true,
                        importedIndex: i
                    });
                    index++;
                }
            }

            return userStakes;
        }
    }

    /**
     * @dev Returns the number of stakes a user has made.
     * @param _user The address of the user.
     * @return The number of stakes.
     */
    function getUserStakeCount(address _user) public view returns (uint256) {
        if (address(masaStakingV1) == address(0)) {
            return stakes[_user].length;
        } else {
            return getUserStakes(_user).length;
        }
    }

    /**
     * @dev Returns details of a specific stake for a user, including whether it can be unstaked.
     * @param _user The address of the user.
     * @param _index The index of the stake in the user's stakes array.
     * @return StakeDetails The details of the stake.
     */
    function getUserStake(
        address _user,
        uint256 _index
    ) external view returns (MasaStakingV1.StakeDetails memory) {
        require(_index < getUserStakeCount(_user), "Invalid index");

        Stake[] memory userStakes = getUserStakes(_user);
        Stake memory stakeData = userStakes[_index];

        MasaStakingV1.Stake memory stakeDataV1 = MasaStakingV1.Stake({
            amount: stakeData.amount,
            startTime: stakeData.startTime,
            unlockTime: stakeData.unlockTime,
            period: stakeData.period,
            interestRate: stakeData.interestRate
        });

        return
            MasaStakingV1.StakeDetails({
                stake: stakeDataV1,
                canUnlock: canUnlockStake(_user, _index),
                canClaim: canClaimStake(_user, _index)
            });
    }

    /**
     * @dev Returns the total staked balance of a user by summing up the amounts in all their stakes.
     * @param _user The address of the user whose total staked balance is being queried.
     * @return uint256 The total staked balance of the user.
     */
    function getUserStakedBalance(
        address _user
    ) external view returns (uint256) {
        uint256 totalBalance = 0;
        Stake[] memory userStakes = getUserStakes(_user);
        for (uint256 i = 0; i < userStakes.length; i++) {
            totalBalance += userStakes[i].amount;
        }
        return totalBalance;
    }

    /**
     * @dev Returns the principal amounts and interest earned for each stake of a user
     * This function calculates the interest based on the elapsed time since each stake was made.
     * @param _user The address of the user whose stakes and interest are being queried.
     * @return principalAmounts An array of the principal amounts for each stake of the user.
     * @return interestEarned An array of the interest earned for each stake of the user.
     */
    function getUserStakesWithInterest(
        address _user
    )
        external
        view
        returns (
            uint256[] memory principalAmounts,
            uint256[] memory interestEarned
        )
    {
        Stake[] memory userStakes = getUserStakes(_user);
        uint256 stakeCount = userStakes.length;
        principalAmounts = new uint256[](stakeCount);
        interestEarned = new uint256[](stakeCount);

        for (uint256 i = 0; i < stakeCount; i++) {
            Stake memory stakeData = userStakes[i];
            principalAmounts[i] = stakeData.amount;

            // Calculate seconds elapsed since the stake started
            uint256 secondsElapsed = block.timestamp - stakeData.startTime;

            // Calculate the fraction of the staking period that has elapsed
            uint256 secondsInPeriod = stakeData.period * secondsForPeriod;

            if (secondsElapsed > secondsInPeriod) {
                secondsElapsed = secondsInPeriod;
            }

            // Multiply by 1e18 for precision
            uint256 elapsedFraction = secondsInPeriod > 0
                ? (secondsElapsed * 1e18) / secondsInPeriod
                : 0;

            // Calculate prorated interest based on the elapsed fraction of the period
            uint256 interestFraction = (stakeData.amount *
                stakeData.interestRate);

            // Note: We divide by 100 and then multiply by elapsedFraction and divide by 1e18 for precision
            interestEarned[i] =
                (interestFraction * elapsedFraction) /
                (100 * INTEREST_PRECISSION * 1e18);
        }

        return (principalAmounts, interestEarned);
    }

    /**
     * @dev Determines if a stake is eligible for unlocking based on the current timestamp.
     * @param _user The address of the user querying unlock eligibility.
     * @param _index The index of the stake within the user's array of stakes.
     * @return canUnlock True if the stake can be unlocked, false otherwise.
     */
    function canUnlockStake(
        address _user,
        uint256 _index
    ) public view returns (bool canUnlock) {
        require(_index < getUserStakeCount(_user), "Invalid index");

        Stake[] memory userStakes = getUserStakes(_user);
        Stake memory stakeData = userStakes[_index];

        if (stakeData.unlockTime > 0) {
            canUnlock = false;
        } else {
            uint256 secondsInPeriod = stakeData.period * secondsForPeriod;
            uint256 unlockTime = stakeData.startTime + secondsInPeriod;

            canUnlock = block.timestamp >= unlockTime;
        }

        return canUnlock;
    }

    /**
     * @dev Determines if a stake is eligible for claiming based on the current timestamp.
     * @param _user The address of the user querying claim eligibility.
     * @param _index The index of the stake within the user's array of stakes.
     * @return canClaim True if the stake can be claimed, false otherwise.
     */
    function canClaimStake(
        address _user,
        uint256 _index
    ) public view returns (bool canClaim) {
        require(_index < getUserStakeCount(_user), "Invalid index");

        Stake[] memory userStakes = getUserStakes(_user);
        Stake memory stakeData = userStakes[_index];
        canClaim =
            stakeData.unlockTime > 0 &&
            block.timestamp >= stakeData.unlockTime + cooldownPeriod;
        return canClaim;
    }

    /**
     * @dev Returns the amount of rewards not reserved for staking.
     * @return uint256 The amount of rewards not reserved for staking.
     */
    function rewardsNotReserved() public view returns (uint256) {
        uint256 masaBalance = masaToken.balanceOf(address(this));
        uint256 totalProtected = rewardsReserved + totalStaked; // This is the amount that must remain in the contract

        return masaBalance - totalProtected;
    }

    /* ========== PRIVATE FUNCTIONS ========================================= */

    /**
     * @dev Removes a stake from the stakes array for a user by index.
     * This is a private function used internally by the unstake function.
     * @param _user The address of the user from whom the stake is removed.
     * @param _index The index of the stake within the user's stakes array to remove.
     */
    function _removeStake(address _user, uint256 _index) private {
        require(_index < stakes[_user].length, "Invalid index");

        stakes[_user][_index] = stakes[_user][stakes[_user].length - 1];
        stakes[_user].pop();
    }

    /// @notice Transfer native tokens.
    /// @param _amount Token amount
    /// @param _receiver Receiver address
    function rescueNativeToken(
        uint256 _amount,
        address _receiver
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Address.sendValue(payable(_receiver), _amount);
    }

    /// @notice Transfer tokens.
    /// @param _token Token contract address
    /// @param _amount Token amount
    /// @param _receiver Receiver address
    function rescueERC20Token(
        address _token,
        uint256 _amount,
        address _receiver
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Ensure the contract doesn't allow rescuing the staking token in a way that affects the staked or reserved funds
        if (_token == address(masaToken)) {
            uint256 masaBalance = masaToken.balanceOf(address(this));
            uint256 totalProtected = rewardsReserved + totalStaked; // This is the amount that must remain in the contract

            require(
                masaBalance - _amount >= totalProtected,
                "Operation would affect staked or reserved funds"
            );
        }

        // Perform the transfer
        IERC20(_token).safeTransfer(_receiver, _amount);
    }
}