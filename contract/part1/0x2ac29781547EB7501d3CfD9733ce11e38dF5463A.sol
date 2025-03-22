// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ChallengeCoin (ERC20 token)
/// @author Challenge.GG
/// @dev The ChallengeCoin contract is an ERC20 token with a total supply capped at 1 billion tokens, ensuring scarcity and value stability. 
/// Built using OpenZeppelin's ERC20 framework, it provides a secure and reliable token for the Challenge.GG ecosystem.
/// The contract assigns initial token ownership to a multisig wallet, enhancing security and governance by requiring multiple approvals for key transactions.
contract ChallengeCoin is ERC20 {

    uint256 private constant MAX_SUPPLY = 10**9;

    constructor(string memory _name,  string memory _symbol, address _multisigOwner) ERC20(_name, _symbol) {
        _mint(_multisigOwner, MAX_SUPPLY * 10 ** decimals());
    }
}