// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: 2024 Kiln <[email protected]>
//
// ██╗  ██╗██╗██╗     ███╗   ██╗
// ██║ ██╔╝██║██║     ████╗  ██║
// █████╔╝ ██║██║     ██╔██╗ ██║
// ██╔═██╗ ██║██║     ██║╚██╗██║
// ██║  ██╗██║███████╗██║ ╚████║
// ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═══╝
//
pragma solidity 0.8.22;

import {BeaconProxy} from "@openzeppelin/proxy/beacon/BeaconProxy.sol";

/// @title Vault Beacon Proxy
contract VaultBeaconProxy is BeaconProxy {
    constructor(address beacon, bytes memory data) BeaconProxy(beacon, data) {}
}