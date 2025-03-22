// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/*
       ---           +=+                ===          
   =--======--   ========+==          =====----      
 --=======================++++        =======----    
--=====----===============+++++       =========---   
-====-     =========     =++++++       ==========-   
-----=      -=======      +++++++       ++========-  
-------      -=======      +++++++       +++======   
 -------      ========      +++++++       ++++===+   
  -------      =======+      =+++++++    ++++++==    
   -------      ========      ++++++++++++++++++     
    -------       =======       +++++++++++++++      
     -------       =======      *++++++++++++        
      -------       =======       ++++++++++         
       -------       =====+=       ++++++++          
        -------      -====+++      +++++++           
         --------  =---===+++++  ++++++++            
          --------------==++++++++++++++             
            -------------+=++++++++++++              
              --------      ++++++++                 
*/

/// @custom:security-contact [email protected]
contract WelshareHealthToken is ERC20, ERC20Permit, Ownable {
    uint256 public constant WEL_SUPPLY = 2_500_000_000 ether;
    constructor(address treasury) ERC20("Welshare Health Token", "WEL") ERC20Permit("Welshare Health Token") Ownable(treasury)  {
        _mint(treasury, WEL_SUPPLY);
    }
}