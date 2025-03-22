/**
 *Submitted for verification at Etherscan.io on 2025-03-17
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract SignatureVerifier {
    struct SignatureData {
        string message;
        bytes signature;
        address signer;
        uint256 timestamp;
    }

    mapping(address => SignatureData[]) public signatures;

    address public owner;

    address public tokenAddress;

    uint256 public minTokenBalance;

    event SignatureStored(
        address indexed signer,
        string message,
        bytes signature,
        uint256 timestamp
    );

    event TokenRequirementUpdated(address tokenAddress, uint256 minTokenBalance);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Seul le proprietaire peut appeler cette fonction");
        _;
    }

    constructor(address _tokenAddress, uint256 _minTokenBalance) {
        owner = msg.sender;
        tokenAddress = _tokenAddress;
        minTokenBalance = _minTokenBalance;
    }

    function verifySignature(
        string memory message,
        bytes memory signature,
        address signer
    ) public returns (bool) {
        require(
            IERC20(tokenAddress).balanceOf(msg.sender) >= minTokenBalance,
            "Solde de tokens insuffisant"
        );

        bytes32 messageHash = getEthSignedMessageHash(message);
        address recoveredSigner = recoverSigner(messageHash, signature);
        bool isValid = (recoveredSigner == signer);

        if (isValid) {
            signatures[signer].push(
                SignatureData({
                    message: message,
                    signature: signature,
                    signer: signer,
                    timestamp: block.timestamp
                })
            );
            emit SignatureStored(signer, message, signature, block.timestamp);
        }

        return isValid;
    }

    function setTokenRequirement(address _tokenAddress, uint256 _minTokenBalance) public onlyOwner {
        tokenAddress = _tokenAddress;
        minTokenBalance = _minTokenBalance;
        emit TokenRequirementUpdated(_tokenAddress, _minTokenBalance);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Nouvelle adresse invalide");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function getSignatureCount(address signer) public view returns (uint256) {
        return signatures[signer].length;
    }

    function getSignature(
        address signer,
        uint256 index
    ) public view returns (string memory, bytes memory, address, uint256) {
        require(index < signatures[signer].length, "Index hors limites");
        SignatureData memory sigData = signatures[signer][index];
        return (sigData.message, sigData.signature, sigData.signer, sigData.timestamp);
    }

    function getEthSignedMessageHash(string memory message) private pure returns (bytes32) {
        bytes memory messageBytes = bytes(message);
        string memory prefix = string(abi.encodePacked("\x19Ethereum Signed Message:\n", uintToString(messageBytes.length)));
        return keccak256(abi.encodePacked(prefix, message));
    }

    function recoverSigner(bytes32 messageHash, bytes memory signature) private pure returns (address) {
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(signature);
        return ecrecover(messageHash, v, r, s);
    }

    function splitSignature(bytes memory sig) private pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) {
            v += 27;
        }
        return (v, r, s);
    }

    function uintToString(uint v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint maxlength = 100;
        bytes memory reversed = new bytes(maxlength);
        uint i = 0;
        while (v != 0) {
            uint remainder = v % 10;
            v = v / 10;
            reversed[i++] = bytes1(uint8(48 + remainder));
        }
        bytes memory s = new bytes(i);
        for (uint j = 0; j < i; j++) {
            s[j] = reversed[i - 1 - j];
        }
        return string(s);
    }
}