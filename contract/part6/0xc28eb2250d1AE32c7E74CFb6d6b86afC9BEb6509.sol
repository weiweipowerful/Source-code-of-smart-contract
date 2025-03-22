// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {ERC20} from "erc20/ERC20.sol";
import {IOPNToken} from "./interfaces/IOPNToken.sol";

/// @title OPNToken
/// @author The OPN Ecosystem Team
contract OPNToken is IOPNToken, ERC20 {
    string public constant NAME = "Open Ecosystem Token";
    string public constant SYMBOL = "OPN";
    uint8 public constant DECIMALS = 18;

    /// @inheritdoc IOPNToken
    address public override mintManagerAddress;

    /// @inheritdoc IOPNToken
    address public override daoControllerAddress;

    /// @inheritdoc IOPNToken
    bool public override migrationIssuanceDisabledPermanently = false;

    constructor(address _initialController) ERC20(NAME, SYMBOL, DECIMALS) {
        daoControllerAddress = _initialController;
        // mint 2 tokens for bridge registrations and testing post migration
        _mint(msg.sender, 2 * 1e18);
    }

    // Modifiers

    modifier onlyMintManager() {
        require(
            msg.sender == mintManagerAddress,
            "OPNToken: UNAUTHORIZED MINT MANAGER"
        );
        _;
    }

    modifier onlyDAOController() {
        require(
            msg.sender == daoControllerAddress,
            "OPNToken: UNAUTHORIZED DAO CONTROLLER"
        );
        _;
    }

    // Operational functions for migration

    /// @inheritdoc IOPNToken
    function issueTokensMigration(
        address _to,
        uint256 _amount
    ) external override onlyMintManager {
        require(
            !migrationIssuanceDisabledPermanently,
            "OPNToken: MIGRATION MINTING DISABLED PERMANENTLY"
        );
        _mint(_to, _amount);
        emit MigrationMint(_to, _amount);
    }

    /// @inheritdoc IOPNToken
    function mintTokenPolygonInventory(
        address _to,
        uint256 _amount
    ) external override onlyDAOController {
        require(
            !migrationIssuanceDisabledPermanently,
            "OPNToken: MIGRATION MINTING DISABLED PERMANENTLY"
        );
        _mint(_to, _amount);
        emit MigrationInventoryMint(_to, _amount);
    }

    // Operational functions for DAO post operations

    /// @inheritdoc IOPNToken
    function mintTokensByDAO(
        address _to,
        uint256 _amount
    ) external override onlyDAOController {
        _mint(_to, _amount);
        emit DaoMint(_to, _amount);
    }

    // Operational functions for token holders

    /// @inheritdoc IOPNToken
    function burn(uint256 _amount) external override {
        _burn(msg.sender, _amount);
        emit TokensBurned(msg.sender, _amount);
    }

    // Configuration functions

    /// @inheritdoc IOPNToken
    function setDAOControllerAddress(
        address _newDaoController
    ) external override onlyDAOController {
        daoControllerAddress = _newDaoController;
        emit DaoControllerSet(_newDaoController);
    }

    /// @inheritdoc IOPNToken
    function finalizeMigration() external override onlyDAOController {
        migrationIssuanceDisabledPermanently = true;
        delete mintManagerAddress;
        emit MigrationConfigFinalized();
    }

    /// @inheritdoc IOPNToken
    function setMintManager(
        address _newMigrationManager
    ) external override onlyDAOController {
        require(
            !migrationIssuanceDisabledPermanently,
            "OPNToken: MIGRATION MINTING DISABLED PERMANENTLY"
        );
        mintManagerAddress = _newMigrationManager;
        emit MigrationManagerSet(_newMigrationManager);
    }
}