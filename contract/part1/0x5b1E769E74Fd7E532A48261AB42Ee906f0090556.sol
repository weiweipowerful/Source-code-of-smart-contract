// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RX is ERC20 {
    constructor() ERC20("RealtyX", "RX") {
        _mint(msg.sender, 1000000000 * 10 ** 18);
    }
}