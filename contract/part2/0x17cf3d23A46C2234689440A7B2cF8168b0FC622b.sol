// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract PepeAirplane {
    struct Staker {
        uint256 amount;
        uint256 reward;
        uint256 totalReward;
    }

    IERC20 public pepeCoin; // The Pepe Coin token contract address
    mapping(address => Staker) public stakers;
    uint256 public totalStaked;
    address[] public stakerAddresses;

    constructor(IERC20 _pepeCoin) {
        pepeCoin = _pepeCoin;
    }

    function stake(uint256 amount) public {
        require(amount > 0, "Must stake some pepe coins");
        require(pepeCoin.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        if (stakers[msg.sender].amount == 0) {
            stakerAddresses.push(msg.sender);
        }

        if (totalStaked == 0) {
            // If no one has staked yet, just give the staker all the rewards
            stakers[msg.sender].amount += amount;
            stakers[msg.sender].reward += amount;
            stakers[msg.sender].totalReward += amount;
            totalStaked += amount;
            return;
        }

        // Calculate rewards for existing stakers
        uint256 totalReward = amount;
        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            address stakerAddress = stakerAddresses[i];
            Staker storage staker = stakers[stakerAddress];

            uint256 reward = (staker.amount * totalReward) / totalStaked;
            staker.reward += reward;
            staker.totalReward += reward;
        }

        // Update stakes
        stakers[msg.sender].amount += amount;
        totalStaked += amount;
    }

    function claim() public {
        Staker storage staker = stakers[msg.sender];
        require(staker.reward > 0, "No rewards to claim");

        uint256 reward = staker.reward;
        staker.reward = 0;

        require(pepeCoin.transfer(msg.sender, reward), "Transfer failed");
    }

    function getStakerInfo(address stakerAddress) public view returns (Staker memory) {
        Staker memory staker = stakers[stakerAddress];
        return staker;
    }

    function getTotalStakesInfo() public view returns (uint256, uint256) {
        return (totalStaked, stakerAddresses.length);
    }

    function getAllStakerInfos() public view returns (address[] memory, Staker[] memory) {
        address[] memory allStakerAddresses = new address[](stakerAddresses.length);
        Staker[] memory allStakerInfos = new Staker[](stakerAddresses.length);
        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            allStakerAddresses[i] = stakerAddresses[i];
            allStakerInfos[i] = stakers[stakerAddresses[i]];
        }
        return (allStakerAddresses, allStakerInfos);
    }
}