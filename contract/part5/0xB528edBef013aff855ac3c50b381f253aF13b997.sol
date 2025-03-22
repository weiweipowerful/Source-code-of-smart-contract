/* SPDX-License-Identifier: GPL-3.0 

888       888 888               888    d8b                                                                                 d8b 888    d8b                  .d8888b.  
888   o   888 888               888    88P                                                                                 Y8P 888    Y8P                 d88P  Y88b 
888  d8b  888 888               888    8P                                                                                      888                             .d88P 
888 d888b 888 88888b.   8888b.  888888 "  .d8888b       888  888  .d88b.  888  888 888d888      88888b.   .d88b.  .d8888b  888 888888 888  .d88b.  88888b.   .d88P"  
888d88888b888 888 "88b     "88b 888       88K           888  888 d88""88b 888  888 888P"        888 "88b d88""88b 88K      888 888    888 d88""88b 888 "88b  888"    
88888P Y88888 888  888 .d888888 888       "Y8888b.      888  888 888  888 888  888 888          888  888 888  888 "Y8888b. 888 888    888 888  888 888  888  888     
8888P   Y8888 888  888 888  888 Y88b.          X88      Y88b 888 Y88..88P Y88b 888 888          888 d88P Y88..88P      X88 888 Y88b.  888 Y88..88P 888  888          
888P     Y888 888  888 "Y888888  "Y888     88888P'       "Y88888  "Y88P"   "Y88888 888          88888P"   "Y88P"   88888P' 888  "Y888 888  "Y88P"  888  888  888     
                                                             888                                888                                                                  
                                                        Y8b d88P                                888                                                                  
                                                         "Y88P"                                 888 
*/

pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Aevo Token
 * @notice Governance token of the Aevo exchange and rollup
 * @dev ERC20 in addition to:
 *        - EIP-2612 signed approval implementation
 *        - `mint` functionality by Aevo DAO
 */
contract AevoToken is AccessControl, ERC20 {
    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    /// @dev The identifier of the role which allows accounts to mint tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _beneficiary)
        ERC20(_name, _symbol, _decimals)
    {
        require(_beneficiary != address(0), "!_beneficiary");

        // Add beneficiary as minter
        _grantRole(MINTER_ROLE, _beneficiary);
        // Add beneficiary as admin
        _grantRole(ADMIN_ROLE, _beneficiary);
        // Set ADMIN role as admin of minter role
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
    }

    /// @dev Mints tokens to a recipient.
    ///
    /// This function reverts if the caller does not have the minter role.
    function mint(address _recipient, uint256 _amount) external {
        require(hasRole(MINTER_ROLE, msg.sender), "!minter");

        _mint(_recipient, _amount);
    }
}