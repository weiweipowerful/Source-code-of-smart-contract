// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;


contract TokenFactory {

    address public owner;
    address public implementation;

    event Upgraded(address indexed implementation);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(tx.origin);
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function upgradeTo(address newImplementation) external onlyOwner {
        _upgradeTo(newImplementation);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _upgradeTo(address newImplementation) private {
        if (newImplementation != address(0)) {
            require(newImplementation.code.length > 0, "Invalid implementation address");
        }
        implementation = newImplementation;
        emit Upgraded(newImplementation);
    }

    function _transferOwnership(address newOwner) private {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    receive() external payable {}

    fallback() external payable {
        address impl = implementation;
        require(impl != address(0), "Implementation not set");
        assembly {
            calldatacopy(0, 0, calldatasize())

            if delegatecall(gas(), impl, 0, calldatasize(), 0, 0) {
                returndatacopy(0, 0, returndatasize())
                return(0, returndatasize())
            }

            returndatacopy(0, 0, returndatasize())
            revert(0, returndatasize())
        }
    }
}