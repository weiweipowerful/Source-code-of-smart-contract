// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: CryptoArt & NFTs Class of 2024
/// @author: manifold.xyz

import "./manifold/ERC1155Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                    //
//                                                                                                                                                    //
//                                                                                                                                                    //
//                                                                                     ,                                                              //
//                                                                           :         Et                                                             //
//            .,                                       .        .           t#,        E#t                                                    .       //
//           ,Wt            i                         ;W       ;W          ;##W.       E##t           t                    t                 ,W       //
//          i#D.           LE              ..        f#E      f#E         :#L:WE       E#W#t          EE.                  EE.              i##       //
//         f#f            L#E             ;W,      .E#f     .E#f         .KG  ,#D      E#tfL.         :KW;           :     :KW;            f###       //
//       .D#i            G#W.            j##,     iWW;     iWW;          EE    ;#f     E#t              G#j         G#j      G#j          G####       //
//      :KW,            D#K.            G###,    L##Lffi  L##Lffi       f#.     t#i ,ffW#Dffj.           j#D.     .E#G#G      j#D.      .K#Ki##       //
//      t#f            E#K.           :E####,   tLLG##L  tLLG##L        :#G     GK   ;LW#ELLLf.       itttG#K,   ,W#; ;#E. itttG#K,    ,W#D.,##       //
//       ;#G         .E#E.           ;W#DG##,     ,W#i     ,W#i          ;#L   LW.     E#t            E##DDDDG: i#K:   :WW:E##DDDDG:  i##E,,i##,      //
//        :KE.      .K#E            j###DW##,    j#E.     j#E.            t#f f#:      E#t            E#E       :WW:   f#D.E#E       ;DDDDDDE##DGi    //
//         .DW:    .K#D            G##i,,G##,  .D#j     .D#j               f#D#;       E#t            E#E        .E#; G#L  E#E              ,##       //
//           L#,  .W#G           :K#K:   L##, ,WK,     ,WK,                 G#t        E#t            E##EEEEEEt   G#K#j   E##EEEEEEt       ,##       //
//            jt :W##########Wt ;##D.    L##, EG.      EG.                   t         E#t            tffffffffft   j#;    tffffffffft      .E#       //
//               :,,,,,,,,,,,,,.,,,      .,,  ,        ,                               ;#t                                                    t       //
//                                                                                      :;                                                            //
//                                                                                                                                                    //
//                                                                                                                                                    //
//                                                                                                                                                    //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract CL2024 is ERC1155Creator {
    constructor() ERC1155Creator("CryptoArt & NFTs Class of 2024", "CL2024") {}
}