// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


import "./interfaces/IEthgasPool.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IACLManager.sol";
import "./libraries/DepositHelper.sol";
import "./libraries/TransferFundHelper.sol";
import "./libraries/InputValidator.sol";

// openzeppelin contracts v4.7.3
import "./dependencies/openzeppelin-v5.0.1/utils/Pausable.sol";
import "./dependencies/openzeppelin-v5.0.1/utils/Context.sol";
import "./dependencies/openzeppelin-v5.0.1/utils/ReentrancyGuard.sol";


contract EthgasPool is IEthgasPool, Context, ReentrancyGuard, Pausable {

	mapping(address => uint256) public dailyWithdrawalCap;
	mapping(address => bool) public supportedToken;
	mapping(address => uint256) public currentDailyWithdrawalAmount;
	mapping(address => uint256) public lastWithdrawalTime;
	

	IACLManager public aclManager;
	IWETH public immutable weth;

	modifier onlyAdminRole() {
		aclManager.checkAdminRole(msg.sender);
		_;
	}

	modifier onlyTreasurerRole() {
		aclManager.checkTreasurerRole(msg.sender);
		_;
	}


	modifier onlyTimelockRole() {
		aclManager.checkTimelockRole(msg.sender);
		_;
	}

	modifier onlyPauserRole() {
		aclManager.checkPauserRole(msg.sender);
		_;
	}

	modifier onlyBookKeeperRole() {
		aclManager.checkBookKeeperRole(msg.sender);
		_;
	}

	constructor(IACLManager _aclManager, IWETH _weth, address[] memory _token, uint256[] memory _cap) {
		InputValidator.validateAddr(address(_aclManager));
		InputValidator.validateAddr(address(_weth));
		aclManager = _aclManager;
		weth = _weth;
		if ((_token.length != _cap.length) || _token.length == 0) {
			revert InvalidParamLength();
		}
		for (uint256 i; i < _token.length; i++) {
			InputValidator.validateAddr(address(_token[i]));
			dailyWithdrawalCap[_token[i]] = _cap[i];
			emit DailyWithdrawalCapChanged(_token[i], _cap[i]);

			supportedToken[_token[i]] = true;
			emit SupportedTokenChanged(_token[i], true);
		}
	}


	function pause() external onlyPauserRole {
		super._pause();
    }

	function unpause() external onlyAdminRole {
		super._unpause();
    }

	function setAclManager(IACLManager _aclManager) external onlyTimelockRole {
		InputValidator.validateAddr(address(_aclManager));
		aclManager = _aclManager;
		emit AclManagerChanged(address(_aclManager));
	}


	function setDailyWithdrawalCap(address _token, uint256 _cap) external onlyTimelockRole {
	    InputValidator.validateAddr(_token);	
		dailyWithdrawalCap[_token] = _cap;
		emit DailyWithdrawalCapChanged(_token, _cap);
	}

	function setSupportedToken(address _token, bool _isSupport) external onlyBookKeeperRole {
		InputValidator.validateAddr(_token);
		supportedToken[_token] = _isSupport;
		emit SupportedTokenChanged(_token, _isSupport);
	}
	
	function deposit(TokenTransfer[] memory tokenTransfers) external whenNotPaused payable {
		DepositHelper.deposit(tokenTransfers, weth, supportedToken);
	}

	



	function serverTransferFundSingle(address clientAddress, TokenTransfer[] calldata tokenTransfer) onlyTreasurerRole nonReentrant whenNotPaused external {
		TransferFundHelper.serverTransferFund(
			false, clientAddress, tokenTransfer, dailyWithdrawalCap, lastWithdrawalTime, currentDailyWithdrawalAmount
		);
	}

	/**
	 * @dev serverTransferFund only transfers external tokens out, does not check nor update internal balance
	 */
	function serverTransferFund(address[] calldata clientAddresses, TokenTransfer[][] calldata tokenTransfers) onlyTreasurerRole nonReentrant whenNotPaused external {
		if ((clientAddresses.length != tokenTransfers.length) || clientAddresses.length == 0) {
			revert InvalidParamLength();
		}
		for(uint i = 0; i < clientAddresses.length; i++) {
			TransferFundHelper.serverTransferFund(
				false, clientAddresses[i], tokenTransfers[i], dailyWithdrawalCap, lastWithdrawalTime, currentDailyWithdrawalAmount
			);
		} 

	}

	/**
	 * @dev can transfer any amount out
	 */
	function serverTransferAnyFund(address[] calldata clientAddresses, TokenTransfer[][] calldata tokenTransfers) onlyTimelockRole nonReentrant whenNotPaused external {
		if ((clientAddresses.length != tokenTransfers.length) || clientAddresses.length == 0) {
			revert InvalidParamLength();
		}
		for(uint i = 0; i < clientAddresses.length; i++) {
			TransferFundHelper.serverTransferFund(
				true, clientAddresses[i], tokenTransfers[i], dailyWithdrawalCap, lastWithdrawalTime, currentDailyWithdrawalAmount
			);
		} 
	}

}