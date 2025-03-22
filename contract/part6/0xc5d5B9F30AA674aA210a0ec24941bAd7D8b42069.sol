// SPDX-License-Identifier: MIT
/*
Version 1 of the HyperCycle Share Manager contract.
*/

pragma solidity 0.8.26;

import {Context} from '@openzeppelin/contracts/utils/Context.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Holder} from '@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol';
import {ERC1155Holder} from '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';
import {ShareManagerErrors as Errors} from '../libs/ShareManagerErrorsV2.sol';
import {ShareManagerEvents as Events} from '../libs/ShareManagerEventsV2.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ShareManagerTypes as Types, IHYPCSwapV2, IHyperCycleLicense, IHyperCycleShareTokensV2, IHYPC} from '../libs/ShareManagerTypesV2.sol';

/**
@title HyperCycle Share ManagerV2, revenue sharing manager.
@author Barry Rowe, Rodolfo Cova
@notice HyperCycle is a network of AI computation nodes offering different AI services in a 
    decentralized manner. In this system, there are license holders, token holders, hardware
    operators, and AI developers. Using the HyperCycleSwapV2 contract, an amount of HyPC (erc20)
    can be swapped for a cHyPC (containerized HyPC) token, which can then point towards a
    license (HyperCycleLicense) NFT id. At this point, the owner of this license can assign
    their license to some hardware running the HyperCycle Node Manager, and can from then
    on accept AI service requests on the network. 

    The HyperCycle Share Manager (This contract) allows the chypc owner to create a revenue sharing proposal, 
    to understand in deep the Share Token Contract, please refer to he Share Token Contract 
    documentation, See {HyperCycleShareTokensV2}.

    The main idea of the Share Manager is to be the one holding and managing the Share Token,
    being able to use the same benefits of the Share Tokens and extend it with the votations that
    share token holders can execute for the Share.

    To create a Share Proposal with the Share Manager, the chypc owner needs to call 
    `createShareProposal` function, this function will create a new Share Proposal and transfer
    the chypc to the Share Manager, the Share Manager will be the one holding the chypc until
    the Share Proposal is ended, in case the Share Proposal is ended, the chypc will be redeemed
    into hypc tokens, in which the share holders will be able to claim the proportional amount
    of share tokens to hypc tokens.

    The Share Proposal will be created with the following data:
        - CHyPC Data: CHyPC Id, CHyPC Owner, CHyPC Level, Initial Revenue Tokens, Initial Wealth Tokens
        - License Data: License Number, License Owner, License Level, Initial Revenue Tokens, Initial Wealth Tokens
        - Operator Data: Operator Revenue, Operator Assigned String, Operator Address
        - Share Token Data: Share Token Number, Revenue Deposit Delay, Revenue Token Id, Wealth Token Id, Valid End Timestamp
        - Status: Pending
    
    The Share Proposal can have the following status in the entire lifecycle of the Share Proposal:
        - Pending: The Share Proposal is created and waiting for the CHyPC NFT to be transfered to the Share Manager
        - Started: The Share Proposal is started and the Share Tokens are created, the CHyPC NFT is transfered to the Share Manager
        - Ended: The Share Proposal is ended and the license is transfered to the License Owner, 
                the CHyPC NFT will be redeem for HyPC tokens and will be claimable by the Share Token Holders.

    The Share Manager contract had a DAO system where share token holderes can be able to create votations to change 
    the hardware operator, the hardware operator revenue, the manager contract and to cancel the share proposal, 
    the votations will be created by the Share Manager and the share token holders will be able to vote.

    The Share Proposal can be ended by the share token holders any time the consensus is reached, for this 100% or 90% (depends on the
    actual `SELECTED_VOTATION_PORCENT`) of the wealth tokens needs to be voted to end the Share Proposal, in case the Share Proposal is 
    ended, the ending process will be executed.

    The Share Manager contract can be changed by the share token holders any time the consensus is reached, for this 100% of the wealth tokens
    needs to be voted to change the Share Manager, in case the Share Manager is changed,  the transfer of the Share Token Ownership will be executed.

    The Hardware Operator can be changed by the share token holders any time the consensus is reached, for this 50% of the wealth tokens
    needs to be voted to change the Hardware Operator, in case the Hardware Operator is changed, the Operator Revenue will be transfered
    to the older operator and the new operator will be set.

    The Hardware Operator Revenue can be changed by the share token holders any time the consensus is reached, 
    for this 50% of the wealth tokens needs to be voted to change the Hardware Operator Revenue, 
    in case the Hardware Operator Revenue is changed, the new operator revenue will be set.

    Another important feature of the Share Manager is the ability to migrate the Share Tokens from the Share Tokens contract
    to the Share Manager, this will allow the Share Manager to be the one holding the Share Tokens and be able to manage the Share
    Proposal and Votations. The Share Manager will be able to claim the Hypc tokens, based in the amount of wealth tokens available, 
    in case the Share Proposal is ended and the CHyPC exists.

    To migrate the Share Tokens to the Share Manager contract, the Share Token owner needs to call `startShareProposalMigration` function,
    this function will start the migration and the Share Manager contract will be able to finish the migration only if the ownership
    of the share token is changed to the Share Manager contract, and the Share Proposal is pending.
*/

