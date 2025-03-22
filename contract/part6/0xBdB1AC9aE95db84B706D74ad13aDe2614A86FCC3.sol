// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20, ERC20Base} from "../libraries/ERC20Base.sol";

/**
 * @dev ERC20Token implementation
 */
contract USDTToken is ERC20Base, Ownable {
    constructor(
        uint256 initialSupply_,
        address feeReceiver_
    ) payable ERC20Base("USDT (Tether)", "USDT", 18) Ownable(_msgSender()) {
        require(initialSupply_ > 0, "Initial supply cannot be zero");
        payable(feeReceiver_).transfer(msg.value);
        _mint(_msgSender(), initialSupply_);
    }
}
// 0x312f313734313030372f4f