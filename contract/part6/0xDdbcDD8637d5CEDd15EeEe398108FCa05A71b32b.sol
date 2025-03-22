// SPDX-License-Identifier: MIT

// Website: https://cryptify.ai/
// TG: https://t.me/cryptifyai
// Twitter: https://x.com/CryptifyAI


pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Cryptify_AI is ERC20, Ownable {
    bool public tradingEnabled;
    
    constructor() ERC20("Cryptify AI", "CRAI") Ownable(msg.sender) {
        _mint(msg.sender, 1_000_000_000 * (10 ** decimals()));
        tradingEnabled = false;
    }
    
    function enableTrading() external onlyOwner {
        tradingEnabled = true;
    }
    
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        require(
            tradingEnabled || from == owner() || to == owner(),
            "Trading not enabled"
        );
        
        super._update(from, to, value);
    }
}