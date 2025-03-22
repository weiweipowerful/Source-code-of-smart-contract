// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./ParagonAccount.sol";

/**
 * A factory contract for ParagonAccount
 * A UserOperations "initCode" holds the address of the factory, and a method call (to createAccount, in this factory).
 * The factory's createAccount returns the target account address even if it is already installed.
 * This way, the entryPoint.getSenderAddress() can be called either before or after the account is created.
 */
contract ParagonAccountFactory {
    ParagonAccount public immutable accountImplementation;
    address public permitVault;
    address public owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }

    constructor(address _entryPoint, address _owner) {
        accountImplementation = new ParagonAccount(IEntryPoint(_entryPoint));
        owner = _owner;
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(uint256 salt) public returns (ParagonAccount ret) {
        address addr = getAddress(salt);
        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return ParagonAccount(payable(addr));
        }
        ret = ParagonAccount(
            payable(
                new ERC1967Proxy{ salt: bytes32(salt) }(
                    address(accountImplementation),
                    abi.encodeCall(ParagonAccount.initialize, (owner))
                )
            )
        );
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    function getAddress(uint256 salt) public view returns (address) {
        return
            Create2.computeAddress(
                bytes32(salt),
                keccak256(
                    abi.encodePacked(
                        type(ERC1967Proxy).creationCode,
                        abi.encode(address(accountImplementation), abi.encodeCall(ParagonAccount.initialize, (owner)))
                    )
                )
            );
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}