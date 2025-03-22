/*

    Copyright 2021 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import {SafeERC20} from "../../lib/SafeERC20.sol";
import {IERC20} from "../../intf/IERC20.sol";
import {SafeMath} from "../../lib/SafeMath.sol";
import {ReentrancyGuard} from "../../lib/ReentrancyGuard.sol";
import {BaseMine} from "./BaseMine.sol";
import {IRewardVault} from "./RewardVault.sol";

contract ERC20MineV3 is ReentrancyGuard, BaseMine {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // ============ Storage ============

    address public _TOKEN_;

    function init(address owner, address token) external {
        super.initOwner(owner);
        _TOKEN_ = token;
    }

    // ============ Event  ============

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event FundAndSet(address rewardToken, uint256 amount, uint256 newEndBlock, uint256 newRewardPerBlock);

    // ============ Deposit && Withdraw && Exit ============

    function deposit(uint256 amount) external preventReentrant {
        require(amount > 0, "DODOMineV3: CANNOT_DEPOSIT_ZERO");

        _updateAllReward(msg.sender);

        uint256 erc20OriginBalance = IERC20(_TOKEN_).balanceOf(address(this));
        IERC20(_TOKEN_).safeTransferFrom(msg.sender, address(this), amount);
        uint256 actualStakeAmount = IERC20(_TOKEN_).balanceOf(address(this)).sub(erc20OriginBalance);
        
        _totalSupply = _totalSupply.add(actualStakeAmount);
        _balances[msg.sender] = _balances[msg.sender].add(actualStakeAmount);

        emit Deposit(msg.sender, actualStakeAmount);
    }

    function withdraw(uint256 amount) external preventReentrant {
        require(amount > 0, "DODOMineV3: CANNOT_WITHDRAW_ZERO");

        _updateAllReward(msg.sender);
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        IERC20(_TOKEN_).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function fundAndSet(
        address rewardToken, 
        uint256 amount, 
        uint256 newEndBlock, 
        uint256 newRewardPerBlock
    ) onlyOwner external {
        address rewardVault = getVaultByRewardToken(rewardToken);
        uint256 id = getIdByRewardToken(rewardToken);

        IERC20(rewardToken).safeTransferFrom(msg.sender, rewardVault, amount);
        IRewardVault(rewardVault).syncValue();

        setReward(id, newRewardPerBlock);
        setEndBlock(id, newEndBlock);

        emit FundAndSet(rewardToken, amount, newEndBlock, newRewardPerBlock);
    }
}