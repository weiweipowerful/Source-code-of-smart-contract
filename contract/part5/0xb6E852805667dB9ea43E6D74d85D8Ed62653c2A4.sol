// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

contract Earn3DailyCheckIn {
    address public owner;
    mapping(address => uint256[]) public checkInDates;
    address[] private users;

    event CheckedIn(address indexed user, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can access this function");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {
        revert("Fund transfers are not allowed to this contract");
    }

    fallback() external payable {
        revert("Fund transfers are not allowed to this contract");
    }

    function checkIn() public {
        uint256 currentTimestamp = block.timestamp;
        uint256[] storage userCheckIns = checkInDates[msg.sender];

        if (userCheckIns.length > 0 && (currentTimestamp / 1 days) == (userCheckIns[userCheckIns.length - 1] / 1 days)) {
            revert("AlreadyCheckedInToday");
        }

        if (userCheckIns.length == 0) {
            users.push(msg.sender);
        }

        userCheckIns.push(currentTimestamp);
        emit CheckedIn(msg.sender, currentTimestamp);
    }

    function getCheckInDates(address user) public view returns (uint256[] memory) {
        return checkInDates[user];
    }

    function hasCheckedInToday(address user) public view returns (bool) {
        uint256[] storage userCheckIns = checkInDates[user];
        if (userCheckIns.length == 0) {
            return false;
        }
        uint256 today = block.timestamp / 1 days;
        uint256 lastCheckInDate = userCheckIns[userCheckIns.length - 1] / 1 days;
        return today == lastCheckInDate;
    }

    function getAllCheckIns() public view onlyOwner returns (address[] memory, uint256[][] memory) {
        uint256[][] memory allCheckIns = new uint256[][](users.length);
        
        for (uint256 i = 0; i < users.length; i++) {
            allCheckIns[i] = checkInDates[users[i]];
        }

        return (users, allCheckIns);
    }
}