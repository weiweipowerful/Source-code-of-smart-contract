// SPDX-License-Identifier: Apache-2.0

/*
     Copyright 2024 Galxe.

     Licensed under the Apache License, Version 2.0 (the "License");
     you may not use this file except in compliance with the License.
     You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

     Unless required by applicable law or agreed to in writing, software
     distributed under the License is distributed on an "AS IS" BASIS,
     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
     See the License for the specific language governing permissions and
     limitations under the License.
 */
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin-v5/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin-v5/contracts/utils/Pausable.sol";
import { Ownable, Ownable2Step } from "@openzeppelin-v5/contracts/access/Ownable2Step.sol";
import { EIP712 } from "@openzeppelin-v5/contracts/utils/cryptography/EIP712.sol";
import { BitMaps } from "@openzeppelin-v5/contracts/utils/structs/BitMaps.sol";
import { ECDSA } from "@openzeppelin-v5/contracts/utils/cryptography/ECDSA.sol";
import { ISaving } from "../../interfaces/ISaving.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract GeneralInstantPaymentLSD is Ownable2Step, Pausable, EIP712 {
  using SafeERC20 for IERC20;

  error InvalidChain();
  error InvalidAddress();
  error InvalidSignature();
  error InvalidDepositToken();
  error InvalidDepositAmount();
  error InvalidSourceSwapParam();
  error InvalidTargetSwapParam();
  error InvalidTargetEndpointId();
  error InvalidTargetToken();
  error InvalidDepositPool();
  error InsufficientDeposit();
  error InsufficientBalance();
  error InvalidTaskFee();
  error AlreadyDeposited();
  error PermissionDenied();
  error WithdrawFailed();
  error RefundFailed();

  event Deposit(address indexed user, address depositToken, uint256 depositAmount, uint256 taskId, uint256 taskFee);
  event Withdraw(address indexed recipient, address token, uint256 amount);

  /// @notice Galxe Signer
  address public signer;

  /// @notice Galxe Treasurer
  address public treasurer;

  /// @notice Saving - Vault Token address
  address public vaultToken;

  /// @notice Saving - Vault Token Chain Id
  uint256 public vaultTokenChainId;

  /// @notice Saving - Vault Deposit contract
  ISaving public savingDeposit;

  ISaving public savingSwapDeposit;

  ISaving public savingCrossChainSwap;

  /// @notice used ids
  BitMaps.BitMap private taskIds;

  constructor(
    address _owner,
    address _signer,
    address _treasurer,
    address _vaultToken,
    uint256 _vaultTokenChainId,
    ISaving _savingDeposit,
    ISaving _savingSwapDeposit,
    ISaving _savingCrossChainSwap
  ) Ownable(_owner) EIP712("Galxe General Instant Payment LSD", "1.0.0") {
    if (_signer == address(0)) {
      revert InvalidAddress();
    }
    if (_treasurer == address(0)) {
      revert InvalidAddress();
    }

    signer = _signer;
    treasurer = _treasurer;
    vaultToken = _vaultToken;
    vaultTokenChainId = _vaultTokenChainId;
    savingDeposit = _savingDeposit;
    savingSwapDeposit = _savingSwapDeposit;
    savingCrossChainSwap = _savingCrossChainSwap;
  }

  receive() external payable {}

  fallback() external payable {}

  modifier checkIfNeedRefund(uint256 _sent, address _recipient) {
    uint256 beforeBalance = address(this).balance;
    _;
    uint256 afterBalance = address(this).balance;
    uint256 refund = _sent - (beforeBalance - afterBalance);
    if (refund > 0) {
      (bool success, ) = _recipient.call{ value: refund }(new bytes(0));
      if (!success) {
        revert RefundFailed();
      }
    }
  }

  /// @notice Stops accepting new deposits.
  /// @dev Emits a `Paused` event.
  function pause() external onlyOwner {
    _pause();
  }
  /// @notice Resumes accepting new deposits.
  /// @dev Emits an `Unpaused` event.
  function unpause() external onlyOwner {
    _unpause();
  }

  /// @notice Set the signer address
  function setSigner(address _signer) external onlyOwner {
    if (_signer == address(0)) {
      revert InvalidAddress();
    }
    signer = _signer;
  }

  /// @notice Set the treasurer address
  function setTreasurer(address _treasurer) external onlyOwner {
    if (_treasurer == address(0)) {
      revert InvalidAddress();
    }
    treasurer = _treasurer;
  }

  /// @notice Set the vault token address
  function setVaultToken(address _vaultToken) external onlyOwner {
    if (_vaultToken == address(0)) {
      revert InvalidAddress();
    }
    vaultToken = _vaultToken;
  }

  /// @notice Set the vault token chain id
  function setVaultTokenChainId(uint256 _vaultTokenChainId) external onlyOwner {
    vaultTokenChainId = _vaultTokenChainId;
  }

  /// @notice Set the saving deposit address
  function setSavingDeposit(ISaving _savingDeposit) external onlyOwner {
    if (address(_savingDeposit) == address(0)) {
      revert InvalidAddress();
    }
    savingDeposit = _savingDeposit;
  }

  /// @notice Set the saving swap deposit address
  function setSavingSwapDeposit(ISaving _savingSwapDeposit) external onlyOwner {
    if (address(_savingSwapDeposit) == address(0)) {
      revert InvalidAddress();
    }
    savingSwapDeposit = _savingSwapDeposit;
  }

  /// @notice Set the saving cross chain swap address
  function setSavingCrossChainSwap(ISaving _savingCrossChainSwap) external onlyOwner {
    if (address(_savingCrossChainSwap) == address(0)) {
      revert InvalidAddress();
    }
    savingCrossChainSwap = _savingCrossChainSwap;
  }

  function hasDeposited(uint256 _taskId) public view returns (bool) {
    return BitMaps.get(taskIds, _taskId);
  }

  function deposit(
    address _user,
    address _depositToken,
    uint256 _depositAmount,
    uint256 _taskId,
    uint256 _taskFee,
    ISaving.ERC20PermitParam calldata _permit,
    uint256 _messageFee,
    bytes calldata _signature
  ) external payable whenNotPaused {
    _depositPreCheck(_user, _depositToken, _depositAmount, _taskId, _taskFee, _permit, _messageFee, _signature);

    BitMaps.set(taskIds, _taskId);

    _transfer(_depositToken, _depositAmount, _permit);

    uint256 savingAmount = _depositAmount - _taskFee;
    if (savingAmount != 0) {
      _deposit(_user, savingAmount, _messageFee);
    }

    emit Deposit(_user, _depositToken, _depositAmount, _taskId, _taskFee);
  }

  function swapDeposit(
    address _user,
    address _depositToken,
    uint256 _depositAmount,
    uint256 _taskId,
    uint256 _taskFee,
    address _depositPool,
    ISaving.BridgeTokenSwapParam calldata _sourceSwap,
    ISaving.ERC20PermitParam calldata _permit,
    uint256 _messgaeFee,
    bytes calldata _signature
  ) external payable whenNotPaused {
    _swapDepositPreCheck(
      _user,
      _depositToken,
      _depositAmount,
      _taskId,
      _taskFee,
      _depositPool,
      _sourceSwap,
      _permit,
      _messgaeFee,
      _signature
    );

    BitMaps.set(taskIds, _taskId);

    _transfer(_depositToken, _depositAmount, _permit);

    uint256 savingAmount = _depositAmount - _taskFee;
    if (savingAmount != 0) {
      uint256 sendNativeTokenAmount = _messgaeFee;
      if (_depositToken == address(0)) {
        sendNativeTokenAmount += savingAmount;
      }
      _swapDeposit(_user, _depositToken, savingAmount, _depositPool, _sourceSwap, _messgaeFee, sendNativeTokenAmount);
    }

    emit Deposit(_user, _depositToken, _depositAmount, _taskId, _taskFee);
  }

  function crossChainSwapDeposit(
    address _user,
    address _depositToken,
    uint256 _depositAmount,
    uint256 _taskId,
    uint256 _taskFee,
    uint32 _targetEndpointId,
    address _targetToken,
    ISaving.BridgeTokenSwapParam calldata _sourceSwap,
    ISaving.BridgeTokenSwapParam calldata _targetSwap,
    ISaving.ERC20PermitParam calldata _permit,
    uint128 _nativeDrop,
    uint256 _messageFee,
    bytes calldata _signature
  ) external payable whenNotPaused {
    _crossChainSwapDepositPreCheck(
      _user,
      _depositToken,
      _depositAmount,
      _taskId,
      _taskFee,
      _targetEndpointId,
      _targetToken,
      _sourceSwap,
      _targetSwap,
      _permit,
      _nativeDrop,
      _messageFee,
      _signature
    );

    BitMaps.set(taskIds, _taskId);

    _transfer(_depositToken, _depositAmount, _permit);

    uint256 savingAmount = _depositAmount - _taskFee;
    if (savingAmount != 0) {
      uint256 sendNativeTokenAmount = _messageFee;
      if (_depositToken == address(0)) {
        sendNativeTokenAmount += savingAmount;
      }
      _crossChainSwapDeposit(
        _user,
        _depositToken,
        savingAmount,
        _targetEndpointId,
        _targetToken,
        _sourceSwap,
        _targetSwap,
        _nativeDrop,
        _messageFee,
        sendNativeTokenAmount
      );
    }

    emit Deposit(_user, _depositToken, _depositAmount, _taskId, _taskFee);
  }

  function withdrawToken(address _token, uint256 _amount, address _recipient) external {
    if (msg.sender != treasurer) {
      revert PermissionDenied();
    }
    if (_token == address(0)) {
      if (address(this).balance < _amount) {
        revert InsufficientBalance();
      }
      (bool success, ) = _recipient.call{ value: _amount }(new bytes(0));
      if (!success) {
        revert WithdrawFailed();
      }
    } else {
      if (IERC20(_token).balanceOf(address(this)) < _amount) {
        revert InsufficientBalance();
      }
      IERC20(_token).safeTransfer(_recipient, _amount);
    }

    emit Withdraw(_recipient, _token, _amount);
  }

  function _depositPreCheck(
    address _user,
    address _depositToken,
    uint256 _depositAmount,
    uint256 _taskId,
    uint256 _taskFee,
    ISaving.ERC20PermitParam calldata _permit,
    uint256 _messageFee,
    bytes calldata _signature
  ) private {
    if (block.chainid != vaultTokenChainId) {
      revert InvalidChain();
    }
    _instantPaymentDepositPreCheck(_user, _depositToken, _depositAmount, _taskId, _taskFee, _messageFee);

    if (_depositToken != vaultToken) {
      revert InvalidDepositToken();
    }

    bool ok = _verify(
      _hashDeposit(_user, _depositToken, _depositAmount, _taskId, _taskFee, _permit, _messageFee),
      _signature
    );
    if (!ok) {
      revert InvalidSignature();
    }
  }

  function _swapDepositPreCheck(
    address _user,
    address _depositToken,
    uint256 _depositAmount,
    uint256 _taskId,
    uint256 _taskFee,
    address _depositPool,
    ISaving.BridgeTokenSwapParam calldata _sourceSwap,
    ISaving.ERC20PermitParam calldata _permit,
    uint256 _messgaeFee,
    bytes calldata _signature
  ) private {
    if (_depositPool == address(0)) {
      revert InvalidDepositPool();
    }

    if (_sourceSwap.minOut == 0 || _sourceSwap.feeTier == 0) {
      revert InvalidSourceSwapParam();
    }

    bool ok = _verify(
      _hashSwapDeposit(
        _user,
        _depositToken,
        _depositAmount,
        _taskId,
        _taskFee,
        _depositPool,
        _sourceSwap,
        _permit,
        _messgaeFee
      ),
      _signature
    );
    if (!ok) {
      revert InvalidSignature();
    }

    _instantPaymentDepositPreCheck(_user, _depositToken, _depositAmount, _taskId, _taskFee, _messgaeFee);
  }

  function _crossChainSwapDepositPreCheck(
    address _user,
    address _depositToken,
    uint256 _depositAmount,
    uint256 _taskId,
    uint256 _taskFee,
    uint32 _targetEndpointId,
    address _targetToken,
    ISaving.BridgeTokenSwapParam calldata _sourceSwap,
    ISaving.BridgeTokenSwapParam calldata _targetSwap,
    ISaving.ERC20PermitParam calldata _permit,
    uint128 _nativeDrop,
    uint256 _messageFee,
    bytes calldata _signature
  ) private {
    if (_targetEndpointId == 0) {
      revert InvalidTargetEndpointId();
    }

    if (_targetToken == address(0)) {
      revert InvalidTargetToken();
    }

    if (_sourceSwap.minOut == 0 || _sourceSwap.feeTier == 0) {
      revert InvalidSourceSwapParam();
    }

    if (_targetSwap.minOut == 0 || _targetSwap.feeTier == 0) {
      revert InvalidTargetSwapParam();
    }

    bool ok = _verify(
      _hashCrossChainSwapDeposit(
        _user,
        _depositToken,
        _depositAmount,
        _taskId,
        _taskFee,
        _targetEndpointId,
        _targetToken,
        _sourceSwap,
        _targetSwap,
        _permit,
        _nativeDrop,
        _messageFee
      ),
      _signature
    );
    if (!ok) {
      revert InvalidSignature();
    }

    _instantPaymentDepositPreCheck(_user, _depositToken, _depositAmount, _taskId, _taskFee, _messageFee);
  }

  function _instantPaymentDepositPreCheck(
    address _user,
    address _depositToken,
    uint256 _depositAmount,
    uint256 _taskId,
    uint256 _taskFee,
    uint256 _messageFee
  ) private {
    if (_user == address(0)) {
      revert InvalidAddress();
    }

    uint256 nativeTokenAmount = _messageFee;
    if (_depositToken == address(0)) {
      nativeTokenAmount += _depositAmount;
    }

    if (msg.value < nativeTokenAmount) {
      revert InsufficientDeposit();
    }

    if (_depositAmount == 0 || _depositAmount < _taskFee) {
      revert InvalidDepositAmount();
    }

    if (_taskFee == 0) {
      revert InvalidTaskFee();
    }

    if (hasDeposited(_taskId)) {
      revert AlreadyDeposited();
    }
  }

  function _deposit(address _to, uint256 _amount, uint256 _messageFee) private checkIfNeedRefund(_messageFee, _to) {
    uint256 savingAmount = _amount;
    IERC20(vaultToken).forceApprove(address(savingDeposit), savingAmount);
    savingDeposit.deposit{ value: _messageFee }(_to, savingAmount, true);
  }

  function _swapDeposit(
    address _recipient,
    address _sourceToken,
    uint256 _amount,
    address _depositPool,
    ISaving.BridgeTokenSwapParam calldata _sourceSwap,
    uint256 _messgaeFee,
    uint256 _sendNativeTokenAmount
  ) private checkIfNeedRefund(_sendNativeTokenAmount, _recipient) {
    if (_sourceToken != address(0)) {
      IERC20(_sourceToken).forceApprove(address(savingSwapDeposit), _amount);
    }
    savingSwapDeposit.swapDeposit{ value: _sendNativeTokenAmount }(
      _recipient,
      _sourceToken,
      _amount,
      _depositPool,
      _sourceSwap,
      ISaving.ERC20PermitParam(0, 0, bytes32(0), bytes32(0))
    );
  }

  function _crossChainSwapDeposit(
    address _recipient,
    address _sourceToken,
    uint256 _amount,
    uint32 _targetEndpointId,
    address _targetToken,
    ISaving.BridgeTokenSwapParam calldata _sourceSwap,
    ISaving.BridgeTokenSwapParam calldata _targetSwap,
    uint128 _nativeDrop,
    uint256 _messageFee,
    uint256 _sendNativeTokenAmount
  ) private checkIfNeedRefund(_sendNativeTokenAmount, _recipient) {
    if (_sourceToken != address(0)) {
      IERC20(_sourceToken).forceApprove(address(savingCrossChainSwap), _amount);
    }

    savingCrossChainSwap.crossChainSwap{ value: _sendNativeTokenAmount }(
      _recipient,
      _sourceToken,
      _amount,
      _targetEndpointId,
      _targetToken,
      _sourceSwap,
      _targetSwap,
      ISaving.ERC20PermitParam(0, 0, bytes32(0), bytes32(0)),
      _nativeDrop,
      0
    );
  }

  function _transfer(address _token, uint256 _amount, ISaving.ERC20PermitParam calldata _permit) private {
    if (_token != address(0)) {
      try
        IERC20Permit(address(_token)).permit(
          msg.sender,
          address(this),
          _amount,
          _permit.deadline,
          _permit.v,
          _permit.r,
          _permit.s
        )
      {} catch {}
      IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }
  }

  function _transferByPermit(
    address _token,
    uint256 _amount,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) private {
    if (_token != address(0)) {
      try IERC20Permit(address(_token)).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s) {} catch {}
      IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }
  }

  function _verify(bytes32 _hash, bytes calldata _signature) private view returns (bool) {
    return ECDSA.recover(_hash, _signature) == signer;
  }

  function _hashDeposit(
    address _user,
    address _depositToken,
    uint256 _depositAmount,
    uint256 _taskId,
    uint256 _taskFee,
    ISaving.ERC20PermitParam calldata _permit,
    uint256 _messageFee
  ) private view returns (bytes32) {
    return
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            keccak256(
              "Deposit(address user,address depositToken,uint256 depositAmount,uint256 taskId,uint256 taskFee,bytes32 permit,uint256 messageFee)"
            ),
            _user,
            _depositToken,
            _depositAmount,
            _taskId,
            _taskFee,
            _hashPermit(_permit),
            _messageFee
          )
        )
      );
  }

  function _hashSwapDeposit(
    address _user,
    address _depositToken,
    uint256 _depositAmount,
    uint256 _taskId,
    uint256 _taskFee,
    address _depositPool,
    ISaving.BridgeTokenSwapParam calldata _sourceSwap,
    ISaving.ERC20PermitParam calldata _permit,
    uint256 _messgaeFee
  ) private view returns (bytes32) {
    return
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            keccak256(
              "SwapDeposit(address user,address depositToken,uint256 depositAmount,uint256 taskId,uint256 taskFee,address depositPool,bytes32 sourceSwap,bytes32 permit,uint256 messageFee)"
            ),
            _user,
            _depositToken,
            _depositAmount,
            _taskId,
            _taskFee,
            _depositPool,
            _hashSwapParams(_sourceSwap),
            _hashPermit(_permit),
            _messgaeFee
          )
        )
      );
  }

  function _hashCrossChainSwapDeposit(
    address _user,
    address _depositToken,
    uint256 _depositAmount,
    uint256 _taskId,
    uint256 _taskFee,
    uint32 _targetEndpointId,
    address _targetToken,
    ISaving.BridgeTokenSwapParam calldata _sourceSwap,
    ISaving.BridgeTokenSwapParam calldata _targetSwap,
    ISaving.ERC20PermitParam calldata _permit,
    uint128 _nativeDrop,
    uint256 _messageFee
  ) private view returns (bytes32) {
    return
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            keccak256(
              "CrossChainSwapDeposit(address user,address depositToken,uint256 depositAmount,uint256 taskId,uint256 taskFee,uint32 targetEndpointId,address targetToken,bytes32 sourceSwap,bytes32 targetSwap,bytes32 permit,uint128 nativeDrop,uint256 messageFee)"
            ),
            _user,
            _depositToken,
            _depositAmount,
            _taskId,
            _taskFee,
            _targetEndpointId,
            _targetToken,
            _hashSwapParams(_sourceSwap),
            _hashSwapParams(_targetSwap),
            _hashPermit(_permit),
            _nativeDrop,
            _messageFee
          )
        )
      );
  }

  function _hashSwapParams(ISaving.BridgeTokenSwapParam calldata _swapParams) private pure returns (bytes32) {
    return keccak256(abi.encode(_swapParams.minOut, _swapParams.feeTier));
  }

  function _hashPermit(ISaving.ERC20PermitParam calldata _permit) private pure returns (bytes32) {
    return keccak256(abi.encode(_permit.deadline, _permit.v, _permit.r, _permit.s));
  }
}