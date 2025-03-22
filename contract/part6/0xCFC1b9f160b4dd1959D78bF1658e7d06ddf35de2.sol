// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BuyIDegenToken is ReentrancyGuard {
    using SafeERC20 for IERC20;

    constructor(address wallet) {
        receiver = wallet;
    }

    event Buy(address token, uint256 payAmount);

    address public immutable receiver;

    mapping(address => uint256) public ethRecord;
    mapping(address => mapping(address => uint256)) public erc20Record;

    function buyERC20(address token, uint256 amount) public {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        erc20Record[token][msg.sender] = erc20Record[token][msg.sender] + amount;
        emit Buy(token, amount);
    }

    function buyETH() public payable {
        ethRecord[msg.sender] = ethRecord[msg.sender] + msg.value;
        emit Buy(address(0), msg.value);
    }

    function withdraw(address[] memory tokens, uint256 ethAmount) public nonReentrant {
        address target = receiver;
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 withdrawAmount = token.balanceOf(address(this));
            token.safeTransfer(target, withdrawAmount);
        }

        address payable ethTarget = payable(receiver);
        (bool success, ) = ethTarget.call{ value: ethAmount }("");
        require(success, "Failed");
    }

    receive() external payable {
        buyETH();
    }
}