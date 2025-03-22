// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract MakToken is ERC20, Ownable2Step {
    uint8 immutable _decimals;
    uint256 public constant INITIAL_SUPPLY = 1000000000 * (10**18);

    mapping(address => bool) public operators;
    mapping(address => bool) public transferBlacklist;
    mapping(address => bool) public receiveBlacklist;

    event AddTransferBlacklist(address addr);
    event RemoveTransferBlacklist(address addr);
    event AddReceiveBlacklist(address addr);
    event RemoveReceiveBlacklist(address addr);
    event AddOperator(address addr);
    event RemoveOperator(address addr);

    constructor(string memory name_, string memory symbol_, address vestingContract) ERC20(name_, symbol_) Ownable(msg.sender) {
        _decimals = 18;
        require(vestingContract != address(0));
        _mint(vestingContract, INITIAL_SUPPLY);
    }

    modifier onlyOperator() {
        require(operators[msg.sender], "sender not allowed");
        _;
    }

    function cap() external pure returns (uint256){
        return INITIAL_SUPPLY;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!transferBlacklist[from], "from in blacklist");
        require(!receiveBlacklist[to], "to in blacklist");
        super._update(from, to, value);
    }

    function addTransferBlacklist(address addr) external onlyOperator {
        transferBlacklist[addr] = true;
        emit AddTransferBlacklist(addr);
    }

    function removeTransferBlacklist(address addr) external onlyOperator {
        delete transferBlacklist[addr];
        emit RemoveTransferBlacklist(addr);
    }


    function addReceiveBlacklist(address addr) external onlyOperator {
        receiveBlacklist[addr] = true;
        emit AddReceiveBlacklist(addr);
    }

    function removeReceiveBlacklist(address addr) external onlyOperator {
        delete receiveBlacklist[addr];
        emit  RemoveReceiveBlacklist(addr);
    }

    function addOperatorRole(address to) external onlyOwner {
        operators[to] = true;
        emit AddOperator(to);
    }

    function removeOperatorRole(address to) external onlyOwner {
        operators[to] = false;
        emit RemoveOperator(to);
    }

}