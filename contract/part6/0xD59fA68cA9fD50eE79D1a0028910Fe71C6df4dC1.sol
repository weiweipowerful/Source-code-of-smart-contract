// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "contracts/GnosisSafe.sol";
import "libraries/DataTypes.sol";
import "libraries/Errors.sol";
import "interfaces/IGovernanceManager.sol";

contract MultisigTimelock {
    event ProposalQueued(DataTypes.ProposalAction[] proposal);
    event ProposalCanceled(DataTypes.ProposalAction[] proposal);
    event ProposalExecuted(DataTypes.ProposalAction[] proposal);
    event DelayChanged(uint256 oldDelay, uint256 newDelay);

    uint256 internal constant _MIN_DELAY = 15 minutes;
    uint256 internal constant _MAX_DELAY = 7 days;

    IGovernanceManager public immutable governanceManager;
    GnosisSafe public immutable multisig;

    DataTypes.ProposalAction[] internal _queuedProposal;
    uint256 public proposalQueuedAt;

    uint256 public delay;

    modifier onlyMultisig() {
        if (msg.sender != address(multisig))
            revert Errors.NotAuthorized(msg.sender, address(multisig));
        _;
    }

    constructor(
        IGovernanceManager governanceManager_,
        GnosisSafe multisig_,
        uint256 delay_
    ) {
        require(
            delay_ >= _MIN_DELAY && delay_ <= _MAX_DELAY,
            "MultisigTimelock: invalid delay"
        );
        require(
            address(multisig_) != address(0),
            "MultisigTimelock: zero address"
        );
        address[] memory owners = multisig_.getOwners();
        require(owners.length > 0, "MultisigTimelock: no owners");

        multisig = multisig_;
        governanceManager = governanceManager_;
        delay = delay_;
    }

    function queueProposal(
        DataTypes.ProposalAction[] calldata actions
    ) external onlyMultisig {
        require(actions.length > 0, "MultisigTimelock: no actions");
        require(
            _queuedProposal.length == 0,
            "MultisigTimelock: proposal already queued"
        );
        for (uint256 i; i < actions.length; i++) {
            _queuedProposal.push(actions[i]);
        }
        proposalQueuedAt = block.timestamp;

        emit ProposalQueued(actions);
    }

    function vetoProposal(uint16 proposalId) external onlyMultisig {
        governanceManager.vetoProposal(proposalId);
    }

    function extendMultisigSunsetAt(
        uint256 extensionPeriod
    ) external onlyMultisig {
        governanceManager.extendMultisigSunsetAt(extensionPeriod);
    }

    function changeDelay(uint256 newDelay) external onlyMultisig {
        require(
            newDelay >= _MIN_DELAY && newDelay <= _MAX_DELAY,
            "MultisigTimelock: invalid delay"
        );
        emit DelayChanged(delay, newDelay);
        delay = newDelay;
    }

    function executeProposal() external {
        if (!_isMultisigOwner(msg.sender))
            revert Errors.NotAuthorized(msg.sender, address(multisig));

        require(
            proposalQueuedAt > 0,
            "MultisigTimelock: no proposal to execute"
        );
        require(
            block.timestamp >= proposalQueuedAt + delay,
            "MultisigTimelock: delay not passed"
        );

        proposalQueuedAt = 0;

        governanceManager.createAndExecuteProposal(_queuedProposal);

        emit ProposalExecuted(_queuedProposal);

        delete _queuedProposal;
    }

    function cancelProposal() external {
        if (!_isMultisigOwner(msg.sender))
            revert Errors.NotAuthorized(msg.sender, address(multisig));
        require(
            _queuedProposal.length > 0,
            "MultisigTimelock: no proposal to cancel"
        );
        emit ProposalCanceled(_queuedProposal);
        delete _queuedProposal;
        proposalQueuedAt = 0;
    }

    function queuedProposal()
        external
        view
        returns (DataTypes.ProposalAction[] memory)
    {
        return _queuedProposal;
    }

    function _isMultisigOwner(address account) internal view returns (bool) {
        if (account == address(multisig)) {
            return true;
        }
        address[] memory owners = multisig.getOwners();
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == account) {
                return true;
            }
        }
        return false;
    }
}