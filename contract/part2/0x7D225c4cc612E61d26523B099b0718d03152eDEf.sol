// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FlokiFork is Context, ERC20, Ownable {
    using Address for address;

    uint256 private started;
    uint256 private end;
    uint256 private _supply;

    bool public swapping;
    bool private tradingEnabled;

    event TradingEnabled(
        bool indexed tradingActivated
    );

    constructor(uint256 _end) ERC20("FlokiFork", "FORK") Ownable(msg.sender) {

        _supply = 1 * 10 ** 13 * 10 ** decimals();
        end = _end;

        _mint(owner(), _supply);
    }

    receive() external payable {

  	}

    function burn(uint256 amount) public {
        _burn(msg.sender, amount * 10 ** decimals());
    }

    function enableTrading() public onlyOwner {
        tradingEnabled = true;
        started = block.timestamp;

        emit TradingEnabled(true);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        
        if(!tradingEnabled && from != owner() && to != owner()) {
            revert("!Trading");
        }

        else if(block.timestamp <= started + end && from != owner() && to != owner()) {
            require(tx.gasprice <= block.basefee + 5 gwei, "Gas price too high");
            uint256 balance = balanceOf(to);
            require(balance + amount <= ((totalSupply() * 944) / 100000), "Transfer amount exceeds maximum wallet");
            uint256 integerAmount = amount / 10**decimals();
            require(integerAmount != amount, "Amount cannot be integer value");

            super._update(from, to, amount);
        }

        else {
            super._update(from, to, amount);
        }
    }
}