// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20, ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract CheddaToken is ERC20Votes, Ownable {
    using SafeERC20 for IERC20;

    uint16 private constant _DENOMINATOR = 100_00;
    uint16 private constant _MAX_TAX_RATE = 2_00;
    uint16 private constant _MAX_BURN_RATE = 1_00;

    bool private _doubleEntered;
    FeesInfo private _feesInfo;

    mapping(address => bool) private _excludedFromFee;

    struct FeesInfo {
        uint16 taxRate;
        uint16 burnRate;
        address taxRecipient;
    }

    error ZeroAmount();
    error ZeroAddress();
    error TooHighRate(uint16 provided, uint16 max);

    event TaxRateSetted(uint16 newRate);
    event BurnRateSetted(uint16 newRate);
    event TaxRecipientSetted(address recipient);
    event ExcludedFromFee(address account);
    event IncludedInFee(address account);
    event TokenRecovered(address token, uint256 amount);
    event FeesTaken(address from, uint256 tax, uint256 burn);

    constructor(
        address admin,
        address recipient
    ) ERC20("CHEDDA", "CHDD") Ownable(admin) EIP712("CHEDDA", "1") {
        if (recipient == address(0)) revert ZeroAddress();
        _feesInfo = FeesInfo(2_00, 1_00, recipient);

        _excludedFromFee[admin] = true;
        _excludedFromFee[recipient] = true;

        _mint(admin, 80_000_000_000 * 1e18);
    }

    // ownable methods

    /** @notice Sets new tax rate
     * @dev For owner only
     * @param newRate percent value with 2 decimal places for the new tax rate
     */
    function setTaxRate(uint16 newRate) external onlyOwner {
        if (newRate > _MAX_TAX_RATE) revert TooHighRate(newRate, _MAX_TAX_RATE);
        _feesInfo.taxRate = newRate;

        emit TaxRateSetted(newRate);
    }

    /** @notice Sets new burn rate
     * @dev For owner only
     * @param newRate percent value with 2 decimal places for the new burn rate
     */
    function setBurnRate(uint16 newRate) external onlyOwner {
        if (newRate > _MAX_BURN_RATE)
            revert TooHighRate(newRate, _MAX_BURN_RATE);
        _feesInfo.burnRate = newRate;

        emit BurnRateSetted(newRate);
    }

    /** @notice Sets new tax recipient
     * @dev For owner only
     * @param newRecipient address
     */
    function setTaxRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        _feesInfo.taxRecipient = newRecipient;

        emit TaxRecipientSetted(newRecipient);
    }

    /** @notice Adds an @param account to `_excludedFromFee` whitelist
     * @dev For owner only
     */
    function addToTaxExempt(address account) external onlyOwner {
        _excludedFromFee[account] = true;

        emit ExcludedFromFee(account);
    }

    /** @notice Removes an @param account from `_excludedFromFee` whitelist
     * @dev For owner only
     */
    function removeFromTaxExempt(address account) external onlyOwner {
        _excludedFromFee[account] = false;

        emit IncludedInFee(account);
    }

    /** @notice Withdraws stuck @param token in specified @param amount
     * @dev For owner only
     */
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransfer(_msgSender(), amount);

        emit TokenRecovered(token, amount);
    }

    // public methods

    /** @notice Destroys a @param value amount of tokens from the caller
     */
    function burn(uint256 value) external {
        _burn(_msgSender(), value);
    }

    // view methods

    /** @notice View method to get transfer fee percent value
     * @return tax fee percent value
     */
    function getTaxRate() external view returns (uint16) {
        return _feesInfo.taxRate;
    }

    /** @notice View method to get burn fee percent value
     * @return burn fee percent value
     */
    function getBurnRate() external view returns (uint16) {
        return _feesInfo.burnRate;
    }

    /** @notice View method to get transfer fee recipient
     * @return tax fee recipient
     */
    function getTaxRecipient() external view returns (address) {
        return _feesInfo.taxRecipient;
    }

    /** @notice View method to get @param account status in `_excludedFromFee` whitelist
     * @return true - excluded, else - false
     */
    function isTaxExempt(address account) external view returns (bool) {
        return _excludedFromFee[account];
    }

    // overrided methods

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        bool takeFee = _takeFee(from, to);
        if (takeFee && !_doubleEntered) {
            _doubleEntered = true;

            (uint256 taxFee, uint256 burnFee) = (
                (value * _feesInfo.taxRate) / _DENOMINATOR,
                (value * _feesInfo.burnRate) / _DENOMINATOR
            );

            value -= taxFee + burnFee;

            if (taxFee > 0) {
                _transfer(from, _feesInfo.taxRecipient, taxFee);
            }

            if (burnFee > 0) {
                _burn(from, burnFee);
            }

            _doubleEntered = false;

            emit FeesTaken(from, taxFee, burnFee);
        }
        super._update(from, to, value);
    }

    // private methods

    function _takeFee(address from, address to) private view returns (bool) {
        if (
            _excludedFromFee[from] ||
            _excludedFromFee[to] ||
            from == address(0) ||
            to == address(0)
        ) return false;
        else return true;
    }
}