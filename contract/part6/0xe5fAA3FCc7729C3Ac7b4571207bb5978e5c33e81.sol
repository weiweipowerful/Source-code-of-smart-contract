// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: 2023 Kiln <[email protected]>
//
// ██╗  ██╗██╗██╗     ███╗   ██╗
// ██║ ██╔╝██║██║     ████╗  ██║
// █████╔╝ ██║██║     ██╔██╗ ██║
// ██╔═██╗ ██║██║     ██║╚██╗██║
// ██║  ██╗██║███████╗██║ ╚████║
// ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═══╝
//
pragma solidity >=0.8.17;

import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./Freezable.sol";

/// @title Openzeppelin Transparent Upgradeable Proxy (with virtual external upgrade methods)
contract TransparentUpgradeableProxy is ERC1967Proxy {
    /**
     * @dev Initializes an upgradeable proxy managed by `_admin`, backed by the implementation at `_logic`, and
     * optionally initialized with `_data` as explained in {ERC1967Proxy-constructor}.
     */
    constructor(address _logic, address admin_, bytes memory _data) payable ERC1967Proxy(_logic, _data) {
        _changeAdmin(admin_);
    }

    /**
     * @dev Modifier used internally that will delegate the call to the implementation unless the sender is the admin.
     */
    // slither-disable-next-line incorrect-modifier
    modifier ifAdmin() {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    /**
     * @dev Returns the current admin.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-getProxyAdmin}.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function admin() external ifAdmin returns (address admin_) {
        admin_ = _getAdmin();
    }

    /**
     * @dev Returns the current implementation.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-getProxyImplementation}.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
     */
    function implementation() external ifAdmin returns (address implementation_) {
        implementation_ = _implementation();
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-changeProxyAdmin}.
     */
    function changeAdmin(address newAdmin) external virtual ifAdmin {
        _changeAdmin(newAdmin);
    }

    /**
     * @dev Upgrade the implementation of the proxy.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-upgrade}.
     */
    function upgradeTo(address newImplementation) external virtual ifAdmin {
        _upgradeToAndCall(newImplementation, bytes(""), false);
    }

    /**
     * @dev Upgrade the implementation of the proxy, and then call a function from the new implementation as specified
     * by `data`, which should be an encoded function call. This is useful to initialize new storage variables in the
     * proxied contract.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-upgradeAndCall}.
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable virtual ifAdmin {
        _upgradeToAndCall(newImplementation, data, true);
    }

    /**
     * @dev Makes sure the admin cannot access the fallback function. See {Proxy-_beforeFallback}.
     */
    function _beforeFallback() internal virtual override {
        require(msg.sender != _getAdmin(), "TransparentUpgradeableProxy: admin cannot fallback to proxy target");
        super._beforeFallback();
    }
}

/// @title TUPProxy (Transparent Upgradeable Pausable Proxy)
/// @author mortimr @ Kiln
/// @notice This contract extends the Transparent Upgradeable proxy and adds a system wide pause feature.
///         When the system is paused, the fallback will fail no matter what calls are made.
contract TUPProxy is TransparentUpgradeableProxy, Freezable {
    /// @dev EIP1967 slot to store the pause status value.
    bytes32 private constant _PAUSE_SLOT = bytes32(uint256(keccak256("eip1967.proxy.pause")) - 1);
    /// @dev EIP1967 slot to store the pauser address value.
    bytes32 private constant _PAUSER_SLOT = bytes32(uint256(keccak256("eip1967.proxy.pauser")) - 1);

    /// @notice Emitted when the proxy dedicated pauser is changed.
    /// @param previousPauser The address of the previous pauser
    /// @param newPauser The address of the new pauser
    event PauserChanged(address previousPauser, address newPauser);

    /// @notice Thrown when a call was attempted and the proxy is paused.
    error CallWhenPaused();

    // slither-disable-next-line incorrect-modifier
    modifier ifAdminOrPauser() {
        if (msg.sender == _getAdmin() || msg.sender == _getPauser()) {
            _;
        } else {
            _fallback();
        }
    }

    /// @param _logic The address of the implementation contract
    /// @param admin_ The address of the admin account able to pause and upgrade the implementation
    /// @param _data Extra data use to perform atomic initializations
    constructor(address _logic, address admin_, bytes memory _data)
        payable
        TransparentUpgradeableProxy(_logic, admin_, _data)
    {}

    /// @notice Retrieves Paused state.
    /// @return Paused state
    function paused() external ifAdminOrPauser returns (bool) {
        return StorageSlot.getBooleanSlot(_PAUSE_SLOT).value;
    }

    /// @notice Pauses system.
    function pause() external ifAdminOrPauser notFrozen {
        StorageSlot.getBooleanSlot(_PAUSE_SLOT).value = true;
    }

    /// @notice Unpauses system.
    function unpause() external ifAdmin notFrozen {
        StorageSlot.getBooleanSlot(_PAUSE_SLOT).value = false;
    }

    /// @notice Sets the freeze timeout.
    function freeze(uint256 freezeTimeout) external ifAdmin {
        _freeze(freezeTimeout);
    }

    /// @notice Cancels the freeze process.
    function cancelFreeze() external ifAdmin {
        _cancelFreeze();
    }

    /// @notice Retrieve the freeze status.
    /// @return True if frozen
    function frozen() external ifAdmin returns (bool) {
        return _isFrozen();
    }

    /// @notice Retrieve the freeze timestamp.
    /// @return The freeze timestamp
    function freezeTime() external ifAdmin returns (uint256) {
        return _freezeTime();
    }

    /// @notice Retrieve the dedicated pauser address.
    /// @return The pauser address
    function pauser() external ifAdminOrPauser returns (address) {
        return _getPauser();
    }

    /// @notice Changes the dedicated pauser address.
    /// @dev Not callable when frozen
    /// @param newPauser The new pauser address
    function changePauser(address newPauser) external ifAdmin notFrozen {
        emit PauserChanged(_getPauser(), newPauser);
        _changePauser(newPauser);
    }

    /// @notice Changed the proxy admin.
    /// @dev Not callable when frozen
    function changeAdmin(address newAdmin) external override ifAdmin notFrozen {
        _changeAdmin(newAdmin);
    }

    /// @notice Performs an upgrade without reinitialization.
    /// @param newImplementation The new implementation address
    function upgradeTo(address newImplementation) external override ifAdmin notFrozen {
        _upgradeToAndCall(newImplementation, bytes(""), false);
    }

    /// @notice Performs an upgrade with reinitialization.
    /// @param newImplementation The new implementation address
    /// @param data The calldata to use atomically after the implementation upgrade
    function upgradeToAndCall(address newImplementation, bytes calldata data)
        external
        payable
        override
        ifAdmin
        notFrozen
    {
        _upgradeToAndCall(newImplementation, data, true);
    }

    /// @dev Internal utility to retrieve the dedicated pauser from storage,
    /// @return The pauser address
    function _getPauser() internal view returns (address) {
        return StorageSlot.getAddressSlot(_PAUSER_SLOT).value;
    }

    /// @dev Internal utility to change the dedicated pauser.
    /// @param newPauser The new pauser address
    function _changePauser(address newPauser) internal {
        StorageSlot.getAddressSlot(_PAUSER_SLOT).value = newPauser;
    }

    /// @dev Overrides the fallback method to check if system is not paused before.
    /// @dev Address Zero is allowed to perform calls even if system is paused. This allows
    ///      view functions to be called when the system is paused as rpc providers can easily
    ///      set the sender address to zero.
    // slither-disable-next-line timestamp
    function _beforeFallback() internal override {
        if ((!StorageSlot.getBooleanSlot(_PAUSE_SLOT).value || _isFrozen()) || msg.sender == address(0)) {
            super._beforeFallback();
        } else {
            revert CallWhenPaused();
        }
    }

    /// @dev Internal utility to retrieve the account allowed to freeze the contract.
    /// @return The freezer account
    function _getFreezer() internal view override returns (address) {
        return _getAdmin();
    }
}