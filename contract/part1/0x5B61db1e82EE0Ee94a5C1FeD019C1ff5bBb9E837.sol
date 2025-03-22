// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {CustodialWallet} from "./CustodialWallet.sol";

contract CustodialWalletFactoryV2 {
    using Clones for CustodialWalletFactoryV2;

    error AddressMismatch();

    uint256 private constant _MAX_ARRAY_BOUNDS = 2000;
    uint256 private constant _MAX_ARRAY_CALCULATE_BOUNDS = 10_000;

    CustodialWallet private rawWallet;

    event WalletDetails(address addr, address owner, uint256 index);
    event Created(address addr);
    event CreateFailed(address addr, address owner, string reason);

    constructor() {
        rawWallet = new CustodialWallet();
    }

    function getWallet(
        address owner,
        uint256 index
    ) public view returns (address addr, bytes32 salt) {
        salt = keccak256(abi.encodePacked(owner, index));
        addr = Clones.predictDeterministicAddress(address(rawWallet), salt);
    }

    function create(address owner, uint256 index) external {
        (address calculatedAddress, bytes32 salt) = getWallet(owner, index);
        address addr = Clones.cloneDeterministic(address(rawWallet), salt);

        if (addr != calculatedAddress) {
            revert AddressMismatch();
        }

        CustodialWallet(payable(addr)).init(owner);
        emit Created(addr);
        emit WalletDetails(addr, owner, index);
    }
}