// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HIRO is ERC20, ERC20Burnable, ERC20Snapshot, Ownable {
    constructor(address _owner) ERC20("HIRO", "HRT") {
        _mint(_owner, 1000000000 * 10 ** decimals());
    }

    function snapshot() public onlyOwner {
        _snapshot();
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Snapshot)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function multiTransfer(address[] memory accounts, uint256[] memory amounts) public returns (bool) {

        require(accounts.length == amounts.length, "ERC20: lengths of two arrays are not equal");

        for(uint i = 0; i < accounts.length; i++) {
            _transfer(msg.sender, accounts[i], amounts[i]);
        }
        return true;
    }
}

contract HIROFactory {
    event Deploy(address indexed addr);

    function deploy(uint _salt) external {
        HIRO _contract = new HIRO{
            salt: bytes32(_salt)
        }(msg.sender);
        emit Deploy(address(_contract));
    }

    function getAddress(bytes memory bytecode, uint _salt) public view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(this), _salt, keccak256(bytecode)
            )
        );
        return address (uint160(uint(hash)));
    }

    function getBytecode(address _owner) public pure returns (bytes memory) {
        bytes memory bytecode = type(HIRO).creationCode;
        return abi.encodePacked(bytecode, abi.encode(_owner));
    }
}