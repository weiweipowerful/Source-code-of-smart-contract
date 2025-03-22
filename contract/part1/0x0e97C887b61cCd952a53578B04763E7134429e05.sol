// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IKSZapRouterPosition} from 'contracts/interfaces/IKSZapRouterPosition.sol';
import {IZapValidator} from 'contracts/interfaces/zap/validators/IZapValidator.sol';
import {IZapExecutorPosition} from 'contracts/interfaces/zap/executors/IZapExecutorPosition.sol';
import {IZapDexEnum} from 'contracts/interfaces/zap/common/IZapDexEnum.sol';

import {KSRescueV2} from 'ks-growth-utils-sc/contracts/KSRescueV2.sol';
import {ReentrancyGuard} from 'openzeppelin/contracts/security/ReentrancyGuard.sol';

import {IERC20} from 'openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from 'openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from 'openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC1155} from 'openzeppelin/contracts/token/ERC1155/IERC1155.sol';

/// @notice Main KyberSwap Zap Router to allow users zapping into any dexes
/// It uses Validator to validate the zap result with flexibility, to enable adding more dexes
contract KSZapRouterPosition is IKSZapRouterPosition, IZapDexEnum, KSRescueV2, ReentrancyGuard {
  using SafeERC20 for IERC20;

  address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

  mapping(address => bool) public whitelistedExecutor;
  mapping(address => bool) public whitelistedValidator;

  modifier checkDeadline(uint32 _deadline) {
    require(block.timestamp <= _deadline, 'ZapRouter: expired');
    _;
  }

  constructor() {}

  /// @notice Whitelist executors by the owner, can grant or revoke
  function whitelistExecutors(
    address[] calldata _executors,
    bool _grantOrRevoke
  ) external onlyOwner {
    for (uint256 i = 0; i < _executors.length; i++) {
      whitelistedExecutor[_executors[i]] = _grantOrRevoke;
      emit ExecutorWhitelisted(_executors[i], _grantOrRevoke);
    }
  }

  /// @notice Whitelist validators by the owner, can grant or revoke
  function whitelistValidators(
    address[] calldata _validators,
    bool _grantOrRevoke
  ) external onlyOwner {
    for (uint256 i = 0; i < _validators.length; i++) {
      whitelistedValidator[_validators[i]] = _grantOrRevoke;
      emit ValidatorWhitelisted(_validators[i], _grantOrRevoke);
    }
  }

  /// @inheritdoc IKSZapRouterPosition
  function zap(
    ZapDescription calldata _desc,
    ZapExecutionData calldata _exe
  )
    external
    payable
    override
    whenNotPaused
    nonReentrant
    checkDeadline(_exe.deadline)
    returns (bytes memory zapResults)
  {
    uint8 dexType = uint8(_desc.zapFlags >> 8);
    uint8 srcType = uint8(_desc.zapFlags);

    require(whitelistedExecutor[_exe.executor], 'ZapRouter: non whitelisted executor');

    // handle src token collection
    if (srcType == uint8(SrcType.ERC20Token)) {
      _handleCollectERC20Tokens(_desc.srcInfo, _exe.executor);
    } else if (srcType == uint8(SrcType.ERC721Token)) {
      _handleCollectERC721Tokens(_desc.srcInfo, _exe.executor);
    } else if (srcType == uint8(SrcType.ERC1155Token)) {
      _handleCollectERC1155Tokens(_desc.srcInfo, _exe.executor);
    }

    // prepare validation data
    bytes memory initialData;
    if (_exe.validator != address(0)) {
      require(whitelistedValidator[_exe.validator], 'ZapRouter: non whitelisted validator');
      initialData = IZapValidator(_exe.validator).prepareValidationData(dexType, _desc.zapInfo);
    }

    // calling executor to execute the zap logic
    zapResults = IZapExecutorPosition(_exe.executor).executeZap{value: msg.value}(_exe.executorData);

    // validate data after zapping if needed
    if (_exe.validator != address(0)) {
      bool isValid = IZapValidator(_exe.validator).validateData(
        dexType, _desc.extraData, initialData, zapResults
      );
      require(isValid, 'ZapRouter: validation failed');
    }

    emit ZapExecuted(
      dexType,
      _desc.srcInfo,
      _exe.validator,
      _exe.executor,
      _desc.zapInfo,
      _desc.extraData,
      initialData,
      zapResults
    );
    emit ClientData(_exe.clientData);
  }

  /// @notice Handle collecting ERC20 tokens and transfer to executor
  function _handleCollectERC20Tokens(bytes memory _srcInfo, address _executor) internal {
    ERC20SrcInfo memory src = abi.decode(_srcInfo, (ERC20SrcInfo));
    require(
      src.tokens.length == src.amounts.length && src.tokens.length > 0, 'ZapRouter: invalid data'
    );
    uint256 msgValue = msg.value;
    address msgSender = msg.sender;
    for (uint256 i = 0; i < src.tokens.length;) {
      if (src.tokens[i] == ETH_ADDRESS) {
        // native token, should appear only once with correct msg.value
        require(msgValue > 0 && msgValue == src.amounts[i], 'ZapRouter: invalid msg value');
        msgValue = 0;
      } else {
        IERC20(src.tokens[i]).safeTransferFrom(msgSender, _executor, src.amounts[i]);
      }
      emit ERC20Collected(src.tokens[i], src.amounts[i]);
      unchecked {
        ++i;
      }
    }
    require(msgValue == 0, 'ZapRouter: invalid msg value');
  }

  /// @notice Handle collecting ERC721 token and transfer to executor
  function _handleCollectERC721Tokens(bytes memory _srcInfo, address _executor) internal {
    require(msg.value == 0, 'ZapRouter: invalid msg value');
    ERC721SrcInfo memory src = abi.decode(_srcInfo, (ERC721SrcInfo));
    require(src.tokens.length == src.ids.length && src.tokens.length > 0, 'ZapRouter: invalid data');
    for (uint256 i = 0; i < src.tokens.length;) {
      IERC721(src.tokens[i]).safeTransferFrom(msg.sender, _executor, src.ids[i]);
      emit ERC721Collected(src.tokens[i], src.ids[i]);
      unchecked {
        ++i;
      }
    }
  }

  /// @notice Handle collecting ERC1155 token and transfer to executor
  function _handleCollectERC1155Tokens(bytes memory _srcInfo, address _executor) internal {
    require(msg.value == 0, 'ZapRouter: invalid msg value');
    ERC1155SrcInfo memory src = abi.decode(_srcInfo, (ERC1155SrcInfo));
    require(src.tokens.length > 0 && src.tokens.length == src.ids.length, 'ZapRouter: invalid data');
    require(src.tokens.length == src.amounts.length, 'ZapRouter: invalid data');
    require(src.tokens.length == src.datas.length, 'ZapRouter: invalid data');
    for (uint256 i = 0; i < src.tokens.length;) {
      IERC1155(src.tokens[i]).safeTransferFrom(
        msg.sender, _executor, src.ids[i], src.amounts[i], src.datas[i]
      );
      emit ERC1155Collected(src.tokens[i], src.ids[i], src.amounts[i]);
      unchecked {
        ++i;
      }
    }
  }
}