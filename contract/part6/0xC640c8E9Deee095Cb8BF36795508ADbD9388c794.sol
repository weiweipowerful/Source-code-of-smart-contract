// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20Burnable} from "./interfaces/IERC20Burnable.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MerkleVestingV2 is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant THRESHOLD = 20_000_000 * 1e18;
    uint32 public constant VESTING_PERIOD = 1 days;

    address public immutable TOKEN;

    bool public emergency;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public pausedTime;
    bytes32 public merkleRoot;

    uint256 private _internalStartTime;

    mapping(address => uint256) public claimed;
    mapping(address => bool) public blacklist;

    event BurnedAfterEnd(uint256 amount);
    event EndTimeChanged(uint256 newEndTime);
    event PauseTimeChanged(uint256 newPauseTime);
    event Initialized(bytes32 root, uint256 start);
    event Claim(address indexed user, uint256 amount);
    event TokenRecovered(address token, uint256 amount);
    event BlacklistUpdated(address[] users, bool isBlacklisted);
    event EmergencyWithdrawed(address receiver, uint256 amount);

    error ZeroInput();
    error EmergencyStopped();
    error WrongUintInput(uint256 value);
    error Blacklisted(address user);
    error AlreadySetted(uint256 currentStart);
    error InvalidProof(address user, uint256 amount, bytes32[] proof);
    error WrongTimeInterval(uint256 current, uint256 start, uint256 end);

    constructor(address _token, address _owner) Ownable(_owner) {
        TOKEN = _token;
    }

    // modifiers

    modifier notEmergency() {
        if (emergency) revert EmergencyStopped();
        _;
    }

    // ownable methods

    /** @notice Set @param _startTime and @param _merkleRoot for initial vesting setup
     * @dev For owner only
     */
    function setStartTime(
        uint256 _startTime,
        bytes32 _merkleRoot
    ) external onlyOwner {
        if (startTime > 0) revert AlreadySetted(_startTime);
        if (_startTime < block.timestamp) revert WrongUintInput(_startTime);
        if (_merkleRoot == bytes32(0)) revert ZeroInput();
        startTime = _startTime;
        endTime = _startTime + 50 * VESTING_PERIOD;
        merkleRoot = _merkleRoot;

        _internalStartTime = _startTime;

        emit Initialized(_merkleRoot, _startTime);
    }

    /** @notice Withdraws stuck @param token in specified @param amount
     * @dev For owner only
     */
    function recoverERC20(
        address token,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (token == address(0) || amount == 0 || token == TOKEN)
            revert ZeroInput();

        IERC20(token).safeTransfer(_msgSender(), amount);

        emit TokenRecovered(token, amount);
    }

    /** @notice Disable `claim` operations
     * @dev For owner only
     */
    function pause() external onlyOwner notEmergency {
        uint256 currentTime = block.timestamp;
        if (startTime == 0 || currentTime >= endTime || currentTime < startTime)
            revert WrongTimeInterval(currentTime, startTime, endTime);

        pausedTime = currentTime;
        _pause();

        emit PauseTimeChanged(currentTime);
    }

    /** @notice Resume `claim` operations
     * @dev For owner only
     */
    function unpause() external onlyOwner notEmergency {
        uint256 difference = block.timestamp - pausedTime;
        uint256 newEndTime = endTime + difference;
        endTime = newEndTime;
        _internalStartTime += difference;
        delete pausedTime;
        _unpause();

        emit PauseTimeChanged(0);
        emit EndTimeChanged(newEndTime);
    }

    /** Add/remove @param users from/to blacklist
     * @param isBlacklisted user's status in blacklist (true - in, false - out)
     * @dev For owner only
     */
    function updateBlacklist(
        address[] calldata users,
        bool isBlacklisted
    ) external onlyOwner {
        uint256 len = users.length;
        if (len == 0) revert ZeroInput();
        for (uint256 i; i < len; ) {
            blacklist[users[i]] = isBlacklisted;
            unchecked {
                ++i;
            }
        }

        emit BlacklistUpdated(users, isBlacklisted);
    }

    /** @notice Increase `endTime` to allow users make `claim` later
     * @param newEndTime new `endTime` value (timestamp)
     * @dev For owner only
     */
    function extendClaimPeriod(
        uint256 newEndTime
    ) external onlyOwner notEmergency whenNotPaused {
        uint256 currentTime = block.timestamp;
        if (startTime == 0 || currentTime >= endTime)
            revert WrongTimeInterval(currentTime, startTime, endTime);

        if (newEndTime < endTime) revert WrongUintInput(newEndTime);

        endTime = newEndTime;

        emit EndTimeChanged(newEndTime);
    }

    /** @notice Transfers all unclaimed tokens to the treasury wallet in case of an emergency
     * @param receiver of unclaimed tokens
     * @dev For owner only
     */
    function emergencyWithdrawFunds(
        address receiver
    ) external onlyOwner notEmergency nonReentrant {
        uint256 currentTime = block.timestamp;
        if (startTime == 0 || currentTime >= endTime)
            revert WrongTimeInterval(currentTime, startTime, endTime);

        if (receiver == address(0)) revert ZeroInput();

        emergency = true;

        uint256 toWithdraw = getTotalUnclaimed();
        IERC20(TOKEN).safeTransfer(receiver, toWithdraw);

        emit EmergencyWithdrawed(receiver, toWithdraw);
    }

    // public methods

    /** @notice Allows users to claim tokens based on their daily unlocked amount and Merkle proof
     * @param totalAmount of locked tokens for sender
     * @param proof of user’s total allocation
     */
    function claim(
        uint256 totalAmount,
        bytes32[] calldata proof
    ) external whenNotPaused notEmergency nonReentrant {
        uint256 currentTime = block.timestamp;
        address sender = _msgSender();

        if (blacklist[sender]) revert Blacklisted(sender);

        if (startTime == 0 || currentTime < startTime || currentTime >= endTime)
            revert WrongTimeInterval(currentTime, startTime, endTime);

        if (!verifyClaim(sender, totalAmount, proof))
            revert InvalidProof(sender, totalAmount, proof);

        uint256 amountToClaim = claimable(sender, totalAmount);
        if (amountToClaim > 0) {
            claimed[sender] += amountToClaim;
            IERC20(TOKEN).safeTransfer(sender, amountToClaim);
        }

        emit Claim(sender, amountToClaim);
    }

    /** @notice Manually burns any leftover tokens in the contract at the end of the claim period
     */
    function burn() external whenNotPaused notEmergency nonReentrant {
        uint256 currentTime = block.timestamp;
        if (startTime == 0 || currentTime < endTime)
            revert WrongTimeInterval(currentTime, startTime, endTime);

        uint256 toBurn = getTotalUnclaimed();
        IERC20Burnable(TOKEN).burn(toBurn);
        emit BurnedAfterEnd(toBurn);
    }

    // view methods

    /** @notice Helper function to calculate how many days have passed since the claim start date + 1
     * @return num of current day in claim period (counting starts from 1, not from 0)
     */
    function currentPeriod() public view returns (uint256) {
        if (startTime > block.timestamp || startTime == 0) {
            return 0;
        }
        return ((_getRightBorder() - _internalStartTime) / VESTING_PERIOD) + 1;
    }

    /** @notice Calculates the number of tokens a user can claim at the current time
     * @param user address
     * @param totalAmount of locked tokens for user
     * @return amountToClaim
     */
    function claimable(
        address user,
        uint256 totalAmount
    ) public view returns (uint256 amountToClaim) {
        uint256 percentage = totalAmount >= THRESHOLD ? 2 : 5;
        amountToClaim = (totalAmount * percentage * currentPeriod()) / 100;
        if (amountToClaim > totalAmount) amountToClaim = totalAmount;
        amountToClaim -= claimed[user];
    }

    /** @notice Returns the total number of unclaimed tokens remaining in the contract
     * @return balance of this contract in CHEDDA tokens
     */
    function getTotalUnclaimed() public view returns (uint256) {
        return IERC20(TOKEN).balanceOf(address(this));
    }

    /** @notice Verifies the validity of a user’s claim using their Merkle proof and the Merkle root
     * @param user address
     * @param amount of locked tokens for user
     * @param merkleProof of user’s total allocation
     * @return true - proof is valid, else - false
     */
    function verifyClaim(
        address user,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        return
            MerkleProof.verifyCalldata(
                merkleProof,
                merkleRoot,
                keccak256(abi.encode(user, amount))
            );
    }

    // private methods

    function _getRightBorder() private view returns (uint256) {
        if (paused()) return pausedTime;
        else return Math.min(block.timestamp, endTime);
    }
}