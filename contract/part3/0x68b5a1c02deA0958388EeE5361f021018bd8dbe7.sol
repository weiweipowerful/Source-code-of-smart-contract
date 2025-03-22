// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOpool} from "./interface/IOpool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Opool is Ownable, IOpool, ReentrancyGuard {
    using SafeERC20 for IERC20;
    /// token address => receiver address
    mapping(address => address) public tokenReceivers;
    /// maker address => status
    mapping(address => bool) public makerList;
    /// token address => manager address
    mapping(address => address) public managerList;

    constructor(address _owner, address[] memory _makers) Ownable(_owner) {
        require(_owner != address(0), "Opool: owner is zero");

        for (uint256 i = 0; i < _makers.length; i++) {
            makerList[_makers[i]] = true;
        }
    }

    function _fetchTokenReceiver(
        address token
    ) internal view returns (address) {
        address receiver = tokenReceivers[token];
        return receiver == address(0) ? address(this) : receiver;
    }

    function _transfer(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool sent, ) = payable(to).call{value: amount}("");
            require(sent, "Opool: call error");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function inbox(
        address feeReceiver,
        address feeToken,
        uint256 feeAmount,
        address bridgeToken,
        uint256 bridgeAmount,
        bytes calldata data
    ) external payable nonReentrant {
        if (feeToken == address(0)) {
            require(msg.value >= feeAmount, "Opool: insufficient fee value");
            (bool sentFee, ) = payable(feeReceiver).call{value: feeAmount}("");
            require(sentFee, "Opool: fee transfer failed");
        } else {
            IERC20(feeToken).safeTransferFrom(msg.sender, feeReceiver, feeAmount);
        }

        address receiver = _fetchTokenReceiver(bridgeToken);
        if (bridgeToken == address(0)) {
            require(
                msg.value >= bridgeAmount + (feeToken == address(0) ? feeAmount : 0),
                "Opool: insufficient value for transfer"
            );
            (bool sent, ) = payable(receiver).call{value: bridgeAmount}("");
            require(sent, "Opool: native token transfer failed");
        } else {
            IERC20(bridgeToken).safeTransferFrom(msg.sender, receiver, bridgeAmount);
        }

        emit Inbox(
            receiver,
            bridgeToken,
            feeReceiver,
            feeToken,
            feeAmount,
            bridgeAmount,
            data
        );
    }

    function outbox(
        address token,
        address to,
        uint256 amount,
        bytes calldata data
    ) external {
        require(makerList[msg.sender], "Opool: not maker");
        _transfer(token, to, amount);
        emit Outbox(token, to, amount, data);
    }

    function outboxBatch(
        address token,
        address[] calldata tos,
        uint256[] calldata amounts,
        bytes[] calldata datas
    ) external {
        require(makerList[msg.sender], "Opool: not maker");
        require(
            tos.length == amounts.length && tos.length == datas.length,
            "Opool: invalid length"
        );
        for (uint256 i = 0; i < tos.length; i++) {
            _transfer(token, tos[i], amounts[i]);
            emit Outbox(token, tos[i], amounts[i], datas[i]);
        }
    }

    function setMakerList(
        address[] calldata makers,
        bool[] calldata status
    ) external onlyOwner {
        require(makers.length == status.length, "Opool: invalid length");
        for (uint256 i = 0; i < makers.length; i++) {
            makerList[makers[i]] = status[i];
        }
    }

    function setManagerList(
        address[] calldata tokens,
        address[] calldata managers
    ) external onlyOwner {
        require(tokens.length == managers.length, "Opool: invalid length");
        for (uint256 i = 0; i < tokens.length; i++) {
            managerList[tokens[i]] = managers[i];
        }
    }

    function setTokenReceiver(
        address[] calldata tokens,
        address[] calldata receivers
    ) external onlyOwner {
        require(tokens.length == receivers.length, "Opool: invalid length");
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenReceivers[tokens[i]] = receivers[i];
        }
    }

    function withdraw(address token, uint256 amount) external {
        require(
            (owner() == msg.sender) || managerList[token] == msg.sender,
            "Opool: no permission"
        );
        _transfer(token, msg.sender, amount);
    }

    receive() external payable {}
}