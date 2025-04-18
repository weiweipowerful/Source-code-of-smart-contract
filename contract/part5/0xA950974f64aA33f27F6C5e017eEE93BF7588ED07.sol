/**
 *Submitted for verification at Etherscan.io on 2023-10-31
*/

// SPDX-License-Identifier: AGPL-3.0 AND MIT AND agpl-3.0

// File @openzeppelin/contracts/utils/[email protected]

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/Address.sol)

pragma solidity ^0.8.1;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
	/**
	 * @dev Returns true if `account` is a contract.
	 *
	 * [IMPORTANT]
	 * ====
	 * It is unsafe to assume that an address for which this function returns
	 * false is an externally-owned account (EOA) and not a contract.
	 *
	 * Among others, `isContract` will return false for the following
	 * types of addresses:
	 *
	 *  - an externally-owned account
	 *  - a contract in construction
	 *  - an address where a contract will be created
	 *  - an address where a contract lived, but was destroyed
	 *
	 * Furthermore, `isContract` will also return true if the target contract within
	 * the same transaction is already scheduled for destruction by `SELFDESTRUCT`,
	 * which only has an effect at the end of a transaction.
	 * ====
	 *
	 * [IMPORTANT]
	 * ====
	 * You shouldn't rely on `isContract` to protect against flash loan attacks!
	 *
	 * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
	 * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
	 * constructor.
	 * ====
	 */
	function isContract(address account) internal view returns (bool) {
		// This method relies on extcodesize/address.code.length, which returns 0
		// for contracts in construction, since the code is only stored at the end
		// of the constructor execution.

		return account.code.length > 0;
	}

	/**
	 * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
	 * `recipient`, forwarding all available gas and reverting on errors.
	 *
	 * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
	 * of certain opcodes, possibly making contracts go over the 2300 gas limit
	 * imposed by `transfer`, making them unable to receive funds via
	 * `transfer`. {sendValue} removes this limitation.
	 *
	 * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
	 *
	 * IMPORTANT: because control is transferred to `recipient`, care must be
	 * taken to not create reentrancy vulnerabilities. Consider using
	 * {ReentrancyGuard} or the
	 * https://solidity.readthedocs.io/en/v0.8.0/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
	 */
	function sendValue(address payable recipient, uint256 amount) internal {
		require(address(this).balance >= amount, "Address: insufficient balance");

		(bool success, ) = recipient.call{value: amount}("");
		require(success, "Address: unable to send value, recipient may have reverted");
	}

	/**
	 * @dev Performs a Solidity function call using a low level `call`. A
	 * plain `call` is an unsafe replacement for a function call: use this
	 * function instead.
	 *
	 * If `target` reverts with a revert reason, it is bubbled up by this
	 * function (like regular Solidity function calls).
	 *
	 * Returns the raw returned data. To convert to the expected return value,
	 * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
	 *
	 * Requirements:
	 *
	 * - `target` must be a contract.
	 * - calling `target` with `data` must not revert.
	 *
	 * _Available since v3.1._
	 */
	function functionCall(address target, bytes memory data) internal returns (bytes memory) {
		return functionCallWithValue(target, data, 0, "Address: low-level call failed");
	}

	/**
	 * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
	 * `errorMessage` as a fallback revert reason when `target` reverts.
	 *
	 * _Available since v3.1._
	 */
	function functionCall(
		address target,
		bytes memory data,
		string memory errorMessage
	) internal returns (bytes memory) {
		return functionCallWithValue(target, data, 0, errorMessage);
	}

	/**
	 * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
	 * but also transferring `value` wei to `target`.
	 *
	 * Requirements:
	 *
	 * - the calling contract must have an ETH balance of at least `value`.
	 * - the called Solidity function must be `payable`.
	 *
	 * _Available since v3.1._
	 */
	function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
		return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
	}

	/**
	 * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
	 * with `errorMessage` as a fallback revert reason when `target` reverts.
	 *
	 * _Available since v3.1._
	 */
	function functionCallWithValue(
		address target,
		bytes memory data,
		uint256 value,
		string memory errorMessage
	) internal returns (bytes memory) {
		require(address(this).balance >= value, "Address: insufficient balance for call");
		(bool success, bytes memory returndata) = target.call{value: value}(data);
		return verifyCallResultFromTarget(target, success, returndata, errorMessage);
	}

	/**
	 * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
	 * but performing a static call.
	 *
	 * _Available since v3.3._
	 */
	function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
		return functionStaticCall(target, data, "Address: low-level static call failed");
	}

	/**
	 * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
	 * but performing a static call.
	 *
	 * _Available since v3.3._
	 */
	function functionStaticCall(
		address target,
		bytes memory data,
		string memory errorMessage
	) internal view returns (bytes memory) {
		(bool success, bytes memory returndata) = target.staticcall(data);
		return verifyCallResultFromTarget(target, success, returndata, errorMessage);
	}

	/**
	 * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
	 * but performing a delegate call.
	 *
	 * _Available since v3.4._
	 */
	function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
		return functionDelegateCall(target, data, "Address: low-level delegate call failed");
	}

	/**
	 * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
	 * but performing a delegate call.
	 *
	 * _Available since v3.4._
	 */
	function functionDelegateCall(
		address target,
		bytes memory data,
		string memory errorMessage
	) internal returns (bytes memory) {
		(bool success, bytes memory returndata) = target.delegatecall(data);
		return verifyCallResultFromTarget(target, success, returndata, errorMessage);
	}

	/**
	 * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
	 * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
	 *
	 * _Available since v4.8._
	 */
	function verifyCallResultFromTarget(
		address target,
		bool success,
		bytes memory returndata,
		string memory errorMessage
	) internal view returns (bytes memory) {
		if (success) {
			if (returndata.length == 0) {
				// only check isContract if the call was successful and the return data is empty
				// otherwise we already know that it was a contract
				require(isContract(target), "Address: call to non-contract");
			}
			return returndata;
		} else {
			_revert(returndata, errorMessage);
		}
	}

	/**
	 * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
	 * revert reason or using the provided one.
	 *
	 * _Available since v4.3._
	 */
	function verifyCallResult(
		bool success,
		bytes memory returndata,
		string memory errorMessage
	) internal pure returns (bytes memory) {
		if (success) {
			return returndata;
		} else {
			_revert(returndata, errorMessage);
		}
	}

	function _revert(bytes memory returndata, string memory errorMessage) private pure {
		// Look for revert reason and bubble it up if present
		if (returndata.length > 0) {
			// The easiest way to bubble the revert reason is using memory via assembly
			/// @solidity memory-safe-assembly
			assembly {
				let returndata_size := mload(returndata)
				revert(add(32, returndata), returndata_size)
			}
		} else {
			revert(errorMessage);
		}
	}
}

