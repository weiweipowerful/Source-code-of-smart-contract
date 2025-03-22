// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { CheckoutPoolInterface } from "../interfaces/CheckoutPoolInterface.sol";
import {
    Create2ForwarderInterface
} from "../interfaces/Create2ForwarderInterface.sol";
import {
    Create2ForwarderFactoryInterface
} from "../interfaces/Create2ForwarderFactoryInterface.sol";
import { CheckoutState } from "../interfaces/CheckoutPoolInterface.sol";
import { WETH9Interface } from "../interfaces/WETH9Interface.sol";
import { Create2ForwarderImpl } from "../forwarder/Create2ForwarderImpl.sol";
import { Create2ForwarderProxy } from "./Create2ForwarderProxy.sol";

/**
 * @title Create2ForwarderFactory
 * @author Fun.xyz
 *
 * @notice Factory for “counterfactual” forwarder contracts for the Checkout Pools protocol.
 *
 *  A forwarder contract is created for each checkout operation executed by the protocol.
 *  It is the entry point for funds into the protocol.
 *
 *  Before the forwarder contract is deployed, its CREATE2 address (the “deposit address”)
 *  is calculated, so that the contract can be deployed only as needed, after funds have
 *  been deposited.
 *
 *  As a gas optimization, each forwarder contract is deployed as a proxy. All of the proxy
 *  contracts reference the same implementation logic, which is a constant on the factory contract.
 *
 *  As a gas optimization, checkout parameters that are not expected to change (often) are
 *  stored as constants on the factory contract. Parameters that do not need to be stored
 *  on-chain (e.g. the full user operation) are expected to be stored off-chain by the liquidity
 *  provider that is responsible for executing the checkout.
 *
 *  Constants (same for all forwarders created by the factory).
 *    - source chain
 *    - guardian address
 *    - CheckoutPools contract address (corresponds to a liquidity provider)
 *    - wrapped native token address
 *
 *  On-chain configuration (different for each forwarder / checkout operation)
 *    - user op hash
 *    - target chain
 *    - target asset and amount
 *    - source asset and amount
 *    - expiration timestamp
 *    - salt (not stored)
 *
 *  Off-chain configuration
 *    - user op
 */
contract Create2ForwarderFactory is Create2ForwarderFactoryInterface {
    error ErrorCreatingProxy();

    Create2ForwarderImpl public immutable IMPLEMENTATION;

    constructor(
        address guardian,
        WETH9Interface wrappedNativeToken,
        CheckoutPoolInterface checkoutPool
    ) {
        IMPLEMENTATION = new Create2ForwarderImpl(
            guardian,
            wrappedNativeToken,
            checkoutPool
        );
    }

    function create(
        CheckoutState calldata checkout,
        bytes32 salt
    ) external returns (Create2ForwarderInterface) {
        return _create(checkout, salt);
    }

    function createAndForward(
        CheckoutState calldata checkout,
        bytes32 salt
    ) external returns (Create2ForwarderInterface) {
        Create2ForwarderInterface proxy = _create(checkout, salt);
        proxy.forward();
        return proxy;
    }

    function getAddress(
        CheckoutState calldata checkout,
        bytes32 salt
    ) external view returns (address payable) {
        return _getAddress(checkout, salt, block.chainid);
    }

    /**
     * @notice Get the deposit address for a target chain ID.
     *
     *  IMPORTANT NOTE: This implementation assumes that the forwarder factory has the same
     *  address on each chain. This has to be ensured before a chain ID is added to the allowed
     *  list of target chain IDs on the CheckoutPools contract.
     */
    function getAddressForChain(
        CheckoutState calldata checkout,
        bytes32 salt,
        uint256 chainId
    ) external view returns (address payable) {
        return _getAddress(checkout, salt, chainId);
    }

    function getProxyCreationCode() external pure returns (bytes memory) {
        return type(Create2ForwarderProxy).creationCode;
    }

    function _create(
        CheckoutState calldata checkout,
        bytes32 salt
    ) internal returns (Create2ForwarderInterface) {
        Create2ForwarderProxy deployed = new Create2ForwarderProxy{
            salt: salt
        }(IMPLEMENTATION, checkout, block.chainid);

        Create2ForwarderInterface proxy = Create2ForwarderInterface(
            address(deployed)
        );
        return proxy;
    }

    function _getAddress(
        CheckoutState calldata checkout,
        bytes32 salt,
        uint256 chainId
    ) internal view returns (address payable) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(
                    abi.encodePacked(
                        type(Create2ForwarderProxy).creationCode,
                        abi.encode(IMPLEMENTATION, checkout, chainId)
                    )
                )
            )
        );
        return payable(address(uint160(uint256(digest))));
    }
}

// Compare with:
// function create3(bytes32 _salt, bytes memory _creationCode, uint256 _value) internal returns (address addr) {
//     // Creation code
//     bytes memory creationCode = PROXY_CHILD_BYTECODE;

//     // Get target final address
//     addr = addressOf(_salt);
//     if (codeSize(addr) != 0) revert TargetAlreadyExists();

//     // Create CREATE2 proxy
//     address proxy; assembly { proxy := create2(0, add(creationCode, 32), mload(creationCode), _salt)}
//     if (proxy == address(0)) revert ErrorCreatingProxy();

//     // Call proxy with final init code
//     (bool success,) = proxy.call{ value: _value }(_creationCode);
//     if (!success || codeSize(addr) == 0) revert ErrorCreatingContract();
// }