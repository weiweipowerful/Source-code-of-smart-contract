// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ExchangeArtNFTMarketTransparentUpgradeableProxy is
  TransparentUpgradeableProxy
{
  constructor(
    address admin,
    address marketLogic
  )
    TransparentUpgradeableProxy(
      marketLogic,
      admin,
      abi.encodeWithSignature("initialize()")
    )
  {}
}