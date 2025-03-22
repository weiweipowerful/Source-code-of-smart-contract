/**
 *Submitted for verification at Etherscan.io on 2025-01-06
*/

//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Owner
 * @dev Set & change owner
 */
contract Ownable {

    address private owner;
    
    // event for EVM logging
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    
    // modifier to check if caller is owner
    modifier onlyOwner() {
        // If the first argument of 'require' evaluates to 'false', execution terminates and all
        // changes to the state and to Ether balances are reverted.
        // This used to consume all gas in old EVM versions, but not anymore.
        // It is often a good idea to use 'require' to check if functions are called correctly.
        // As a second argument, you can also provide an explanation about what went wrong.
        require(msg.sender == owner, "Caller is not owner");
        _;
    }
    
    /**
     * @dev Set contract deployer as owner
     */
    constructor() {
        owner = msg.sender; // 'msg.sender' is sender of current call, contract deployer for a constructor
        emit OwnerSet(address(0), owner);
    }

    /**
     * @dev Change owner
     * @param newOwner address of new owner
     */
    function changeOwner(address newOwner) public onlyOwner {
        emit OwnerSet(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Return owner address 
     * @return address of owner
     */
    function getOwner() external view returns (address) {
        return owner;
    }
}

interface IPriceFeed {
    function latestRoundData() external view returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

contract Presale is Ownable {

    // Receiver Of Donation
    address public presaleReceiver;

    // Price Feed
    IPriceFeed public immutable priceFeed;// = IPriceFeed(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70);

    // Donation Structure
    struct Donation {
        address user;
        uint256 amount;
        int256 priceOfNative;
        uint256 timestamp;
        string promoCode;
    }
    uint256 public donationNonce;

    // maps donation nonce to donation
    mapping ( uint256 => Donation ) public donations;

    // Address => User
    mapping ( address => uint256 ) public donors;

    // List Of All Donors
    address[] private _allDonors;

    // Total Amount Donated
    uint256 private _totalDonated;

    // sale has ended
    bool public hasStarted;

    // maps promo code to number of times used
    mapping ( string => uint256 ) public numTimesPromoCodeUsed;

    // event to track purchase
    event Contribution(address indexed user, uint256 amount);

    constructor(address _presaleReceiver, address _priceFeed) {
        // set args
        hasStarted = true;
        presaleReceiver = _presaleReceiver;
        priceFeed = IPriceFeed(_priceFeed);
    }

    function startSale() external onlyOwner {
        hasStarted = true;
    }

    function endSale() external onlyOwner {
        hasStarted = false;
    }

    function withdraw(address token_, uint256 amount) external onlyOwner {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token_.call(abi.encodeWithSelector(0xa9059cbb, msg.sender, amount));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeTransfer: transfer failed'
        );
    }

    function withdrawETH() external onlyOwner {
        (bool s1,) = payable(presaleReceiver).call{value: address(this).balance}("");
        require(s1, 'Failure On ETH Transfer');
    }

    function setPresaleReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), 'Zero Address');
        presaleReceiver = newReceiver;
    }

    function getDonations(uint256 start, uint256 end) external view returns (Donation[] memory) {
        if (end > donationNonce) {
            end = donationNonce;
        }
        Donation[] memory donos = new Donation[](end - start);
        for (uint i = start; i < end; i++) {
            donos[i - start] = donations[i];
        }
        return donos;
    }

    function donateETH(address user, string calldata promoCode) external payable {
        _handleETH();
        _processETH(user, msg.value, promoCode);
    }

    receive() external payable {
        _handleETH();
        _processETHNoCode(msg.sender, msg.value);
    }

    function getCurrentPrice() public view returns (int256 answer) {
        (
            ,
            answer,
            ,
            ,
        ) = priceFeed.latestRoundData();
    }

    function donated(address user) external view returns(uint256) {
        return donors[user];
    }

    function allDonors() external view returns (address[] memory) {
        return _allDonors;
    }

    function allDonorsAndDonationAmounts() external view returns (address[] memory, uint256[] memory) {
        uint len = _allDonors.length;
        uint256[] memory amounts = new uint256[](len);
        for (uint i = 0; i < len;) {
            amounts[i] = donors[_allDonors[i]];
            unchecked { ++i; }
        }
        return (_allDonors, amounts);
    }

    function paginateDonorsAndDonationAmounts(uint256 start, uint256 end) external view returns (address[] memory, uint256[] memory) {
        if (end > _allDonors.length) {
            end = _allDonors.length;
        }
        uint256 len = end - start;
        address[] memory addresses = new address[](len);
        uint256[] memory amounts = new uint256[](len);
        for (uint i = start; i < end;) {
            addresses[i - start] = _allDonors[i];
            amounts[i - start] = donors[_allDonors[i]];
            unchecked { ++i; }
        }
        return (addresses, amounts);
    }

    function donorAtIndex(uint256 index) external view returns (address) {
        return _allDonors[index];
    }

    function numberOfDonors() external view returns (uint256) {
        return _allDonors.length;
    }

    function totalDonated() external view returns (uint256) {
        return _totalDonated;
    }

    function _processETH(address user, uint amount, string calldata promoCode) internal {
        require(
            hasStarted,
            'Sale Has Not Started'
        );

        // add to donor list if first donation
        if (donors[user] == 0) {
            _allDonors.push(user);
        }

        // increment amounts donated
        unchecked {
            donors[user] += amount;
            _totalDonated += amount;
        }

        // add to donation structure
        donations[donationNonce] = Donation({
            user: user,
            amount: amount,
            priceOfNative: getCurrentPrice(),
            timestamp: block.timestamp,
            promoCode: promoCode
        });

        // incremenet donation Nonce
        unchecked {
            ++donationNonce;
            ++numTimesPromoCodeUsed[promoCode];
        }

        // emit event
        emit Contribution(user, amount);
    }

    function _processETHNoCode(address user, uint amount) internal {
        require(
            hasStarted,
            'Sale Has Not Started'
        );

        // add to donor list if first donation
        if (donors[user] == 0) {
            _allDonors.push(user);
        }

        // increment amounts donated
        unchecked {
            donors[user] += amount;
            _totalDonated += amount;
        }

        // add to donation structure
        donations[donationNonce] = Donation({
            user: user,
            amount: amount,
            priceOfNative: getCurrentPrice(),
            timestamp: block.timestamp,
            promoCode: ""
        });

        // incremenet donation Nonce
        unchecked {
            ++donationNonce;
        }

        // emit event
        emit Contribution(user, amount);
    }

    function _handleETH() internal {
        (bool s1,) = payable(presaleReceiver).call{value: address(this).balance}("");
        require(s1, 'Failure On ETH Transfer');
    }
}