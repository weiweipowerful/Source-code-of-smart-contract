// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*    

 ########      ##### 
  ###    #   #####   
    ###   ######     
     ###   ###       
       ###   ##      
       ####   ##     
     #### ##    ##   
   #####    ##   ##  
 #####       ########
                     
      barlmarx       


┌──────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│     __  __           _         _             _______         ______                      _               │
│    |  \/  |         | |       | |           |__   __|       |  ____|                    (_)              │
│    | \  / | __ _  __| | ___   | |__  _   _     | | __ ___  _| |__ __ _ _ __ _ __ ___     _ _ __   __ _   │
│    | |\/| |/ _` |/ _|` |/ _ \  | '_ \| | | |    | |/ _` | / /  __/ _` | '__| '_ ` _ \   | | '_ \ / _` |  │
│    | |  | | (_| | (_| |  __/  | |_) | |_| |    | | (_| |>  <| | | (_| | |  | | | | | |  | | | | | (_| |  │
│    |_|  |_|\__,_|\__,_|\___|  |_.__/ \__, |    |_|\__,_/_/\_\_|  \__,_|_|  |_| |_| |_|(_)_|_| |_|\__, |  │
│                                       __/ |                                                      __/ |   │
│                                      |___/                                                      |___/    │
│                                                                                                          │
│                                             taxfarm.ing                                                  │
│                                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────┘

*/


contract TokenProxy {
    // constant stored in runtime bytecode to ensure contract uniqueness and be able to verify it on etherscan with custom comments
    uint256 public constant uniqueId = 0x1000100000000000000000000000000000000000000000000000000000000023; // use a 32 bytes uint to ensure consistency of PUSH32 opcode, 1st byte to ensure 32 bytes length, 2 next bytes are used as a placeholder for factory version and the next 29 bytes are used as a placeholder for unique id

    address public immutable tokenLogic;

    constructor(address _tokenLogic) {
        tokenLogic = _tokenLogic;
    }

    // delegate functions call to the token logic contract
    fallback() external payable {
        address dest = tokenLogic;
        
        assembly {
            calldatacopy(0, 0, calldatasize())

            let result := delegatecall(gas(), dest, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}