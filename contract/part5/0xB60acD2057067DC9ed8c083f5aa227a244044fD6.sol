// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { TransparentUpgradeableProxy } from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ERC1967Utils } from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract PlxTAOProxy is TransparentUpgradeableProxy {
  constructor(
    address _logic,
    address admin,
    bytes memory _data
  ) TransparentUpgradeableProxy(_logic, admin, _data) {}
}