/**
 *Submitted for verification at Etherscan.io on 2025-02-27
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Token {

    
    function totalSupply() public view virtual returns (uint256) {}

    function balanceOf(address _owner) public view virtual returns (uint256) {}
    
    function transfer(address _to, uint256 _value) public virtual returns (bool success) {}

    function transferFrom(address _from, address _to, uint256 _value) public virtual returns (bool success) {}

    function approve(address _spender, uint256 _value) public virtual returns (bool success) {}

    function allowance(address _owner, address _spender) public view virtual returns (uint256 remaining) {}

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract StandardToken is Token {

    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;
    uint256 _totalSupply;  

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;  
    }

    function transfer(address _to, uint256 _value) public override returns (bool success) {
        require(balances[msg.sender] >= _value && _value > 0, "Insufficient balance");
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public override returns (bool success) {
        require(balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0, "Transfer not allowed");
        balances[_to] += _value;
        balances[_from] -= _value;
        allowed[_from][msg.sender] -= _value;
        emit Transfer(_from, _to, _value);
        return true;
    }

    function balanceOf(address _owner) public view override returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) public override returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public view override returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    constructor(uint256 initialSupply) {
        _totalSupply = initialSupply;  
        balances[msg.sender] = _totalSupply;  
    }
}

contract HashnodeTestCoin is StandardToken {

    string public name;
    uint8 public decimals;
    string public symbol;
    string public version = 'H1.0';
    uint256 public unitsOneEthCanBuy;
    uint256 public totalEthInWei;
    address public fundsWallet;

    // Updated constructor to set initial values
    constructor(uint256 initialSupply) StandardToken(initialSupply) {
        _totalSupply = 1000000000000000000000000000000;
        balances[msg.sender] = 1000000000000000000000000000000;              
        name = "METALBANK X";                      
        decimals = 18;
        symbol = "MBXAU";
        unitsOneEthCanBuy = 10000;  // Adjust the price of your token here
        fundsWallet = msg.sender;
    }

    receive() external payable {
        totalEthInWei += msg.value;
        uint256 amount = msg.value * unitsOneEthCanBuy;
        require(balances[fundsWallet] >= amount, "Not enough tokens available");

        balances[fundsWallet] -= amount;
        balances[msg.sender] += amount;

        emit Transfer(fundsWallet, msg.sender, amount);

        payable(fundsWallet).transfer(msg.value);  // Send the ETH to the fundsWallet
    }

    function approveAndCall(address _spender, uint256 _value, bytes memory _extraData) public returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);

        (bool successCall, ) = _spender.call(abi.encodeWithSignature("receiveApproval(address,uint256,address,bytes)", msg.sender, _value, address(this), _extraData));
        require(successCall, "Approve and call failed");

        return true;
    }
}