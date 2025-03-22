// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20.sol";

contract SKYG is ERC20("SKYGATE TOKEN", "SKYG") {

    /**
     * @param wallet Address of the wallet, where tokens will be transferred to
     */
    constructor(address wallet) {
        _mint(wallet, 10_000_000_000 ether);
    }
}