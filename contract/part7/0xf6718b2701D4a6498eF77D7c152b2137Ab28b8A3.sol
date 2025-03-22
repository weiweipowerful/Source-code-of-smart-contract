// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract stBTC is ERC20Burnable, Ownable {
    error InvalidMintor(address receiver);
    error InvaildAddress();

    address public _minter_contract;

    constructor() ERC20("Lorenzo stBTC", "stBTC") Ownable(msg.sender) {}

    modifier onlyMinterContract() {
        if (msg.sender != _minter_contract) {
            revert InvalidMintor(msg.sender);
        }
        _;
    }

    function setNewMinterContract(
        address newMinterContract
    ) external onlyOwner returns (bool) {
        if (newMinterContract == address(0x0)) {
            revert InvaildAddress();
        }
        _minter_contract = newMinterContract;
        return true;
    }

    function mint(address receipt, uint256 amount) external onlyMinterContract {
        _mint(receipt, amount);
    }
}