contract HyperCycleShareManagerV2 is ERC721Holder, ERC1155Holder, ReentrancyGuard, Context {
    Types.ManagerData private managerData;

    uint256 public sharesProposalsCounter = 1;

    uint256 constant ONE_HUNDRED_PERCENT = 1e18;
    uint256 constant SIX_DECIMALS = 1e6;

    uint256 constant MAX_REVENUE_DELAY = 14 days;

    uint256 public SELECTED_VOTATION_PERCENT;
    uint256 public maxVotationDuration;

    mapping(uint256 shareProposalId => mapping(address user => uint256)) private _votePower;

    mapping(uint256 shareProposalId => mapping(uint256 votationIndex =>mapping(address user => bool))) private _voted;

    
    mapping(uint256 shareProposalId => mapping(address user => uint256)) public _lastVotationCreated;

    mapping(uint256 shareProposalId => mapping(address user => uint256)) private _votedFreeTime;

    mapping(uint256 shareProposalId => Types.Votation[]) private _votations;
  
    mapping(uint256 shareProposalId => Types.ShareProposalData) private _shareProposals;

    mapping(uint256 shareProposalId => bool) private shareCancelled;

    mapping(uint256 shareTokenNumber => uint256) public shareTokenExists;

    modifier onlyVoter(uint256 shareProposalId) {
        if (_votePower[shareProposalId][_msgSender()] == 0) revert Errors.NotEnoughWealthTokensAvailable();   
        _;
    }

    modifier validVoter(uint256 shareProposalId) {
        if (_votePower[shareProposalId][_msgSender()] == 0) revert Errors.NotEnoughWealthTokensAvailable();
        if (_shareProposals[shareProposalId].status != Types.ShareProposalStatus.STARTED) revert Errors.ShareProposalMustBeActive();
        if (_lastVotationCreated[shareProposalId][_msgSender()] > block.timestamp - 2 hours) revert Errors.VotationCreatedTooSoon();
         _;
    }

    modifier validVotation(uint256 shareProposalId, uint256 votationIndex) {
        if (_votations[shareProposalId].length <= votationIndex) {
            revert Errors.InvalidVotation();
        }
        _;
    }

    modifier onlyCHyPCOwner(uint256 shareProposalId) {
        if (_shareProposals[shareProposalId].chypcData.tokenOwner != _msgSender()) revert Errors.InvalidCHYPCOwner();
        _;
    }

    modifier onlyLicenseOwner(uint256 licenseNumber) {
        if (managerData.licenseContract.ownerOf(licenseNumber) != _msgSender()) revert Errors.InvalidLicenseOwner();
        _;
    }

    modifier proposalActive(uint256 shareProposalId) {
        if (_shareProposals[shareProposalId].status != Types.ShareProposalStatus.STARTED) {
            revert Errors.ShareProposalMustBeActive();
        }
        _;
    }

    modifier isHardwareOperator(uint256 shareProposalId) {
        if (_shareProposals[shareProposalId].operatorData.operatorAddress != _msgSender()) {
            revert Errors.MustBeClaimedByHardwareOperatorAddress();
        }
        _;
    }

    modifier validProposedDeadline(uint256 shareProposalId, uint256 deadline) {
        if (deadline <= block.timestamp+1 days) revert Errors.InvalidDeadline();
        if (_votations[shareProposalId].length > 0 && _votations[shareProposalId][_votations[shareProposalId].length-1].deadline > deadline) revert Errors.DeadlineMustBeIncreasing();
        if (deadline - block.timestamp > maxVotationDuration) revert Errors.DeadlineTooLate();
        _;
    }

    /**
    @dev The constructor takes in the contract addresses for the HyPC token, license, cHyPC NFTs and Share Tokens contract.
    @param _consensusOption: The consensus option to be used for the votations.
    @param _hypcToken: The HyPC ERC20 contract address.
    @param _chypcV2: The cHyPC ERC721 contract address.
    @param _licenseContract: The license ERC721 contract address.
    @param _hypcShareTokens: The license ERC721 contract address.
    */
    constructor(Types.ConsensusOptions _consensusOption, address _hypcToken, address _chypcV2, address _licenseContract, 
                address _hypcShareTokens, uint256 _maxVotingTime) {
        if (_hypcToken == address(0)) revert Errors.InvalidHYPCTokenAddress();

        if (_chypcV2 == address(0)) revert Errors.InvalidCHYPCAddress();

        if (_licenseContract == address(0)) revert Errors.InvalidLicenseAddress();

        if (_hypcShareTokens == address(0)) revert Errors.InvalidShareTokenContract();

        if (_maxVotingTime < 1 days || _maxVotingTime > 14 days) revert Errors.InvalidVotingDuration();

        maxVotationDuration = _maxVotingTime;

        _consensusOption == Types.ConsensusOptions.ONE_HUNDRED_PERCENT ?
            SELECTED_VOTATION_PERCENT = ONE_HUNDRED_PERCENT :
            SELECTED_VOTATION_PERCENT = ONE_HUNDRED_PERCENT * 9 / 10;

        managerData = Types.ManagerData({
            hypcToken: IHYPC(_hypcToken),
            chypcV2: IHYPCSwapV2(_chypcV2),
            licenseContract: IHyperCycleLicense(_licenseContract),
            hypcShareTokens: IHyperCycleShareTokensV2(_hypcShareTokens)
       });
    }

    // Share proposal management functions

    /**
    @notice Allows a user to create a new share.
    @param proposalData The encoded data needed to create a new share proposal, should have encoded: 
                        (uint256,uint256,uint256,uint256,uint256,string,address,bool,bool).
    @notice chypcId: should be the license number to be used for the share.
    @notice revenueToAssignToChypc: should be the amount of revenue tokens to be assigned to the chypc owner.
    @notice wealthToAssignToChypc: should be the amount of wealth tokens to be assigned to the chypc owner.
    @notice revenueDepositDelay: should be the amount of time in seconds that the revenue tokens will be locked.
    @notice licenseNumber: the license number to user for the proposal. If 0, then proposal will wait for a license owner to complete it.
    @notice operatorAssignedString: should be the string to be used as the operator assigned string for the share.
    @notice hardwareOperator: should be the address of the hardware operator to be used for the share.
    */
    function createShareProposal(bytes memory proposalData) external nonReentrant {
        (
            uint256 chypcId,
            uint256 revenueToAssignToChypc,
            uint256 wealthToAssignToChypc,
            uint256 revenueDepositDelay,
            uint256 licenseNumber,
            string memory operatorAssignedString,
            address hardwareOperator
        ) = abi.decode(proposalData, (uint256, uint256, uint256, uint256, uint256, string, address));

        uint256 chypcLevel = managerData.chypcV2.getTokenLevel(chypcId);

        if (managerData.chypcV2.ownerOf(chypcId) != _msgSender()) revert Errors.InvalidCHYPCOwner();

        if (hardwareOperator == address(0)) revert Errors.InvalidProposedAddress();

        if (revenueDepositDelay > MAX_REVENUE_DELAY) revert Errors.InvalidDepositRevenueDelay();

        if (
            revenueToAssignToChypc > (1 << chypcLevel) * 7 / 10 ||
            wealthToAssignToChypc > (1 << chypcLevel)
        ) revert Errors.InvalidTokenAmount();

        // @dev We don't want one person to be able to cancel a share themselves off the bat, so
        //      we prevent the creator from getting >= 90% or <= 10% (the acceptor getting 90%),
        //      in the case of 90% consensus.
        // @dev Due to division by ONE_HUNDRED_PERCENT rounds down, the second condition needs + 1.
        //      For example, totalSupply = 524288, 90%, gives 471859.2 -> 471859 as the required
        //      votes to pass. But 524288*1/10 = 52428.8 -> 52428, so if wealthToAssignToChypc is
        //      52429, then this condition would pass, but 524288-52429 = 471859, which would be
        //      enough to pass a cancel share proposal by the other user, which we want to avoid.
        //      Adding 1 to the second condition addresses this.
        if (wealthToAssignToChypc >= (1<<chypcLevel) * SELECTED_VOTATION_PERCENT/ONE_HUNDRED_PERCENT || 
            wealthToAssignToChypc <= (1<<chypcLevel) * (ONE_HUNDRED_PERCENT-SELECTED_VOTATION_PERCENT)/ONE_HUNDRED_PERCENT + 1) {
            revert Errors.InvalidTokenAmount();

        }

        uint256 shareProposalId = sharesProposalsCounter++;

        Types.ShareProposalData storage shareProposal = _shareProposals[shareProposalId];
  
        // @dev  operatorRevenue: (1 << chypcLevel) * 2 * SIX_DECIMALS / 10,
        //       but is simplified to reduce the contract size. 
        shareProposal.operatorData = Types.HardwareOperatorData({
            operatorRevenue: (1 << chypcLevel) * 200000,
            operatorAssignedString: operatorAssignedString,
            operatorAddress: hardwareOperator
        });

        shareProposal.status = Types.ShareProposalStatus.PENDING;

        shareProposal.chypcData = Types.TokenHolderData({
            tokenNumber: chypcId,
            tokenOwner: _msgSender(),
            tokenLevel: chypcLevel,
            initialRevenueTokens: revenueToAssignToChypc,
            initialWealthTokens: wealthToAssignToChypc
        });

        shareProposal.shareTokenData.revenueDepositDelay = revenueDepositDelay;

        managerData.chypcV2.safeTransferFrom(_msgSender(), address(this), chypcId);

        if (licenseNumber != 0) {
            if (managerData.licenseContract.ownerOf(licenseNumber) != _msgSender()) revert Errors.InvalidLicenseOwner();

            _completeProposal(shareProposalId, licenseNumber);
        }

        emit Events.ShareProposalCreated(shareProposalId);
    }

    /// @notice Allows the owner of the cHyPC to cancel a pending share proposal.
    /// @param shareProposalId the share proposal Id to be cancelled.
    function cancelPendingShareProposal(uint256 shareProposalId) external nonReentrant onlyCHyPCOwner(shareProposalId) {
        if (_shareProposals[shareProposalId].status != Types.ShareProposalStatus.PENDING)
            revert Errors.ShareProposalIsNotPending();

        _endShareProposal(shareProposalId);
    }

    /// @notice Allows the owner of the License to complete a pending share proposal.
    /// @param shareProposalId The share proposal Id to be used to complete the share.
    /// @param licenseNumber The License NFT id to be used to start the share.
    function completeShareProposal(uint256 shareProposalId, uint256 licenseNumber) external nonReentrant onlyLicenseOwner(licenseNumber) {
        if (_shareProposals[shareProposalId].status != Types.ShareProposalStatus.PENDING)
            revert Errors.ShareProposalIsNotPending();

        _completeProposal(shareProposalId, licenseNumber);
    }

    /// @notice Internal function to allow the License NFT owner to complete a pending share proposal.
    /// @param shareProposalId The share proposal Id to be used to complete the share.
    /// @param licenseNumber The License NFT id to be used to start the share.
    function _completeProposal(uint256 shareProposalId, uint256 licenseNumber) private {
        Types.ShareProposalData storage shareProposal = _shareProposals[shareProposalId];

        uint256 licenseLevel = managerData.licenseContract.getLicenseHeight(licenseNumber);
        uint256 totalSupply = 1 << shareProposal.chypcData.tokenLevel;

        if (licenseLevel != shareProposal.chypcData.tokenLevel)
            revert Errors.TokenLevelMismatch();

        shareProposal.status = Types.ShareProposalStatus.STARTED;

        shareProposal.licenseData = Types.TokenHolderData({
            tokenNumber: licenseNumber,
            tokenOwner: _msgSender(),
            tokenLevel: licenseLevel,
            initialRevenueTokens: (totalSupply * 7 / 10) - shareProposal.chypcData.initialRevenueTokens,
            initialWealthTokens: totalSupply - shareProposal.chypcData.initialWealthTokens
        });

        uint256 currentShareNumber = managerData.hypcShareTokens.currentShareNumber();
        shareTokenExists[currentShareNumber] = shareProposalId;

        shareProposal.shareTokenData = Types.ShareTokenData({
            shareTokenNumber: currentShareNumber,
            revenueDepositDelay: shareProposal.shareTokenData.revenueDepositDelay,
            rTokenId: currentShareNumber << 1,
            wTokenId: (currentShareNumber << 1) + 1,
            validEndTimestamp: block.timestamp + 1 days
        });

        managerData.licenseContract.safeTransferFrom(_msgSender(), address(this), licenseNumber);

        managerData.licenseContract.approve(
            address(managerData.hypcShareTokens),
            licenseNumber
        );

        managerData.chypcV2.approve(address(managerData.hypcShareTokens), shareProposal.chypcData.tokenNumber);

        managerData.hypcShareTokens.createShareTokens(
            licenseNumber,
            shareProposal.chypcData.tokenNumber,
            true,
            shareProposal.operatorData.operatorAssignedString,
            shareProposal.shareTokenData.revenueDepositDelay
        );

        _sendRevenueAndWealthTokens(
            shareProposal.licenseData.tokenOwner,
            shareProposal.shareTokenData.rTokenId,
            shareProposal.shareTokenData.wTokenId,
            shareProposal.licenseData.initialRevenueTokens,
            shareProposal.licenseData.initialWealthTokens
        );

        _sendRevenueAndWealthTokens(
            shareProposal.chypcData.tokenOwner,
            shareProposal.shareTokenData.rTokenId,
            shareProposal.shareTokenData.wTokenId,
            shareProposal.chypcData.initialRevenueTokens,
            shareProposal.chypcData.initialWealthTokens
        );

        emit Events.ShareProposalStarted(shareProposalId);
    }

    /// @notice Private function to send the share proposal tokens
    /// @param to address to send tokens
    /// @param rTokenId id of the revenue token
    /// @param wTokenId id of the wealth token
    /// @param rTokenAmount amount of revenue to send
    /// @param wTokenAmount amount of wealth to send
    function _sendRevenueAndWealthTokens(
        address to,
        uint256 rTokenId,
        uint256 wTokenId,
        uint256 rTokenAmount,
        uint256 wTokenAmount
    ) private {
        uint256[] memory amounts = new uint256[](2);
        (amounts[0], amounts[1]) = (rTokenAmount, wTokenAmount);
        uint256[] memory tokenIds = new uint256[](2);
        (tokenIds[0], tokenIds[1]) = (rTokenId, wTokenId);

        managerData.hypcShareTokens.safeBatchTransferFrom(address(this), to, tokenIds, amounts, '');
    }
    
    /// @notice This contract will start the migration to the Share Manager contract
    ///         to be able to migrate the share proposal, it needs to be called by the share owner
    /// @param shareTokenNumber share token number to start migration from Share Tokens contract
    /// @param hardwareOperator address of the hardware operator to be used for the share
    function startShareProposalMigration(
        uint256 shareTokenNumber,
        address hardwareOperator,
        string memory operatorAssignedString
    ) external nonReentrant {
        if (managerData.hypcShareTokens.getShareOwner(shareTokenNumber) != _msgSender())
            revert Errors.InvalidShareTokenOwner();

        if (!managerData.hypcShareTokens.isShareActive(shareTokenNumber)) revert Errors.GetShareDataFailed();

        if (shareTokenExists[shareTokenNumber] > 0) revert Errors.ShareTokenAlreadyExists();

        if (hardwareOperator == address(0)) revert Errors.InvalidProposedAddress();

        (uint256 revenueDepositDelay, bool chypcExists) = _getShareDataRevenueDelayAndCHYPCExists(shareTokenNumber);

        if (revenueDepositDelay > MAX_REVENUE_DELAY) revert Errors.InvalidDepositRevenueDelay();

        if (!chypcExists) revert Errors.ChypcIsNotHeld();

        uint256 shareProposalId = sharesProposalsCounter++;

        _shareProposals[shareProposalId].shareTokenData = Types.ShareTokenData({
            shareTokenNumber: shareTokenNumber,
            revenueDepositDelay: revenueDepositDelay,
            rTokenId: shareTokenNumber << 1,
            wTokenId: (shareTokenNumber << 1) + 1,
            validEndTimestamp: block.timestamp + 1 days
        });

        uint256 chypcId = managerData.hypcShareTokens.getShareCHyPCId(shareTokenNumber);
        uint256 licenseId = managerData.hypcShareTokens.getShareLicenseId(shareTokenNumber);
        uint256 chypcLevel = managerData.chypcV2.getTokenLevel(chypcId);
        uint256 licenseLevel = managerData.licenseContract.getLicenseHeight(licenseId);
        uint256 revenueTokensSupply = managerData.hypcShareTokens.getRevenueTokenTotalSupply(shareTokenNumber);

        if (licenseLevel != chypcLevel)
            revert Errors.TokenLevelMismatch();

        _shareProposals[shareProposalId].chypcData = Types.TokenHolderData({
            tokenNumber: chypcId,
            tokenOwner: _msgSender(),
            tokenLevel: chypcLevel,
            initialRevenueTokens: revenueTokensSupply * 7 / 10,
            initialWealthTokens: revenueTokensSupply
        });

        _shareProposals[shareProposalId].licenseData = Types.TokenHolderData({
            tokenNumber: licenseId,
            tokenOwner: _msgSender(),
            tokenLevel: licenseLevel,
            initialRevenueTokens: 0,
            initialWealthTokens: 0
        });

        // @dev operatorRevenue: revenueTokensSupply * 2 * SIX_DECIMALS / 10,
        //      simlipified to reduce contract size.
        _shareProposals[shareProposalId].operatorData = Types.HardwareOperatorData({
            operatorRevenue: revenueTokensSupply * 200000,
            operatorAssignedString: operatorAssignedString,
            operatorAddress: hardwareOperator
        });

        _shareProposals[shareProposalId].status = Types.ShareProposalStatus.MIGRATING;

        managerData.hypcShareTokens.safeTransferFrom(
            _msgSender(), 
            address(this), 
            _shareProposals[shareProposalId].shareTokenData.rTokenId, 
            revenueTokensSupply * 3 / 10, 
            ''
        );
        shareTokenExists[shareTokenNumber] = shareProposalId;

        emit Events.ShareProposalCreated(shareProposalId);
    }

    // @notice Cancels a pending share migration
    // @param  shareProposalId Id of the proposal migration to cancel.
    function cancelShareTokenMigration(uint256 shareProposalId) external nonReentrant {
        Types.ShareProposalData storage shareProposal = _shareProposals[shareProposalId];

        uint256 shareTokenNumber = shareProposal.shareTokenData.shareTokenNumber;

        if (shareProposal.status != Types.ShareProposalStatus.MIGRATING)
            revert Errors.NotMigratingProposal();
        
        // @dev Note that the chypcDat.tokenOwner is the user that started the migration in this case.
        if (_msgSender() != shareProposal.chypcData.tokenOwner) revert Errors.InvalidCHYPCOwner();

        shareProposal.status = Types.ShareProposalStatus.ENDED;
        if (managerData.hypcShareTokens.getShareOwner(shareTokenNumber) == address(this)) {
            // @dev for the case that the user transferred the ownership of the share, but
            //      decided to cancel it instead of finishing the migration.
            managerData.hypcShareTokens.transferShareOwnership(shareTokenNumber, _msgSender());
        }
        uint256 revenueTokensSupply = managerData.hypcShareTokens.getRevenueTokenTotalSupply(shareTokenNumber);

        managerData.hypcShareTokens.safeTransferFrom(
            address(this),
            _msgSender(),
            _shareProposals[shareProposalId].shareTokenData.rTokenId, 
            revenueTokensSupply * 3 / 10, 
            ''
        );
        shareTokenExists[shareTokenNumber] = 0;

        emit Events.ShareProposalEnded(shareProposalId);
    }

    /// @notice This function will finish the migration to the Share Manager contract
    ///         The owner will be able to finish the migration only if the ownership of the share token
    ///         is changed to this contract, and the share proposal is pending
    /// @param shareProposalId Share proposal id to finish migration
    function finishShareTokenMigration(uint256 shareProposalId) external nonReentrant {
        Types.ShareProposalData storage shareProposal = _shareProposals[shareProposalId];

        uint256 shareTokenNumber = shareProposal.shareTokenData.shareTokenNumber;
       
        if (_shareProposals[shareProposalId].status != Types.ShareProposalStatus.MIGRATING) revert Errors.NotMigratingProposal();

        if (_msgSender() != shareProposal.chypcData.tokenOwner) revert Errors.InvalidShareTokenOwner();

        if (managerData.hypcShareTokens.getShareOwner(shareTokenNumber) != address(this)) 
            revert Errors.InvalidShareTokenOwner();

        managerData.hypcShareTokens.setShareMessage(
            shareTokenNumber,
            shareProposal.operatorData.operatorAssignedString
        );

        managerData.hypcShareTokens.changePendingRevenueDelay(
            shareTokenNumber,
            shareProposal.shareTokenData.revenueDepositDelay
        );        

        _shareProposals[shareProposalId].status = Types.ShareProposalStatus.STARTED;
    }

    /// @notice Private function to get the sharde data from the share token contract, 
    ///         and return the revenue deposit delay and if the share is backed by a cHyPC
    ///         Using the specific slot of the `ShareData` struct to initialize the variables
    /// @param shareNumber share number to get the data from
    /// @return revenueDepositDelay delay in seconds to unlock the revenue deposited
    /// @return chypcExists if the share was backed by a HyPC or using a cHyPC NFT
    function _getShareDataRevenueDelayAndCHYPCExists(uint256 shareNumber) private view returns(uint256 revenueDepositDelay, bool chypcExists) {
        (bool success, bytes memory data) = address(managerData.hypcShareTokens).staticcall(abi.encodeWithSelector(managerData.hypcShareTokens.shareData.selector, shareNumber));
        
        if (!success) revert Errors.GetShareDataFailed();

        assembly {
            revenueDepositDelay := mload(add(data, 0x160))
            chypcExists := mload(add(data, 0x1A0))
        }
    }

    /// @notice Private function that returns the revenue deposited into the given share.
    /// @param  shareNumber to get the data from
    /// @return revenueDeposited total revenue deposited into the share.
    function _getShareDataRevenueDeposited(uint256 shareNumber) private view returns (uint256 revenueDeposited) {
        (bool success, bytes memory data) = address(managerData.hypcShareTokens).staticcall(abi.encodeWithSelector(managerData.hypcShareTokens.shareData.selector, shareNumber));
        
        if (!success) revert Errors.GetShareDataFailed();

        assembly {
            revenueDeposited := mload(add(data, 0x140))
        }
    }

    // @notice Returns the amount of deposited revenuf or this share
    // @param  shareNumber the share tokens number
    // @return The total HyPC deposited into this share
    function getShareDataRevenueDeposited(uint256 shareNumber) external view returns(uint256) {
        return _getShareDataRevenueDeposited(shareNumber);
    }

    /// @notice Allows an user to claim Hypc tokens, based in the amount of wealth tokens available,
    ///         and also claim the surplus HyPC revenue based on their revenue tokens.
    ///         The Share Proposal needs to be ended and the user needs to have wTokens or rTokes.
    /// @param shareProposalId The share proposal Id to be used to claim the Hypc.
    /// @param overridePendingDeposits  Bool for whether or not to ignore pending deposits left in the share.
    //          It is generally advised to not override pending revenue deposits and make sure they are unlocked
    //          and claimed before claiming HyPC and surplus.
    function claimHypcPortionAndSurplus(uint256 shareProposalId, bool overridePendingDeposits) external nonReentrant {
        Types.ShareProposalData storage shareProposal = _shareProposals[shareProposalId];
        if (shareProposal.status != Types.ShareProposalStatus.ENDED || shareCancelled[shareProposalId] != true) {
            revert Errors.ShareProposalIsNotEnded();
        }

        uint256 userWealthTokenBalance = managerData.hypcShareTokens.balanceOf(
            _msgSender(),
            shareProposal.shareTokenData.wTokenId
        );
        uint256 userRevenueTokenBalance = managerData.hypcShareTokens.balanceOf(
            _msgSender(),
            shareProposal.shareTokenData.rTokenId
        );
        uint256 shareTokenNumber = shareProposal.shareTokenData.shareTokenNumber;
        uint256 userVotePower = _votePower[shareProposalId][_msgSender()];

        if ( userRevenueTokenBalance == 0 && userVotePower + userWealthTokenBalance == 0 ) {
            revert Errors.NoWealthOrRevenueTokensAvailable();
        }

        uint256 hypcRefundAmount = 0;

        if ( userRevenueTokenBalance > 0 ) {    
            // @dev Suppose there's 1000 HyPC left after share was ended. This is the shareData.hypcSurplus amount.
            //      hardware operator had 10%, so 20% of the last deposit was held (this is the 1000 HyPC).
            //      This 1000 HyPC needs to be distributed amongst the remaining 70% of rTokens in the wild.
            uint256 revenueDeposited = _getShareDataRevenueDeposited(shareTokenNumber);
            if (overridePendingDeposits == false) {
                if (managerData.hypcShareTokens.getPendingDepositsLength(shareTokenNumber) != 0) {
                    revert Errors.MustUnlockRevenueBeforeClaimingSurplus();
                } 
                if (managerData.hypcShareTokens.lastShareClaimRevenue(shareTokenNumber, _msgSender()) != revenueDeposited) {
                    revert Errors.MustClaimRevenueBeforeClaimingSurplus();
                }
            
                if (managerData.hypcShareTokens.withdrawableAmounts(shareTokenNumber, _msgSender()) != 0 ) {
                    revert Errors.MustWithdrawRevenueBeforeClaimingSurplus();
                }
            }  
           
            uint256 surplusAmount = shareProposal.hypcSurplus;
            uint256 revenueTokenTotalSupply = managerData.hypcShareTokens.getRevenueTokenTotalSupply(shareTokenNumber);
            uint256 totalWildRevenueTokens = revenueTokenTotalSupply * 7 / 10;
            uint256 amountToRefund = surplusAmount * userRevenueTokenBalance / totalWildRevenueTokens;

            managerData.hypcShareTokens.safeTransferFrom(
                _msgSender(),
                address(this),
                shareProposal.shareTokenData.rTokenId,
                userRevenueTokenBalance,
                ''
            );
            hypcRefundAmount += amountToRefund;
        }      

        if ( userWealthTokenBalance + userVotePower > 0 ) {
            uint256 wealthTokenTotalSupply = managerData.hypcShareTokens.getWealthTokenTotalSupply(shareTokenNumber);

            uint256 hypcBacked = (1 << shareProposal.chypcData.tokenLevel ) * SIX_DECIMALS;

            uint256 userTransferAmount = (hypcBacked * (userWealthTokenBalance + userVotePower)) / wealthTokenTotalSupply;

            delete _votePower[shareProposalId][_msgSender()];

            if (userWealthTokenBalance > 0) {
                managerData.hypcShareTokens.safeTransferFrom(
                    _msgSender(),
                    address(this),
                    shareProposal.shareTokenData.wTokenId,
                    userWealthTokenBalance,
                    ''
                );
            }
            
            hypcRefundAmount += userTransferAmount;
        }
        if (hypcRefundAmount > 0) {
            managerData.hypcToken.transfer(
                _msgSender(),
                hypcRefundAmount
            );
            emit Events.HypcClaimed(shareProposalId, hypcRefundAmount);
        }

    }

    /// @notice Private function to end the share proposal
    /// @dev It will send the license only if the proposal was started.
    /// @dev It will send the cHyPC only if the token was transfered
    /// @dev It will send the hardware operator revenue only if proposal started
    /// @param shareProposalId The share proposal Id to be used to end the share.
    function _endShareProposal(uint256 shareProposalId) private {
        Types.ShareProposalData storage shareProposal = _shareProposals[shareProposalId];

        bool shareProposalStarted = shareProposal.status == Types.ShareProposalStatus.STARTED;

        shareProposal.status = Types.ShareProposalStatus.ENDED;

        if (!shareProposalStarted) {
            managerData.chypcV2.safeTransferFrom(
                address(this),
                shareProposal.chypcData.tokenOwner,
                shareProposal.chypcData.tokenNumber
            );
        } else {
            managerData.licenseContract.safeTransferFrom(
                address(this),
                shareProposal.licenseData.tokenOwner,
                shareProposal.licenseData.tokenNumber
            );

            _sendRevenueToHardwareOperator(shareProposalId);
            shareCancelled[shareProposalId] = true;
            managerData.chypcV2.redeem(shareProposal.chypcData.tokenNumber);
        }

        emit Events.ShareProposalEnded(shareProposalId);
    }

    /// @notice Public function for the hardware operator to use to claim their revenue 
    /// @param  shareProposalId The share proposal Id to send out the hardware revenue.
    function sendRevenueToHardwareOperator(uint256 shareProposalId) external nonReentrant isHardwareOperator(shareProposalId) proposalActive(shareProposalId) {
        _sendRevenueToHardwareOperator(shareProposalId);
    }

    /// @notice Private function that will send the revenue collected to the hardware operator
    /// @param shareProposalId The share proposal Id to send out the hardware revenue.
    function _sendRevenueToHardwareOperator(uint256 shareProposalId) private {
        Types.ShareProposalData storage shareProposal = _shareProposals[shareProposalId];

        uint256 oldBalance = managerData.hypcToken.balanceOf(address(this));

        try managerData.hypcShareTokens.claimAndWithdraw(shareProposal.shareTokenData.shareTokenNumber) {
            // ...
        } catch (bytes memory err) {
            if (keccak256(abi.encodeWithSignature('NoRevenueToClaim()')) != keccak256(err)) {
                revert(string(err));
                
            }
        }

        uint256 newBalance = managerData.hypcToken.balanceOf(address(this));
        uint256 amountReceived = newBalance - oldBalance;
        if (amountReceived > 0) {
            uint256 hardwareOperatorRevenue = (amountReceived * shareProposal.operatorData.operatorRevenue*10) / ((1 << shareProposal.chypcData.tokenLevel) * 3000000);// 3 * SIX_DECIMALS
        
            // @dev If the hardware operator revenue is 10%, then the 20% surplus will be divide up amongst the rToken holders.
            //      However, if the share is now cancelled (specifically from the cancel share votation), then we can't deposit the revenue anymore, 
            //      so in that case we hold it in the contract so rToken holders can get their share of the final remaining HyPC in the share.
            uint256 hypcSurplus = amountReceived - hardwareOperatorRevenue;
            if ( shareProposal.status != Types.ShareProposalStatus.ENDED ) {
                managerData.hypcToken.approve(address(managerData.hypcShareTokens), hypcSurplus);
                managerData.hypcShareTokens.depositRevenue(shareProposal.shareTokenData.shareTokenNumber, hypcSurplus);
            } else {
                // @dev Add this to the hypcSurplus, that will be claimed on a per-user basis.
                shareProposal.hypcSurplus += hypcSurplus;
            }

            managerData.hypcToken.transfer(shareProposal.operatorData.operatorAddress, hardwareOperatorRevenue);
        }
    }

    // Propose functions

    /// @notice Allows an user to create a new votation and propose to cancel the share.
    /// @param shareProposalId The share proposal Id to be used to create the votation
    /// @param deadline Time to be waited to complete the votation
    function proposeCancelShare(
        uint256 shareProposalId,
        uint256 deadline
    ) external nonReentrant validVoter(shareProposalId) validProposedDeadline(shareProposalId, deadline) {
        uint256 votationId = _votations[shareProposalId].length;
        _lastVotationCreated[shareProposalId][_msgSender()] = block.timestamp;
        _votations[shareProposalId].push(Types.Votation({
            votesFor: 0,
            votesAgainst: 0,
            deadline: deadline,
            proposedData: '',
            option: Types.VotationOptions.CANCEL_SHARE,
            amountReached: false
        }));
        emit Events.VoteStarted(shareProposalId, votationId, Types.VotationOptions.CANCEL_SHARE);
    }

    /// @notice Allows an user to create a new votation and propose a new Hardware Operator.
    /// @param shareProposalId The share proposal Id to be used to create the votation
    /// @param deadline Time to be waited to complete the votation
    /// @param newProposedString the new proposed assigned string for the hardware operator
    /// @param newHardwareOperator the new hardware operator address
    function proposeNewHardwareOperatorAddress(
        uint256 shareProposalId,
        uint256 deadline,
        string memory newProposedString,
        address newHardwareOperator
    ) external nonReentrant validVoter(shareProposalId) validProposedDeadline(shareProposalId, deadline) {
        if (newHardwareOperator == address(0)) revert Errors.InvalidProposedAddress();

        _lastVotationCreated[shareProposalId][_msgSender()] = block.timestamp;
        uint256 votationId = _votations[shareProposalId].length;

        _votations[shareProposalId].push(Types.Votation({
            votesFor: 0,
            votesAgainst: 0,
            deadline: deadline,
            proposedData: abi.encode(newProposedString, newHardwareOperator),
            option: Types.VotationOptions.CHANGE_HARDWARE_OPERATOR_ADDRESS,
            amountReached: false
        }));

        emit Events.VoteStarted(shareProposalId, votationId, Types.VotationOptions.CHANGE_HARDWARE_OPERATOR_ADDRESS);
    }

    /// @notice Allows an user to create a new votation and propose a new Hardware Operator Revenue.
    /// @param shareProposalId The share proposal Id to be used to create the votation
    /// @param deadline Time to be waited to complete the votation
    /// @param newRevenue the new proposed hardware operator revenue
    /// @dev `newRevenue` should be greater or equal than 1/10 of the W Token total supply times 1,000,000
    /// @dev `newRevenue` should be less or equal than 3/10 of the W Token total supply times 1,000,000
    function proposeNewHardwareOperatorRevenue(
        uint256 shareProposalId,
        uint256 deadline,
        uint256 newRevenue
    ) external nonReentrant validVoter(shareProposalId) validProposedDeadline(shareProposalId, deadline) {
        uint256 revenueTotalSupply = managerData.hypcShareTokens.getRevenueTokenTotalSupply(
            _shareProposals[shareProposalId].shareTokenData.shareTokenNumber
        );
        // @dev revenueTotalSupply * 3 * SIX_DECIMALS / 10  but compressed to lower contract size.
        if ( newRevenue > revenueTotalSupply * 300000 ) {
            revert Errors.InvalidTokenAmount();
        }
        _lastVotationCreated[shareProposalId][_msgSender()] = block.timestamp;

        uint256 votationId = _votations[shareProposalId].length;

        _votations[shareProposalId].push(Types.Votation({
            votesFor: 0,
            votesAgainst: 0,
            deadline: deadline,
            proposedData: abi.encode(newRevenue),
            option: Types.VotationOptions.CHANGE_HARDWARE_OPERATOR_REVENUE,
            amountReached: false
        }));
        emit Events.VoteStarted(shareProposalId, votationId, Types.VotationOptions.CHANGE_HARDWARE_OPERATOR_REVENUE);
    }

    /// @notice Allows an user to create a new votation and propose a new share manager
    /// @param shareProposalId The share proposal Id to be used to create the votation
    /// @param deadline Time to be waited to complete the votation
    /// @param newShareManager The new share manager address
    function proposeNewManager(
        uint256 shareProposalId,
        uint256 deadline,
        address newShareManager
    ) external nonReentrant validVoter(shareProposalId) validProposedDeadline(shareProposalId, deadline) {
        if (
            newShareManager == address(0) ||
            newShareManager == address(this)
        ) revert Errors.InvalidProposedAddress();
        _lastVotationCreated[shareProposalId][_msgSender()] = block.timestamp;

        uint256 votationId = _votations[shareProposalId].length;

        _votations[shareProposalId].push(Types.Votation({
            votesFor: 0,
            votesAgainst: 0,
            deadline: deadline,
            proposedData: abi.encode(newShareManager),
            option: Types.VotationOptions.CHANGE_MANAGER_CONTRACT,
            amountReached: false
        }));

        emit Events.VoteStarted(shareProposalId, votationId, Types.VotationOptions.CHANGE_MANAGER_CONTRACT);
    }

    function proposeNewDepositRevenueDelay(
        uint256 shareProposalId,
        uint256 deadline,
        uint256 newDepositRevenueDelay
    ) external nonReentrant validVoter(shareProposalId) validProposedDeadline(shareProposalId, deadline) {
        if (newDepositRevenueDelay > MAX_REVENUE_DELAY) revert Errors.InvalidDepositRevenueDelay();

        uint256 votationId = _votations[shareProposalId].length;
        _lastVotationCreated[shareProposalId][_msgSender()] = block.timestamp;

        _votations[shareProposalId].push(Types.Votation({
            votesFor: 0,
            votesAgainst: 0,
            deadline: deadline,
            proposedData: abi.encode(newDepositRevenueDelay),
            option: Types.VotationOptions.CHANGE_DEPOSIT_REVENUE_DELAY,
            amountReached: false
        }));

        emit Events.VoteStarted(shareProposalId, votationId, Types.VotationOptions.CHANGE_DEPOSIT_REVENUE_DELAY);
    }

    // Votation functions

    /// @notice Function to execute or finish a votation, only able to vote if user increase the vote power
    /// @param shareProposalId Share Proposal Id to get the votations
    /// @param votationIndex Index of the votation to vote
    /// @param voteFor If true will increase the votes to execute the votation, otherwise will increase the votes to finish it.
    function vote(uint256 shareProposalId, uint256 votationIndex, bool voteFor) external nonReentrant onlyVoter(shareProposalId) validVotation(shareProposalId, votationIndex) {
        Types.Votation storage votation = _votations[shareProposalId][votationIndex];

        if (_shareProposals[shareProposalId].status == Types.ShareProposalStatus.ENDED)
            revert Errors.ShareTokenIsNotActive();

        if (votation.amountReached) revert Errors.VotationAmountReached();

        if (block.timestamp > votation.deadline) revert Errors.VotationDeadlineReached();

        if (_voted[shareProposalId][votationIndex][_msgSender()]) revert Errors.ParticipantAlreadyVote();

        _voted[shareProposalId][votationIndex][_msgSender()] = true;

        if (_votedFreeTime[shareProposalId][_msgSender()] < votation.deadline) {
            _votedFreeTime[shareProposalId][_msgSender()] = votation.deadline;
        }

        uint256 votePower = _votePower[shareProposalId][_msgSender()];

        voteFor ? votation.votesFor += votePower : votation.votesAgainst += votePower;

        uint256 wealthTokenSupply = managerData.hypcShareTokens.getWealthTokenTotalSupply(
            _shareProposals[shareProposalId].shareTokenData.shareTokenNumber
        );

        if (
            votation.option == Types.VotationOptions.CANCEL_SHARE ||
            votation.option == Types.VotationOptions.CHANGE_MANAGER_CONTRACT
        ) {
            if (
                (voteFor ? votation.votesFor : votation.votesAgainst ) >= wealthTokenSupply * SELECTED_VOTATION_PERCENT / ONE_HUNDRED_PERCENT
            ) {
                votation.amountReached = true;
            }
        } else {
            if (
                (voteFor ? votation.votesFor : votation.votesAgainst) > (wealthTokenSupply >> 1) 
            ) {
                votation.amountReached = true;
            }
        }

        if (votation.amountReached) {
            if(voteFor) {
                _executeVotationAction(shareProposalId, votationIndex);
            }
            emit Events.VotationEnded(shareProposalId, votationIndex, voteFor);
        }

        emit Events.VoteEmitted(shareProposalId, _msgSender(), votationIndex, voteFor, votePower);
    }

    /// @notice Increase the caller votation power, transfering the wealth tokens from the user to the contract
    /// @param shareProposalId Id of the Share Proposal to increase the vote power
    function increaseVotePower(uint256 shareProposalId, uint256 amount) external nonReentrant proposalActive(shareProposalId) {
        Types.ShareTokenData storage shareTokenData = _shareProposals[shareProposalId].shareTokenData;
        
        uint256 balance = managerData.hypcShareTokens.balanceOf(_msgSender(), shareTokenData.wTokenId);

        if (amount > balance || balance == 0) revert Errors.NotEnoughWealthTokensAvailable();

        managerData.hypcShareTokens.safeTransferFrom(_msgSender(), address(this), shareTokenData.wTokenId, amount, '');

        _votePower[shareProposalId][_msgSender()] += amount;
    }

    /// @notice Decrease the caller votation power, transfering the wealth tokens from the contract to the user
    /// @param shareProposalId Id of the Share Proposal to decrease the vote power
    function decreaseVotePower(uint256 shareProposalId) external nonReentrant {
        if (_shareProposals[shareProposalId].status != Types.ShareProposalStatus.ENDED && _votations[shareProposalId].length > 0 && _votedFreeTime[shareProposalId][_msgSender()] >= block.timestamp)
            revert Errors.VotePowerLockedUntilDeadline();
        Types.ShareTokenData storage shareTokenData = _shareProposals[shareProposalId].shareTokenData;

        uint256 balance = _votePower[shareProposalId][_msgSender()];

        delete _votePower[shareProposalId][_msgSender()];

        managerData.hypcShareTokens.safeTransferFrom(address(this), _msgSender(), shareTokenData.wTokenId, balance, '');
    }

    // Votation Actions

    /// Private function that will execute the votations actions based on the votation type
    /// @param shareProposalId Id of the Share Proposal to execute the action
    /// @param votationIndex Index of the votation to execute the action
    /// @dev If `votationIndex` is zero the proposal will be cancelled
    function _executeVotationAction(uint256 shareProposalId, uint256 votationIndex) private {
        Types.VotationOptions votationOption = _votations[shareProposalId][votationIndex].option;

        if (votationOption == Types.VotationOptions.CANCEL_SHARE) {
            _cancelShareProposal(shareProposalId);
        }

        if (votationOption == Types.VotationOptions.CHANGE_HARDWARE_OPERATOR_ADDRESS) {
            _changeHardwareOperatorAddress(shareProposalId, votationIndex);
        }

        if (votationOption == Types.VotationOptions.CHANGE_HARDWARE_OPERATOR_REVENUE) {
            _changeHardwareOperatorRevenue(shareProposalId, votationIndex);
        }

        if (votationOption == Types.VotationOptions.CHANGE_MANAGER_CONTRACT) {
            _changeShareManagerContract(shareProposalId, votationIndex);
        }

        if (votationOption == Types.VotationOptions.CHANGE_DEPOSIT_REVENUE_DELAY) {
            _changeDepositRevenueDelay(shareProposalId, votationIndex);
        }
    }

    /// Private function that will execute the cancel action
    /// @param shareProposalId Id of the Share Proposal to be cancelled
    function _cancelShareProposal(uint256 shareProposalId) private {
        if (_shareProposals[shareProposalId].shareTokenData.validEndTimestamp > block.timestamp)
            revert Errors.ShareProposalEndTimeNotReached();

        managerData.hypcShareTokens.cancelShareTokens(_shareProposals[shareProposalId].shareTokenData.shareTokenNumber);

        _endShareProposal(shareProposalId);

        emit Events.VoteActionExecuted(shareProposalId, Types.VotationOptions.CANCEL_SHARE);
    }

    /// Private function that will execute the change hardware operator action
    /// @param shareProposalId Id of the Share Proposal to be changed
    /// @param votationIndex Index of the votation to execute
    function _changeHardwareOperatorAddress(uint256 shareProposalId, uint256 votationIndex) private {

        Types.ShareProposalData storage shareProposal = _shareProposals[shareProposalId];
       
        _sendRevenueToHardwareOperator(shareProposalId);

        (string memory newHardwareOperatorString, address newHardwareOperatorAddress) = abi.decode(
            _votations[shareProposalId][votationIndex].proposedData,
            (string, address)
        );

        shareProposal.operatorData.operatorAddress = newHardwareOperatorAddress;
        shareProposal.operatorData.operatorAssignedString = newHardwareOperatorString;

        managerData.hypcShareTokens.setShareMessage(
            shareProposal.shareTokenData.shareTokenNumber,
            shareProposal.operatorData.operatorAssignedString
        );

        emit Events.VoteActionExecuted(shareProposalId, Types.VotationOptions.CHANGE_HARDWARE_OPERATOR_ADDRESS);
    }

    /// Private function that will execute the change hardware operator revenue action
    /// @param shareProposalId Id of the Share Proposal to be changed
    /// @param votationIndex Index of the votation to execute
    function _changeHardwareOperatorRevenue(uint256 shareProposalId, uint256 votationIndex) private{
        _sendRevenueToHardwareOperator(shareProposalId);

        _shareProposals[shareProposalId].operatorData.operatorRevenue = abi.decode(_votations[shareProposalId][votationIndex].proposedData, (uint256));

        emit Events.VoteActionExecuted(shareProposalId, Types.VotationOptions.CHANGE_HARDWARE_OPERATOR_REVENUE);
    }

    /// Private function that will execute the change share manager action
    /// @param shareProposalId Id of the Share Proposal to be changed
    /// @param votationIndex Index of the votation to execute
    /// @dev The share proposal will be ended afterward
    function _changeShareManagerContract(uint256 shareProposalId, uint256 votationIndex) private {
        Types.ShareProposalData storage shareProposal = _shareProposals[shareProposalId];
        uint256 shareTokenNumber = shareProposal.shareTokenData.shareTokenNumber;

        address newManager = abi.decode(_votations[shareProposalId][votationIndex].proposedData, (address));

        managerData.hypcShareTokens.transferShareOwnership(shareTokenNumber, newManager);

        _sendRevenueToHardwareOperator(shareProposalId);

        shareProposal.status = Types.ShareProposalStatus.ENDED;

        _sendRevenueAndWealthTokens(
            newManager,
            shareProposal.shareTokenData.rTokenId,
            shareProposal.shareTokenData.wTokenId,
            managerData.hypcShareTokens.balanceOf(
                address(this),
                shareProposal.shareTokenData.rTokenId
            ),
            0
        );
        shareTokenExists[shareTokenNumber] = 0;

        emit Events.VoteActionExecuted(shareProposalId, Types.VotationOptions.CHANGE_MANAGER_CONTRACT);
    }

    /// Private function that will execute the change deposit revenue delay
    /// @param shareProposalId Id of the Share Proposal to be changed
    /// @param votationIndex Index of the votation to execute
    function _changeDepositRevenueDelay(uint256 shareProposalId, uint256 votationIndex) private {

        _shareProposals[shareProposalId].shareTokenData.revenueDepositDelay = abi.decode(_votations[shareProposalId][votationIndex].proposedData, (uint256));

        managerData.hypcShareTokens.changePendingRevenueDelay(
            _shareProposals[shareProposalId].shareTokenData.shareTokenNumber,
            _shareProposals[shareProposalId].shareTokenData.revenueDepositDelay
        );

        emit Events.VoteActionExecuted(shareProposalId, Types.VotationOptions.CHANGE_DEPOSIT_REVENUE_DELAY);
    }

    // Get functions

    // ManagerData getters

/*   
    /// @notice Get the setted swap V2 contract
    /// @return Swap V2 contract address
    function getCHYPC() external view returns (address) {
        return address(managerData.chypcV2);
    }

    /// @notice Get the setted License contract
    /// @return License contract address
    function getLicenseContract() external view returns (address) {
        return address(managerData.licenseContract);
    }

    /// @notice Get the setted HyperCycle Share Token contract
    /// @return HyperCycle Share Token contract address
    function getHypcShareTokenContract() external view returns (address) {
        return address(managerData.hypcShareTokens);
    }

    /// @notice Get the setted HyperCycle Token contract
    /// @return HyperCycle ERC 20 token
    function getHypcToken() external view returns (address) {
        return address(managerData.hypcToken);
    }
*/
    /// @notice Get the contract addresses used by this contrat
    /// @return addresses of the cHyPC contract, the License contract, the ShareTokens contract, and the HyPC contract.
    function getContracts() external view returns (address,address,address,address) {
        return (address(managerData.chypcV2), address(managerData.licenseContract), address(managerData.hypcShareTokens), address(managerData.hypcToken));
    }

    // ShareProposalData getters

    /// @notice Get the data of a selected share proposal
    /// @param shareProposalId Id of the Share Proposal
    /// @return Share Proposal Data
    function getShareProposalData(uint256 shareProposalId) external view returns (Types.ShareProposalData memory) {
        return _shareProposals[shareProposalId];
    }
/*
    /// @notice Get the status of a selected share proposal
    /// @param shareProposalId Id of the share proposal
    /// @return Share proposal status
    function getShareProposalStatus(uint256 shareProposalId) external view returns (Types.ShareProposalStatus) {
        return _shareProposals[shareProposalId].status;
    }
    
    /// @notice Get the revenue deposit delay of a selected share proposal
    /// @param shareProposalId Id of the share proposal
    /// @return Revenue deposit delay
    function getRevenueDelay(uint256 shareProposalId) external view returns (uint256) {
        return _shareProposals[shareProposalId].shareTokenData.revenueDepositDelay;
    }

    /// @notice Get the actual Hardware Operator Revenue of a selected share proposal
    /// @param shareProposalId Id of the share proposal
    /// @return Hardware Operator Revenue
    function getShareProposalHardwareOperatorRevenue(uint256 shareProposalId) external view returns (uint256) {
        return _shareProposals[shareProposalId].operatorData.operatorRevenue;
    }

    /// @notice Get the License token id
    /// @param shareProposalId Id of the share proposal
    /// @return License token id
    function getShareProposalLicenseNumber(uint256 shareProposalId) external view returns (uint256) {
        return _shareProposals[shareProposalId].licenseData.tokenNumber;
    }

    /// @notice Get the License Owner
    /// @param shareProposalId Id of the share proposal
    /// @return License Owner
    function getShareProposalLicenseOwner(uint256 shareProposalId) external view returns (address) {
        return _shareProposals[shareProposalId].licenseData.tokenOwner;
    }

    /// @notice Get the License Level
    /// @param shareProposalId Id of the share proposal
    /// @return License level
    function getShareProposalLicenseLevel(uint256 shareProposalId) external view returns (uint256) {
        return _shareProposals[shareProposalId].licenseData.tokenLevel;
    }

    /// @notice Get the cHyPc token id
    /// @param shareProposalId Id of the share proposal
    /// @return cHyPc token id
    function getShareProposalCHYPCNumber(uint256 shareProposalId) external view returns (uint256) {
        return _shareProposals[shareProposalId].chypcData.tokenNumber;
    }

    /// @notice Get the cHyPc owner
    /// @param shareProposalId Id of the share proposal
    /// @return cHyPc owner
    function getShareProposalCHYPCOwner(uint256 shareProposalId) external view returns (address) {
        return _shareProposals[shareProposalId].chypcData.tokenOwner;
    }

    /// @notice Get the cHyPc level
    /// @param shareProposalId Id of the share proposal
    /// @return cHyPc level
    function getShareProposalCHYPCLevel(uint256 shareProposalId) external view returns (uint256) {
        return _shareProposals[shareProposalId].chypcData.tokenLevel;
    }

    /// @notice Get the Hardware Operator address
    /// @param shareProposalId Id of the share proposal
    /// @return Hardware Operator address
    function getShareProposalHardwareOperator(uint256 shareProposalId) external view returns (address) {
        return _shareProposals[shareProposalId].operatorData.operatorAddress;
    }

    /// @notice Get the Hardware Operator address
    /// @param shareProposalId Id of the share proposal
    /// @return the share number for this proposal
    function getShareProposalShareNumber(uint256 shareProposalId) external view returns (uint256) {
        return _shareProposals[shareProposalId].shareTokenData.shareTokenNumber;
    }
*/  

    // Votation getters

    /// @notice Get the amount of votes needed to execute or finish the votation
    /// @return Votes needed 
    function getVotationConsensus(uint256 shareProposalId, Types.VotationOptions votationOption) external view returns (uint256) {
        uint256 totalSupply = managerData.hypcShareTokens.getWealthTokenTotalSupply(
            _shareProposals[shareProposalId].shareTokenData.shareTokenNumber
        );
        if (votationOption == Types.VotationOptions.CANCEL_SHARE || votationOption == Types.VotationOptions.CHANGE_MANAGER_CONTRACT) {
            return totalSupply * SELECTED_VOTATION_PERCENT / ONE_HUNDRED_PERCENT;
        } else {
            return (totalSupply >> 1);
        }
    }

    /// @notice Get the voting stats for this user, including the vote power and votedFreeTime. 
    /// @param shareProposalId Id of the share proposal
    /// @param user address of the voter to check
    /// @return votePower of this user.
    ///         votedFreeTime: the timestamp when this user will be able to decrease their votePower
    function getVoteStats(uint256 shareProposalId, address user) external view returns (uint256, uint256) {
        return (_votePower[shareProposalId][user], _votedFreeTime[shareProposalId][user]);
    }

    /// @notice Get if a selected address has voted in a specific votation
    /// @param shareProposalId Id of the share proposal
    /// @param votationIndex Index of the votation
    /// @param voter address of the voter to check
    /// @return If voter has voted
    function getUserVote(uint256 shareProposalId, uint256 votationIndex, address voter) external view returns (bool) {
        return _voted[shareProposalId][votationIndex][voter];
    }


    /// @notice Get the amount of votations a share proposal has
    /// @param shareProposalId Id of the share proposal
    /// @return Amount of votations
    function getVotationsLength(uint256 shareProposalId) external view returns (uint256) {
        return _votations[shareProposalId].length;
    }

    /// @notice Get the votation data
    /// @param shareProposalId Id of the share proposal
    /// @param votationIndex Index of the votation
    /// @return Votation data
    function getVotationData(
        uint256 shareProposalId,
        uint256 votationIndex
    ) external view validVotation(shareProposalId, votationIndex) returns (Types.Votation memory) {
        return _votations[shareProposalId][votationIndex];
    }
}