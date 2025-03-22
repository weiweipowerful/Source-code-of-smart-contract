// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TetherUSD is ERC20, Ownable, Pausable {
    AggregatorV3Interface internal priceFeed;
    mapping(address => bool) private _blacklist;

    event Blacklisted(address indexed account, bool value);

    constructor(uint256 initialSupply, address priceFeedAddress)
    ERC20("Tether USD", "USDT")
    Ownable(msg.sender)  // ✅ pass msg.sender explicitly here
{
    _mint(msg.sender, initialSupply * 10 ** decimals());
    priceFeed = AggregatorV3Interface(priceFeedAddress);
}

    // constructor(uint256 initialSupply, address priceFeedAddress) ERC20("GHST", "GHST") {
    //     _mint(msg.sender, initialSupply * 10 ** decimals());
    //     priceFeed = AggregatorV3Interface(priceFeedAddress);
    // }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount * 10 ** decimals());
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount * 10 ** decimals());
    }

    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount * 10 ** decimals());
        _burn(account, amount * 10 ** decimals());
    }

    function blacklist(address account, bool value) external onlyOwner {
        _blacklist[account] = value;
        emit Blacklisted(account, value);
    }

    function isBlacklisted(address account) external view returns (bool) {
        return _blacklist[account];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function transfer(address recipient, uint256 amount) public override whenNotPaused returns (bool) {
        require(!_blacklist[msg.sender], "Sender is blacklisted");
        require(!_blacklist[recipient], "Recipient is blacklisted");
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override whenNotPaused returns (bool) {
        require(!_blacklist[sender], "Sender is blacklisted");
        require(!_blacklist[recipient], "Recipient is blacklisted");
        return super.transferFrom(sender, recipient, amount);
    }

    function getLatestPrice() public view returns (int) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return price;
    }
}