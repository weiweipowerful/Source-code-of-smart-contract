// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: SKULLS
/// @author: manifold.xyz

import "./manifold/ERC721Creator.sol";

///////////////////////////////////////
//                                   //
//                                   //
//             _______________       //
//            /               \      //
//           /                 \     //
//          /                   \    //
//          |   XXXX     XXXX   |    //
//          |   XXXX     XXXX   |    //
//          |   XXX       XXX   |    //
//          |         X         |    //
//          \__      XXX     __/     //
//            |\     XXX     /|      //
//            | |           | |      //
//            | I I I I I I I |      //
//            |  I I I I I I  |      //
//             \_           _/       //
//              \_         _/        //
//                \_______/          //
//                                   //
//                                   //
///////////////////////////////////////


contract SKULLS is ERC721Creator {
    constructor() ERC721Creator("SKULLS", "SKULLS") {}
}