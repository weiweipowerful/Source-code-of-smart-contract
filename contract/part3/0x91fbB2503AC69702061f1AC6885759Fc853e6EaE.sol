// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./interfaces/IPair.sol";
import "./interfaces/IFactory.sol";

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract Token is ERC20Burnable, ERC20Capped, Pausable, Ownable {
    uint16 public constant DENOMINATOR = 100_00;
    uint16 public constant MAX_TAX = 30_00;
    address public immutable FACTORY;

    Taxes public taxes;

    mapping(address => bool) public whitelist;
    mapping(address => bool) public blacklist;
    mapping(address => bool) public excludedFromFee;

    struct Taxes {
        uint16 buy;
        uint16 sell;
        address feeReceiver;
    }

    error WrongTaxes(uint16 buyTax, uint16 sellTax);
    error TransferForbidden(address user, bool paused, bool blacklisted);

    constructor(
        address admin,
        address firstHolder,
        address factory,
        Taxes memory settings
    )
        Ownable(admin)
        ERC20("K9 Finance DAO", "KNINE")
        ERC20Capped(999_999_999_999 * 10 ** 18)
    {
        FACTORY = factory;
        whitelist[firstHolder] = true;
        excludedFromFee[firstHolder] = true;
        _chageSettings(settings);
        _mint(firstHolder, cap());

        _pause();
    }

    // OWNER METHODS

    /** @dev Mint tokens to @param user address in the @param amount
     * @notice Available for owner only
     */
    function mint(address user, uint256 amount) external onlyOwner {
        _mint(user, amount);
    }

    /** @dev Stops any transfers
     * @notice Available for owner only
     */
    function pause() external onlyOwner {
        _pause();
    }

    /** @dev Allow transfers again
     * @notice Available for owner only
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /** @dev Add or remove users to/from whitelist
     * @notice Available for owner only
     */
    function changeWhiteStatus(address[] memory users) external onlyOwner {
        for (uint256 i; i < users.length; i++) {
            whitelist[users[i]] = !whitelist[users[i]];
        }
    }

    /** @dev Add or remove users to/from blacklist
     * @notice Available for owner only
     */
    function changeBlackStatus(address[] memory users) external onlyOwner {
        for (uint256 i; i < users.length; i++) {
            blacklist[users[i]] = !blacklist[users[i]];
        }
    }

    /** @dev Add or remove users to/from excluded from fee list
     * @notice Available for owner only
     */
    function changeExcludedStatus(address[] memory users) external onlyOwner {
        for (uint256 i; i < users.length; i++) {
            excludedFromFee[users[i]] = !excludedFromFee[users[i]];
        }
    }

    /** @dev Changes taxes settings (buy/sell fee percents and fee receiver address)
     * @notice Available for owner only
     */
    function changeSettings(Taxes memory settings) external onlyOwner {
        _chageSettings(settings);
    }

    // INTERNAL METHODS

    function _chageSettings(Taxes memory _settings) internal {
        require(_settings.feeReceiver != address(0), "Token: Invalid receiver");
        require(_settings.buy <= MAX_TAX && _settings.sell <= MAX_TAX, "Token: Wrong taxes");
        taxes = _settings;
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Capped) {
        require(whitelist[from] || !(paused() || blacklist[from]), "Token: Transfer forbidden");

        bool isSell = _pairCheck(to);
        bool isBuy = _pairCheck(from);
        uint256 fee = uint256(
            isBuy && !excludedFromFee[to]
                ? (value * taxes.buy) / DENOMINATOR
                : isSell && !excludedFromFee[from]
                ? (value * taxes.sell) / DENOMINATOR
                : 0
        );

        if (fee > 0) {
            ERC20._update(from, taxes.feeReceiver, fee);
            value -= fee;
        }

        ERC20Capped._update(from, to, value);
    }

    function _pairCheck(address _token) internal view returns (bool) {
        address token0;
        address token1;

        if (isContract(_token)) {
            try IPair(_token).token0() returns (address _token0) {
                token0 = _token0;
            } catch {
                return false;
            }

            try IPair(_token).token1() returns (address _token1) {
                token1 = _token1;
            } catch {
                return false;
            }

            address goodPair = IFactory(FACTORY).getPair(token0, token1);
            if (goodPair != _token) {
                return false;
            }

            if (token0 == address(this) || token1 == address(this)) return true;
            else return false;
        } else return false;
    }

    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}