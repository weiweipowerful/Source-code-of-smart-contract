// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import "@openzeppelin/[email protected]/access/Ownable2Step.sol";
import "@openzeppelin/[email protected]/token/ERC20/ERC20.sol";

contract OpSecToken is ERC20, Ownable2Step {
    bool public launched;

    uint128 public launchBlock;
    uint128 public launchTime;

    mapping(address => bool) public isExcludedFromLimits;

    event Launch();
    event ExcludeFromLimits(address indexed account, bool value);

    error AlreadyLaunched();
    error NotLaunched();

    constructor(address _initialTokenRecipient) ERC20("OpSec", "OPSEC") {
        _excludeFromLimits(msg.sender, true);
        _excludeFromLimits(_initialTokenRecipient, true);
        _excludeFromLimits(address(0), true);
        _excludeFromLimits(address(this), true);
        _excludeFromLimits(0x61fFE014bA17989E743c5F6cB21bF9697530B21e, true); // Uniswap V3 QuoterV2
        _excludeFromLimits(0x000000fee13a103A10D593b9AE06b3e05F2E7E1c, true); // Uniswap Fee Collector

        _mint(_initialTokenRecipient, 100_000_000 ether);
    }

    function burn(uint256 amount) external virtual {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Trigger the launch of the token
     */
    function launch() external onlyOwner {
        require(!launched, AlreadyLaunched());
        launched = true;
        launchBlock = uint128(block.number);
        launchTime = uint128(block.timestamp);
        emit Launch();
    }

    /**
     * @dev Exclude (or not) accounts from limits
     */
    function excludeFromLimits(
        address[] calldata accounts,
        bool value
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _excludeFromLimits(accounts[i], value);
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal virtual override {
        require(
            launched || isExcludedFromLimits[from] || isExcludedFromLimits[to],
            NotLaunched()
        );
    }

    function _excludeFromLimits(address account, bool value) internal virtual {
        isExcludedFromLimits[account] = value;
        emit ExcludeFromLimits(account, value);
    }
}