// File contracts/dependencies/openzeppelin/upgradeability/Proxy.sol

// Original license: SPDX_License_Identifier: agpl-3.0
pragma solidity 0.8.12;

/**
 * @title Proxy
 * @dev Implements delegation of calls to other contracts, with proper
 * forwarding of return values and bubbling of failures.
 * It defines a fallback function that delegates all calls to the address
 * returned by the abstract _implementation() internal function.
 */
abstract contract Proxy {
	/**
	 * @dev Fallback function.
	 * Implemented entirely in `_fallback`.
	 */
	fallback() external payable {
		_fallback();
	}

	/**
	 * @return The Address of the implementation.
	 */
	function _implementation() internal view virtual returns (address);

	/**
	 * @dev Delegates execution to an implementation contract.
	 * This is a low level function that doesn't return to its internal call site.
	 * It will return to the external caller whatever the implementation returns.
	 * @param implementation Address to delegate.
	 */
	function _delegate(address implementation) internal {
		//solium-disable-next-line
		assembly {
			// Copy msg.data. We take full control of memory in this inline assembly
			// block because it will not return to Solidity code. We overwrite the
			// Solidity scratch pad at memory position 0.
			calldatacopy(0, 0, calldatasize())

			// Call the implementation.
			// out and outsize are 0 because we don't know the size yet.
			let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

			// Copy the returned data.
			returndatacopy(0, 0, returndatasize())

			switch result
			// delegatecall returns 0 on error.
			case 0 {
				revert(0, returndatasize())
			}
			default {
				return(0, returndatasize())
			}
		}
	}

	/**
	 * @dev Function that is run as the first thing in the fallback function.
	 * Can be redefined in derived contracts to add functionality.
	 * Redefinitions must call super._willFallback().
	 */
	function _willFallback() internal virtual {}

	/**
	 * @dev fallback implementation.
	 * Extracted to enable manual triggering.
	 */
	function _fallback() internal {
		_willFallback();
		_delegate(_implementation());
	}
}

// File contracts/dependencies/openzeppelin/upgradeability/BaseUpgradeabilityProxy.sol

// Original license: SPDX_License_Identifier: agpl-3.0
pragma solidity 0.8.12;

/**
 * @title BaseUpgradeabilityProxy
 * @dev This contract implements a proxy that allows to change the
 * implementation address to which it will delegate.
 * Such a change is called an implementation upgrade.
 */
contract BaseUpgradeabilityProxy is Proxy {
	/**
	 * @dev Emitted when the implementation is upgraded.
	 * @param implementation Address of the new implementation.
	 */
	event Upgraded(address indexed implementation);

	/**
	 * @dev Storage slot with the address of the current implementation.
	 * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
	 * validated in the constructor.
	 */
	bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

	/**
	 * @dev Returns the current implementation.
	 * @return impl Address of the current implementation
	 */
	function _implementation() internal view override returns (address impl) {
		bytes32 slot = IMPLEMENTATION_SLOT;
		//solium-disable-next-line
		assembly {
			impl := sload(slot)
		}
	}

	/**
	 * @dev Upgrades the proxy to a new implementation.
	 * @param newImplementation Address of the new implementation.
	 */
	function _upgradeTo(address newImplementation) internal {
		_setImplementation(newImplementation);
		emit Upgraded(newImplementation);
	}

	/**
	 * @dev Sets the implementation address of the proxy.
	 * @param newImplementation Address of the new implementation.
	 */
	function _setImplementation(address newImplementation) internal {
		require(Address.isContract(newImplementation), "Cannot set a proxy implementation to a non-contract address");

		bytes32 slot = IMPLEMENTATION_SLOT;

		//solium-disable-next-line
		assembly {
			sstore(slot, newImplementation)
		}
	}
}

