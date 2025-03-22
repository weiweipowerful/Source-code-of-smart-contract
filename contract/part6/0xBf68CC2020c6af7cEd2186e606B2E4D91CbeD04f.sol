// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IDistributor.sol";
import "../Errors.sol";

/**
 * @title BatchDistributor
 * @author @trmaphi
 * @notice This contract is used to claim airdrops for multiple users in one call.
 */
contract BatchDistributor is ReentrancyGuard {
    struct BatchClaimParams {
        address distributorContract;
        bool isInit;
        bytes32 userVestingId;
        bytes proof;
    }

    event BatchClaimed(address indexed caller, address[] distributors, address recipient);

    constructor() {
    }

    /**
     * Claim for multiple airdrops
     * @param params BatchClaimParams[]
     * @param recipient address
     */
    function batchClaim(BatchClaimParams[] calldata params, address recipient) external nonReentrant {
        if (params.length == 0) revert EmptyArray();
        if (recipient != msg.sender) revert InvalidRecipient();
        address[] memory distributors = new address[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            BatchClaimParams memory param = params[i];
            distributors[i] = param.distributorContract;
            IDistributor distributor = IDistributor(param.distributorContract);
            
            if (param.isInit) {
                if (param.proof.length == 0) revert InvalidProofs();
                distributor.initClaim(
                    msg.sender,
                    param.proof,
                    recipient
                );
            } else {
                distributor.claim(
                    msg.sender,
                    param.userVestingId,
                    recipient
                );
            }
        }

        emit BatchClaimed(msg.sender, distributors, recipient);
    }
}