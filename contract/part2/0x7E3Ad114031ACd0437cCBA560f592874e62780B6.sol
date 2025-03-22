// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

/**
 * @title TRUF vesting contract
 * @author Ryuhei Matsuda
 * @notice Admin registers vesting information for users,
 *      and users could claim or lock vesting to veTRUF to get voting power and TRUF staking rewards
 */
contract TrufVesting is Ownable2Step {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error Forbidden(address sender);
    error InvalidTimestamp();
    error InvalidAmount();
    error InvalidVestingCategory(uint256 id);
    error InvalidEmissions();
    error InvalidVestingInfo(uint256 categoryIdx, uint256 id);
    error InvalidUserVesting();
    error ClaimAmountExceed();
    error UserVestingAlreadySet(uint256 categoryIdx, uint256 vestingId, address user);
    error UserVestingDoesNotExists(uint256 categoryIdx, uint256 vestingId, address user);
    error MaxAllocationExceed();
    error AlreadyVested(uint256 categoryIdx, uint256 vestingId, address user);
    error LockExist();
    error LockDoesNotExist();
    error InvalidInitialReleasePct();
    error InvalidInitialReleasePeriod();
    error InvalidCliff();
    error InvalidPeriod();
    error InvalidUnit();
    error Initialized();

    /// @dev Emitted when vesting category is set
    event VestingCategorySet(uint256 indexed id, string category, uint256 maxAllocation, bool adminClaimable);

    /// @dev Emitted when emission schedule is set
    event EmissionScheduleSet(uint256 indexed categoryId, uint256[] emissions);

    /// @dev Emitted when vesting info is set
    event VestingInfoSet(uint256 indexed categoryId, uint256 indexed id, VestingInfo info);

    /// @dev Emitted when user vesting info is set
    event UserVestingSet(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount, uint64 startTime
    );

    /// @dev Emitted when user vesting is migrated using the migrator contract.
    event UserVestingMigrated(
        uint256 indexed categoryId,
        uint256 indexed vestingId,
        address indexed user,
        uint256 amount,
        uint256 claimed,
        uint256 locked,
        uint64 startTime
    );

    /// @dev Emitted when admin migrates user's vesting to another address
    event MigrateUser(
        uint256 indexed categoryId, uint256 indexed vestingId, address prevUser, address newUser, uint256 newLockupId
    );

    /// @dev Emitted when admin cancel user's vesting
    event CancelVesting(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, bool giveUnclaimed
    );

    /// @dev Emitted when admin has been set
    event AdminSet(address indexed admin, bool indexed flag);

    /// @dev Emitted when user claimed vested TRUF tokens
    event Claimed(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);

    /// @dev Emitted when veTRUF token has been set
    event VeTrufSet(address indexed veTRUF);

    /// @dev Emitted when user stakes vesting to veTRUF
    event Staked(
        uint256 indexed categoryId,
        uint256 indexed vestingId,
        address indexed user,
        uint256 amount,
        uint256 start,
        uint256 duration,
        uint256 lockupId
    );

    /// @dev Emitted when user extended veTRUF staking period or increased amount
    event ExtendedStaking(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount, uint256 duration
    );

    /// @dev Emitted when user unstakes from veTRUF
    event Unstaked(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);

    /// @dev Vesting Category struct
    struct VestingCategory {
        string category; // Category name
        uint256 maxAllocation; // Maximum allocation for this category
        uint256 allocated; // Current allocated amount
        bool adminClaimable; // Allow admin to claim if value is true
        uint256 totalClaimed; // Total claimed amount
    }

    /// @dev Vesting info struct
    struct VestingInfo {
        uint64 initialReleasePct; // Initial Release percentage
        uint64 initialReleasePeriod; // Initial release period after TGE
        uint64 cliff; // Cliff period
        uint64 period; // Total period
        uint64 unit; // The period to claim. ex. monthly or 6 monthly
    }

    /// @dev User vesting info struct
    struct UserVesting {
        uint256 amount; // Total vesting amount
        uint256 claimed; // Total claimed amount
        uint256 locked; // Locked amount at VotingEscrow
        uint64 startTime; // Vesting start time
    }

    uint256 public constant DENOMINATOR = 1e18;
    uint64 public constant ONE_MONTH = 30 days;

    /// @dev Is category initialized
    mapping(uint256 => bool) public isInitialized;

    /// @dev TRUF token address
    IERC20 public immutable trufToken;

    /// @dev TRUF Migration contract address
    address public immutable trufMigrator;

    /// @dev veTRUF token address
    IVotingEscrow public veTRUF;

    /// @dev TGE timestamp
    uint64 public immutable tgeTime;

    /// @dev Vesting categories
    VestingCategory[] public categories;

    // @dev Emission schedule per category. x index item of array indicates emission limit on x+1 months after TGE time.
    mapping(uint256 => uint256[]) public emissionSchedule;

    /// @dev Vesting info per category
    mapping(uint256 => VestingInfo[]) public vestingInfos;

    /// @dev User vesting information (category => info => user address => user vesting)
    mapping(uint256 => mapping(uint256 => mapping(address => UserVesting))) public userVestings;

    /// @dev Vesting lockup ids (category => info => user address => lockup id)
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public lockupIds;

    /// @dev True if account has admin permission
    mapping(address => bool) public isAdmin;

    modifier onlyAdmin() {
        if (!isAdmin[msg.sender] && msg.sender != owner()) {
            revert Forbidden(msg.sender);
        }
        _;
    }

    /**
     * @notice TRUF Vesting constructor
     * @param _trufToken TRUF token address
     */
    constructor(IERC20 _trufToken, address _trufMigrator, uint64 _tgeTime) {
        if (address(_trufToken) == address(0)) revert ZeroAddress();

        trufToken = _trufToken;
        trufMigrator = _trufMigrator;
        tgeTime = _tgeTime;
    }

    /**
     * @notice Calculate claimable amount (total vested amount - previously claimed amount - locked amount)
     * @param categoryId Vesting category id
     * @param vestingId Vesting id
     * @param user user address
     * @return claimableAmount Claimable amount
     */
    function claimable(uint256 categoryId, uint256 vestingId, address user)
        public
        view
        returns (uint256 claimableAmount)
    {
        if (isInitialized[categoryId] == false) revert Initialized();

        UserVesting memory userVesting = userVestings[categoryId][vestingId][user];

        VestingInfo memory info = vestingInfos[categoryId][vestingId];

        uint64 startTime = userVesting.startTime + info.initialReleasePeriod;

        if (startTime > block.timestamp) {
            return 0;
        }

        uint256 totalAmount = userVesting.amount;

        uint256 initialRelease = (totalAmount * info.initialReleasePct) / DENOMINATOR;

        startTime += info.cliff;

        uint256 vestedAmount;

        if (startTime > block.timestamp) {
            vestedAmount = initialRelease;
        } else {
            uint64 timeElapsed = ((uint64(block.timestamp) - startTime) / info.unit) * info.unit;

            vestedAmount = ((totalAmount - initialRelease) * timeElapsed) / info.period + initialRelease;
        }

        uint256 maxClaimable = userVesting.amount - userVesting.locked;
        if (vestedAmount > maxClaimable) {
            vestedAmount = maxClaimable;
        }
        if (vestedAmount <= userVesting.claimed) {
            return 0;
        }

        claimableAmount = vestedAmount - userVesting.claimed;
        uint256 emissionLeft = getEmission(categoryId) - categories[categoryId].totalClaimed;

        if (claimableAmount > emissionLeft) {
            claimableAmount = emissionLeft;
        }
    }

    /**
     * @notice Claim available amount
     * @dev Owner is able to claim for admin claimable categories.
     * @param user user account(For non-admin claimable categories, it must be msg.sender)
     * @param categoryId category id
     * @param vestingId vesting id
     * @param claimAmount token amount to claim
     */
    function claim(address user, uint256 categoryId, uint256 vestingId, uint256 claimAmount) public {
        if (isInitialized[categoryId] == false) revert Initialized();

        if (user != msg.sender && (!categories[categoryId].adminClaimable || !isAdmin[msg.sender])) {
            revert Forbidden(msg.sender);
        }

        uint256 claimableAmount = claimable(categoryId, vestingId, user);
        if (claimAmount == type(uint256).max) {
            claimAmount = claimableAmount;
        } else if (claimAmount > claimableAmount) {
            revert ClaimAmountExceed();
        }
        if (claimAmount == 0) {
            revert ZeroAmount();
        }

        categories[categoryId].totalClaimed += claimAmount;
        userVestings[categoryId][vestingId][user].claimed += claimAmount;
        trufToken.safeTransfer(user, claimAmount);

        emit Claimed(categoryId, vestingId, user, claimAmount);
    }

    /**
     * @notice Stake vesting to veTRUF to get voting power and get staking TRUF rewards
     * @param categoryId category id
     * @param vestingId vesting id
     * @param amount amount to stake
     * @param duration lock period in seconds
     */
    function stake(uint256 categoryId, uint256 vestingId, uint256 amount, uint256 duration) external {
        _stake(msg.sender, categoryId, vestingId, amount, block.timestamp, duration);
    }

    /**
     * @notice Extend veTRUF staking period and increase amount
     * @param categoryId category id
     * @param vestingId vesting id
     * @param amount token amount to increase
     * @param duration lock period from now
     */
    function extendStaking(uint256 categoryId, uint256 vestingId, uint256 amount, uint256 duration) external {
        if (isInitialized[categoryId] == false) revert Initialized();

        uint256 lockupId = lockupIds[categoryId][vestingId][msg.sender];
        if (lockupId == 0) {
            revert LockDoesNotExist();
        }

        if (amount != 0) {
            UserVesting storage userVesting = userVestings[categoryId][vestingId][msg.sender];

            if (amount > userVesting.amount - userVesting.claimed - userVesting.locked) {
                revert InvalidAmount();
            }

            userVesting.locked += amount;

            trufToken.safeIncreaseAllowance(address(veTRUF), amount);
        }
        veTRUF.extendVestingLock(msg.sender, lockupId - 1, amount, duration);

        emit ExtendedStaking(categoryId, vestingId, msg.sender, amount, duration);
    }

    /**
     * @notice Unstake vesting from veTRUF
     * @param categoryId category id
     * @param vestingId vesting id
     */
    function unstake(uint256 categoryId, uint256 vestingId) external {
        if (isInitialized[categoryId] == false) revert Initialized();

        uint256 lockupId = lockupIds[categoryId][vestingId][msg.sender];
        if (lockupId == 0) {
            revert LockDoesNotExist();
        }

        uint256 amount = veTRUF.unstakeVesting(msg.sender, lockupId - 1, false);

        UserVesting storage userVesting = userVestings[categoryId][vestingId][msg.sender];

        userVesting.locked -= amount;
        delete lockupIds[categoryId][vestingId][msg.sender];

        emit Unstaked(categoryId, vestingId, msg.sender, amount);
    }

    /**
     * @notice Migrate owner of vesting. Used when user lost his private key
     * @dev Only admin can migrate users vesting
     * @param categoryId Category id
     * @param vestingId Vesting id
     * @param prevUser previous user address
     * @param newUser new user address
     */
    function migrateUser(uint256 categoryId, uint256 vestingId, address prevUser, address newUser) external onlyAdmin {
        if (newUser == address(0)) {
            revert ZeroAddress();
        }

        UserVesting storage prevVesting = userVestings[categoryId][vestingId][prevUser];
        UserVesting storage newVesting = userVestings[categoryId][vestingId][newUser];

        if (newVesting.amount != 0) {
            revert UserVestingAlreadySet(categoryId, vestingId, newUser);
        }
        if (prevVesting.amount == 0) {
            revert UserVestingDoesNotExists(categoryId, vestingId, prevUser);
        }

        newVesting.amount = prevVesting.amount;
        newVesting.claimed = prevVesting.claimed;
        newVesting.startTime = prevVesting.startTime;

        uint256 lockupId = lockupIds[categoryId][vestingId][prevUser];
        uint256 newLockupId;

        if (lockupId != 0) {
            newLockupId = veTRUF.migrateVestingLock(prevUser, newUser, lockupId - 1) + 1;
            lockupIds[categoryId][vestingId][newUser] = newLockupId;
            delete lockupIds[categoryId][vestingId][prevUser];

            newVesting.locked = prevVesting.locked;
        }
        delete userVestings[categoryId][vestingId][prevUser];

        emit MigrateUser(categoryId, vestingId, prevUser, newUser, newLockupId);
    }

    /**
     * @notice Cancel vesting and force cancel from voting escrow
     * @dev Only admin can cancel users vesting
     * @param categoryId Category id
     * @param vestingId Vesting id
     * @param user user address
     * @param giveUnclaimed Send currently vested, but unclaimed amount to use or not
     */
    function cancelVesting(uint256 categoryId, uint256 vestingId, address user, bool giveUnclaimed)
        external
        onlyAdmin
    {
        UserVesting storage userVesting = userVestings[categoryId][vestingId][user];

        if (userVesting.amount == 0) {
            revert UserVestingDoesNotExists(categoryId, vestingId, user);
        }

        VestingInfo memory vestingInfo = vestingInfos[categoryId][vestingId];
        if (
            userVesting.startTime + vestingInfo.initialReleasePeriod + vestingInfo.cliff + vestingInfo.period
                <= block.timestamp
        ) {
            revert AlreadyVested(categoryId, vestingId, user);
        }

        uint256 lockupId = lockupIds[categoryId][vestingId][user];

        if (lockupId != 0) {
            veTRUF.unstakeVesting(user, lockupId - 1, true);
            delete lockupIds[categoryId][vestingId][user];
            userVesting.locked = 0;
        }

        VestingCategory storage category = categories[categoryId];

        uint256 claimableAmount = claimable(categoryId, vestingId, user);

        uint256 unvested = userVesting.amount - (userVesting.claimed + (giveUnclaimed ? claimableAmount : 0));

        delete userVestings[categoryId][vestingId][user];

        category.allocated -= unvested;

        if (giveUnclaimed && claimableAmount != 0) {
            trufToken.safeTransfer(user, claimableAmount);

            category.totalClaimed += claimableAmount;
            emit Claimed(categoryId, vestingId, user, claimableAmount);
        }

        emit CancelVesting(categoryId, vestingId, user, giveUnclaimed);
    }

    /**
     * @notice Add a new vesting category
     * @dev Only admin can add a vesting category
     * @param category new vesting category
     * @param maxAllocation Max allocation amount for this category
     * @param adminClaimable Admin claimable flag
     */
    function setVestingCategory(string calldata category, uint256 maxAllocation, bool adminClaimable)
        public
        onlyOwner
    {
        if (maxAllocation == 0) {
            revert ZeroAmount();
        }

        uint256 id = categories.length;
        categories.push(VestingCategory(category, maxAllocation, 0, adminClaimable, 0));

        emit VestingCategorySet(id, category, maxAllocation, adminClaimable);
    }

    /**
     * @notice Set emission schedule
     * @dev Only admin can set emission schedule
     * @param categoryId category id
     * @param emissions Emission schedule
     */
    function setEmissionSchedule(uint256 categoryId, uint256[] memory emissions) public onlyOwner {
        if (isInitialized[categoryId]) {
            revert Initialized();
        }

        uint256 maxAllocation = categories[categoryId].maxAllocation;

        if (emissions.length == 0 || emissions[emissions.length - 1] != maxAllocation) {
            revert InvalidEmissions();
        }

        delete emissionSchedule[categoryId];
        emissionSchedule[categoryId] = emissions;

        emit EmissionScheduleSet(categoryId, emissions);
    }

    /**
     * @notice Add or modify vesting information
     * @dev Only admin can set vesting info
     * @param categoryIdx category id
     * @param id id to modify or uint256.max to add new info
     * @param info new vesting info
     */
    function setVestingInfo(uint256 categoryIdx, uint256 id, VestingInfo calldata info) public onlyAdmin {
        if (info.initialReleasePct > DENOMINATOR) {
            revert InvalidInitialReleasePct();
        } else if (info.initialReleasePeriod > info.period) {
            revert InvalidInitialReleasePeriod();
        } else if (info.cliff > 365 days) {
            revert InvalidCliff();
        } else if (info.period > 8 * 365 days) {
            revert InvalidPeriod();
        } else if (info.period % info.unit != 0) {
            revert InvalidUnit();
        }
        if (id == type(uint256).max) {
            id = vestingInfos[categoryIdx].length;
            vestingInfos[categoryIdx].push(info);
        } else {
            vestingInfos[categoryIdx][id] = info;
        }

        emit VestingInfoSet(categoryIdx, id, info);
    }

    /**
     * @notice Migrate vesting from old contracts.
     * @param categoryId category id
     * @param vestingId vesting id
     * @param user user address
     * @param amount vesting amount
     * @param claimed vesting claimed amount
     * @param locked vesting locked amount, 0 if no staking
     * @param vestingStartTime zero to start from TGE or non-zero to set up custom start time
     * @param stakingStartTime timestamp where the staking began, 0 if no staking
     * @param stakingDuration duration of the staking, 0 if no staking
     */
    function migrate(
        uint256 categoryId,
        uint256 vestingId,
        address user,
        uint256 amount,
        uint256 claimed,
        uint256 locked,
        uint64 vestingStartTime,
        uint256 stakingStartTime,
        uint256 stakingDuration
    ) public {
        if (msg.sender != trufMigrator) {
            revert();
        }
        if (user == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (categoryId >= categories.length) {
            revert InvalidVestingCategory(categoryId);
        }
        if (vestingId >= vestingInfos[categoryId].length) {
            revert InvalidVestingInfo(categoryId, vestingId);
        }
        if (isInitialized[categoryId]) {
            trufToken.safeTransferFrom(msg.sender, address(this), amount - claimed);
        } else if (locked > 0) {
            revert Initialized();
        }

        VestingCategory storage category = categories[categoryId];
        UserVesting storage userVesting = userVestings[categoryId][vestingId][user];

        if (amount < claimed + locked) {
            revert InvalidUserVesting();
        }

        category.allocated += amount;
        category.totalClaimed += claimed;
        if (category.allocated > category.maxAllocation) {
            revert MaxAllocationExceed();
        }

        if (vestingStartTime != 0 && vestingStartTime < tgeTime) revert InvalidTimestamp();

        userVesting.amount += amount;
        userVesting.claimed += claimed;
        userVesting.startTime = vestingStartTime == 0 ? tgeTime : vestingStartTime;

        emit UserVestingMigrated(categoryId, vestingId, user, amount, claimed, locked, userVesting.startTime);

        if (locked > 0) {
            _stake(user, categoryId, vestingId, locked, stakingStartTime, stakingDuration);
        }
    }

    /**
     * @notice Set user vesting amount
     * @dev Only admin can set user vesting
     * @dev It will be failed if it exceeds max allocation
     * @param categoryId category id
     * @param vestingId vesting id
     * @param user user address
     * @param startTime zero to start from TGE or non-zero to set up custom start time
     * @param amount vesting amount
     */
    function setUserVesting(uint256 categoryId, uint256 vestingId, address user, uint64 startTime, uint256 amount)
        public
        onlyAdmin
    {
        if (user == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (categoryId >= categories.length) {
            revert InvalidVestingCategory(categoryId);
        }
        if (vestingId >= vestingInfos[categoryId].length) {
            revert InvalidVestingInfo(categoryId, vestingId);
        }

        VestingCategory storage category = categories[categoryId];
        UserVesting storage userVesting = userVestings[categoryId][vestingId][user];

        category.allocated += amount;
        category.allocated -= userVesting.amount;
        if (category.allocated > category.maxAllocation) {
            revert MaxAllocationExceed();
        }

        if (amount < userVesting.claimed + userVesting.locked) {
            revert InvalidUserVesting();
        }
        if (startTime != 0 && startTime < tgeTime) revert InvalidTimestamp();

        userVesting.amount = amount;
        userVesting.startTime = startTime == 0 ? tgeTime : startTime;

        emit UserVestingSet(categoryId, vestingId, user, amount, userVesting.startTime);
    }

    /**
     * @notice Set veTRUF token
     * @dev Only admin can set veTRUF
     * @param _veTRUF veTRUF token address
     */
    function setVeTruf(address _veTRUF) external onlyOwner {
        if (_veTRUF == address(0)) {
            revert ZeroAddress();
        }
        veTRUF = IVotingEscrow(_veTRUF);

        emit VeTrufSet(_veTRUF);
    }

    /**
     * @notice Set admin
     * @dev Only owner can set
     * @param _admin admin address
     * @param _flag true to set, false to remove
     */
    function setAdmin(address _admin, bool _flag) external onlyOwner {
        isAdmin[_admin] = _flag;

        emit AdminSet(_admin, _flag);
    }

    /**
     * @notice Initialize category by transferring TRUF tokens
     * @param _categoryId category to initialize
     */
    function initialize(uint256 _categoryId) external {
        if (isInitialized[_categoryId]) {
            revert Initialized();
        }

        isInitialized[_categoryId] = true;

        // Categories ID 0 and 7 have already been initialized previously and will be handled in `migrate` function.
        if (_categoryId != 0 && _categoryId != 7) {
            trufToken.safeTransferFrom(msg.sender, address(this), categories[_categoryId].maxAllocation);
        }
    }

    /**
     * @notice Multicall several functions in single transaction
     * @dev Could be for setting vesting categories, vesting info, and user vesting in single transaction at once
     * @param payloads list of payloads
     */
    function multicall(bytes[] calldata payloads) external {
        uint256 len = payloads.length;
        for (uint256 i; i < len;) {
            (bool success, bytes memory result) = address(this).delegatecall(payloads[i]);
            if (!success) {
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            unchecked {
                i += 1;
            }
        }
    }

    /**
     * @return emissions returns emission schedule of category
     */
    function getEmissionSchedule(uint256 categoryId) external view returns (uint256[] memory emissions) {
        emissions = emissionSchedule[categoryId];
    }

    /**
     * @return emissionLimit returns current emission limit of category
     */
    function getEmission(uint256 categoryId) public view returns (uint256 emissionLimit) {
        uint64 _tgeTime = tgeTime;

        if (block.timestamp >= _tgeTime) {
            uint256 maxAllocation = categories[categoryId].maxAllocation;

            if (emissionSchedule[categoryId].length == 0) {
                return maxAllocation;
            }
            uint64 elapsedTime = uint64(block.timestamp) - _tgeTime + ONE_MONTH;
            uint64 elapsedMonth = elapsedTime / ONE_MONTH;

            if (elapsedMonth >= emissionSchedule[categoryId].length) {
                return maxAllocation;
            }

            uint256 lastMonthEmission = elapsedMonth == 0 ? 0 : emissionSchedule[categoryId][elapsedMonth - 1];
            uint256 thisMonthEmission = emissionSchedule[categoryId][elapsedMonth];

            uint64 elapsedTimeOfLastMonth = elapsedTime % ONE_MONTH;
            emissionLimit =
                (thisMonthEmission - lastMonthEmission) * elapsedTimeOfLastMonth / ONE_MONTH + lastMonthEmission;
            if (emissionLimit > maxAllocation) {
                emissionLimit = maxAllocation;
            }
        }
    }

    /**
     * @notice Stake vesting to veTRUF to get voting power and get staking TRUF rewards
     * @param user user address
     * @param categoryId category id
     * @param vestingId vesting id
     * @param amount amount to stake
     * @param start lock start timestamp
     * @param duration lock period in seconds
     */
    function _stake(
        address user,
        uint256 categoryId,
        uint256 vestingId,
        uint256 amount,
        uint256 start,
        uint256 duration
    ) internal {
        if (isInitialized[categoryId] == false) revert Initialized();

        if (amount == 0) {
            revert ZeroAmount();
        }
        if (lockupIds[categoryId][vestingId][user] != 0) {
            revert LockExist();
        }

        UserVesting storage userVesting = userVestings[categoryId][vestingId][user];

        if (amount > userVesting.amount - userVesting.claimed - userVesting.locked) {
            revert InvalidAmount();
        }

        userVesting.locked += amount;

        trufToken.safeIncreaseAllowance(address(veTRUF), amount);
        uint256 lockupId = veTRUF.stakeVesting(amount, duration, user, start) + 1;
        lockupIds[categoryId][vestingId][user] = lockupId;

        emit Staked(categoryId, vestingId, user, amount, start, duration, lockupId);
    }
}