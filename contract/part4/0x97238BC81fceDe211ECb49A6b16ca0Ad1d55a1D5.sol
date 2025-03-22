// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.6.10 <0.8.0;

import "../interfaces/IVotingEscrow.sol";

interface IClaimRewards {
    function claimRewards(address account) external;

    function claimRewardsAndUnwrap(address account) external;
}

contract BatchOperationHelper {
    string public constant VERSION = "2.0.0";

    function batchClaimRewards(address[] calldata contracts, address account) public {
        uint256 count = contracts.length;
        for (uint256 i = 0; i < count; i++) {
            IClaimRewards(contracts[i]).claimRewards(account);
        }
    }

    function batchClaimRewardsAndUnwrap(
        address[] calldata contracts,
        address[] calldata wrappedContracts,
        address account
    ) external {
        batchClaimRewards(contracts, account);
        uint256 count = wrappedContracts.length;
        for (uint256 i = 0; i < count; i++) {
            IClaimRewards(wrappedContracts[i]).claimRewardsAndUnwrap(account);
        }
    }

    function batchSyncWithVotingEscrow(address[] calldata contracts, address account) external {
        uint256 count = contracts.length;
        for (uint256 i = 0; i < count; i++) {
            IVotingEscrowCallback(contracts[i]).syncWithVotingEscrow(account);
        }
    }
}