// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @author Syky - Nathan Rempel

/*
           @@@   @@@@@   @@@@@@@         @@@@    @@@@@@@      @@@@@     @@@@@@@        @@@@
         @@@@      @@@     @@@@@@        @@       @@@@@@       @@        @@@@@@        @@
         @@@@@      @@      @@@@@       @@        @@@@@       @            @@@@@      @@
         @@@@@@      @@      @@@@@     @@         @@@@@     @               @@@@     @@
          @@@@@@      @       @@@@@   @@          @@@@@    @                @@@@@    @
           @@@@@@@             @@@@@ @@           @@@@@  @@@                 @@@@@  @
             @@@@@@             @@@@@@            @@@@@@@@@@@                 @@@@@@
               @@@@@@           @@@@@             @@@@@  @@@@@                 @@@@@
                @@@@@@@         @@@@@             @@@@@   @@@@@                @@@@@
         @        @@@@@@        @@@@@             @@@@@    @@@@@               @@@@@
         @@        @@@@@        @@@@@             @@@@@     @@@@@              @@@@@
         @@@@      @@@@@        @@@@@             @@@@@@     @@@@@@           @@@@@@
         @@@@@@   @@@@         @@@@@@@           @@@@@@@     @@@@@@@          @@@@@@@
*/

import "../base/GroupRegistry.sol";

contract SykyGroups is GroupRegistry {
    /*//////////////////////////////////////////////////////////////
                            Version Info
    //////////////////////////////////////////////////////////////*/

    string public constant ENV = "GOERLI";
    string public constant VER = "1.0.0";

    /*//////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address defaultAdmin_) GroupRegistry(defaultAdmin_) {}
}