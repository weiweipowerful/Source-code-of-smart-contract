// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "../abstract/roles/EeseeRoleHandler.sol";
import "../abstract/BlastPointsReceiver.sol";

contract EeseeRewards is EIP712, EeseeRoleHandler, BlastPointsReceiver {
    using SafeERC20 for IERC20;

    struct SignatureData {
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }

    struct Reward {
        bytes32 id;
        uint256 amount;
    }

    ///@dev Claim typehash.
    bytes32 private constant CLAIM_TYPEHASH = keccak256("Claim(address token,address recipient,bytes32 rewardsHash,address sender,uint256 nonce,uint256 deadline)");

    ///@dev SIGNER role af defined in {accessManager}.
    bytes32 private constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    ///@dev Mapping from reward id to amount of claimed tokens.
    mapping(bytes32 => uint256) public rewardsClaimed;
    ///@dev Is nonce used.
    mapping(uint256 => bool) public nonceUsed;

    event Claimed(
        IERC20 token, 
        bytes32 indexed rewardId, 
        address indexed recipient, 
        uint256 amount, 
        uint256 indexed nonce
    );
    event RevokeSignature(uint256 indexed nonce);

    error ExpiredDeadline();
    error NonceUsed();
    error InvalidSignature();
    error NoRewardsToClaim();

    constructor(
        IEeseeAccessManager _accessManager, 
        IBlastPoints _blastPoints, 
        address _blastPointsOperator
    ) EIP712("EeseeRewards", "1") EeseeRoleHandler(_accessManager) BlastPointsReceiver(_blastPoints, _blastPointsOperator) {}

    /**
     * @dev Sends tokens to recipient. Emits {Claimed} event.
     * @param token - Token to send.
     * @param recipient - Recipient's address.
     * @param rewards - Array of rewards to claim.
     * @param signatureData - Signature for input and data signed by SIGNER_ROLE.
     */
    function claim(
        IERC20 token,
        address recipient,
        Reward[] calldata rewards,
        SignatureData calldata signatureData
    ) external {
        _checkSignature(
            msg.sender, 
            _getClaimStructHash(
                address(token),
                recipient,
                rewards,
                msg.sender,
                signatureData.nonce,
                signatureData.deadline
            ), 
            signatureData
        );

        uint256 length = rewards.length;
        uint256 amount = 0;

        for (uint256 i; i < length;) {
            Reward memory reward = rewards[i];
            bytes32 rewardId = reward.id;
            uint256 rewardAmount = reward.amount;
            if (rewardsClaimed[rewardId] > 0) continue;
            rewardsClaimed[rewardId] = rewardAmount;
            amount += rewardAmount;
            emit Claimed(token, rewardId, recipient, rewardAmount, signatureData.nonce);
            unchecked { ++i; }
        }

        if (amount == 0) revert NoRewardsToClaim();

        token.safeTransfer(recipient, amount);
    }

    /**
     * @dev Callable by SIGNER_ROLE to revoke signatures. Emits {RevokeSignature} for each signature revoked.
     * @param nonces - Signature nonces to revoke.
     */
    function revokeSignatures(uint256[] calldata nonces) external {
        if(!_isSigner(_msgSender())) revert CallerNotAuthorized();
        for (uint256 i; i < nonces.length;) {
            if (nonceUsed[nonces[i]]) revert NonceUsed();
            nonceUsed[nonces[i]] = true;
            emit RevokeSignature(nonces[i]);
            unchecked { ++i; }
        }
    }

    function _checkSignature(
        address msgSender,
        bytes32 structHash,
        SignatureData calldata signatureData
    ) internal {
        if(nonceUsed[signatureData.nonce]) revert NonceUsed();
        nonceUsed[signatureData.nonce] = true;
        if(_isSigner(msgSender)) return;
        if(block.timestamp > signatureData.deadline) revert ExpiredDeadline();

        address signer = ECDSA.recover(_hashTypedDataV4(structHash), signatureData.signature);
        if(!_isSigner(signer)) revert InvalidSignature();
    }

    function _getClaimStructHash(
        address token,
        address recipient, 
        Reward[] calldata rewards,
        address sender, 
        uint256 nonce, 
        uint256 deadline
    ) internal pure returns (bytes32){
        return keccak256(abi.encode(
            CLAIM_TYPEHASH, 
            token,
            recipient,
            keccak256(abi.encode(rewards)),
            sender,
            nonce,
            deadline
        ));
    }

    function _isSigner(address _addr) internal view returns(bool){
        return _hasRole(SIGNER_ROLE, _addr);
    }
}