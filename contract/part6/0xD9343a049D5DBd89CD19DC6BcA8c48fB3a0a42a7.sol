// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Lumia is ERC20Burnable, Ownable {
    uint private constant _CAP = 238888888 * 1e18;

    mapping(address => bool) public minters;

    event ToggleMinter(
        address account,
        bool isMinter
    );

    event Mint(
        address to,
        uint256 amount
    );

    error NotAMinter();

    constructor(address _owner) ERC20("Lumia Token", "LUMIA")  {
        transferOwnership(_owner);
        minters[_owner] = true;
    }

    /**
     * @dev Returns the cap on the token's total supply.
     */
    function cap() public view virtual returns (uint256) {
        return _CAP;
    }

    /**
     * @dev See {ERC20-_mint}.
     */
    function _mint(address account, uint256 amount) internal virtual override {
        require(ERC20.totalSupply() + amount <= cap(), "ERC20Capped: cap exceeded");
        super._mint(account, amount);
    }

    function mint(address to, uint256 amount) external {
        if (!minters[msg.sender]) revert NotAMinter();
        _mint(to, amount);

        emit Mint(to, amount);
    }

    function toggleMinter(address minter) onlyOwner external {
        bool isMinter = minters[minter];
        minters[minter] = !isMinter;

        emit ToggleMinter(minter, !isMinter);
    }

    function burnFrom(address account, uint256 amount) onlyOwner public virtual override {
        _burn(account, amount);
    }

}