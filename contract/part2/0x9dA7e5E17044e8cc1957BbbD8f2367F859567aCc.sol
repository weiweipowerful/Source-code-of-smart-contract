/**
 *Submitted for verification at Etherscan.io on 2024-07-04
*/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

interface IOCMDessert {
    function burnDessertForAddress(uint256 typeId, address burnTokenAddress) external;
}

contract OCMDessertBurn {
    mapping(bytes32 => bool) burned;
    address public immutable OCMDessert;

    error DoubleSpend();

    constructor(address dessert) {
        OCMDessert = dessert;
    }

    function burn(uint256 dessertId, uint256 data) external {
        bytes32 hash = keccak256(abi.encodePacked(dessertId, data, msg.sender));

        if (burned[hash]) revert DoubleSpend();

        burned[hash] = true;
        IOCMDessert(OCMDessert).burnDessertForAddress(dessertId, msg.sender);
    }
}