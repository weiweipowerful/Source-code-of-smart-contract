// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "../tools/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

contract DogeX is ERC20Pausable, Ownable {

    uint256 public constant MAX_SUPPLY = 1E10 * 1E18;

    mapping(address => bool) public whitelist;

    constructor() ERC20('DogeX', 'DogeX') {
        whitelist[_msgSender()] = true;
        _mint(_msgSender(), MAX_SUPPLY);
        _pause();
    }

    function setWhitelist(address receiver, bool isAdd) public onlyOwner {
        require(whitelist[receiver] != isAdd, 'Error');
        whitelist[receiver] = isAdd;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (!whitelist[from]) super._beforeTokenTransfer(from, to, amount);
    }
}