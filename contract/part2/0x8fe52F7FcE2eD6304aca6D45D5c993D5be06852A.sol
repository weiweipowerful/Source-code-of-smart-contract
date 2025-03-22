// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: 2024 Kiln <[email protected]>
//
// ██╗  ██╗██╗██╗     ███╗   ██╗
// ██║ ██╔╝██║██║     ████╗  ██║
// █████╔╝ ██║██║     ██╔██╗ ██║
// ██╔═██╗ ██║██║     ██║╚██╗██║
// ██║  ██╗██║███████╗██║ ╚████║
// ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═══╝
//
pragma solidity 0.8.18;

import {IExitQueueClaimHelper} from "@src/interfaces/integrations/IExitQueueClaimHelper.sol";
import {IFeeDispatcher} from "@src/interfaces/integrations/IFeeDispatcher.sol";
import {IvExitQueue} from "@src/interfaces/IvExitQueue.sol";

/// @title ExitQueueClaimHelper (V1) Contract
/// @author gauthiermyr @ Kiln
/// @notice This contract contains functions to resolve and claim casks on several exit queues.
contract ExitQueueClaimHelper is IExitQueueClaimHelper {
    /// @inheritdoc IExitQueueClaimHelper
    function multiClaim(address[] calldata exitQueues, uint256[][] calldata ticketIds, uint32[][] calldata casksIds)
        external
        override
        returns (IvExitQueue.ClaimStatus[][] memory statuses)
    {
        if (exitQueues.length != ticketIds.length) {
            revert IFeeDispatcher.UnequalLengths(exitQueues.length, ticketIds.length);
        }
        if (exitQueues.length != casksIds.length) {
            revert IFeeDispatcher.UnequalLengths(exitQueues.length, casksIds.length);
        }

        statuses = new IvExitQueue.ClaimStatus[][](exitQueues.length);

        for (uint256 i = 0; i < exitQueues.length;) {
            IvExitQueue exitQueue = IvExitQueue(exitQueues[i]);
            // slither-disable-next-line calls-loop
            statuses[i] = exitQueue.claim(ticketIds[i], casksIds[i], type(uint16).max);

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IExitQueueClaimHelper
    function multiResolve(address[] calldata exitQueues, uint256[][] calldata ticketIds)
        external
        view
        override
        returns (int64[][] memory caskIdsOrErrors)
    {
        if (exitQueues.length != ticketIds.length) {
            revert IFeeDispatcher.UnequalLengths(exitQueues.length, ticketIds.length);
        }

        caskIdsOrErrors = new int64[][](exitQueues.length);

        for (uint256 i = 0; i < exitQueues.length;) {
            IvExitQueue exitQueue = IvExitQueue(exitQueues[i]);
            // slither-disable-next-line calls-loop
            caskIdsOrErrors[i] = exitQueue.resolve(ticketIds[i]);

            unchecked {
                ++i;
            }
        }
    }
}