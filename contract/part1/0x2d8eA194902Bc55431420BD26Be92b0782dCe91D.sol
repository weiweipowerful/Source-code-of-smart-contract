// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
* @notice ERC20 token that implements EIP-2612 permit functionality.
* @notice Total supply of tokens is minted upon deployment and none of the tokens can be minted ever again.
* @notice Token owners can burn their tokens.
*/
contract ZNDToken is ERC20, Ownable2Step, ERC20Permit, ERC20Burnable {
    error RenouncingOwnershipIsDisabled();

    /**
     * @dev Initial and final supply of tokens. Tokens can not be minted after this contract is deployed.
     */
    uint256 constant public TOTAL_SUPPLY = 700_000_000;

    constructor() ERC20("ZNDToken", "ZND") ERC20Permit("ZNDToken") Ownable(msg.sender) {
        _mint(msg.sender, TOTAL_SUPPLY * 10 ** decimals());
    }

    /**
     * @notice Always reverts in order to prevent losing ownership.
     */
    function renounceOwnership() public view override onlyOwner {
        revert RenouncingOwnershipIsDisabled();
    }
}