// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPrimeCaching, Deposit} from "./interfaces/IPrimeCaching.sol";
import {IInvokeEchelonHandler} from "./interfaces/IInvokeEchelonHandler.sol";

/**
 * @title PrimeCaching
 * @notice Contract for caching PRIME tokens
 */
contract PrimeCaching is Context, IPrimeCaching, IInvokeEchelonHandler {
    using SafeERC20 for IERC20;

    /// @notice Deposit mapping for each user
    mapping(address => Deposit[]) public deposits;

    /// @notice Prime token
    IERC20 public primeToken;

    /// @notice Final timestamp for lock duration
    uint256 public immutable MAX_LOCK_TIMESTAMP;

    /// @notice Maximum lock duration, 3 years
    uint256 public constant MAX_LOCK_DURATION = 1095 days;

    constructor(address primeTokenAddress, uint256 maxLockTimestamp) {
        primeToken = IERC20(primeTokenAddress);
        MAX_LOCK_TIMESTAMP = maxLockTimestamp;
    }

    /**
     * @notice Function invoked by the prime token contract to handle totalCardCount increase and emit payment event
     * @param from The address of the original msg.sender
     * @param primeAmount The amount of prime that was sent from the prime token contract
     * @param data Catch-all param to allow the caller to pass additional data to the handler,
     *      includes the lock duration of the deposit
     */
    function handleInvokeEchelon(
        address from,
        address,
        address,
        uint256,
        uint256,
        uint256 primeAmount,
        bytes memory data
    ) external payable {
        require(_msgSender() == address(primeToken), "Invalid invoker");

        require(primeAmount > 1 ether, "Amount must be greater than one");

        uint256 lockDuration = abi.decode(data, (uint256));

        uint256 endTimestamp = _getEndTimestamp(
            lockDuration,
            block.timestamp,
            block.timestamp
        );

        deposits[from].push(
            Deposit(
                primeAmount,
                endTimestamp,
                block.timestamp,
                block.timestamp,
                false
            )
        );

        emit DepositCreated(
            from,
            deposits[from].length - 1,
            primeAmount,
            endTimestamp,
            block.timestamp
        );
    }

    /**
     * @notice Extends the lock duration of a deposit
     * @param depositIndex Index of the deposit to extend
     * @param lockDuration Duration in seconds to extend the lock
     *      Use type(uint256).max for infinite lock duration
     */
    function extendDeposit(
        uint256 depositIndex,
        uint256 lockDuration
    ) external {
        require(
            depositIndex < deposits[_msgSender()].length,
            "Invalid deposit index"
        );

        Deposit storage deposit = deposits[_msgSender()][depositIndex];
        require(
            block.timestamp < deposit.endTimestamp,
            "Deposit has already ended"
        );

        deposit.endTimestamp = _getEndTimestamp(
            lockDuration,
            deposit.endTimestamp,
            deposit.createdTimestamp
        );

        deposit.updatedTimestamp = block.timestamp;

        emit DepositExtended(
            _msgSender(),
            depositIndex,
            deposit.endTimestamp,
            deposit.createdTimestamp,
            deposit.updatedTimestamp
        );
    }

    /**
     * @notice Gets the number of deposits for a user
     * @param user The address of the user
     */
    function getDepositCount(address user) external view returns (uint256) {
        return deposits[user].length;
    }

    /**
     * Returns list of deposits for a user
     * @param user The address of the user
     * @param fromIndex The starting index of the deposits
     * @param toIndex The ending index of the deposits
     * @return depositList List deposit info
     */
    function getDeposits(
        address user,
        uint256 fromIndex,
        uint256 toIndex
    ) external view returns (Deposit[] memory depositList) {
        require(fromIndex <= toIndex, "Invalid index inputs");
        require(toIndex < deposits[user].length, "Invalid index range");

        uint256 numDeposits = toIndex - fromIndex + 1;
        depositList = new Deposit[](numDeposits);

        for (uint256 i = 0; i < numDeposits; i++) {
            depositList[i] = deposits[user][fromIndex + i];
        }
    }

    /**
     * @notice Withdraws list of deposits
     * @param depositIndexes Indexes of deposits to withdraw
     */
    function withdrawDeposits(uint256[] calldata depositIndexes) external {
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < depositIndexes.length; i++) {
            require(
                depositIndexes[i] < deposits[_msgSender()].length,
                "Invalid deposit index"
            );

            Deposit storage deposit = deposits[_msgSender()][depositIndexes[i]];
            require(
                block.timestamp >= deposit.endTimestamp,
                "Deposit has not ended yet"
            );
            require(!deposit.isWithdrawn, "Deposit has already been withdrawn");

            deposit.isWithdrawn = true;
            deposit.updatedTimestamp = block.timestamp;
            totalAmount += deposit.amount;
        }

        primeToken.safeTransfer(_msgSender(), totalAmount);

        emit DepositsWithdrawn(
            _msgSender(),
            depositIndexes,
            totalAmount,
            block.timestamp
        );
    }

    /**
     * @notice Gets the end timestamp of a deposit
     * @param lockDuration Duration in seconds to extend the lock
     * @param endTimestamp End timestamp of the deposit
     * @param createdTimestamp Created timestamp of the deposit
     */
    function _getEndTimestamp(
        uint256 lockDuration,
        uint256 endTimestamp,
        uint256 createdTimestamp
    ) internal view returns (uint256) {
        require(
            lockDuration >= 21 days,
            "Lock duration must be at least 21 days"
        );

        if (lockDuration == type(uint256).max) {
            if (createdTimestamp + MAX_LOCK_DURATION > MAX_LOCK_TIMESTAMP) {
                return MAX_LOCK_TIMESTAMP;
            } else {
                return createdTimestamp + MAX_LOCK_DURATION;
            }
        } else {
            if (
                lockDuration > MAX_LOCK_DURATION ||
                lockDuration + endTimestamp > MAX_LOCK_TIMESTAMP ||
                endTimestamp - createdTimestamp + lockDuration >
                MAX_LOCK_DURATION
            ) {
                revert("Total lock duration must be less than 1095 days");
            }

            return endTimestamp + lockDuration;
        }
    }
}