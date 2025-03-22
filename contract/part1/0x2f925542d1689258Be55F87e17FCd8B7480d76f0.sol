// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';

contract BonusDistributor is Ownable, EIP712 {
    using SafeERC20 for IERC20;

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    string private constant _NAME = 'YIELD TOKEN DISTRIBUTOR';
    string private constant _VERSION = '2.0';
    address private signer;

    bytes32 constant MESSAGE_TYPEHASH = keccak256('Message(address token,address account,bytes32 key,uint256 amountMax,uint256 expireTime)');

    // account => key  => amount
    mapping(address => mapping(bytes32 => uint256)) private claimedMap;

    constructor(address _signer) EIP712(_NAME,_VERSION) {
        require(_signer != address(0), 'ZERO_ADDRESS');
        signer = _signer;
    }

    //-------------------------------
    //------- Events ----------------
    //-------------------------------
    event Claimed(address account, bytes32 key, uint256 amount, uint256 amountMax, uint256 expireTime);
    event SetSigner(address, address);

    //-------------------------------
    //------- Admin functions -------
    //-------------------------------

    function updateSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), 'ZERO_ADDRESS');
        address oldSigner = signer;
        signer = newSigner;
        emit SetSigner(oldSigner, newSigner);
    }

    //-------------------------------
    //------- Users Functions -------
    //-------------------------------

    function claimWithSig(
        address account,
        bytes32 key,
        uint256 amountMax,
        uint256 expireTime,
        bytes calldata signature
    ) external {
        uint256 claimed = claimedMap[account][key];
        require(amountMax > claimed, 'no bonus to claim');
        require(block.timestamp <= expireTime, 'time expired');

        address token = address(bytes20(key));
        bytes32 digest = keccak256(abi.encode(MESSAGE_TYPEHASH, token, account, key, amountMax, expireTime));
        require(validateSig(digest, signature), 'sign error');

        claimed = amountMax - claimed;
        claimedMap[account][key] = amountMax;
        transfer(token, account, claimed);
        emit Claimed(account, key, claimed, amountMax, expireTime);
    }

    function getUserClaimedAmount(address user, bytes32 key) external view returns (uint256) {
        return claimedMap[user][key];
    }

    function getSigner() external view returns (address) {
        return signer;
    }

    function validateSig(bytes32 message, bytes memory signature) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(message);

        address signerRecovered = ECDSA.recover(digest, signature);

        return signerRecovered == signer;
    }

    function transfer(address token, address to, uint256 amount) internal {
        if (token == ETH_ADDRESS) {
            (bool success, ) = payable(to).call{ value: amount, gas: 5000 }("");
            require(success, 'failed');
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    receive() external payable {}
}