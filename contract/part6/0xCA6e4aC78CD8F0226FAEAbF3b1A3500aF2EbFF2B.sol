// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract Genify is ERC20 {

    address private Team = 0xe609CD3f39c0Eb66CC0e78aDe4767faFbf5C0925;
    address private CuratorCommittee = 0xE5FC73E37C18665cee518b2532eb36dc7BA189aC;
    address private PlatformUsers = 0x50a1D886949EFffbbe814b1d4a2c8282D4570D4E;
    address private Market = 0x07EadA9bC9f2Deb72CAd48df95fE97eBe4feE611;
    address private Airdrops = 0xeAcc21956F67e18Fb62dcaC52892c67122C79FED;
    address private Investors = 0x68509cE3256bB07D1c6BdD6248da366aA3499C82;
    address private ArtistFoundation = 0xb5C584cE9dc293449AcbC8D02730BBA0144Bd425;
    address private Liquidity = 0xaf25a3421c69c4801Cc1De205778f9AaBeA47B13;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(Team, 1_500_000_000 * 10 ** 18);
        _mint(CuratorCommittee, 1_500_000_000 * 10 ** 18);
        _mint(PlatformUsers, 1_500_000_000 * 10 ** 18);
        _mint(Market, 1_400_000_000 * 10 ** 18);
        _mint(Airdrops, 100_000_000 * 10 ** 18);
        _mint(Investors, 400_000_000 * 10 ** 18);
        _mint(ArtistFoundation, 3_000_000_000 * 10 ** 18);
        _mint(Liquidity, 600_000_000 * 10 ** 18);
    }
}