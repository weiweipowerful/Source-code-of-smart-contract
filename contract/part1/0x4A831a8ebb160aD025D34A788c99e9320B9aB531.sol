/**
 *Submitted for verification at Etherscan.io on 2024-07-31
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IBridge {
    function bridgeToken(address token_address, uint256  value, bytes3 destination, bytes calldata destination_address) external;
    function unlockBridgedToken(bytes32 txHash, bytes3 source, address token, address to, uint256 value) external;
    function unlocked(address sender,address token, uint value) external;
    function isUnlocked(bytes32 hash) external  view returns(bool);

}

interface IERC20 {
    function transferFrom(address sender,address recipient,uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address owner) external returns (uint256);
}

contract Bridge{
    
    uint8 immutable public networkId;
    address immutable public nodeConsensus;
    address immutable public ownersConsensus;

    mapping(bytes32 tx_hash => bool check) _isUnlocked;

    constructor(uint8 _networkid, address _nodeConsensus, address _ownersConsensus) {
        networkId = _networkid;
        nodeConsensus = _nodeConsensus;
        ownersConsensus = _ownersConsensus;
    }

    modifier onlyConsensusNodes(){
        require(msg.sender == nodeConsensus,"Call the consensus node function");
        _;
    }

    modifier onlyConsensusOwners(){
        require(msg.sender == ownersConsensus,"Call the consensus node function");
        _;
    }

    event BridgeRequest (address sender, address token, uint256 value,uint8 netID, bytes3  destination, bytes destination_address);
    event UnlockedBridged(bytes32  txHash, bytes3 source, address token, address to, uint256 value);
    event UnlockedLiquidity(address token, address to, uint256 value);

    function bridgeToken(address token, uint256  value, bytes3 destination, bytes calldata destination_address) external{
        IERC20(token).transferFrom(msg.sender, address(this), value);
        emit BridgeRequest(msg.sender, token, value, networkId, destination, destination_address);
    }

    function unlockBridgedToken(bytes32 txHash, bytes3 source, address token, address to, uint256 value) public onlyConsensusNodes{
        IERC20(token).transfer(to, value);
        bytes32 hash = keccak256(abi.encode(txHash,source));
        _isUnlocked[hash] = true;
        emit UnlockedBridged(txHash, source, token, to, value);
    }

    function unlocked(address sender,address token, uint value) external onlyConsensusOwners{
        IERC20(token).transfer(sender, value);
        emit UnlockedLiquidity(token, sender, value);
    }

    function isUnlocked(bytes32 hash) public view returns(bool) {
        return _isUnlocked[hash];
    }

}