// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import "murky/Merkle.sol";

// forked from https://bscscan.com/address/0x17e994b2586f6a6059ba918078c5a3c52d41e03b#code
// this contract is an unified vesting contract for all IDOs.
// this will be deployed once for each chain

// #features
// - vesing contracts for all ido
// - refund supported with deadline
// - sync the list of investors cross chain
// - role based access (ROOT: cricital operation / ADMIN: management operation)

struct VestingProject {
    uint256 id;
    string name;
    /**
     * if `false`, user won't be able to claim or request refund
     */
    bool active;
    uint256 investors;
    bytes32 merkleProofRoot;
    // claim params
    uint256 tgeAt;
    uint256 tgeAmount;
    uint256 cliffDuration;
    uint256 vestingDuration;
    uint256 vestingAmount;
    address tokenAddr;
    uint256 tokenDeposited;
    uint256 tokenRemains;
    uint8 tokenDecimals;
    // refund params
    uint256 refundInvestors;
    uint256 refundDeadlineAt;
    address refundTokenAddr;
    uint256 refundAmount;
    uint8 refundTokenDecimals;
    uint256 refundTokenDeposited;
    uint256 refundTokenRemains;
}

contract ApeVestingUnified is
    Pausable,
    AccessControlEnumerable,
    AxelarExecutable,
    ReentrancyGuard
{
    using Address for address;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    bytes32 public constant ROOT_ROLE = keccak256("ROOT_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // fix AVU-02S
    Merkle private mTree = new Merkle();
    // fix AVU-03S
    uint256 public projectIdCounter;
    IAxelarGasService public immutable gasService;
    // mpr = Merkle Proof Root
    EnumerableSet.Bytes32Set private s_trustedMprSource;
    mapping(uint256 => VestingProject) public s_project;
    mapping(uint256 projectId => mapping(address account => uint256 timestamp)) public s_refundRequestedAt;
    mapping(uint256 projectId => mapping(address account => uint256 timestamp)) public s_refundedAt;
    mapping(uint256 projectId => mapping(address account => uint256 amount)) public s_claimedAmount;
    mapping(uint256 projectId => bytes32[] accountList) public s_refundAccountList;

    constructor(
        address _gateway,
        address _gasReceiver
    ) AxelarExecutable(_gateway) {
        // fix AVU-01S
        assert(_gateway != address(0) && _gasReceiver != address(0));
        _grantRole(ROOT_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ROOT_ROLE, ROOT_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ROOT_ROLE);
        gasService = IAxelarGasService(_gasReceiver);
    }

    // REGION: events

    event MerkleProofRootSet(uint256 indexed projectId, uint256 investors, bytes32 merkleRoot);
    event ProjectAdded(
        uint256 indexed projectId,
        string _name,
        uint256 _tgeAt,
        uint256 _tgeAmount,
        uint256 _cliffDuration,
        uint256 _vestingDuration,
        uint256 _vestingAmount,
        address _tokenAddr
    );
    event ProjectRefundParamsUpdated(
        uint256 indexed projectId,
        address refundTokenAddr,
        uint256 refundAmount,
        uint256 refundDeadlineAt,
        uint256 refundTokenDecimals
    );
    event TrustedMprSourceAdded(
        string sourceChain,
        string sourceAddress,
        bytes32 sourceId
    );
    event TrustedMprSourceRemoved(
        string sourceChain,
        string sourceAddress,
        bytes32 sourceId
    );
    event ProjectActiveStatusChanged(uint256 indexed projectId, bool activeStatus);
    event Claimed(
        uint256 indexed projectId,
        address indexed account,
        uint256 amount
    );
    event RefundRequested(uint256 indexed projectId, address indexed account);
    event Refunded(uint256 indexed projectId, address indexed account);
    event ProjectTokenDeposited(uint256 indexed projectId, uint256 amount, address funder);
    event ProjectRefundTokenDeposited(uint256 indexed projectId, uint256 amount, address funder);
    event UnusedTokenWithdrew(address indexed tokenAddr, uint256 amount, address receiver);
    event OrphanTokenWithdrew(uint256 projectId, address tokenAddr, uint256 amount, address receiver);

    // REGION: modifiers

    modifier whenProjectExist(uint256 projectId_) {
        require(s_project[projectId_].tokenAddr != address(0), "The Project does not exist");
        _;
    }

    modifier whenProjectActive(uint256 projectId_) {
        VestingProject memory sVProject = s_project[projectId_];
        require(sVProject.tokenAddr != address(0) && sVProject.active, "The Project does not active");
        _;
    }

    // REGION: internal functions

    function _setProjectMerkleRoot(
        uint256 projectId_,
        uint256 investors_,
        bytes32 merkleRoot_
    ) internal whenProjectExist(projectId_) {
        VestingProject storage sVProject = s_project[projectId_];
        require(sVProject.merkleProofRoot == bytes32(0), "Merkle proof root has been set");
        sVProject.investors = investors_;
        sVProject.merkleProofRoot = merkleRoot_;
        emit MerkleProofRootSet(projectId_, investors_, merkleRoot_);
    }

    // REGION: admin functions

    function addTrustedMprSource(
        string memory _sourceChain,
        string memory _sourceAddress
    ) public onlyRole(ROOT_ROLE) {
        bytes32 sourceId = keccak256(abi.encode(_sourceChain, _sourceAddress));
        if(!s_trustedMprSource.contains(sourceId)) {
            s_trustedMprSource.add(sourceId);
            emit TrustedMprSourceAdded(_sourceChain, _sourceAddress, sourceId);
        }
    }

    function removeTrustedMprSource(
        string memory _sourceChain,
        string memory _sourceAddress
    ) public onlyRole(ROOT_ROLE) {
        bytes32 sourceId = keccak256(abi.encode(_sourceChain, _sourceAddress));
        if(s_trustedMprSource.contains(sourceId)) {
            s_trustedMprSource.remove(sourceId);
            emit TrustedMprSourceRemoved(_sourceChain, _sourceAddress, sourceId);
        }
    }

    function removeTrustedMprSource(
        bytes32 _sourceId
    ) public onlyRole(ROOT_ROLE) {
        if(s_trustedMprSource.contains(_sourceId)) {
            s_trustedMprSource.remove(_sourceId);
            emit TrustedMprSourceRemoved("", "", _sourceId);
        }
    }

    function pause() public onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * manually set Merkle Proof Root in case autosync via Axelar does not work
     */
    function setProjectMerkleRoot(
        uint256 projectId_,
        uint256 investors_,
        bytes32 merkleRoot_
    ) external onlyRole(ROOT_ROLE) {
        _setProjectMerkleRoot(projectId_, investors_, merkleRoot_);
    }

    /**
     * Set up new Project
     * - The vesting token must be already debut-ed
     * - Refund are not enabled by default
     * @param _tgeAt - the TGE date
     * @param _tgeAmount - the amount unlock at TGE date
     * @param _cliffDuration - the duration after TGE when no token will be unlocked
     * @param _vestingDuration - the duration that `vestingAmount` will be unlocked linearly 
     * @param _vestingAmount - 
     * @param _tokenAddr - the project's token
     */
    function addProject(
        string calldata _name,
        uint256 _tgeAt,
        uint256 _tgeAmount,
        uint256 _cliffDuration,
        uint256 _vestingDuration,
        uint256 _vestingAmount,
        address _tokenAddr
    ) public onlyRole(ADMIN_ROLE) returns (uint256 projectId) {
        // prevent adding unix time in milliseconds
        require(_tgeAt < 100_000_000_000, "5138-11-16T09:46:40.000Z");
        require(_vestingDuration > 0, "Assert: _vestingDuration > 0");
        require(_tokenAddr != address(0), "Assert: _tokenAddr != null");
        uint8 tokenDecimals = IERC20Metadata(_tokenAddr).decimals();
        require(tokenDecimals > 0, "Assert: tokenDecimals > 0");
        projectId = projectIdCounter++;
        s_project[projectId] = VestingProject({
            id: projectId,
            name: _name,
            active: true,
            investors: 0,
            tgeAt: _tgeAt,
            tgeAmount: _tgeAmount,
            cliffDuration: _cliffDuration,
            vestingDuration: _vestingDuration,
            vestingAmount: _vestingAmount,
            tokenAddr: _tokenAddr,
            tokenDeposited: 0,
            tokenRemains: 0,
            merkleProofRoot: bytes32(0),
            refundInvestors: 0,
            refundDeadlineAt: 0,
            refundTokenAddr: address(0),
            refundAmount: 0,
            tokenDecimals: tokenDecimals,
            refundTokenDecimals: 0,
            refundTokenDeposited: 0,
            refundTokenRemains: 0
        });
        emit ProjectAdded(
            projectId,
            _name,
            _tgeAt,
            _tgeAmount,
            _cliffDuration,
            _vestingDuration,
            _vestingAmount,
            _tokenAddr
        );
        return projectId;
    }

    function setProjectActiveStatus(uint256 projectId_, bool status_) public whenProjectExist(projectId_) onlyRole(ADMIN_ROLE) {
        s_project[projectId_].active = status_;
        emit ProjectActiveStatusChanged(projectId_, status_);
    }

    function setRefundParams(
        uint256 projectId_,
        address refundTokenAddr_,
        uint256 refundAmount_,
        uint256 refundDeadlineAt_
    ) public whenProjectExist(projectId_) onlyRole(ADMIN_ROLE) {
        VestingProject storage sVProject = s_project[projectId_];
        require(sVProject.refundTokenAddr == address(0), "Refund params has been set");
        uint8 refundTokenDecimals = IERC20Metadata(refundTokenAddr_).decimals();
        require(refundTokenDecimals > 0, "Assert: refundTokenDecimals > 0");
        require(refundAmount_ > 0, "Assert: refundAmount_ > 0");
        require(refundDeadlineAt_ > 0, "Assert: refundDeadlineAt_ > 0");
        require(refundTokenAddr_ != sVProject.tokenAddr, "Assert: refundTokenAddr != tokenAddr");
        sVProject.refundAmount = refundAmount_;
        sVProject.refundDeadlineAt = refundDeadlineAt_;
        sVProject.refundTokenAddr = refundTokenAddr_;
        sVProject.refundTokenDecimals = refundTokenDecimals;
        emit ProjectRefundParamsUpdated(
            projectId_,
            refundTokenAddr_,
            refundAmount_,
            refundDeadlineAt_,
            refundTokenDecimals
        );
    }

    /**
     * Allow ROOT user to withdraw the fund that has been sent to this contract by mistake
     * This function will fail if the number of projects is a big number like 5k
     */
    function withdrawUnusedToken(address tokenAddr_) external onlyRole(ROOT_ROLE) returns (uint256) {
        require(tokenAddr_ != address(0), "Assert: tokenAddr_ != null");
        uint256 unusedBalance = IERC20(tokenAddr_).balanceOf(address(this));
        // fix AVU-01C
        uint256 cachedProjectIdCounter = projectIdCounter;
        for(uint256 i=0; i<cachedProjectIdCounter; i++) {
            if(s_project[i].tokenAddr == tokenAddr_) {
                unusedBalance -= s_project[i].tokenRemains;
                continue;
            }
            if(s_project[i].refundTokenAddr == tokenAddr_) {
                unusedBalance -= s_project[i].refundTokenRemains;
            }
        }
        require(unusedBalance > 0, "Assert: unusedBalance > 0");
        IERC20(tokenAddr_).safeTransfer(
            msg.sender,
            unusedBalance
        );
        emit UnusedTokenWithdrew(tokenAddr_, unusedBalance, msg.sender);
        return unusedBalance;
    }

    /**
     * Allow ROOT user to withdraw the amount of token that is orphan
     */
    function withdrawOrphanToken(uint256 projectId_) external onlyRole(ROOT_ROLE) whenProjectExist(projectId_) returns(uint256) {
        VestingProject storage sVProject = s_project[projectId_];
        uint256 tgeAmount = sVProject.tgeAmount;
        uint256 vestingAmount = sVProject.vestingAmount;
        address tokenAddr = sVProject.tokenAddr;
        uint256 tokenDeposited = sVProject.tokenDeposited;
        uint256 refundDeadlineAt = sVProject.refundDeadlineAt;
        require(block.timestamp >= refundDeadlineAt, "Assert: block.timestamp >= refundDeadlineAt");
        uint256 investors = sVProject.investors;
        uint256 refundInvestors = sVProject.refundInvestors;
        require(refundInvestors > 0, "Assert: refundInvestors > 0");
        // orphan fund has been collected before
        require(tokenDeposited == investors * (tgeAmount + vestingAmount), "Assert: !orphanAmount");
        uint256 orphanAmount = refundInvestors * (tgeAmount + vestingAmount);
        sVProject.tokenRemains -= orphanAmount;
        sVProject.tokenDeposited -= orphanAmount;
        IERC20(tokenAddr).safeTransfer(
            msg.sender,
            orphanAmount
        );
        emit OrphanTokenWithdrew(projectId_, tokenAddr, orphanAmount, msg.sender);
        return orphanAmount;
    }

    function syncRefundRootCrossChain(
        uint256 vestingProjectId,
        uint256 refundProjectId,
        string calldata refundChain,
        string calldata refundAddress
    ) external payable onlyRole(ADMIN_ROLE) {
        bytes32 refundProofRoot = getRefundProofRoot(vestingProjectId);
        require(msg.value > 0, "Gas payment is required");
        VestingProject storage sVProject = s_project[vestingProjectId];
        bytes memory payload = abi.encode(
            refundProjectId,
            sVProject.refundInvestors,
            refundProofRoot
        );
        gasService.payNativeGasForContractCall{value: msg.value}(
            address(this),
            refundChain,
            refundAddress,
            payload,
            msg.sender
        );
        gateway.callContract(refundChain, refundAddress, payload);
    }

    // REGION: public view functions

    function getTrustedMprSources() public view returns (bytes32[] memory) {
        return s_trustedMprSource.values();
    }

    function isTrustedMprSource(bytes32 sourceId_) public view returns (bool) {
        return s_trustedMprSource.contains(sourceId_);
    }

    function getProject(uint256 projectId) public view returns (VestingProject memory) {
        return s_project[projectId];
    }

    /**
     * Return the stats for the account at specific project.
     * This function assume account has a valid investment proof
     */
    function getAccountStatsAt(
        uint256 projectId,
        address account
    )
        public
        view
        returns (
            uint256 refundRequestedAt,
            uint256 refundedAt,
            uint256 claimedAmount,
            uint256 claimableAmount
        )
    {
        refundRequestedAt = s_refundRequestedAt[projectId][account];
        refundedAt = s_refundedAt[projectId][account];
        claimedAmount = s_claimedAmount[projectId][account];
        uint256 tgeAt = s_project[projectId].tgeAt;
        uint256 tgeAmount = s_project[projectId].tgeAmount;
        uint256 vestingAmount = s_project[projectId].vestingAmount;
        uint256 cliffDuration = s_project[projectId].cliffDuration;
        uint256 vestingDuration = s_project[projectId].vestingDuration;
        if (block.timestamp < tgeAt) {
            claimableAmount = 0;
        } else {
            if (block.timestamp <= tgeAt + cliffDuration) {
                claimableAmount = tgeAmount - claimedAmount;
            } else {
                uint256 totalAmount = tgeAmount +
                    ((vestingAmount *
                        (block.timestamp - (tgeAt + cliffDuration))) /
                        vestingDuration);
                // fix AVU-05C
                if (totalAmount > vestingAmount + tgeAmount) {
                    totalAmount = vestingAmount + tgeAmount;
                }
                claimableAmount = totalAmount - claimedAmount;
            }
        }
        return (
            refundRequestedAt,
            // fix AVU-06C
            refundedAt,
            claimedAmount,
            claimableAmount
        );
    }

    // REGION: public write functions

    /**
     * called crosschain by Axelar
     */
    function _execute(
        string calldata _sourceChain,
        string calldata _sourceAddress,
        bytes calldata _payload
    ) internal virtual override {
        bytes32 sourceId = keccak256(abi.encode(_sourceChain, _sourceAddress));
        require(s_trustedMprSource.contains(sourceId), "Untrusted mpr source");
        (uint256 projectId, uint256 investors, bytes32 merkleRoot) = abi.decode(
            _payload,
            (uint256, uint256, bytes32)
        );
        _setProjectMerkleRoot(projectId, investors, merkleRoot);
    }

    /**
     * allow user to request a refund if they has not claimed yet
     */
    // 23Nov'24 removed `nonReentrant` since it is has no effect
    // 23Nov'24 removed `whenProjectActive(projectId_)` and `whenNotPaused` since it is make sense
    function requestRefund(
        uint256 projectId_,
        bytes32[] memory proof
    ) external {
        address sender = msg.sender;
        VestingProject storage sVProject = s_project[projectId_];
        bytes32 merkleProofRoot = sVProject.merkleProofRoot;
        address refundTokenAddr = sVProject.refundTokenAddr;
        require(
            merkleProofRoot != bytes32(0),
            "Merkle proof root has not been set"
        );
        require(
            refundTokenAddr != address(0),
            "Refund params has not been set"
        );
        require(
            block.timestamp < sVProject.refundDeadlineAt,
            "Refund deadline has passed"
        );
        require(
            s_refundRequestedAt[projectId_][sender] == 0,
            "Refund requested"
        );
        require(
            s_claimedAmount[projectId_][sender] == 0,
            "Not eligible for a refund (claimed)"
        );
        require(
            mTree.verifyProof(
                merkleProofRoot,
                proof,
                bytes32(abi.encode(sender))
            ),
            "Mismatch investment proof"
        );
        s_refundRequestedAt[projectId_][sender] = block.timestamp;
        sVProject.refundInvestors += 1;
        s_refundAccountList[projectId_].push(
            bytes32(abi.encode(sender))
        );
        emit RefundRequested(projectId_, sender);
    }

    function claimToken(
        uint256 projectId_,
        bytes32[] calldata proof_
    ) external whenNotPaused nonReentrant whenProjectActive(projectId_) {
        address sender = msg.sender;
        VestingProject storage sVProject = s_project[projectId_];
        bytes32 merkleProofRoot = sVProject.merkleProofRoot;
        require(
            merkleProofRoot != bytes32(0),
            "Merkle proof root has not been set"
        );
        require(
            mTree.verifyProof(
                merkleProofRoot,
                proof_,
                bytes32(abi.encode(sender))
            ),
            "Mismatch investment proof"
        );
        require(
            s_refundRequestedAt[projectId_][sender] == 0,
            "Not eligible for a claim (refund requested)"
        );
        (, , , uint256 claimableAmount) = getAccountStatsAt(projectId_, sender);
        require(claimableAmount > 0, "No claimable tokens");
        s_claimedAmount[projectId_][sender] += claimableAmount;
        sVProject.tokenRemains -= claimableAmount;
        IERC20(sVProject.tokenAddr).safeTransfer(
            sender,
            claimableAmount
        );
        emit Claimed(projectId_, sender, claimableAmount);
    }

    function claimRefundToken(
        uint256 projectId_
    ) public whenNotPaused nonReentrant whenProjectActive(projectId_) {
        address sender = msg.sender;
        VestingProject storage sVProject = s_project[projectId_];
        uint256 refundAmount = sVProject.refundAmount;
        address refundTokenAddr = sVProject.refundTokenAddr;
        require(
            block.timestamp >= sVProject.refundDeadlineAt,
            "Refund deadline has not passed"
        );
        require(
            s_refundRequestedAt[projectId_][sender] != 0,
            "Not eligible for a refund (unrequested)"
        );
        require(
            s_refundedAt[projectId_][sender] == 0,
            "Not eligible for a refund (refunded)"
        );
        s_refundedAt[projectId_][sender] = block.timestamp;
        sVProject.refundTokenRemains -= refundAmount;
        IERC20(refundTokenAddr).safeTransfer(
            sender,
            refundAmount
        );
        emit Refunded(
            projectId_,
            sender
        );
    }

    /**
     * allow anyone to deposit the project's token
     */
    function depositProjectToken(uint256 projectId_) public virtual whenProjectExist(projectId_) {
        VestingProject storage sVProject = s_project[projectId_];
        uint256 investors = sVProject.investors;
        uint256 tgeAmount = sVProject.tgeAmount;
        uint256 vestingAmount = sVProject.vestingAmount;
        address tokenAddr = sVProject.tokenAddr;
        require(sVProject.tokenDeposited == 0, "Assert: tokenDeposited = 0");
        // this also mean the merkle proof root has been set
        require(investors > 0, "Assert: investors > 0");
        uint256 depositAmount = (tgeAmount + vestingAmount) * investors;
        sVProject.tokenDeposited = depositAmount;
        sVProject.tokenRemains = depositAmount;
        IERC20(tokenAddr).safeTransferFrom(
            msg.sender,
            address(this),
            depositAmount
        );
        emit ProjectTokenDeposited(projectId_, depositAmount, msg.sender);
    }

    /**
     * allow anyone to deposit the project's refund token after the refund deadline
     */
    function depositProjectRefundToken(uint256 projectId_) public whenProjectExist(projectId_) {
        VestingProject storage sVProject = s_project[projectId_];
        uint256 refundInvestors = sVProject.refundInvestors;
        uint256 refundAmount = sVProject.refundAmount;
        address refundTokenAddr = sVProject.refundTokenAddr;
        require(sVProject.refundTokenDeposited == 0, "Assert: refundTokenDeposited = 0");
        uint256 refundDeadlineAt = sVProject.refundDeadlineAt;
        require(block.timestamp >= refundDeadlineAt, "Refund deadline has not passed");
        // this also mean the merkle proof root has been set
        require(refundInvestors > 0, "Assert: refundInvestors > 0");
        uint256 depositAmount = refundAmount * refundInvestors;
        sVProject.refundTokenDeposited = depositAmount;
        sVProject.refundTokenRemains = depositAmount;
        IERC20(refundTokenAddr).safeTransferFrom(
            msg.sender,
            address(this),
            depositAmount
        );
        emit ProjectRefundTokenDeposited(projectId_, depositAmount, msg.sender);
    }

    function getRefundProofRoot(uint256 projectId_) public view returns(bytes32) {
        VestingProject storage sVProject = s_project[projectId_];
        require(sVProject.refundDeadlineAt > 0 && block.timestamp >= sVProject.refundDeadlineAt, "Refund deadline has not passed");
        return mTree.getRoot(s_refundAccountList[projectId_]);
    }

    function getRefundIndex(uint256 projectId_, address account_) public view returns(uint256) {
        uint256 length = s_refundAccountList[projectId_].length;
        bytes32 accountB32 = bytes32(abi.encode(account_));
        for(uint256 i=0; i<length; i++) {
            if(s_refundAccountList[projectId_][i] == accountB32) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function getRefundProof(uint256 projectId_, uint256 index_) external view returns(bytes32[] memory) {
        return mTree.getProof(s_refundAccountList[projectId_], index_);
    }

    function getRefundProof(uint256 projectId_, address account_) external view returns(bytes32[] memory) {
        uint256 refundIndex = getRefundIndex(projectId_, account_);
        return mTree.getProof(s_refundAccountList[projectId_], refundIndex);
    }

}