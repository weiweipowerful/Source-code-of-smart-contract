// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/*

Built with ♥ by

░██╗░░░░░░░██╗░█████╗░███╗░░██╗██████╗░███████╗██████╗░██╗░░░░░░█████╗░███╗░░██╗██████╗░
░██║░░██╗░░██║██╔══██╗████╗░██║██╔══██╗██╔════╝██╔══██╗██║░░░░░██╔══██╗████╗░██║██╔══██╗
░╚██╗████╗██╔╝██║░░██║██╔██╗██║██║░░██║█████╗░░██████╔╝██║░░░░░███████║██╔██╗██║██║░░██║
░░████╔═████║░██║░░██║██║╚████║██║░░██║██╔══╝░░██╔══██╗██║░░░░░██╔══██║██║╚████║██║░░██║
░░╚██╔╝░╚██╔╝░╚█████╔╝██║░╚███║██████╔╝███████╗██║░░██║███████╗██║░░██║██║░╚███║██████╔╝
░░░╚═╝░░░╚═╝░░░╚════╝░╚═╝░░╚══╝╚═════╝░╚══════╝╚═╝░░╚═╝╚══════╝╚═╝░░╚═╝╚═╝░░╚══╝╚═════╝░

https://defi.sucks

*/

import {ISignedDistributor} from 'interfaces/ISignedDistributor.sol';

import {Ownable, Ownable2Step} from 'openzeppelin/access/Ownable2Step.sol';
import {IERC20} from 'openzeppelin/token/ERC20/IERC20.sol';
import {ECDSA} from 'openzeppelin/utils/cryptography/ECDSA.sol';
import {MerkleProof} from 'openzeppelin/utils/cryptography/MerkleProof.sol';
import {MessageHashUtils} from 'openzeppelin/utils/cryptography/MessageHashUtils.sol';

contract SignedDistributor is ISignedDistributor, Ownable2Step {
  using ECDSA for bytes32;
  using MessageHashUtils for bytes32;

  /// @inheritdoc ISignedDistributor
  bytes32 public immutable MERKLE_ROOT;

  /// @inheritdoc ISignedDistributor
  IERC20 public immutable TOKEN;

  /// @inheritdoc ISignedDistributor
  address public signer;

  /// @inheritdoc ISignedDistributor
  mapping(address => bool) public hasClaimed;

  // solhint-disable-next-line no-unused-vars
  constructor(bytes32 _merkleRoot, address _signer, address _token, address _owner) Ownable(_owner) {
    MERKLE_ROOT = _merkleRoot;
    TOKEN = IERC20(_token);
    _updateSigner(_signer);
  }

  /// @inheritdoc ISignedDistributor
  function claim(uint256 amount, bytes32[] calldata merkleProof, bytes calldata signature) external {
    if (amount == 0) revert InvalidAmount();
    if (signature.length == 0) revert InvalidSignature();
    if (hasClaimed[msg.sender]) revert AlreadyClaimed();

    // Verify the signature
    bytes32 _messageHash = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));
    bytes32 _ethSignedMessageHash = _messageHash.toEthSignedMessageHash();
    address _recoveredSigner = _ethSignedMessageHash.recover(signature);
    if (_recoveredSigner != signer) revert InvalidSigner();

    // Verify the merkle proof
    if (!MerkleProof.verify(merkleProof, MERKLE_ROOT, _messageHash)) revert InvalidProof();

    // Mark as claimed and send the tokens
    hasClaimed[msg.sender] = true;
    TOKEN.transfer({to: msg.sender, value: amount});

    emit Claimed(msg.sender, amount);
  }

  /// @inheritdoc ISignedDistributor
  function withdraw() external onlyOwner {
    uint256 _remainingBalance = TOKEN.balanceOf(address(this));
    TOKEN.transfer({to: owner(), value: _remainingBalance});

    emit Withdrawn(owner(), _remainingBalance);
  }

  /// @inheritdoc ISignedDistributor
  function updateSigner(address newSigner) external onlyOwner {
    _updateSigner(newSigner);
  }

  /**
   * @notice Updates the signer address
   * @param newSigner The new signer address
   */
  function _updateSigner(address newSigner) internal {
    if (newSigner == address(0)) revert InvalidNewSigner();

    address _oldSigner = signer;
    signer = newSigner;

    emit SignerUpdated(_oldSigner, newSigner);
  }
}