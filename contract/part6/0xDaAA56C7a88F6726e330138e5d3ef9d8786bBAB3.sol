// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: TRINITY TOTEM
/// @author: manifold.xyz

import "./manifold/ERC721Creator.sol";

///////////////////////////////////////////////////////////////////////////////
//                                                                           //
//                                                                           //
//     _________  ________  ___  ________   ___  _________    ___    ___     //
//    |\___   ___\\   __  \|\  \|\   ___  \|\  \|\___   ___\ |\  \  /  /|    //
//    \|___ \  \_\ \  \|\  \ \  \ \  \\ \  \ \  \|___ \  \_| \ \  \/  / /    //
//         \ \  \ \ \   _  _\ \  \ \  \\ \  \ \  \   \ \  \   \ \    / /     //
//          \ \  \ \ \  \\  \\ \  \ \  \\ \  \ \  \   \ \  \   \/  /  /      //
//           \ \__\ \ \__\\ _\\ \__\ \__\\ \__\ \__\   \ \__\__/  / /        //
//            \|__|  \|__|\|__|\|__|\|__| \|__|\|__|    \|__|\___/ /         //
//                                                          \|___|/          //
//                                                                           //
//                                                                           //
//     _________  ________  _________  _______   _____ ______                //
//    |\___   ___\\   __  \|\___   ___\\  ___ \ |\   _ \  _   \              //
//    \|___ \  \_\ \  \|\  \|___ \  \_\ \   __/|\ \  \\\__\ \  \             //
//         \ \  \ \ \  \\\  \   \ \  \ \ \  \_|/_\ \  \\|__| \  \            //
//          \ \  \ \ \  \\\  \   \ \  \ \ \  \_|\ \ \  \    \ \  \           //
//           \ \__\ \ \_______\   \ \__\ \ \_______\ \__\    \ \__\          //
//            \|__|  \|_______|    \|__|  \|_______|\|__|     \|__|          //
//                                                                           //
//                                                                           //
//                                                                           //
//                                                                           //
//                                                                           //
///////////////////////////////////////////////////////////////////////////////


contract TOTEM is ERC721Creator {
    constructor() ERC721Creator("TRINITY TOTEM", "TOTEM") {}
}