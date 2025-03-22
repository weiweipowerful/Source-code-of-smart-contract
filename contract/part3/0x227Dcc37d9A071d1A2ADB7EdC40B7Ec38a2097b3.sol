// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ProxyOFT} from "@layerzerolabs/solidity-examples/contracts/token/oft/v1/ProxyOFT.sol";

/**
 * @title ProxyOFT by LayerZero for OX Coin (OX)
 * @notice Proxy contract for OX to enable bridging across
 * several EVM-compatible chains using LayerZero endpoints
 * through OFT contracts.
 */

contract OXProxyOFT is ProxyOFT { 
    constructor(
        address _lzEndpoint,
        address _token
	) ProxyOFT(_lzEndpoint, _token) {}
}