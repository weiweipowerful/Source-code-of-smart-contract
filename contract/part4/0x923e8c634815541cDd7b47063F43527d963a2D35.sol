// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: OSF Editions Season 4
/// @author: manifold.xyz

import "./manifold/ERC1155Creator.sol";

//////////////////////////
//                      //
//                      //
//    SZN FOUR BEBEH    //
//                      //
//                      //
//////////////////////////


contract OSF4 is ERC1155Creator {
    constructor() ERC1155Creator("OSF Editions Season 4", "OSF4") {}
}