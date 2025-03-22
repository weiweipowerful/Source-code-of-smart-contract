// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import {ERC20} from "./ERC20.sol";
import {TOTOAdmin} from "./TotoAdmin.sol";

/**
 * @title TOTO
 * @notice Implementation of the TOTO Token
 *
 * Token details:
 * - Name: TOTO Token
 * - Symbol: TOTO
 * - Decimals: 9
 * - Maximum Supply: 1 billion tokens (1,000,000,000 * 10^9 units)
 *
 * Key Features:
 * - Maximum Token Cap: The total token supply is permanently capped at 1 billion tokens.
 * - Pausing Mechanism: The owner, via inherited functionality from the TOTOAdmin contract,
 *   can pause or unpause minting and burning of tokens.
 * - Permissioned Minting and Burning: Only addresses with the required permissions
 *   (`minter` or `burner` roles) can execute mint or burn operations.
 */
contract TOTO is ERC20, TOTOAdmin {
    /**
     * @dev The maximum limit to the token supply
     */
    uint256 public immutable MAX_SUPPLY;

    /**
     * @dev Initialize the maximum supply cap to 1 billion
     */
    constructor() ERC20("TOTO Token", "TOTO") {
        uint256 maxSupply = 1_000_000_000;
        MAX_SUPPLY = maxSupply * (10 ** decimals());
    }

    /**
     * @dev Overrides the decimals function to return 9 decimals.
     */
    function decimals() public pure override returns (uint8) {
        return 9;
    }

    /**
     * @dev Mints new tokens to a specified address.
     *
     * Requirements:
     * - The contract must not be paused.
     * - The caller must have the minting permission.
     * - The resulting total supply must not exceed the `MAX_SUPPLY`.
     *
     * @param to The address to receive the newly minted tokens.
     * @param amount The number of tokens to mint (in smallest units).
     */
    function mint(address to, uint256 amount) external whenNotPaused {
        require(
            hasMintPermission(_msgSender()),
            "TOTO: must have minter role to mint"
        );
        require(
            totalSupply() + amount <= MAX_SUPPLY,
            "TOTO: Exceeds max supply"
        );
        _mint(to, amount);
    }

    /**
     * @dev Burns a specified amount of tokens from the caller's account.
     *
     * Requirements:
     * - The contract must not be paused.
     * - The caller must have the required burning permission.
     * - The caller's account must have at least the amount of tokens to be burned.
     *
     * @param amount The number of tokens to burn (in smallest units).
     */
    function burn(uint256 amount) external whenNotPaused {
        require(
            hasBurnPermission(_msgSender()),
            "TOTO: must have burner role to burn"
        );
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Override the function to always update allowance amount.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal override {
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        unchecked {
            _approve(owner, spender, currentAllowance - amount);
        }
    }
}
