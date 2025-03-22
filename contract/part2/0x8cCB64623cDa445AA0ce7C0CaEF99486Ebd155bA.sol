// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import './ShezmuStablecoin.sol';

contract ShezmuETH is ShezmuStablecoin {
    constructor(
        string memory _version
    ) ShezmuStablecoin('ShezmuETH', 'ShezETH', _version) {}
}