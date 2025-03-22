// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ESRV1} from "src/ESRV1.sol";

contract DeployESRUpgradeable is Script, ESRV1 {
    function run() external returns (ESRV1) {
        return deployESRUpgradeable();
    }

    function deployESRUpgradeable() public returns (ESRV1) {
        vm.startBroadcast();
        ESRV1 esr = new ESRV1(); // implementation logic
        vm.stopBroadcast();
        return esr;
    }
}

contract ESRProxy is ERC1967Proxy {
    constructor(address _implementation, bytes memory _data) ERC1967Proxy(_implementation, _data) {}
}

contract DeployESRProxy is Script, ESRV1 {
    function run() external returns (ESRProxy) {
        return deployESRProxy();
    }

    function deployESRProxy() public returns (ESRProxy) {
        address implementation = vm.getDeployment("ESRV1", uint64(block.chainid));
        vm.startBroadcast();
        ESRProxy proxy = new ESRProxy(implementation, "");
        ESRV1(address(proxy)).initialize();
        vm.stopBroadcast();
        return proxy;
    }
}