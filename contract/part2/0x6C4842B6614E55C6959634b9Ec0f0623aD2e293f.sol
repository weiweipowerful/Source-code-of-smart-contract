// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: FRUG COMICS
/// @author: manifold.xyz

import "./manifold/ERC1155Creator.sol";

////////////////
//            //
//            //
//    @..@    //
//    (__)    //
//    //\\    //
//    FRUG    //
//            //
//            //
////////////////


contract FrugComics is ERC1155Creator {
    constructor() ERC1155Creator("FRUG COMICS", "FrugComics") {}
}