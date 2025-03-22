// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title A Vault contract that locks up tokens
/// @author Orderly Network
/// @notice This contract is used to lock up tokens for a period of time and release them gradually
contract LockedTokenVault is Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    address _TOKEN_;

    mapping(address => uint256) internal originBalances;
    mapping(address => uint256) internal claimedBalances;
    mapping(address => uint256) internal startReleaseTime;
    mapping(address => uint256) internal releaseDuration;
    mapping(address => uint256) internal cliffTime;

    uint256 public _UNDISTRIBUTED_AMOUNT_;

    // ============ constant ============

    uint256 constant ONE = 10 ** 18;

    // ============ Events & Error ============

    event Claim(
        address indexed holder,
        uint256 origin,
        uint256 claimed,
        uint256 amount
    );

    error BatchGrantLengthNotMatch();
    error CliffTimeBeforeStartTime();
    error CliffTimeTooLate();
    error AmountZero();
    error DurationZero();

    // ============ Init Functions ============

    constructor(address initialOwner, address _token) Ownable(initialOwner) {
        _TOKEN_ = _token;
    }

    function deposit(uint256 amount) external onlyOwner {
        _tokenTransferIn(owner(), amount);
        _UNDISTRIBUTED_AMOUNT_ = _UNDISTRIBUTED_AMOUNT_ + amount;
    }

    function withdraw(uint256 amount) external onlyOwner {
        _UNDISTRIBUTED_AMOUNT_ = _UNDISTRIBUTED_AMOUNT_ - amount;
        _tokenTransferOut(owner(), amount);
    }

    // ============ For Owner ============

    /// @notice Grant token to the holder
    /// @dev all the list should have the same length
    /// @dev support regrant, the new grant will overwrite the old one, and the balance will be accumulated
    /// @param holderList holder list, the address of the holder
    /// @param amountList amount list, the amount of token to grant
    /// @param startList start time list, the timestamp when the token start to release
    /// @param durationList duration list, the duration of the release
    /// @param cliffList cliff time list, the timestamp when the token is able to claim
    function grant(
        address[] calldata holderList,
        uint256[] calldata amountList,
        uint256[] calldata startList,
        uint256[] calldata durationList,
        uint256[] calldata cliffList
    ) external onlyOwner {
        if (holderList.length != amountList.length)
            revert BatchGrantLengthNotMatch();
        if (holderList.length != startList.length)
            revert BatchGrantLengthNotMatch();
        if (holderList.length != durationList.length)
            revert BatchGrantLengthNotMatch();
        if (holderList.length != cliffList.length)
            revert BatchGrantLengthNotMatch();
        uint256 amount = 0;
        for (uint256 i = 0; i < holderList.length; ++i) {
            address holder = holderList[i];
            if (cliffList[i] < startList[i]) {
                revert CliffTimeBeforeStartTime();
            }
            if (cliffList[i] > startList[i] + durationList[i]) {
                revert CliffTimeTooLate();
            }
            if (amountList[i] == 0) {
                revert AmountZero();
            }
            if (durationList[i] == 0) {
                revert DurationZero();
            }
            originBalances[holder] = originBalances[holder] + amountList[i];
            startReleaseTime[holder] = startList[i];
            releaseDuration[holder] = durationList[i];
            cliffTime[holder] = cliffList[i];
            amount = amount + amountList[i];
        }
        _UNDISTRIBUTED_AMOUNT_ = _UNDISTRIBUTED_AMOUNT_ - amount;
    }

    /// @notice recall the token from the holder, all the token will be returned to the owner
    /// @param holder holder address
    function recall(address holder) external onlyOwner {
        _UNDISTRIBUTED_AMOUNT_ =
            _UNDISTRIBUTED_AMOUNT_ +
            originBalances[holder] -
            claimedBalances[holder];
        originBalances[holder] = 0;
        claimedBalances[holder] = 0;
        startReleaseTime[holder] = 0;
        releaseDuration[holder] = 0;
        cliffTime[holder] = 0;
    }

    // ============ For Holder ============

    /// @notice claim the token that is able to claim
    function claim() external {
        uint256 claimableToken = getClaimableBalance(msg.sender);
        claimedBalances[msg.sender] =
            claimedBalances[msg.sender] +
            claimableToken;
        _tokenTransferOut(msg.sender, claimableToken);
        emit Claim(
            msg.sender,
            originBalances[msg.sender],
            claimedBalances[msg.sender],
            claimableToken
        );
    }

    // ============ View ============

    function isReleaseStart(address holder) external view returns (bool) {
        return block.timestamp >= startReleaseTime[holder];
    }

    function isCliffStart(address holder) external view returns (bool) {
        return block.timestamp >= cliffTime[holder];
    }

    function getStartReleaseTime(
        address holder
    ) external view returns (uint256) {
        return startReleaseTime[holder];
    }

    function getReleaseDuration(
        address holder
    ) external view returns (uint256) {
        return releaseDuration[holder];
    }

    function getOriginBalance(address holder) external view returns (uint256) {
        return originBalances[holder];
    }

    function getClaimedBalance(address holder) external view returns (uint256) {
        return claimedBalances[holder];
    }

    function getCliffTime(address holder) external view returns (uint256) {
        return cliffTime[holder];
    }

    function getClaimableBalance(address holder) public view returns (uint256) {
        // first check if the cliff time is passed
        if (block.timestamp < cliffTime[holder]) {
            return 0;
        }
        uint256 remainingToken = getRemainingBalance(holder);
        // regrant may cause `claimableToken - claimedBalances[holder]` to be negative
        uint256 claimableToken = originBalances[holder] - remainingToken;
        if (claimableToken < claimedBalances[holder]) {
            return 0;
        } else {
            return claimableToken - claimedBalances[holder];
        }
    }

    function getRemainingBalance(address holder) public view returns (uint256) {
        uint256 remainingRatio = getRemainingRatio(block.timestamp, holder);
        return originBalances[holder].mulDiv(remainingRatio, ONE);
    }

    function getRemainingRatio(
        uint256 timestamp,
        address holder
    ) public view returns (uint256) {
        if (timestamp < startReleaseTime[holder]) {
            return ONE;
        }
        uint256 timePast = timestamp - startReleaseTime[holder];
        if (timePast < releaseDuration[holder]) {
            uint256 remainingTime = releaseDuration[holder] - timePast;
            return ONE.mulDiv(remainingTime, releaseDuration[holder]);
        } else {
            return 0;
        }
    }

    // ============ Internal Helper ============

    function _tokenTransferIn(address from, uint256 amount) internal {
        IERC20(_TOKEN_).safeTransferFrom(from, address(this), amount);
    }

    function _tokenTransferOut(address to, uint256 amount) internal {
        IERC20(_TOKEN_).safeTransfer(to, amount);
    }
}