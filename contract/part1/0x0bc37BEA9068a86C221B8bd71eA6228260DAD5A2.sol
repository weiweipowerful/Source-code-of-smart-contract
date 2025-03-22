// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

import "./interfaces/IVesting.sol";

/**
 * @title UplandToken
 * @author Upland
 * @dev ERC20 token contract with cap and vesting.
 */
contract UplandToken is ERC20Capped {
    /// @dev Maximum supply of the token.
    uint256 public constant MAX_SUPPLY = 1000000000 * 1e18;

    /// @dev Address of the vesting contract.
    address public immutable vesting;

    /// Attempt to transfer to vesting account
    error TransferToVestingAccount();

    /// Attempt to initialize with zero address
    error AddressIsZero();

    /**
     * @dev Constructor to initialize the token with vesting contract. Max supply is minted to the vesting contract.
     * @param vestingContract Address of the vesting contract. Cannot be zero address.
     */
    constructor(address vestingContract)
        ERC20("Upland", "SPARKLET")
        ERC20Capped(MAX_SUPPLY)
    {
        if (vestingContract == address(0)) {
            revert AddressIsZero();
        }

        vesting = vestingContract;
        _mint(vestingContract, MAX_SUPPLY);
    }

    /**
     * @dev Overriding ERC20._update() to only allow
     * transfers to vesting accounts from vesting contract.
     */
    function _update(address from, address to, uint256 value) internal override(ERC20Capped) {
        if (IVesting(vesting).vestingAccount(to) && vesting != from) {
            revert TransferToVestingAccount();
        }

        super._update(from, to, value);
    }
}