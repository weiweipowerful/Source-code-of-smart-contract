//SPDX-License-Identifier: MIT

/***
 *                                                                                                        
 *     ██████   █████  ██       █████  ██   ██ ██ ███████     ████████  ██████  ██   ██ ███████ ███    ██ 
 *    ██       ██   ██ ██      ██   ██  ██ ██  ██ ██             ██    ██    ██ ██  ██  ██      ████   ██ 
 *    ██   ███ ███████ ██      ███████   ███   ██ ███████        ██    ██    ██ █████   █████   ██ ██  ██ 
 *    ██    ██ ██   ██ ██      ██   ██  ██ ██  ██      ██        ██    ██    ██ ██  ██  ██      ██  ██ ██ 
 *     ██████  ██   ██ ███████ ██   ██ ██   ██ ██ ███████        ██     ██████  ██   ██ ███████ ██   ████ 
 *                                                                                                        
 *    Galaxis.xyz                                                              
 */

pragma solidity 0.8.25;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GALAXIS is ERC20 {

    address public immutable    safe;
    uint256 public              maxSupply      = 10000000000 * 10 ** decimals();
    uint256 internal            initialSupply  =  7500000000 * 10 ** decimals();

    constructor(address _safe) ERC20("GALAXIS Token", "GALAXIS") {
        require(initialSupply <= maxSupply, "ERC20: Initial supply cannot be higher than max!");
        safe = _safe;
        _mint(safe, initialSupply);
    }

    function mintToSafe(uint256 amount) public {
        require(msg.sender == safe, "ERC20: only safe can mint!");
        require(ERC20.totalSupply() + amount <= maxSupply, "ERC20: maxSupply exceeded!");
        super._mint(msg.sender, amount);
    }
}