// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./IAirdrop.sol";

contract Airdrop is IAirdrop, AccessControl {
  /// the merkle root of the airdrop recipient addresses
  bytes32 public root;

  /// the address of the MyShell ERC20 token
  IERC20 public myshellToken;

  /// the timestamp when claiming of tokens can begin
  bool public isOpenToClaim = false;

  /// a way of tracking which users have claimed their tokens using their merkle proofs
  mapping(bytes32 usedClaim => bool hasClaimed) public usedClaims;

  constructor(
    bytes32 _merkleroot,
    address _myshellToken,
    address _adminWallet
  ) {
    root = _merkleroot;
    myshellToken = IERC20(_myshellToken);

    _grantRole(DEFAULT_ADMIN_ROLE, _adminWallet);
  }

  /// @inheritdoc IAirdrop
  function redeem(
    address _account,
    uint256 _amount,
    bytes32[] calldata _proof
  ) external {
    require(isOpenToClaim, "Airdrop: Claiming is not open yet");
    bytes32 claimLeaf = _constructLeaf(_account, _amount);

    require(!usedClaims[claimLeaf], "Airdrop: Claim has already been used");
    require(
      _verifyMerkleProof(claimLeaf, _proof),
      "Airdrop: Invalid merkle proof"
    );
    usedClaims[claimLeaf] = true;
    myshellToken.transfer(_account, _amount);
  }

  /// An internal helper function that hashes a users public key and amount to match the merkle tree leaf we expect
  /// @param account The account claiming their amount
  /// @param amount The amount their claiming
  function _constructLeaf(
    address account,
    uint256 amount
  ) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(amount, account));
  }

  /// The logic around verifying that the proof the user has submitted a valid proof
  /// @param leaf The leaf value of the merkle tree proof being proved
  /// @param proof The proof that constructs this leaf + others to match the contracts `root` state variable
  function _verifyMerkleProof(
    bytes32 leaf,
    bytes32[] memory proof
  ) internal view returns (bool) {
    return MerkleProof.verify(proof, root, leaf);
  }

  /////////////////////
  // ADMIN METHODS
  /////////////////////

  /// @inheritdoc IAirdrop
  function setOpenToClaim(
    bool _isOpenToClaim
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    emit ClaimOpenUpdated(_isOpenToClaim);
    isOpenToClaim = _isOpenToClaim;
  }

  /// @inheritdoc IAirdrop
  function withdrawLeftoverMyShell() external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 balance = myshellToken.balanceOf(address(this));

    require(balance > 0, "No tokens left to claim");

    emit LeftoverMyShellWithdrawn(msg.sender, balance);
    myshellToken.transfer(msg.sender, balance);
  }

  /// @inheritdoc IAirdrop
  function setRoot(bytes32 _root) external onlyRole(DEFAULT_ADMIN_ROLE) {
    emit MerkleRootUpdated(_root);
    root = _root;
  }
}