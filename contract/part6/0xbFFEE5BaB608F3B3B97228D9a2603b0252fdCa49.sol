/**
 *Submitted for verification at Etherscan.io on 2024-12-13
*/

// SPDX-License-Identifier: MIT

// Contract to manage DRBT Memberships
// t.me/DeFi_Robot_Portal

pragma solidity 0.8.28;

contract DRBT_Membership {
    address public owner;
    bool public purchasesEnabled;

    struct MembershipOption {
        uint256 ethAmount;
        uint256 validityPeriod;
    }

    struct MembershipInfo {
        address userAddress;
        uint256[] optionIds;
        uint256[] expirationTimestamps;
    }

    event MembershipPurchased(address indexed buyerAddress, uint256 indexed key, uint256 optionId);
    event PurchasesStatusUpdated(bool newStatus);

    mapping(uint256 => MembershipOption) public membershipOptions; // Option ID to MembershipOption
    mapping(address => mapping(uint256 => uint256)) public userExpirations; // User address to (Option ID to Expiration Timestamp)
    mapping(address => bool) private userExists; // Mapping to keep track of existing users
    address[] private users; // List of all users who purchased memberships
    uint256 public numberOfOptions;

    constructor() {
        owner = msg.sender;
        purchasesEnabled = true; // Enable purchases by default
        // Initialize with default options
        membershipOptions[1] = MembershipOption(0.15 ether, 730 hours);
        membershipOptions[2] = MembershipOption(0.05 ether, 730 hours);
        membershipOptions[4] = MembershipOption(0.07 ether, 730 hours);
        membershipOptions[5] = MembershipOption(0.05 ether, 3 days);
        numberOfOptions = 5;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    // Function to toggle the status of purchases
    function togglePurchases(bool status) external onlyOwner {
        purchasesEnabled = status;
        emit PurchasesStatusUpdated(status);
    }

    // Function to buy a membership
    function buyMembership(uint256 optionId, uint256 key) external payable {
        require(purchasesEnabled, "Purchases are currently disabled");
        require(optionId > 0 && optionId <= numberOfOptions, "Invalid option ID");

        // Check if option 3 is being bought, and handle accordingly
        if (optionId == 3) {
            // Ensure the total ETH sent matches the combined price of option 1 and option 2
            require(
                msg.value == (membershipOptions[1].ethAmount + membershipOptions[2].ethAmount),
                "Incorrect ETH amount sent for combined option"
            );

            // Process the purchase of option 1 and option 2 separately
            _buyOption(msg.sender, 1);
            _buyOption(msg.sender, 2);
        } else {
            // Process a normal purchase
            MembershipOption memory option = membershipOptions[optionId];
            require(msg.value == option.ethAmount, "Incorrect ETH amount sent");
            _buyOption(msg.sender, optionId);
        }

        // Add user to the list if they haven't been added before
        if (!userExists[msg.sender]) {
            users.push(msg.sender);
            userExists[msg.sender] = true;
        }

        // Emit an event for logging purposes
        emit MembershipPurchased(msg.sender, key, optionId);
    }

    // Internal function to handle purchasing a specific option
    function _buyOption(address buyer, uint256 optionId) internal {
        MembershipOption memory option = membershipOptions[optionId];
        uint256 expiration = userExpirations[buyer][optionId];
        if (expiration == 0 || expiration < block.timestamp) {
            userExpirations[buyer][optionId] = block.timestamp + option.validityPeriod;
        } else {
            userExpirations[buyer][optionId] += option.validityPeriod;
        }
    }

    // Function to check memberships for a wallet
    function checkMembership(address userAddress)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256[] memory activeOptionIds = new uint256[](numberOfOptions);
        uint256[] memory expirationTimestamps = new uint256[](numberOfOptions);
        uint256 count = 0;

        for (uint256 i = 1; i <= numberOfOptions; i++) {
            if (userExpirations[userAddress][i] > block.timestamp) {
                activeOptionIds[count] = i;
                expirationTimestamps[count] = userExpirations[userAddress][i];
                count++;
            }
        }

        uint256[] memory validOptionIds = new uint256[](count);
        uint256[] memory validExpirations = new uint256[](count);
        for (uint256 j = 0; j < count; j++) {
            validOptionIds[j] = activeOptionIds[j];
            validExpirations[j] = expirationTimestamps[j];
        }

        return (validOptionIds, validExpirations);
    }

    // Function to get all active memberships across all users
    function getAllActiveMemberships()
        external
        view
        returns (MembershipInfo[] memory)
    {
        uint256 userCount = users.length;
        uint256 activeUserCount = 0;

        // Count how many users have active memberships
        for (uint256 i = 0; i < userCount; i++) {
            (uint256[] memory options, ) = checkMembership(users[i]);
            if (options.length > 0) {
                activeUserCount++;
            }
        }

        // Initialize an array of MembershipInfo structs
        MembershipInfo[] memory activeMemberships = new MembershipInfo[](activeUserCount);
        uint256 index = 0;

        // Populate the array with data for each active user
        for (uint256 i = 0; i < userCount; i++) {
            address user = users[i];
            (uint256[] memory options, uint256[] memory expirations) = checkMembership(user);
            if (options.length > 0) {
                activeMemberships[index] = MembershipInfo(user, options, expirations);
                index++;
            }
        }

        return activeMemberships;
    }

    // Function to set a membership option
    function setMembershipOption(
        uint256 optionId,
        uint256 ethAmount,
        uint256 validityPeriod
    ) external onlyOwner {
        require(optionId > 0, "Invalid option ID");
        membershipOptions[optionId] = MembershipOption(ethAmount, validityPeriod);
        if (optionId > numberOfOptions) {
            numberOfOptions = optionId;
        }
    }

    // Function to manually add time to an option for a given wallet
    function addTimeToMembership(
        address userAddress,
        uint256 optionId,
        uint256 additionalTime
    ) external onlyOwner {
        if (optionId == 3) {
            // Option 3 corresponds to options 1 and 2
            require(
                membershipOptions[1].validityPeriod > 0 && membershipOptions[2].validityPeriod > 0,
                "Options 1 or 2 do not exist"
            );

            _addTimeToOption(userAddress, 1, additionalTime);
            _addTimeToOption(userAddress, 2, additionalTime);
        } else {
            require(membershipOptions[optionId].validityPeriod > 0, "Option does not exist");
            _addTimeToOption(userAddress, optionId, additionalTime);
        }
    }

    // Internal function to add time to a specific option for a user
    function _addTimeToOption(
        address userAddress,
        uint256 optionId,
        uint256 additionalTime
    ) internal {
        uint256 currentExpiration = userExpirations[userAddress][optionId];
        if (currentExpiration == 0 || currentExpiration < block.timestamp) {
            userExpirations[userAddress][optionId] = block.timestamp + additionalTime;
        } else {
            userExpirations[userAddress][optionId] += additionalTime;
        }

        // Add user to the list if they haven't been added before
        if (!userExists[userAddress]) {
            users.push(userAddress);
            userExists[userAddress] = true;
        }
    }

    // Function to cancel a membership for a given wallet
    function cancelMembership(address userAddress, uint256 optionId) external onlyOwner {
        if (optionId == 3) {
            // Option 3 corresponds to options 1 and 2
            require(
                membershipOptions[1].validityPeriod > 0 && membershipOptions[2].validityPeriod > 0,
                "Options 1 or 2 do not exist"
            );

            _cancelOption(userAddress, 1);
            _cancelOption(userAddress, 2);
        } else {
            require(membershipOptions[optionId].validityPeriod > 0, "Option does not exist");
            _cancelOption(userAddress, optionId);
        }
    }

    // Internal function to cancel a specific option for a user
    function _cancelOption(address userAddress, uint256 optionId) internal {
        userExpirations[userAddress][optionId] = 0;
    }
    
    function withdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
}