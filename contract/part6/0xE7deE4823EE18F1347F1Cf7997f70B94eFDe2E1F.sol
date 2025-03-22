// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {FormTokenBase} from "./FormTokenBase.sol";

contract FormToken is FormTokenBase {
    bool public minted;
    address minter;
    event InitialMint(address indexed to, uint256 amount);
    event MinterUpdated(address indexed minter);

    // 5 billion units, 18 decimals
    uint256 constant INITIAL_SUPPLY = 5_000_000_000 * 10 ** 18;

    constructor(
        string memory _name,
        string memory _symbol,
        address _delegate,
        address _minter
    ) FormTokenBase(_name, _symbol, _delegate, 0) {
        minted = false;
        minter = _minter;
    }

    function updateMinter(address _minter) external onlyOwner {
        require(!minted, "Already minted");
        minter = _minter;
        emit MinterUpdated(_minter);
    }

    function mint(address to) external {
        require(msg.sender == minter, "Not minter");
        require(!minted, "Already minted");
        minted = true;
        _mint(to, INITIAL_SUPPLY);
        emit InitialMint(to, INITIAL_SUPPLY);
    }
}