// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./Migrator.sol";

contract VAIX is ERC20, ERC20Permit {
    Migrator public immutable migrator;

    constructor(
        string memory name,
        string memory symbol,
        address treasuryAddress,
        address vxvAddress,
        address sbioAddress,
        bytes32 sbioWhitelistRoot,
        uint256 sbioMigrationCap,
        uint32 migrationClosesAfter,
        uint256 totalSupply
    ) ERC20(name, symbol) ERC20Permit(name) {
        migrator = new Migrator(
            treasuryAddress,
            address(this),
            vxvAddress,
            sbioAddress,
            sbioWhitelistRoot,
            sbioMigrationCap,
            migrationClosesAfter
        );
        uint256 migrationSupply = migrator.maximumMigrationSupply();
        require(totalSupply > migrationSupply);
        _mint(address(migrator), migrationSupply);
        _mint(treasuryAddress, totalSupply - migrationSupply);
    }
}