// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@imtbl/contracts/contracts/token/erc20/preset/ImmutableERC20FixedSupplyNoBurn.sol";

contract MetalCore is ImmutableERC20FixedSupplyNoBurn {
    constructor(
        address _treasurer,
        address _owner
    ) ImmutableERC20FixedSupplyNoBurn("MetalCore", "MCG", 3_000_000_000 ether, _treasurer, _owner) {}
}