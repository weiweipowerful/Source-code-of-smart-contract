// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract DAPP is ERC20, ERC20Burnable, ERC20Capped, AccessControl, ERC20Permit, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BLOCKLISTER_ROLE = keccak256("BLOCKLISTER_ROLE");

    mapping(address => bool) blocklisted;

    event Blocklisted(address _account);
    event UnBlocklisted(address _account);
    event MinterAdded(address _account);
    event MinterRemoved(address _account);
    event BlocklisterAdded(address _account);
    event BlocklisterRemoved(address _account);
    event AdminTransferred(address _oldOwner, address _newOwner);

    modifier notBlocklisted(address _account) {
        require(!blocklisted[_account], "Account is blocklisted");
        _;
    }

    modifier notZeroAddress(address _account) {
        require(_account != address(0), "address cannot be zero");
        _;
    }

    constructor(string memory _name, string memory _symbol, uint256 _cap, address _minter, address _blocklister)
        ERC20(_name, _symbol)
        ERC20Capped(_cap)
        ERC20Permit(_name)
        notZeroAddress(_minter)
        notZeroAddress(_blocklister)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _minter);
        _grantRole(BLOCKLISTER_ROLE, _blocklister);
    }

    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) {
        require(_amount > 0, "amount must be greater than 0");
        _mint(_to, _amount);
    }

    function mintBulk(address[] memory _accounts, uint256[] memory _amounts)
        external
        onlyRole(MINTER_ROLE)
        returns (bool)
    {
        require(_accounts.length == _amounts.length, "arrays must have same length");

        for (uint256 i = 0; i < _accounts.length; i++) {
            require(_amounts[i] > 0, "amount must be greater than 0");
            _mint(_accounts[i], _amounts[i]);
        }
        return true;
    }

    function approve(address _spender, uint256 _value)
        public
        override
        notBlocklisted(_msgSender())
        notBlocklisted(_spender)
        whenNotPaused
        returns (bool)
    {
        return super.approve(_spender, _value);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function isBlocklisted(address _account) external view returns (bool) {
        return blocklisted[_account];
    }

    function blocklist(address _account) external onlyRole(BLOCKLISTER_ROLE) notZeroAddress(_account) whenNotPaused {
        if (isMinter(_account) || isBlocklister(_account)) {
            revert("account has a role and cannot be blocklisted");
        }

        blocklisted[_account] = true;
        emit Blocklisted(_account);
    }

    function unBlocklist(address _account) external onlyRole(BLOCKLISTER_ROLE) notZeroAddress(_account) whenNotPaused {
        blocklisted[_account] = false;
        emit UnBlocklisted(_account);
    }

    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public override notBlocklisted(_owner) notBlocklisted(_spender) whenNotPaused {
        super.permit(_owner, _spender, _value, _deadline, _v, _r, _s);
    }

    function isMinter(address _account) public view returns (bool) {
        return hasRole(MINTER_ROLE, _account);
    }

    function isBlocklister(address _account) public view returns (bool) {
        return hasRole(BLOCKLISTER_ROLE, _account);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function addMinter(address _account) public {
        grantRole(MINTER_ROLE, _account);
        emit MinterAdded(_account);
    }

    function removeMinter(address _account) public {
        revokeRole(MINTER_ROLE, _account);
        emit MinterRemoved(_account);
    }

    function addBlocklister(address _account) public {
        grantRole(BLOCKLISTER_ROLE, _account);
        emit BlocklisterAdded(_account);
    }

    function removeBlocklister(address _account) public {
        revokeRole(BLOCKLISTER_ROLE, _account);
        emit BlocklisterRemoved(_account);
    }

    function transferAdmin(address _newOwner) public {
        grantRole(DEFAULT_ADMIN_ROLE, _newOwner);
        revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
        emit AdminTransferred(_msgSender(), _newOwner);
    }

    function grantRole(bytes32 role, address _account)
        public
        virtual
        override
        onlyRole(getRoleAdmin(role))
        notBlocklisted(_account)
        notZeroAddress(_account)
        whenNotPaused
    {
        _grantRole(role, _account);
    }

    function revokeRole(bytes32 role, address _account)
        public
        override
        onlyRole(getRoleAdmin(role))
        notZeroAddress(_account)
        whenNotPaused
    {
        _revokeRole(role, _account);
    }

    function _update(address from, address to, uint256 value)
        internal
        virtual
        override(ERC20, ERC20Capped)
        notBlocklisted(from)
        notBlocklisted(to)
        notBlocklisted(_msgSender())
    {
        super._update(from, to, value);
    }
}