// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract BaseToken is ERC20, AccessControl, Pausable {
    bytes32 public constant CASHIER = "CASHIER";
    mapping(address => bool) public blacklist;
    uint8 immutable decimal;
    uint256 public immutable maxSupply;

    event AddBlackList(address user);
    event RemoveBlackList(address user);

    modifier onlyNoBlackList(address from, address to) {
        require(!blacklist[from], "blacklist");
        require(!blacklist[to], "blacklist");
        _;
    }
    modifier noExceed(uint256 amount) {
        require(super.totalSupply() + amount <= maxSupply, "MaxSupply Exceeded");
        _;
    }

    constructor (
        string memory _name,
        string memory _symbol,
        uint8 _decimal,
        uint256 _maxSupply,
        address _owner,
        address _cashier
    ) ERC20(_name, _symbol) {
        decimal = _decimal;
        maxSupply = _maxSupply;
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(CASHIER, _cashier);
    }

    function addBlackList(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        blacklist[_address] = true;

        emit AddBlackList(_address);
    }

    function removeBlackList(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        blacklist[_address] = false;
        delete blacklist[_address];

        emit RemoveBlackList(_address);
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE)  {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE)  {
        _unpause();
    }

    /// mint to address
    /// @dev only with `CASHIER` role can mint to `account`
    /// @param account address to mint
    /// @param amount amount to mint
    function mint(address account, uint256 amount) external onlyRole(CASHIER) whenNotPaused noExceed(amount) {
        require(!blacklist[account], "blacklist");
        _mint(account, amount);
    }

    /// @dev only with `CASHIER` role can burn
    /// @param amount amount to burn
    function burn(uint256 amount) external onlyRole(CASHIER) whenNotPaused {
        _burn(_msgSender(), amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused onlyNoBlackList(from, to) {
        super._transfer(from, to, amount);
    }

    function decimals() public view override returns (uint8) {
        return decimal;
    }
}