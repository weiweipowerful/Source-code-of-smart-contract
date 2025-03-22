// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "FungifyPriceFeed.sol";
import "Ownable.sol";

// This is intended to reduce the number of transactions made.
contract BatchUpdateRate is Ownable {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external onlyOwner { wards[guy] = 1; }
    function deny(address guy) external onlyOwner { wards[guy] = 0; }
    modifier auth {
        if (wards[msg.sender] == 0) {
            revert Unauthorized();
        }
        _;
    }

    event FailedToUpdate(FungifyPriceFeed feed, int256 answer);

    error UnequalParamLengths();
    error Unauthorized();

    constructor() Ownable(msg.sender) {}

    // Sets the price answer to multiple price feeds at once
    function batchSetAnswer(FungifyPriceFeed[] memory priceFeeds, int256[] calldata newAnswers) external auth {
        uint numFeeds = priceFeeds.length;

        if (numFeeds != newAnswers.length) {
            revert UnequalParamLengths();
        }

        // Loops through all the provided feeds and attempts to set their answers
        for (uint i = 0; i < numFeeds;) {
            try priceFeeds[i].updateRate(newAnswers[i]) {
            } catch {
                emit FailedToUpdate(priceFeeds[i], newAnswers[i]);
            }
            unchecked { i++; }
        }
    }
}