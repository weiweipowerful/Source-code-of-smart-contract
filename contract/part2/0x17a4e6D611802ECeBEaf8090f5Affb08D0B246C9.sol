/**
 *Submitted for verification at Etherscan.io on 2025-03-18
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MYTOKEN {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    uint256 public burnedTokens;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed burner, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _initialSupply * 10 ** uint256(_decimals);
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address _to, uint256 _value) external returns (bool success) {
        require(_to != address(0), "MYTOKEN: transfer to the zero address");
        require(balanceOf[msg.sender] >= _value, "MYTOKEN: transfer amount exceeds balance");

        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) external returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success) {
        require(_from != address(0), "MYTOKEN: transfer from the zero address");
        require(_to != address(0), "MYTOKEN: transfer to the zero address");
        require(balanceOf[_from] >= _value, "MYTOKEN: transfer amount exceeds balance");
        require(_value <= allowance[_from][msg.sender], "MYTOKEN: transfer amount exceeds allowance");

        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        allowance[_from][msg.sender] -= _value;
        emit Transfer(_from, _to, _value);
        return true;
    }

    function burnedSupply() external view returns (uint256) {
        return burnedTokens;
    }

    function burn(uint256 _amount) external {
        require(balanceOf[msg.sender] >= _amount, "MYTOKEN: burn amount exceeds balance");

        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        burnedTokens += _amount;
        emit Transfer(msg.sender, address(0), _amount);
        emit Burn(msg.sender, _amount);
    }
}