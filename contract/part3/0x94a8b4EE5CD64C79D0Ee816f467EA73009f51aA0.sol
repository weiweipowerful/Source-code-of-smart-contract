// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract RIOToken is ERC20, ERC20Burnable, AccessControl {
    uint256 public constant MAX_SUPPLY = 175_000_000 * 10 ** 18; // 175 million tokens with 18 decimals

    uint256 public dailyMintCap = 1_750_000 * 10 ** 18; // 1.75M tokens with 18 decimals
    uint256 public lastMintTimestamp;
    uint256 public mintedToday;

    // Variables for delayed daily mint cap updates
    uint256 public pendingDailyMintCap;
    uint256 public dailyMintCapUpdateTimestamp;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    event BridgedOut(address, uint256);
    event DailyCapUpdated(uint256);

    constructor(address defaultAdmin, address minter) ERC20("Realio Network", "RIO") {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
    }

    /*******************************************************************************************\
     *  @dev mint function to mint new tokens
     *  @param recipient address of recipient of the newly-minted tokens
     *  @param amount amount of the newly-minted tokens to go to recipient
     *  The mint function will revert if the minted amount would result in either
     *  the MAX_SUPPLY or the active dailyMintCap being exceeded
    \*******************************************************************************************/
    function mint(
        address recipient,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) {
        // Apply the new daily cap if 24 hours have passed
        if (
            pendingDailyMintCap > 0 &&
            block.timestamp >= dailyMintCapUpdateTimestamp + 1 days
        ) {
            dailyMintCap = pendingDailyMintCap;
            pendingDailyMintCap = 0; // Clear the pending update
        }

        uint256 newSupply = totalSupply() + amount; // Calculate the new total supply

        require(newSupply <= MAX_SUPPLY, "Exceeds max supply");

        if (block.timestamp >= _nextResetTime()) {
            mintedToday = 0;
            lastMintTimestamp = block.timestamp;
        }

        require(mintedToday + amount <= dailyMintCap, "Exceeds daily cap");

        mintedToday += amount;

        _mint(recipient, amount);
    }

    /*******************************************************************************************\
     *  @dev batchMint function to mint new tokens in batches
     *  @param recipients list of recipients of the newly-minted tokens
     *  @param amounts list of amounts of the newly-minted tokens per recipient
     *  The lists are in corresponding orders, i.e. recipients[n] receives amounts[n]
     *  The batchMint function will revert if the total minted amount would result in either
     *  the MAX_SUPPLY or the active dailyMintCap being exceeded
    \*******************************************************************************************/
    function batchMint(
        address[] memory recipients,
        uint256[] memory amounts
    ) external onlyRole(MINTER_ROLE) {
        require(
            recipients.length == amounts.length,
            "Mismatched input lengths"
        );

        // Apply the new daily cap if 24 hours have passed
        if (
            pendingDailyMintCap > 0 &&
            block.timestamp >= dailyMintCapUpdateTimestamp + 1 days
        ) {
            dailyMintCap = pendingDailyMintCap;
            pendingDailyMintCap = 0; // Clear the pending update
        }

        uint256 totalMintAmount = _sumArray(amounts); // Sum all the amounts in the batch
        uint256 newSupply = totalSupply() + totalMintAmount; // Calculate the new total supply

        require(newSupply <= MAX_SUPPLY, "Exceeds max supply");

        if (block.timestamp >= _nextResetTime()) {
            mintedToday = 0;
            lastMintTimestamp = block.timestamp;
        }

        require(
            mintedToday + totalMintAmount <= dailyMintCap,
            "Exceeds daily cap"
        );

        mintedToday += totalMintAmount;

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    // Helper function to calculate the next daily cap reset time
    function _nextResetTime() private view returns (uint256) {
        // Calculate the next daily cap reset time at midnight UTC
        return (lastMintTimestamp / 1 days + 1) * 1 days;
    }

    // Helper function to sum an array of uint256 values
    function _sumArray(
        uint256[] memory amounts
    ) private pure returns (uint256 total) {
        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
    }

    /*******************************************************************************************\
     *  @dev Admin function to modify the daily mint limit
     *  @param newCap new limit value
     *  The new cap will only take effect after 24hr have passed since the update was made
     *  Only the admin (owner) can modify the daily limit
    \*******************************************************************************************/
    function updateDailyMintCap(
        uint newCap
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pendingDailyMintCap = newCap;
        dailyMintCapUpdateTimestamp = block.timestamp; // Store update timestamp
        emit DailyCapUpdated(pendingDailyMintCap);
    }

    /*******************************************************************************************\
     *  @dev Admin function to burn tokens on behalf of a user (for bridging out)
     *  @param account address of the account whose tokens will be burned
     *  @param amount amount of tokens to burn
     *  The admin must be approved for (at least) the amount by the user, and this is exactly
     *  equivalent to calling burnFrom directly, with an added event emission
     *  Only the admin can call this function to burn tokens on behalf of users
    \*******************************************************************************************/
    function bridgeOut(
        address account,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Burn the tokens (requires approval)
        burnFrom(account, amount);

        // Emit the BridgedOut event
        emit BridgedOut(account, amount);
    }
}