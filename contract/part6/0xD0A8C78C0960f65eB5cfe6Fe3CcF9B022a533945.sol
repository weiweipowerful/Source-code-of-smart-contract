// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// +========================================================+
// | ██╗          ██████╗███████╗   ███████╗██╗         ██╗ |
// |██╔╝         ██╔════╝██╔════╝   ██╔════╝██║         ╚██╗|
// |██║█████╗    ██║     █████╗     █████╗  ██║    █████╗██║|
// |██║╚════╝    ██║     ██╔══╝     ██╔══╝  ██║    ╚════╝██║|
// |╚██╗         ╚██████╗███████╗██╗██║     ██║         ██╔╝|
// | ╚═╝          ╚═════╝╚══════╝╚═╝╚═╝     ╚═╝         ╚═╝ |
// +========================================================+
//Visit https://CE.FI
//CE.FI: Decentralized AI-Driven Finance for Real-World Assets
//Stake with Confidence for Optimal APR Powered by DeFi, AI, and RWA!

//⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡
//─────────────────────────────────────────────────────────────────────────────────────────────────────
//─██████─██████─██████─██████████████─██████─────────██████████████─████████████████───██████████████─
//─██░░██─██░░██─██░░██─██░░░░░░░░░░██─██░░██─────────██░░░░░░░░░░██─██░░░░░░░░░░░░██───██░░░░░░░░░░██─
//─██░░██─██░░██─██░░██─██░░██████░░██─██░░██─────────██░░██████████─██░░████████░░██───██████░░██████─
//─██░░██─██░░██─██░░██─██░░██──██░░██─██░░██─────────██░░██─────────██░░██────██░░██───────██░░██─────
//─██░░██─██░░██─██░░██─██░░██████░░██─██░░██─────────██░░██████████─██░░████████░░██───────██░░██─────
//─██░░██─██░░██─██░░██─██░░░░░░░░░░██─██░░██─────────██░░░░░░░░░░██─██░░░░░░░░░░░░██───────██░░██─────
//─██████─██████─██████─██░░██████░░██─██░░██─────────██░░██████████─██░░██████░░████───────██░░██─────
//──────────────────────██░░██──██░░██─██░░██─────────██░░██─────────██░░██──██░░██─────────██░░██─────
//─██████─██████─██████─██░░██──██░░██─██░░██████████─██░░██████████─██░░██──██░░██████─────██░░██─────
//─██░░██─██░░██─██░░██─██░░██──██░░██─██░░░░░░░░░░██─██░░░░░░░░░░██─██░░██──██░░░░░░██─────██░░██─────
//─██████─██████─██████─██████──██████─██████████████─██████████████─██████──██████████─────██████─────
//─────────────────────────────────────────────────────────────────────────────────────────────────────
//⚠️ Encounter a bug or issue? Email [email protected] to report and earn a bounty reward! 🚀
//💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡💡


