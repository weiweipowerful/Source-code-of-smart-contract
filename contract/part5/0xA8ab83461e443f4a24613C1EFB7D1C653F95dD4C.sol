// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice OFTAdapter uses a deployed ERC-20 token and safeERC20 to interact with the OFTCore contract.
contract YayLSTOFTAdapter is OFTAdapter {
    constructor(
        address _token,
        address _lzEndpoint,
        address _initialAuthority
    ) OFTAdapter(_token, _lzEndpoint, _initialAuthority) Ownable(_initialAuthority) {}
}