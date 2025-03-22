// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Ownable2Step, Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title Staking
/// @notice $BLOCK staking
contract Staking is Ownable2Step, ReentrancyGuard {
    /*==============================================================
                      CONSTANTS & IMMUTABLES
    ==============================================================*/

    /// @notice $BLOCK address
    IERC20 public immutable token;

    /*==============================================================
                       STORAGE VARIABLES
    ==============================================================*/

    struct Pool {
        uint256 poolId;
        uint256 amountLimit;
        uint256 amount;
        uint256[] lockupPeriods;
        bool paused;
        bool terminated;
    }

    struct Stake {
        uint256 poolId;
        uint256 amount;
        uint256 lockupPeriod;
        uint256 expiresAt;
        bool unstaked;
    }

    /// @notice Pool ID => Pool
    mapping(uint256 => Pool) public pools;

    /// @notice User => Stake[]
    mapping(address => Stake[]) public stakes;

    /// @notice User => Stake count
    mapping(address => uint256) public stakesCount;

    /*==============================================================
                            FUNCTIONS
    ==============================================================*/

    /// @notice Staking contract constructor
    /// @param _initialOwner Initial owner of the contract
    /// @param _token $BLOCK token address
    constructor(address _initialOwner, address _token) Ownable(_initialOwner) {
        if (_token == address(0)) {
            revert InvalidTokenAddressSet();
        }

        token = IERC20(_token);
    }

    /// @notice Stake $BLOCK tokens
    /// @param _poolId Pool ID
    /// @param _amount Amount of $BLOCK tokens to stake
    /// @param _lockupPeriod Lockup period in seconds
    function stake(
        uint256 _poolId,
        uint256 _amount,
        uint256 _lockupPeriod
    ) external nonReentrant {
        if (pools[_poolId].amountLimit == 0) {
            revert PoolDoesNotExist();
        }

        Pool memory pool = pools[_poolId];
        if (pool.terminated) {
            revert PoolIsTerminated();
        } else if (pool.paused) {
            revert PoolIsPaused();
        } else if (_amount + pool.amount > pools[_poolId].amountLimit) {
            revert ExceedsLimit();
        } else if (!_exists(pool.lockupPeriods, _lockupPeriod)) {
            revert InvalidLockupPeriod();
        }

        token.transferFrom(msg.sender, address(this), _amount);
        stakes[msg.sender].push(
            Stake({
                poolId: _poolId,
                amount: _amount,
                lockupPeriod: _lockupPeriod,
                expiresAt: block.timestamp + _lockupPeriod,
                unstaked: false
            })
        );

        stakesCount[msg.sender]++;
        pools[_poolId].amount += _amount;

        emit Staked(msg.sender, _poolId, _amount, _lockupPeriod);
    }

    /// @notice Unstake $BLOCK tokens
    /// @param _stakeIds Stake ID
    function unstake(uint256[] calldata _stakeIds) external nonReentrant {
        uint256 unstakeAmount = 0;

        for (uint256 i = 0; i < _stakeIds.length; i++) {
            Stake storage stake_ = stakes[msg.sender][_stakeIds[i]];
            if (stake_.unstaked) {
                revert AlreadyUnstaked();
            }

            Pool memory pool = pools[stake_.poolId];
            if (!pool.terminated && stake_.expiresAt > block.timestamp) {
                revert StakeNotExpired();
            }

            stake_.unstaked = true;
            unstakeAmount += stake_.amount;
        }

        token.transfer(msg.sender, unstakeAmount);

        emit Unstaked(_stakeIds);
    }

    /*==============================================================
                        ADMIN FUNCTIONS
    ==============================================================*/

    /// @notice Create a new pool
    /// @param _poolId Pool ID
    /// @param _amountLimit Total limit of the pool
    /// @param _lockupPeriods Lockup periods
    function createPool(uint256 _poolId, uint256 _amountLimit, uint256[] calldata _lockupPeriods) external onlyOwner {
        if (pools[_poolId].amountLimit != 0) {
            revert PoolAlreadyExists();
        } else if (_amountLimit == 0) {
            revert InvalidAmountLimitSet();
        }

        for (uint256 i = 0; i < _lockupPeriods.length; i++) {
            if (_lockupPeriods[i] == 0) {
                revert InvalidLockupPeriodSet();
            }
        }

        pools[_poolId] = Pool({
            poolId: _poolId,
            amountLimit: _amountLimit,
            lockupPeriods: _lockupPeriods,
            amount: 0,
            paused: false,
            terminated: false
        });
        emit PoolCreated(_poolId, _amountLimit);
    }

    /// @notice Pause a pool
    /// @param _poolId Pool ID
    function pausePool(uint256 _poolId) external onlyOwner {
        pools[_poolId].paused = true;
        emit PoolPaused(_poolId);
    }

    /// @notice Unpause a pool
    /// @param _poolId Pool ID
    function unpausePool(uint256 _poolId) external onlyOwner {
        pools[_poolId].paused = false;
        emit PoolUnpaused(_poolId);
    }

    /// @notice Terminate a pool
    /// @param _poolId Pool ID
    function terminatePool(uint256 _poolId) external onlyOwner {
        pools[_poolId].terminated = true;
        emit PoolTerminated(_poolId);
    }

    /*==============================================================
                      INTERNAL FUNCTIONS
    ==============================================================*/

    /// @notice Check if a lockup period exists
    /// @param _periods Lockup periods
    /// @param _period Lockup period
    function _exists(
        uint256[] memory _periods,
        uint256 _period
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < _periods.length; i++) {
            if (_periods[i] == _period) {
                return true;
            }
        }
        return false;
    }

    /*==============================================================
                            EVENTS
    ==============================================================*/

    /// @notice Emitted when a pool is created
    /// @param poolId Pool ID
    /// @param amountLimit Total limit of the pool
    event PoolCreated(uint256 indexed poolId, uint256 indexed amountLimit);

    /// @notice Emitted when a pool is paused
    /// @param poolId Pool ID
    event PoolPaused(uint256 indexed poolId);

    /// @notice Emitted when a pool is unpaused
    /// @param poolId Pool ID
    event PoolUnpaused(uint256 indexed poolId);

    /// @notice Emitted when a pool is terminated
    /// @param poolId Pool ID
    event PoolTerminated(uint256 indexed poolId);

    /// @notice Emitted when a user stakes to a pool
    /// @param walletAddress Address of staker
    /// @param poolId Pool ID
    /// @param amount Amount of $BLOCK tokens staked
    /// @param lockupPeriod Lockup period
    event Staked(
        address indexed walletAddress,
        uint256 indexed poolId,
        uint256 amount,
        uint256 indexed lockupPeriod
    );

    /// @notice Emitted when a user unstakes from a pool
    /// @param stakeIds Stake IDs
    event Unstaked(uint256[] indexed stakeIds);

    /*==============================================================
                            ERRORS
    ==============================================================*/

    /// @notice Error when pool does not exist
    error PoolDoesNotExist();

    /// @notice Error when pool already exists
    error PoolAlreadyExists();

    /// @notice Error when pool is paused
    error PoolIsPaused();

    /// @notice Error when pool is terminated
    error PoolIsTerminated();

    /// @notice Error when pool amount limit is exceeded
    error ExceedsLimit();

    /// @notice Error when lockup period is invalid
    error InvalidLockupPeriod();

    /// @notice Error when stake is already unstaked
    error TransferFailed();

    /// @notice Error when stake is already unstaked
    error AlreadyUnstaked();

    /// @notice Error when stake is not expired
    error StakeNotExpired();

    /// @notice Error when stake does not exist
    error StakeDoesNotExist();

    /// @notice Error when adding invalid token address
    error InvalidTokenAddressSet();

    /// @notice Error when setting invalid amount limit
    error InvalidAmountLimitSet();

    /// @notice Error when setting invalid lockup period
    error InvalidLockupPeriodSet();
}