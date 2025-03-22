/**
 *Submitted for verification at Etherscan.io on 2025-03-19
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract SecureEURTTransfer {
    address public owner;
    string private clearingCode;
    string public ipfsHash;
    IERC20 public eurtToken;

    address[] public receivers;
    mapping(address => uint256) public allocations;
    bool public receiversFinalized;

    constructor(address _eurtToken, string memory _ipfsHash, string memory _clearingCode) {
        owner = msg.sender;
        eurtToken = IERC20(_eurtToken);
        ipfsHash = _ipfsHash;
        clearingCode = _clearingCode;
        receiversFinalized = false;
    }

    function setReceiversAndAllocations(address[] memory _receivers, uint256[] memory amounts) public {
        require(msg.sender == owner, "Only owner can set receivers");
        require(!receiversFinalized, "Receivers are already finalized");
        require(_receivers.length == amounts.length, "Mismatched arrays");

        for (uint256 i = 0; i < _receivers.length; i++) {
            receivers.push(_receivers[i]);
            allocations[_receivers[i]] = amounts[i];
        }
        receiversFinalized = true;
    }

    function verifyAndTransfer(string memory inputCode) public {
        require(receiversFinalized, "Receivers are not set yet");
        require(keccak256(abi.encodePacked(inputCode)) == keccak256(abi.encodePacked(clearingCode)), "Invalid Clearing Code!");

        for (uint256 i = 0; i < receivers.length; i++) {
            require(eurtToken.transfer(receivers[i], allocations[receivers[i]]), "EURT Transfer Failed!");
        }
    }

    function getFileHash() public view returns (string memory) {
        return ipfsHash;
    }
}