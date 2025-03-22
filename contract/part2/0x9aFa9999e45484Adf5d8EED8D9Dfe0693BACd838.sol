// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

contract Token is ERC20Capped {
    uint8 private immutable customDecimals;

    error Token_InvalidMintParams();
    error Token_InvalidSupply();

    constructor(
        string memory _erc20Name,
        string memory _erc20Symbol,
        uint8 _decimals,
        uint256 _cap,
        address[] memory _mintAddresses,
        uint256[] memory _mintAmounts
    ) ERC20(_erc20Name, _erc20Symbol) ERC20Capped(_cap) {
        uint256 _mintAddressesLength = _mintAddresses.length;
        if (_mintAddressesLength != _mintAmounts.length) {
            revert Token_InvalidMintParams();
        }

        customDecimals = _decimals;

        for (uint256 i; i < _mintAddressesLength; ++i) {
            ERC20._mint(_mintAddresses[i], _mintAmounts[i]);
        }

        if (_cap < totalSupply()) {
            revert Token_InvalidSupply();
        }
    }

    function decimals() public view override returns (uint8) {
        return customDecimals;
    }
}