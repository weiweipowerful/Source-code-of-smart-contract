// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IUniRouter.sol";

/*
I see you nerd! ⌐⊙_⊙
*/

contract Pipo is ERC20, Ownable {
    IUniRouter public uniRouter;
    address public uniPair;
    bool public openTrading = false;

    // Errors
    error TradingNotOpen();

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _router
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        uniRouter = IUniRouter(_router);
        uniPair = IUniFactory(uniRouter.factory()).createPair(
            address(this),
            uniRouter.WETH()
        );

        _mint(msg.sender, _totalSupply);
    }

    function startTrading() external onlyOwner {
        openTrading = true;
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (!openTrading && from != owner() && to != owner()) {
            revert TradingNotOpen();
        }

        super._update(from, to, value);
    }
}