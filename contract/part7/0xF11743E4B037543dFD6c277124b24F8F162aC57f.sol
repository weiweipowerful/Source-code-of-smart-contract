// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PIPOAdapter is OFTAdapter {
    constructor(
        address _token,
        address _lzEndpoint
    ) OFTAdapter(_token, _lzEndpoint, msg.sender) Ownable(msg.sender) {}
}