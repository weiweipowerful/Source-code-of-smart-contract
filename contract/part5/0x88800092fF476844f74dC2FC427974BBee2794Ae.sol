/**
 *Submitted for verification at Etherscan.io on 2022-01-27
*/

// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.7;

// https://github.com/AmbireTech/wallet/blob/main/contracts/WALLET.sol
contract WALLETToken {
	// Constants
	string public constant name = "Ambire Wallet";
	string public constant symbol = "WALLET";
	uint8 public constant decimals = 18;
	uint public constant MAX_SUPPLY = 1_000_000_000 * 1e18;

	// Mutable variables
	uint public totalSupply;
	mapping(address => uint) balances;
	mapping(address => mapping(address => uint)) allowed;

	event Approval(address indexed owner, address indexed spender, uint amount);
	event Transfer(address indexed from, address indexed to, uint amount);

	event SupplyControllerChanged(address indexed prev, address indexed current);

	address public supplyController;
	constructor(address _supplyController) {
		supplyController = _supplyController;
		emit SupplyControllerChanged(address(0), _supplyController);
	}

	function balanceOf(address owner) external view returns (uint balance) {
		return balances[owner];
	}

	function transfer(address to, uint amount) external returns (bool success) {
		balances[msg.sender] = balances[msg.sender] - amount;
		balances[to] = balances[to] + amount;
		emit Transfer(msg.sender, to, amount);
		return true;
	}

	function transferFrom(address from, address to, uint amount) external returns (bool success) {
		balances[from] = balances[from] - amount;
		allowed[from][msg.sender] = allowed[from][msg.sender] - amount;
		balances[to] = balances[to] + amount;
		emit Transfer(from, to, amount);
		return true;
	}

	function approve(address spender, uint amount) external returns (bool success) {
		allowed[msg.sender][spender] = amount;
		emit Approval(msg.sender, spender, amount);
		return true;
	}

	function allowance(address owner, address spender) external view returns (uint remaining) {
		return allowed[owner][spender];
	}

	// Supply control
	function innerMint(address owner, uint amount) internal {
		totalSupply = totalSupply + amount;
		require(totalSupply < MAX_SUPPLY, 'MAX_SUPPLY');
		balances[owner] = balances[owner] + amount;
		// Because of https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#transfer-1
		emit Transfer(address(0), owner, amount);
	}

	function mint(address owner, uint amount) external {
		require(msg.sender == supplyController, 'NOT_SUPPLYCONTROLLER');
		innerMint(owner, amount);
	}

	function changeSupplyController(address newSupplyController) external {
		require(msg.sender == supplyController, 'NOT_SUPPLYCONTROLLER');
		// Emitting here does not follow checks-effects-interactions-logs, but it's safe anyway cause there are no external calls
		emit SupplyControllerChanged(supplyController, newSupplyController);
		supplyController = newSupplyController;
	}
}