// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; 
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SharpeStake is ReentrancyGuard{
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken;

    address public owner;
    uint256 public timeLock;
    uint Counter;

    struct Deposit {
        uint256 amount;
        uint256 timestamp;
    }
    
    mapping(address => mapping(uint => Deposit)) public userDeposits;

    // Events
    event Staked(address indexed user, uint256 depositId, uint256 amount, uint256 timestamp);
    event Unstaked(address indexed user, uint256 depositId, uint256 amount, uint256 timestamp);

    constructor(address _owner, address _stakingToken, uint _timeLock) {
        owner = _owner;
        stakingToken = IERC20(_stakingToken);
        timeLock = _timeLock;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    function stake(uint256 _amount) external nonReentrant{
        require(_amount > 0, "amount = 0");
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 depositId = Counter;
        uint _timestamp = block.timestamp;
        userDeposits[msg.sender][depositId] = Deposit({
            amount: _amount,
            timestamp: _timestamp
        });
        Counter++;

        emit Staked(msg.sender, depositId, _amount, _timestamp);
    }

    function unstake(uint _depositId) external nonReentrant{
        require(_depositId < Counter, "invalid _depositId");
        Deposit storage userDeposit = userDeposits[msg.sender][_depositId];
        require(userDeposit.amount > 0, "no deposit found");
        require(block.timestamp >= userDeposit.timestamp + timeLock, "time lock has not passed");
        
        uint256 amountToUnstake = userDeposit.amount;
        userDeposit.amount = 0; // Set amount to 0 to prevent re-unstaking of same deposit

        stakingToken.safeTransfer(msg.sender, amountToUnstake);

        emit Unstaked(msg.sender, _depositId, amountToUnstake, block.timestamp);
    }

    function unstakeMultiple(uint[] calldata _depositIds) external nonReentrant {
        uint256 totalAmountToUnstake = 0;

        for (uint i = 0; i < _depositIds.length; i++) {
            uint depositId = _depositIds[i];
            require(depositId < Counter, "invalid depositId");

            Deposit storage userDeposit = userDeposits[msg.sender][depositId];
            require(userDeposit.amount > 0, "no deposit found");
            require(block.timestamp >= userDeposit.timestamp + timeLock, "time lock has not passed");

            uint _amountOfDeposit = userDeposit.amount;
            totalAmountToUnstake += userDeposit.amount;
            userDeposit.amount = 0; // Set amount to 0 to prevent re-unstaking of same deposit

            emit Unstaked(msg.sender, depositId, _amountOfDeposit, block.timestamp);
        }

        stakingToken.safeTransfer(msg.sender, totalAmountToUnstake);
    }

    // This Function is Only use for Emergency Case where Contract is found to vulnerable
    function withdrawFunds(uint _amount) external onlyOwner {
        stakingToken.safeTransfer(msg.sender, _amount);
    }

    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "newOwner is the zero address");
        owner = newOwner;
    }

}