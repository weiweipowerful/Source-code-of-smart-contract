// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title a token contract that locks the transfer function for a period of time
contract ZRC is Ownable, ERC20Permit {
    bool public locked;

    /// @notice allowed senders during locked period
    mapping(address => bool) public allowedSenders;
    /// @notice allowed receiver during locked period
    mapping(address => bool) public allowedReceivers;

    /// @notice event emitted when it is being unlocked
    event Unlocked();

    /// @notice event emitted when allowedSenders is being updated
    event SetAllowedSenders(address indexed target, bool allowed);
    /// @notice event emitted when allowedReceivers is being updated
    event SetAllowedReceivers(address indexed target, bool allowed);

    /**
     * @notice constructor for ZRC
     * @param _allowedSenders List of addresses allowed to send tokens during the locked period
     * @param _allowedReceivers List of addresses allowed to receive tokens during the locked period
     * @param totalSupply Total supply of the token
     */
    constructor(address[] memory _allowedSenders, address[] memory _allowedReceivers, uint256 totalSupply)
        ERC20("Zircuit", "ZRC")
        Ownable(msg.sender)
        ERC20Permit("Zircuit")
    {
        locked = true;
        allowedSenders[msg.sender] = true;
        emit SetAllowedSenders(msg.sender, true);

        for (uint256 i = 0; i < _allowedSenders.length; ++i) {
            allowedSenders[_allowedSenders[i]] = true;
            emit SetAllowedSenders(_allowedSenders[i], true);
        }

        for (uint256 i = 0; i < _allowedReceivers.length; ++i) {
            allowedReceivers[_allowedReceivers[i]] = true;
            emit SetAllowedReceivers(_allowedReceivers[i], true);
        }

        _mint(msg.sender, totalSupply);
    }

    /**
     * @notice override the _update function to check if the token transfer is locked
     * allow transfer when:
     *  - the token is unlocked
     *  - minting tokens
     *  - allowedSender is sending tokens
     *  - allowedReceiver is receiving tokens
     * @param from Address sending the tokens
     * @param to Address receiving the tokens
     * @param amount Amount of tokens being transferred
     */
    function _update(address from, address to, uint256 amount) internal override {
        require(
            !locked || from == address(0) || allowedSenders[from] || allowedReceivers[to], "Token transfer is locked"
        );
        super._update(from, to, amount);
    }

    //////  Admin functions  //////
    /**
     * @notice unlock the token
     */
    function unlock() external onlyOwner {
        require(locked, "Transfer already unlocked");
        locked = false;
        emit Unlocked();
    }

    /**
     * @notice set a list of senders to be allowed or disallowed to send tokens during the locked period
     * @param _allowedSenders List of addresses to allow transfer from
     * @param allow Boolean to set if the senders are allowed or disallowed
     */
    function setAllowedSenders(address[] memory _allowedSenders, bool allow) external onlyOwner {
        for (uint256 i = 0; i < _allowedSenders.length; ++i) {
            allowedSenders[_allowedSenders[i]] = allow;
            emit SetAllowedSenders(_allowedSenders[i], allow);
        }
    }

    /**
     * @notice set a list of receivers to be allowed or disallowed to receive tokens during the locked period
     * @param _allowedReceivers List of addresses to allow transfer to
     * @param allow Boolean to set if the receivers are allowed or disallowed
     */
    function setAllowedReceivers(address[] memory _allowedReceivers, bool allow) external onlyOwner {
        for (uint256 i = 0; i < _allowedReceivers.length; ++i) {
            allowedReceivers[_allowedReceivers[i]] = allow;
            emit SetAllowedReceivers(_allowedReceivers[i], allow);
        }
    }
}