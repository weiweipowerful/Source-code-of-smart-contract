// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IGelatoRelay1BalanceV2} from "./interfaces/IGelatoRelay1BalanceV2.sol";
import {IGelato1BalanceV2} from "./interfaces/IGelato1BalanceV2.sol";
import {GelatoCallUtils} from "./lib/GelatoCallUtils.sol";

/// @title  Gelato Relay V2 contract
/// @notice This contract deals with Gelato 1Balance payments
/// @dev    This contract must NEVER hold funds!
/// @dev    Maliciously crafted transaction payloads could wipe out any funds left here
// solhint-disable-next-line max-states-count
contract GelatoRelay1BalanceV2 is IGelatoRelay1BalanceV2, IGelato1BalanceV2 {
    using GelatoCallUtils for address;

    /// @notice Relay call + One Balance payment - with sponsor authentication
    /// @dev    This method can be called directly without passing through the diamond
    /// @dev    The validity of the emitted LogUseGelato1BalanceV2 event must be verified off-chain
    /// @dev    Payment is handled with off-chain accounting using Gelato's 1Balance system
    /// @param _target Relay call target
    /// @param _data Relay call data
    /// @param _correlationId Unique task identifier generated by gelato
    /// Signature is split into `r` and `vs` - See https://eips.ethereum.org/EIPS/eip-2098
    /// @param _r Checker signature
    /// @param _vs Checker signature
    function sponsoredCallV2(
        address _target,
        bytes calldata _data,
        bytes32 _correlationId,
        bytes32 _r,
        bytes32 _vs
    ) external {
        // These parameters are decoded from calldata
        (_correlationId);
        (_r);
        (_vs);

        // INTERACTIONS
        _target.revertingContractCall(_data, "GelatoRelay.sponsoredCallV2:");

        emit LogUseGelato1BalanceV2();
    }
}