import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract CeFidApp is ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    address public admin;

    struct DepositRecord {
        uint256 amount;
        uint256 depositTime;
        bool withdrawn;
        uint256 lockInTime; // Added: Store lock-in time at deposit
        uint256 interestRate; // Added: Store interest rate at deposit
    }

    struct Pool {
        uint256 poolSize;
        uint256 interestRate;
        uint256 lockInTime;
        uint256 totalDeposits;
        uint256 lastUpdated;
        bool isETHPool;
        address tokenAddress;
        uint256 managerWithdrawals; // Added: Track manager withdrawals
        mapping(address => DepositRecord[]) deposits;
        address[] depositors;
    }

    struct Manager {
        uint256 limit;
        bool isActive;
    }

    mapping(uint256 => Pool) public pools;
    mapping(address => Manager) public managers;
    uint256 public poolCount;

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 reward
    );
    event ManagerWithdraw(
        address indexed manager,
        uint256 indexed poolId,
        uint256 amount
    );
    event PoolCreated(
        uint256 indexed poolId,
        bool isETHPool,
        address tokenAddress
    );
    event PoolUpdated(
        uint256 indexed poolId,
        uint256 interestRate,
        uint256 lockInTime
    );
    event ManagerAdded(address indexed manager, uint256 limit);
    event ManagerLimitUpdated(address indexed manager, uint256 newLimit);
    event ManagerRemoved(address indexed manager);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not an admin");
        _;
    }

    modifier onlyManager() {
        require(hasRole(MANAGER_ROLE, msg.sender), "Not a manager");
        _;
    }

    modifier validPool(uint256 poolId) {
        require(poolId < poolCount, "Invalid pool ID");
        _;
    }

    constructor() {
        admin = msg.sender;
        _grantRole(ADMIN_ROLE, admin);
    }

    // 🔹 ADMIN FUNCTIONS
    function addETHPool(
        uint256 poolSize,
        uint256 interestRate,
        uint256 lockInTime
    ) public onlyAdmin whenNotPaused {
        require(poolSize > 0, "Invalid pool size");
        require(interestRate > 0, "Interest rate must be greater than 0");
        require(lockInTime > 0, "Lock-in time must be greater than 0");

        uint256 poolId = poolCount++;
        Pool storage pool = pools[poolId];
        pool.poolSize = poolSize;
        pool.interestRate = interestRate;
        pool.lockInTime = lockInTime;
        pool.isETHPool = true;
        pool.tokenAddress = address(0);
        pool.lastUpdated = block.timestamp;

        emit PoolCreated(poolId, true, address(0));
    }

    function addERC20Pool(
        uint256 poolSize,
        uint256 interestRate,
        uint256 lockInTime,
        address tokenAddress
    ) public onlyAdmin whenNotPaused {
        require(poolSize > 0, "Invalid pool size");
        require(interestRate > 0, "Interest rate must be greater than 0");
        require(lockInTime > 0, "Lock-in time must be greater than 0");
        require(tokenAddress != address(0), "Invalid token address");

        uint256 poolId = poolCount++;
        Pool storage pool = pools[poolId];
        pool.poolSize = poolSize;
        pool.interestRate = interestRate;
        pool.lockInTime = lockInTime;
        pool.isETHPool = false;
        pool.tokenAddress = tokenAddress;
        pool.lastUpdated = block.timestamp;

        emit PoolCreated(poolId, false, tokenAddress);
    }

    function updatePool(
        uint256 poolId,
        uint256 interestRate,
        uint256 lockInTime
    ) public onlyAdmin validPool(poolId) whenNotPaused {
        require(interestRate > 0, "Interest rate must be greater than 0");
        require(lockInTime > 0, "Lock-in time must be greater than 0");

        Pool storage pool = pools[poolId];
        pool.interestRate = interestRate;
        pool.lockInTime = lockInTime;

        emit PoolUpdated(poolId, interestRate, lockInTime);
    }

    function addManager(address manager, uint256 limit)
        public
        onlyAdmin
        whenNotPaused
    {
        require(manager != address(0), "Invalid manager address");
        require(limit > 0, "Limit must be greater than 0");

        managers[manager] = Manager({limit: limit, isActive: true});
        _grantRole(MANAGER_ROLE, manager);

        emit ManagerAdded(manager, limit);
    }

    function updateManagerLimit(address manager, uint256 newLimit)
        public
        onlyAdmin
        whenNotPaused
    {
        require(newLimit > 0, "New limit must be greater than 0");
        require(managers[manager].isActive, "Manager is not active");

        managers[manager].limit = newLimit;

        emit ManagerLimitUpdated(manager, newLimit);
    }

    function removeManager(address manager) public onlyAdmin whenNotPaused {
        require(managers[manager].isActive, "Manager is not active");

        managers[manager].isActive = false;
        _revokeRole(MANAGER_ROLE, manager);

        emit ManagerRemoved(manager);
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    // 🔹 USER FUNCTIONS
    function deposit(uint256 poolId, uint256 amount)
        public
        payable
        nonReentrant
        validPool(poolId)
        whenNotPaused
    {
        require(amount > 0, "Deposit amount must be greater than 0");

        Pool storage pool = pools[poolId];
        require(
            pool.totalDeposits + amount <= pool.poolSize,
            "Exceeds pool size"
        );

        if (pool.isETHPool) {
            require(msg.value == amount, "ETH amount mismatch");
            pool.totalDeposits += msg.value;
        } else {
            IERC20(pool.tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
            pool.totalDeposits += amount;
        }

        if (pool.deposits[msg.sender].length == 0) {
            pool.depositors.push(msg.sender);
        }

        pool.deposits[msg.sender].push(
            DepositRecord({
                amount: amount,
                depositTime: block.timestamp,
                withdrawn: false,
                lockInTime: pool.lockInTime, // Store lock-in time
                interestRate: pool.interestRate // Store interest rate
            })
        );

        pool.lastUpdated = block.timestamp;

        emit Deposit(msg.sender, poolId, amount);
    }

    function withdraw(uint256 poolId)
        public
        nonReentrant
        validPool(poolId)
        whenNotPaused
    {
        Pool storage pool = pools[poolId];
        uint256 totalWithdrawable = 0;
        uint256 totalReward = 0;

        DepositRecord[] storage userDeposits = pool.deposits[msg.sender];

        for (uint256 i = 0; i < userDeposits.length; ) {
            DepositRecord storage depositRecord = userDeposits[i];

            if (
                !depositRecord.withdrawn &&
                block.timestamp >=
                depositRecord.depositTime + depositRecord.lockInTime // Use stored lock-in time
            ) {
                uint256 reward = (depositRecord.amount *
                    depositRecord.interestRate * // Use stored interest rate
                    (block.timestamp - depositRecord.depositTime)) /
                    (365 days * 10000);
                totalReward += reward;
                totalWithdrawable += depositRecord.amount;
                depositRecord.withdrawn = true;
            }

            unchecked {
                i++;
            }
        }

        require(totalWithdrawable > 0, "No unlocked funds to withdraw");

        pool.totalDeposits -= totalWithdrawable;
        uint256 totalPayout = totalWithdrawable + totalReward;

        require(
            getAvailablePoolBalance(poolId) >= totalPayout,
            "Insufficient contract balance"
        );

        if (pool.isETHPool) {
            (bool success, ) = msg.sender.call{value: totalPayout}("");
            require(success, "ETH withdrawal failed");
        } else {
            IERC20(pool.tokenAddress).safeTransfer(msg.sender, totalPayout);
        }

        emit Withdraw(msg.sender, poolId, totalWithdrawable, totalReward);
    }

    // 🔹 MANAGER FUNCTIONS
    function withdrawByManager(uint256 poolId, uint256 amount)
        public
        nonReentrant
        onlyManager
        validPool(poolId)
        whenNotPaused
    {
        Pool storage pool = pools[poolId];
        Manager storage manager = managers[msg.sender];

        require(manager.isActive, "Manager is inactive");
        require(amount > 0, "Withdrawal amount must be greater than 0");
        require(amount <= manager.limit, "Exceeds manager's withdrawal limit");
        require(
            getAvailablePoolBalance(poolId) >= amount,
            "Insufficient pool balance"
        );

        // Update manager's limit and pool state
        manager.limit -= amount;
        pool.managerWithdrawals += amount; // Track manager withdrawals

        // Transfer funds
        if (pool.isETHPool) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH withdrawal failed");
        } else {
            IERC20(pool.tokenAddress).safeTransfer(msg.sender, amount);
        }

        emit ManagerWithdraw(msg.sender, poolId, amount);
    }

    // 🔹 PUBLIC READ FUNCTIONS
    function getDepositors(uint256 poolId)
        public
        view
        validPool(poolId)
        returns (address[] memory)
    {
        return pools[poolId].depositors;
    }

    function getUserDeposits(uint256 poolId, address user)
        public
        view
        validPool(poolId)
        returns (DepositRecord[] memory)
    {
        return pools[poolId].deposits[user];
    }

    function getTotalDeposits(uint256 poolId)
        public
        view
        validPool(poolId)
        returns (uint256)
    {
        return pools[poolId].totalDeposits;
    }

    function getPoolSize(uint256 poolId)
        public
        view
        validPool(poolId)
        returns (uint256)
    {
        return pools[poolId].poolSize;
    }

    function getPoolPercentageFull(uint256 poolId)
        public
        view
        validPool(poolId)
        returns (uint256)
    {
        Pool storage pool = pools[poolId];
        require(pool.poolSize > 0, "Pool size must be greater than 0");
        return (pool.totalDeposits * 100) / pool.poolSize;
    }

    function getUserDeposit(uint256 poolId, address user)
        public
        view
        validPool(poolId)
        returns (uint256)
    {
        uint256 totalDeposit = 0;
        DepositRecord[] storage userDeposits = pools[poolId].deposits[user];

        for (uint256 i = 0; i < userDeposits.length; ) {
            if (!userDeposits[i].withdrawn) {
                totalDeposit += userDeposits[i].amount;
            }
            unchecked {
                i++;
            }
        }

        return totalDeposit;
    }

    function getUserReward(uint256 poolId, address user)
        public
        view
        validPool(poolId)
        returns (uint256)
    {
        Pool storage pool = pools[poolId];
        uint256 totalReward = 0;

        DepositRecord[] storage userDeposits = pool.deposits[user];

        for (uint256 i = 0; i < userDeposits.length; ) {
            DepositRecord storage depositRecord = userDeposits[i];

            // Only calculate reward for non-withdrawn deposits
            if (!depositRecord.withdrawn) {
                uint256 timeElapsed = block.timestamp -
                    depositRecord.depositTime;
                uint256 reward = (depositRecord.amount *
                    depositRecord.interestRate *
                    timeElapsed) / (365 days * 10000);
                totalReward += reward;
            }

            unchecked {
                i++;
            }
        }

        return totalReward;
    }

    function getMaxWithdrawableAmount(uint256 poolId, address user)
        public
        view
        validPool(poolId)
        returns (uint256, uint256)
    {
        Pool storage pool = pools[poolId];
        uint256 totalWithdrawable = 0;
        uint256 totalReward = 0;

        DepositRecord[] storage userDeposits = pool.deposits[user];

        for (uint256 i = 0; i < userDeposits.length; ) {
            DepositRecord storage depositRecord = userDeposits[i];

            if (
                !depositRecord.withdrawn &&
                block.timestamp >=
                depositRecord.depositTime + depositRecord.lockInTime
            ) {
                uint256 reward = (depositRecord.amount *
                    depositRecord.interestRate *
                    (block.timestamp - depositRecord.depositTime)) /
                    (365 days * 10000);
                totalReward += reward;
                totalWithdrawable += depositRecord.amount;
            }

            unchecked {
                i++;
            }
        }

        return (totalWithdrawable, totalReward);
    }

    function getAvailablePoolBalance(uint256 poolId)
        public
        view
        validPool(poolId)
        returns (uint256)
    {
        Pool storage pool = pools[poolId];
        if (pool.isETHPool) {
            return address(this).balance - pool.managerWithdrawals;
        } else {
            return
                IERC20(pool.tokenAddress).balanceOf(address(this)) -
                pool.managerWithdrawals;
        }
    }

    function getInterestRate(uint256 poolId)
        public
        view
        validPool(poolId)
        returns (uint256)
    {
        return pools[poolId].interestRate;
    }

    function getLockInTime(uint256 poolId)
        public
        view
        validPool(poolId)
        returns (uint256)
    {
        return pools[poolId].lockInTime;
    }

    function getIsETHPool(uint256 poolId)
        public
        view
        validPool(poolId)
        returns (bool)
    {
        return pools[poolId].isETHPool;
    }

    function getTokenAddress(uint256 poolId)
        public
        view
        validPool(poolId)
        returns (address)
    {
        return pools[poolId].tokenAddress;
    }

    function getUnlockTimeAndAmountsForActiveDeposits(
        uint256 poolId,
        address user
    )
        public
        view
        validPool(poolId)
        returns (uint256[] memory unlockTimestamps, uint256[] memory amounts)
    {
        Pool storage pool = pools[poolId];
        DepositRecord[] storage userDeposits = pool.deposits[user];

        // Count the number of active deposits (not withdrawn)
        uint256 activeCount = 0;
        for (uint256 i = 0; i < userDeposits.length; i++) {
            if (!userDeposits[i].withdrawn) {
                activeCount++;
            }
        }

        // Initialize arrays to store the unlock timestamps and amounts
        unlockTimestamps = new uint256[](activeCount);
        amounts = new uint256[](activeCount);
        uint256 index = 0;

        // Iterate through deposits and collect unlock timestamps and amounts for active deposits
        for (uint256 i = 0; i < userDeposits.length; i++) {
            DepositRecord storage depositRecord = userDeposits[i];

            if (!depositRecord.withdrawn) {
                uint256 unlockTimestamp = depositRecord.depositTime +
                    depositRecord.lockInTime;
                unlockTimestamps[index] = unlockTimestamp;
                amounts[index] = depositRecord.amount;
                index++;
            }
        }

        return (unlockTimestamps, amounts);
    }
}