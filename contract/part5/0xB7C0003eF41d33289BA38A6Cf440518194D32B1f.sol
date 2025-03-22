// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract PUMP is ERC20, Ownable2Step {

    mapping(address => bool) public isMinter;

    event MinterSet(address indexed minter, bool status);

    modifier onlyMinter() {
        require(isMinter[_msgSender()], "PUMP: caller is not a minter");
        _;
    }

    constructor() ERC20("pumpBTC Governance token","PUMP") Ownable(tx.origin) {}

    function setMinter(address minter, bool status) public onlyOwner {
        isMinter[minter] = status;
        emit MinterSet(minter, status);
    }

    function mint(address to, uint256 amount) public onlyMinter {
        _mint(to, amount);
    }

    function burn(uint256 amount) public onlyMinter {
        _burn(_msgSender(), amount);
    }
}