// File contracts/dependencies/openzeppelin/upgradeability/InitializableUpgradeabilityProxy.sol

// Original license: SPDX_License_Identifier: agpl-3.0
pragma solidity 0.8.12;

/**
 * @title InitializableUpgradeabilityProxy
 * @dev Extends BaseUpgradeabilityProxy with an initializer for initializing
 * implementation and init data.
 */
contract InitializableUpgradeabilityProxy is BaseUpgradeabilityProxy {
	/**
	 * @dev Contract initializer.
	 * @param _logic Address of the initial implementation.
	 * @param _data Data to send as msg.data to the implementation to initialize the proxied contract.
	 * It should include the signature and the parameters of the function to be called, as described in
	 * https://solidity.readthedocs.io/en/v0.4.24/abi-spec.html#function-selector-and-argument-encoding.
	 * This parameter is optional, if no data is given the initialization call to proxied contract will be skipped.
	 */
	function initialize(address _logic, bytes memory _data) public payable {
		require(_implementation() == address(0));
		assert(IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
		_setImplementation(_logic);
		if (_data.length > 0) {
			(bool success, ) = _logic.delegatecall(_data);
			require(success);
		}
	}
}

// File contracts/lending/libraries/aave-upgradeability/BaseImmutableAdminUpgradeabilityProxy.sol

// Original license: SPDX_License_Identifier: AGPL-3.0
pragma solidity 0.8.12;

/**
 * @title BaseImmutableAdminUpgradeabilityProxy
 * @author Aave, inspired by the OpenZeppelin upgradeability proxy pattern
 * @dev This contract combines an upgradeability proxy with an authorization
 * mechanism for administrative tasks. The admin role is stored in an immutable, which
 * helps saving transactions costs
 * All external functions in this contract must be guarded by the
 * `ifAdmin` modifier. See ethereum/solidity#3864 for a Solidity
 * feature proposal that would enable this to be done automatically.
 */
contract BaseImmutableAdminUpgradeabilityProxy is BaseUpgradeabilityProxy {
	address immutable ADMIN;

	constructor(address _admin) {
		ADMIN = _admin;
	}

	modifier ifAdmin() {
		if (msg.sender == ADMIN) {
			_;
		} else {
			_fallback();
		}
	}

	/**
	 * @return _address The address of the proxy admin.
	 */
	function admin() external ifAdmin returns (address _address) {
		return ADMIN;
	}

	/**
	 * @return _address The address of the implementation.
	 */
	function implementation() external ifAdmin returns (address _address) {
		return _implementation();
	}

	/**
	 * @dev Upgrade the backing implementation of the proxy.
	 * Only the admin can call this function.
	 * @param newImplementation Address of the new implementation.
	 */
	function upgradeTo(address newImplementation) external ifAdmin {
		_upgradeTo(newImplementation);
	}

	/**
	 * @dev Upgrade the backing implementation of the proxy and call a function
	 * on the new implementation.
	 * This is useful to initialize the proxied contract.
	 * @param newImplementation Address of the new implementation.
	 * @param data Data to send as msg.data in the low level call.
	 * It should include the signature and the parameters of the function to be called, as described in
	 * https://solidity.readthedocs.io/en/v0.4.24/abi-spec.html#function-selector-and-argument-encoding.
	 */
	function upgradeToAndCall(address newImplementation, bytes calldata data) external payable ifAdmin {
		_upgradeTo(newImplementation);
		(bool success, ) = newImplementation.delegatecall(data);
		require(success);
	}

	/**
	 * @dev Only fall back when the sender is not the admin.
	 */
	function _willFallback() internal virtual override {
		require(msg.sender != ADMIN, "Cannot call fallback function from the proxy admin");
		super._willFallback();
	}
}

// File contracts/lending/libraries/aave-upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol

// Original license: SPDX_License_Identifier: AGPL-3.0
pragma solidity 0.8.12;

/**
 * @title InitializableAdminUpgradeabilityProxy
 * @dev Extends BaseAdminUpgradeabilityProxy with an initializer function
 */
contract InitializableImmutableAdminUpgradeabilityProxy is
	BaseImmutableAdminUpgradeabilityProxy,
	InitializableUpgradeabilityProxy
{
	constructor(address admin) BaseImmutableAdminUpgradeabilityProxy(admin) {}

	/**
	 * @dev Only fall back when the sender is not the admin.
	 */
	function _willFallback() internal override(BaseImmutableAdminUpgradeabilityProxy, Proxy) {
		BaseImmutableAdminUpgradeabilityProxy._willFallback();
	}
}