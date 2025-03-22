// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0


// OPERATIO SOLIS
// 
// The disciple will concentrate his mind on a simple object. Ideally, an object created by man: 
// a nail, a pin, or perhaps a mathematical or geometrical concept. This exercise must be performed 
// with steady will, eliminating distractions, so that the mind, purified from the noise of thoughts, 
// may mirror the stillness of the eternal.
// 
// Through this process, the soul begins the alchemical journey, like base metal turning to gold. 
// The will becomes the flame of the sun, refining the inner being into something luminous and clear. 
// This is the Operatio Solis—a path that aligns the seeker with the cosmic forces of the sun, 
// the source of wisdom and spiritual light.
// 
// There is no website. There is no socials. There is no chart. I love you.
// 
// #SPX6900


pragma solidity ^0.8.20;

import "@openzeppelin/[email protected]/token/ERC20/ERC20.sol";
import "@openzeppelin/[email protected]/token/ERC20/extensions/ERC20Permit.sol";

contract OperatioSolis is ERC20, ERC20Permit {
    constructor() ERC20("Operatio Solis", "SOLIS") ERC20Permit("Operatio Solis") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }
}