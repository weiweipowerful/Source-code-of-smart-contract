// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

//___/\/\/\/\__________________________________________/\/\______________________________________/\/\/\/\/\____/\/\/\/\____/\/\/\/\___
//_/\/\____/\/\__/\/\__/\/\__/\/\/\______/\/\/\/\____/\/\/\/\/\__/\/\__/\/\__/\/\/\__/\/\________/\/\____/\/\____/\/\____/\/\____/\/\_
//_/\/\____/\/\__/\/\__/\/\______/\/\____/\/\__/\/\____/\/\______/\/\__/\/\__/\/\/\/\/\/\/\______/\/\/\/\/\______/\/\____/\/\____/\/\_
//_/\/\__/\/\____/\/\__/\/\__/\/\/\/\____/\/\__/\/\____/\/\______/\/\__/\/\__/\/\__/\__/\/\______/\/\____/\/\____/\/\____/\/\____/\/\_
//___/\/\/\/\/\____/\/\/\/\__/\/\/\/\/\__/\/\__/\/\____/\/\/\______/\/\/\/\__/\/\______/\/\______/\/\/\/\/\____/\/\/\/\____/\/\/\/\___
//____________________________________________________________________________________________________________________________________


import { BioToken } from "../BioToken.sol";

contract QBioToken is BioToken {
    constructor(string memory name, string memory symbol) BioToken(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}