/**
 *Submitted for verification at Etherscan.io on 2024-11-16
*/

//SPDX-License-Identifier:UNLICENSE
pragma solidity ^0.8.19;

contract PlotsFinance {
    uint256 public totalSupply;
    uint256 public maxSupply = 1000000000000000000000000000;
    string public name;
    string public symbol;
    uint8 public decimals;
    address private ZeroAddress = address(0);
    address public distributor;

    // Event Declarations
    event Transfer(address indexed from, address indexed to, uint256 value);    
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BurnEvent(address indexed burner, uint256 indexed buramount);

    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        totalSupply = 0;
        name = _name;
        symbol = _symbol;
        decimals = 18;
        distributor = ZeroAddress; // Set distributor to address zero
    }

    function setDistributor(address _distributor) external {
        require(distributor == ZeroAddress, "Distributor already set");
        require(msg.sender == 0xc932b3a342658A2d3dF79E4661f29DfF6D7e93Ce, "Unauthorized sender");
        distributor = _distributor;
    }

    function balanceOf(address Address) public view returns (uint256 balance) {
        return balances[Address];
    }

    function approve(address delegate, uint256 _amount) public returns (bool) {
        allowance[msg.sender][delegate] = _amount;
        emit Approval(msg.sender, delegate, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool) {
        require(_amount <= balances[_from]);    
        require(_amount <= allowance[_from][msg.sender]); 
    
        balances[_from] -= _amount;
        allowance[_from][msg.sender] -= _amount;
        balances[_to] += _amount;
        emit Transfer(_from, _to, _amount);
        return true;
    }

    function transfer(address _to, uint256 _amount) public returns (bool) {
        require(_amount <= balances[msg.sender]);
        balances[msg.sender] -= _amount;
        balances[_to] += _amount;
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function mint(address _MintTo, uint256 _MintAmount) public returns (bool success) {
        require(msg.sender == distributor, "Unauthorized distributor");
        require(totalSupply + _MintAmount <= maxSupply, "Exceeds max supply");
        balances[_MintTo] += _MintAmount;
        totalSupply += _MintAmount;
        emit Transfer(ZeroAddress, _MintTo, _MintAmount);
        return true;
    }

    function burn(uint256 _BurnAmount) public {
        require(balances[msg.sender] >= _BurnAmount, "Insufficient balance");
        balances[msg.sender] -= _BurnAmount;
        totalSupply -= _BurnAmount;
        emit Transfer(msg.sender, ZeroAddress, _BurnAmount);
        emit BurnEvent(msg.sender, _BurnAmount);
    }
}