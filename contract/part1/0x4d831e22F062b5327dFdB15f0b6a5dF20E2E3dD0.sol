// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IStoneVault} from "../interfaces/IStoneVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract StoneCarnival is ERC20, Ownable2Step {
    address public immutable stoneAddr;
    address public immutable stoneVaultAddr;

    uint256 public immutable lockPeriod = 90 days;
    uint256 public immutable startTime;
    uint256 public immutable minStoneAllowed;

    uint256 public cap;
    uint256 public totalStoneDeposited;
    uint256 public finalStoneAmount;

    bool public depositPaused;
    bool public terminated;

    mapping(address => uint256) public stoneDeposited;

    event StoneDeposited(address _user, uint256 _amount);
    event StoneWithdrawn(
        address _user,
        uint256 _amount,
        uint256 _burnAmount,
        uint256 _withAmount
    );
    event RequestMade(uint256 _amount);
    event DepositMade(uint256 _ethAmount, uint256 _stoneAmount);
    event ETHWithdrawn(uint256 _amount);
    event DepositPause(uint256 totalStone);
    event WithdrawalCancelled(uint256 _amount);
    event Terminate(uint256 timestamp);
    event SetCap(uint256 oldCap, uint256 newCap);

    constructor(
        address _stoneAddr,
        address _stoneVaultAddr,
        uint256 _cap,
        uint256 _minStoneAllowed
    ) ERC20("STONE Carnival LP", "cSTONE") {
        require(
            _stoneAddr != address(0) && _stoneVaultAddr != address(0),
            "invalid addr"
        );

        stoneAddr = _stoneAddr;
        stoneVaultAddr = _stoneVaultAddr;
        cap = _cap;
        startTime = block.timestamp;
        minStoneAllowed = _minStoneAllowed;
    }

    modifier DepositNotPaused() {
        require(!depositPaused, "deposit paused");
        _;
    }

    modifier DepositPaused() {
        require(depositPaused, "deposit not paused");
        _;
    }

    modifier OnlyTerminated() {
        require(terminated, "not terminated");
        _;
    }

    modifier NotTerminated() {
        require(!terminated, " terminated");
        _;
    }

    function depositStone(
        uint256 _amount
    ) external DepositNotPaused returns (uint256 cStoneAmount) {
        TransferHelper.safeTransferFrom(
            stoneAddr,
            msg.sender,
            address(this),
            _amount
        );

        cStoneAmount = _depositStone(msg.sender, _amount);
    }

    function depositStoneFor(
        address _user,
        uint256 _amount
    ) external DepositNotPaused returns (uint256 cStoneAmount) {
        TransferHelper.safeTransferFrom(
            stoneAddr,
            msg.sender,
            address(this),
            _amount
        );

        cStoneAmount = _depositStone(_user, _amount);
    }

    function _depositStone(
        address _user,
        uint256 _amount
    ) internal returns (uint256 cStoneAmount) {
        require(cap >= _amount + totalStoneDeposited, "cap");
        require(
            _amount + stoneDeposited[_user] >= minStoneAllowed,
            "not allowed"
        );

        stoneDeposited[_user] += _amount;
        totalStoneDeposited += _amount;

        _mint(_user, _amount);

        cStoneAmount = _amount;

        emit StoneDeposited(_user, _amount);
    }

    function withdrawStone() external OnlyTerminated {
        uint256 stoneShare = balanceOf(msg.sender);

        uint256 stoneAmountWith = (stoneShare * finalStoneAmount) /
            totalStoneDeposited;

        require(stoneAmountWith != 0, "zero amount");

        _burn(msg.sender, stoneShare);

        TransferHelper.safeTransfer(stoneAddr, msg.sender, stoneAmountWith);

        emit StoneWithdrawn(
            msg.sender,
            stoneDeposited[msg.sender],
            stoneShare,
            stoneAmountWith
        );
    }

    function terminate() external NotTerminated {
        require(block.timestamp >= startTime + lockPeriod, "cannot terminate");

        finalStoneAmount = IERC20(stoneAddr).balanceOf(address(this));

        depositPaused = true;
        terminated = true;

        emit Terminate(block.timestamp);
    }

    function setCap(uint256 _cap) external onlyOwner DepositNotPaused {
        emit SetCap(cap, _cap);
        cap = _cap;
    }

    function forceTerminate() external onlyOwner DepositPaused {
        finalStoneAmount = IERC20(stoneAddr).balanceOf(address(this));

        depositPaused = true;
        terminated = true;

        emit Terminate(block.timestamp);
    }

    function pauseDeposit() external onlyOwner DepositNotPaused {
        depositPaused = true;

        emit DepositPause(totalStoneDeposited);
    }

    function makeRequest(
        uint256 _amount
    ) external onlyOwner DepositPaused NotTerminated {
        require(
            _amount <= IERC20(stoneAddr).balanceOf(address(this)),
            "STONE not enough"
        );

        TransferHelper.safeApprove(stoneAddr, stoneVaultAddr, _amount);
        IStoneVault(stoneVaultAddr).requestWithdraw(_amount);

        emit RequestMade(_amount);
    }

    function withdrawETH(
        uint256 _amount
    ) external onlyOwner DepositPaused NotTerminated {
        uint256 amount = IStoneVault(stoneVaultAddr).instantWithdraw(
            _amount,
            0
        );

        emit ETHWithdrawn(amount);
    }

    function cancelWithdraw(
        uint256 _amount
    ) external onlyOwner DepositPaused NotTerminated {
        IStoneVault(stoneVaultAddr).cancelWithdraw(_amount);

        emit WithdrawalCancelled(_amount);
    }

    function makeDeposit(
        uint256 _amount
    ) external onlyOwner DepositPaused NotTerminated {
        require(_amount <= address(this).balance, "ether not enough");

        uint256 stoneAmount = IStoneVault(stoneVaultAddr).deposit{
            value: _amount
        }();

        emit DepositMade(_amount, stoneAmount);
    }

    receive() external payable {}
}