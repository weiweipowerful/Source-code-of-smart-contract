// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {AbstractSystemPause} from "../security/AbstractSystemPause.sol";
import {IViceToken} from "../interfaces/IViceToken.sol";
import {IAccess} from "../interfaces/IAccess.sol";
import {ISystemPause} from "../interfaces/ISystemPause.sol";

// @title: Vice Token
// @author: Richard Ryan (derelict.eth)

contract ViceToken is
    Initializable,
    ERC20VotesUpgradeable,
    PausableUpgradeable,
    AbstractSystemPause,
    IViceToken,
    ERC20PermitUpgradeable
{
    /* ========== STATE VARIABLES ========== */

    /// Access interface
    IAccess access;
    /// total accounts
    uint256 totalAccounts;
    /// max supply
    uint256 public maxSupply;

    /* ========== REVERT STATEMENTS ========== */

    error ExceedsMaxSupply(uint256 value, uint256 maxSupply);

    /* ========== MODIFIERS ========== */

    /**
     @dev this modifier calls the Access contract. Reverts if caller does not have role
     */

    modifier onlyViceRole() {
        access.onlyViceRole(msg.sender);
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        address _accessAddress,
        address _systemPauseAddress,
        uint256 _maximumSupply
    ) public initializer {
        __ERC20_init("Vice", "VICE");
        __Pausable_init();
        __ERC20Permit_init("Vice");
        __ERC20Votes_init();
        require(
            _accessAddress != address(0) && _systemPauseAddress != address(0),
            "Address zero input"
        );
        access = IAccess(_accessAddress);
        system = ISystemPause(_systemPauseAddress);
        maxSupply = _maximumSupply;
    }

    /* ========== EXTERNAL ========== */

    /**
    @dev this function is for minting tokens. 
    Callable when system is not paused and contract is not paused. Callable by executive.
     */
    function mint(
        address to,
        uint256 amount
    ) external override whenNotPaused whenSystemNotPaused onlyViceRole {
        if (totalSupply() + amount > maxSupply)
            revert ExceedsMaxSupply(totalSupply() + amount, maxSupply);

        if (amount != 0) _increaseTotalAccounts(to);
        super._mint(to, amount);
    }

    /**
    @dev this function is for burning tokens. 
    Callable when system is not paused and contract is not paused. Callable by executive.
     */

    function burn(
        address from,
        uint256 amount
    ) external virtual override whenNotPaused whenSystemNotPaused {
        require(from == msg.sender, "User can only burn owned tokens");
        super._burn(from, amount);
        if (amount != 0) _decreaseTotalAccounts(from);
    }

    /**
     * @dev function to pause contract only callable by admin
     */
    function pauseContract() external virtual override onlyViceRole {
        _pause();
    }

    /**
     * @dev function to unpause contract only callable by admin
     */
    function unpauseContract() external virtual override onlyViceRole {
        _unpause();
    }

    /**
    @dev this function returns the total accounts
    @return uint256 total accounts that own VICE
     */

    function getTotalAccounts() external view override returns (uint256) {
        return totalAccounts;
    }

    /* ========== PUBLIC ========== */

    /**
    @dev this function is for transferring tokens. 
    Callable when system is not paused and contract is not paused.
    @return bool if the transfer was successful
     */

    function transfer(
        address to,
        uint256 amount
    ) public virtual override(ERC20Upgradeable, IViceToken) returns (bool) {
        if (amount != 0) _increaseTotalAccounts(to);
        super.transfer(to, amount);
        if (amount != 0) _decreaseTotalAccounts(msg.sender);
        return true;
    }

    /**
    @dev this function is for third party transfer of tokens. 
    Callable when system is not paused and contract is not paused.
    @return true if the transfer was successful
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override(ERC20Upgradeable, IViceToken) returns (bool) {
        if (amount != 0) _increaseTotalAccounts(to);
        super.transferFrom(from, to, amount);
        if (amount != 0) {
            _decreaseTotalAccounts(from);
        }
        return true;
    }

    /**
    @dev approve function to approve spender with amount. 
    Can be called when system and this contract is unpaused.
    @param spender. The approved address. 
    @param amount. The amount spender is approved for. 
    @return true if the approval was successful
     */
    function approve(
        address spender,
        uint256 amount
    ) public virtual override(ERC20Upgradeable, IViceToken) returns (bool) {
        return super.approve(spender, amount);
    }

    /**
    @dev this function returns the allowance for spender.
    @param owner. The owner of approved tokens. 
    @param spender. The amount spender is approved for. 
    @return uint256. The amount spender is approved for
     */

    function allowance(
        address owner,
        address spender
    )
        public
        view
        virtual
        override(ERC20Upgradeable, IViceToken)
        returns (uint256)
    {
        return super.allowance(owner, spender);
    }

    /**
    @dev this function returns the balance of account
    @param account. The account to return balance for
    @return balance 
     */

    function balanceOf(
        address account
    )
        public
        view
        virtual
        override(ERC20Upgradeable, IViceToken)
        returns (uint256)
    {
        return super.balanceOf(account);
    }

    /**
    @dev this function returns the total supply
     */

    function totalSupply()
        public
        view
        virtual
        override(ERC20Upgradeable, IViceToken)
        returns (uint256)
    {
        return super.totalSupply();
    }

    function decimals()
        public
        view
        virtual
        override(ERC20Upgradeable, IViceToken)
        returns (uint8)
    {
        return super.decimals();
    }

    function nonces(address owner) public view virtual override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(owner);
    }

    /* ========== INTERNAL ========== */

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._update(from, to, amount);
    }

    /**
    @dev internal function which increases total accounts holding VICE
    @param _account. It checks that account is not address zero and account's balance is zero. 
     */

    function _increaseTotalAccounts(address _account) internal {
        if (_account != address(0) && balanceOf(_account) == uint256(0))
            ++totalAccounts;

        emit TotalAccounts(totalAccounts);
    }

    /**
    @dev internal function which decreases total accounts holding VICE
    @param _account. It checks that account is not address zero and account's balance is zero. 
     */

    function _decreaseTotalAccounts(address _account) internal {
        if (_account != address(0) && balanceOf(_account) == uint256(0))
            --totalAccounts;

        emit TotalAccounts(totalAccounts);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}