// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BaseInbox} from "./BaseInbox.sol";
import {SORInbox} from "./SORInbox.sol";
import {SRInbox} from "./SRInbox.sol";

/**
 * @title BungeeInbox
 * @notice An Inbox contract for Bungee Protocol that enables creating requests via traditional approval flow
 * @dev Supports both SingleOutputRequest & SwapRequest
 * @dev Supports both ERC20 & native tokens
 */
contract BungeeInbox is BaseInbox, SORInbox, SRInbox {
    constructor(
        address _owner,
        address _permit2,
        address _bungeeGateway,
        address payable _wrappedNativeToken
    ) BaseInbox(_owner, _permit2, _bungeeGateway, _wrappedNativeToken) {}
}