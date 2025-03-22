// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BlackUnicornCoin is ERC20, Ownable {
    error WrongArrayLen(uint256 walletsLen, uint256 amountsLen);
    error MaxSupplyOverflow(uint256 currentSupply);

    uint256 private constant _MAX_SUPPLY = 13_500_000_000 * 1e18;

    constructor(
        address newOwner
    ) ERC20("Black Unicorn Corp.", "MOON") Ownable(newOwner) {
        //
    }

    function mint(
        address[] calldata wallets,
        uint256[] calldata amounts
    ) external onlyOwner {
        uint256 len = wallets.length;
        if (len == 0 || len != amounts.length)
            revert WrongArrayLen(len, amounts.length);

        for (uint256 i; i < len; ) {
            _mint(wallets[i], amounts[i]);
            unchecked {
                ++i;
            }
        }

        if (totalSupply() > _MAX_SUPPLY)
            revert MaxSupplyOverflow(totalSupply());
    }
}