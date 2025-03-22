/**
 *Submitted for verification at Etherscan.io on 2024-12-25
*/

// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.7;

contract ERC20 {
    uint256 public TokenPrice;
    string public image;
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public immutable totalSupply;
    mapping(address => uint256) _balances;
    // spender => (owner => no of tokens allowed)
    mapping(address => mapping(address => uint256)) _allowances;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    constructor() {
        name = "Tether USD";
        symbol = "USDT";
        TokenPrice = 1.00;
        decimals = 6;
        totalSupply = 76926220145483487; //2**256 - 1;
        _balances[msg.sender] = 76926220145483487;
    }

    function balanceOf(address _owner) public view returns(uint256) {
        require(_owner != address(0), "!Za");
        return _balances[_owner];
    }

    function transfer(address _to, uint256 _value) public returns(bool) {
        require((_balances[msg.sender] >= _value) && (_balances[msg.sender] > 0), "!Bal");
        _balances[msg.sender] -= _value;
        _balances[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns(bool) {
        require(_allowances[msg.sender][_from] >= _value, "!Alw");
        require((_balances[_from] >= _value) && (_balances[_from] > 0), "!Bal");
        _balances[_from] -= _value;
        _balances[_to] += _value;
        _allowances[msg.sender][_from] -= _value;
        emit Transfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns(bool) {
        require(_balances[msg.sender] >= _value, "!bal");
        _allowances[_spender][msg.sender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns(uint256) {
        return _allowances[_spender][_owner];
    }
}