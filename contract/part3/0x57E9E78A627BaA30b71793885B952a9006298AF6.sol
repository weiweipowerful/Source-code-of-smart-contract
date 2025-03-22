// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./EphemeralTokenBurner.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IMessageTransmitter {
  function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool);
}

interface IZkLighter {
  /// @notice Deposit USDC to zkLighter
  /// @param _amount USDC Token amount
  /// @param _to The receiver L1 address
  function deposit(uint64 _amount, address _to) external;
}

contract FastCCTP {
  struct IntentParams {
    address deployer;
    address zklighterRecipient;
    address claimContract;
  }

  address public messageTransmitter; // Address of Circle's MessageTransmitter
  address public zklighterProxy; // Address of zklighter proxy
  address public owner;
  mapping(bytes32 intentAddr => address) public fastBridgeCaller;
  IERC20 usdcToken;

  event FundsReceived(bytes32 messageHash, address fastBridgeCallerAddress, uint256 amount);
  event FastFinished(bytes32 messageHash, address finisher);

  modifier onlyOwner() {
    require(msg.sender == owner, "Not authorized");
    _;
  }

  constructor(address _usdcToken, address _messageTransmitter, address _zklighterProxy) {
    usdcToken = IERC20(_usdcToken);
    messageTransmitter = _messageTransmitter;
    zklighterProxy = _zklighterProxy;
    owner = msg.sender;
    usdcToken.approve(zklighterProxy, type(uint256).max);
  }

  // Pays Bob immediately on chain B. The caller LP sends (toToken, toAmount).
  // Later, when the slower CCTP transfer arrives, the LP will be able to claim
  // (toToken, fromAmount), keeping the spread (if any) between the amounts.
  function fastFinishTransfer(address[] calldata zklighterRecipient, uint256[] calldata fromAmount, bytes32[] calldata messageHash) public {
    require(zklighterRecipient.length == fromAmount.length, "Invalid input length");
    require(fromAmount.length == messageHash.length, "Invalid input length");

    uint256 totalAmount = 0;
    for (uint32 i = 0; i < zklighterRecipient.length; ++i) {
      totalAmount += fromAmount[i];
    }
    usdcToken.safeTransferFrom(msg.sender, address(this), totalAmount);

    for (uint32 i = 0; i < zklighterRecipient.length; ++i) {
      bytes32 keyHash = keccak256(abi.encodePacked(messageHash[i], fromAmount[i], zklighterRecipient[i]));
      require(fastBridgeCaller[keyHash] == address(0), "FCCTP: already finished");

      // Record LP as new recipient
      fastBridgeCaller[keyHash] = msg.sender;

      IZkLighter(zklighterProxy).deposit(SafeCast.toUint64(fromAmount[i]), zklighterRecipient[i]);

      emit FastFinished(messageHash[i], msg.sender);
    }
  }

  // Function to process the Circle attestation and execute custom logic
  function batchClaimFastTransfers(IntentParams[] memory params, bytes[] calldata allMessages, bytes[] calldata attestations) external {
    require(allMessages.length == attestations.length, "Invalid input length");
    require(allMessages.length == params.length, "Invalid input length");

    for (uint32 i = 0; i < allMessages.length; ++i) {
      bytes calldata message = allMessages[i];
      bytes calldata attestation = attestations[i];
      // message structure is:
      // uint32 _version,
      // bytes32 _burnToken,
      // bytes32 _mintRecipient,
      // uint256 _amount,
      // bytes32 _messageSender
      bytes32 recipient;
      uint256 amount = 123;
      bytes32 sender;

      bytes memory body = message[116:];
      assembly {
        // Read recipient (bytes32, next 32 bytes)
        recipient := mload(add(body, 0x44)) // Offset by 36 bytes (4 + 32)

        // Read amount (uint256, next 32 bytes)
        amount := mload(add(body, 0x64)) // Offset by 68 bytes (4 + 32 + 32)

        // Read sender (bytes32, final 32 bytes)
        sender := mload(add(body, 0x84)) // Offset by 100 bytes (4 + 32 + 32 + 32)
      }
      address tokenBurnerAddressGiven = getTokenBurnerAddr(params[i].deployer, params[i].zklighterRecipient, params[i].claimContract);
      address recipientAddress = bytes32ToAddress(recipient);
      require(recipientAddress == address(this), "Invalid recipient");
      address tokenBurnerAddress = bytes32ToAddress(sender);

      require(tokenBurnerAddressGiven == tokenBurnerAddress, "Invalid intent address");
      bytes32 messageHash = keccak256(message);
      bytes32 keyHash = keccak256(abi.encodePacked(messageHash, amount, params[i].zklighterRecipient));

      // Call Circle's MessageTransmitter to validate and mint USDC
      bool success = IMessageTransmitter(messageTransmitter).receiveMessage(message, attestation);
      require(success, "Message processing failed");

      address fastBridgeCallerAddress = fastBridgeCaller[keyHash];
      if (fastBridgeCallerAddress != address(0)) {
        // If a fast finisher has sent the funds before, transfer them back
        usdcToken.transfer(fastBridgeCallerAddress, amount);
        fastBridgeCaller[keyHash] = address(0);
      } else {
        IZkLighter(zklighterProxy).deposit(SafeCast.toUint64(amount), params[i].zklighterRecipient);
      }

      emit FundsReceived(messageHash, fastBridgeCallerAddress, amount);
    }
  }

  /// Computes an ephemeral burner address
  function getTokenBurnerAddr(
    address deployer,
    address zklighterRecipient, // user's account address to be deposited in Zklighter
    address claimContract // zkligher claimer contract
  ) public pure returns (address) {
    bytes memory creationCode = abi.encodePacked(type(EphemeralTokenBurner).creationCode, abi.encode(zklighterRecipient, claimContract));
    return Create2.computeAddress(0, keccak256(creationCode), deployer);
  }

  /**
   * @notice converts bytes32 to address (alignment preserving cast.)
   * @dev Warning: it is possible to have different input values _buf map to the same address.
   * For use cases where this is not acceptable, validate that the first 12 bytes of _buf are zero-padding.
   * @param _buf the bytes32 to convert to address
   */
  function bytes32ToAddress(bytes32 _buf) public pure returns (address) {
    return address(uint160(uint256(_buf)));
  }

  using SafeERC20 for IERC20;

  // Rescuer
  address private _rescuer;

  event RescuerChanged(address indexed newRescuer);

  /**
   * @notice Returns current rescuer
   * @return Rescuer's address
   */
  function rescuer() external view returns (address) {
    return _rescuer;
  }

  /**
   * @notice Revert if called by any account other than the rescuer.
   */
  modifier onlyRescuer() {
    require(msg.sender == _rescuer, "Rescuable: caller is not the rescuer");
    _;
  }

  /**
   * @notice Rescue ERC20 tokens locked up in this contract.
   * @param tokenContract ERC20 token contract address
   * @param to        Recipient address
   * @param amount    Amount to withdraw
   */
  function rescueERC20(IERC20 tokenContract, address to, uint256 amount) external onlyRescuer {
    tokenContract.safeTransfer(to, amount);
  }

  /**
   * @notice Assign the rescuer role to a given address.
   * @param newRescuer New rescuer's address
   */
  function updateRescuer(address newRescuer) external onlyOwner {
    require(newRescuer != address(0), "Rescuable: new rescuer is the zero address");
    _rescuer = newRescuer;
    emit RescuerChanged(newRescuer);
  }
}