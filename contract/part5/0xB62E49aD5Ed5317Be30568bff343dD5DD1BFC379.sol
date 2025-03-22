// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "./DN404Mirror.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "contract-allow-list/contracts/proxy/interface/IContractAllowListProxy.sol";

/**
 * @title ExtendedDN404Mirror
 * @dev Extends DN404Mirror with ERC721C capabilities and maintains CAL functionality
 */
contract MUTANT_ALIENS_VILLAIN is
    DN404Mirror,
    AccessControl,
    ERC2981,
    ReentrancyGuard
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using ECDSA for bytes32;

    // === Constants and Interfaces ===
    bytes32 public constant NFT_SECURITY_NAMESPACE = keccak256("NFT_SECURITY");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes4 private constant _SEAPORT_HOOK_INTERFACE = 0x9059e6c3;
    bytes4 private constant INTERFACE_ID_ERC721C = 0x3f4ce757;
    bytes4 private constant INTERFACE_ID_CONTRACT_LEVEL = 0xa40eb359;

    uint96 private defaultRoyaltyRate;
    uint96 private constant MAX_ROYALTY_RATE = 1000; // 10%

    // === State Variables ===
    IContractAllowListProxy public CAL;
    EnumerableSet.AddressSet private localAllowedAddresses;

    // New NFT Security Enum
    enum NFTSecurityLevel {
        NONE, // No restrictions
        CAL_ONLY, // Only CAL restrictions
        FULL // Full restrictions (CAL + Additional)
    }

    // State Variables
    NFTSecurityLevel public defaultNFTSecurityLevel = NFTSecurityLevel.FULL;
    bool public enableRestrict = true;
    uint256 public CALLevel = 2;
    bool public contractLocked = false;

    // Mappings
    mapping(uint256 => bool) public tokenLocked;
    mapping(address => bool) public walletLocked;
    mapping(uint256 => NFTSecurityLevel) public tokenSecurityLevels;
    mapping(uint256 => uint256) public tokenCALLevel;
    mapping(address => uint256) public walletCALLevel;

    // Events
    event SecurityLevelUpdated(NFTSecurityLevel level);
    event TokenSecurityLevelChanged(
        uint256 indexed tokenId,
        NFTSecurityLevel level
    );
    event RoyaltyPaid(
        address indexed tokenContract,
        uint256 indexed tokenId,
        address indexed royaltyReceiver,
        address seller,
        address buyer,
        uint256 amount
    );
    event MarketplaceApproved(
        address indexed marketplace,
        bool approved,
        uint256 fee
    );
    event TokenMarketplaceSet(
        uint256 indexed tokenId,
        address indexed marketplace
    );
    event OwnershipSynced(address indexed oldOwner, address indexed newOwner);
    event RoyaltyEnforced(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    );
    event CreatorEarningsConfigured(address receiver, uint96 feeNumerator);
    event ApprovalAttempt(
        address indexed owner,
        address indexed spender,
        uint256 indexed tokenId,
        bool success,
        string reason
    );
    event SetApprovalForAllAttempt(
        address indexed owner,
        address indexed operator,
        bool approved,
        bool success,
        string reason
    );
    event TransferAttempt(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId,
        bool success,
        string reason
    );
    event SafeTransferAttempt(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId,
        bytes data,
        bool success,
        string reason
    );
    event LocalCalAdded(address indexed operator, address indexed transferer);
    event LocalCalRemoved(address indexed operator, address indexed transferer);

    event ContractLevelUpdated(uint256 newLevel);
    event TokenLevelUpdated(uint256 indexed tokenId, uint256 newLevel);

    // === Constructor ===
    constructor(
        address deployer,
        address _cal,
        address defaultRoyaltyReceiver
    ) DN404Mirror(deployer) {
        console.log("Deploying ExtendedDN404Mirror with deployer:", deployer);
        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(ADMIN_ROLE, deployer);
        _grantRole(MINTER_ROLE, deployer);

        defaultNFTSecurityLevel = NFTSecurityLevel.FULL;

        defaultRoyaltyRate = 1000; // 10%
        _setDefaultRoyalty(defaultRoyaltyReceiver, defaultRoyaltyRate);
        CAL = IContractAllowListProxy(_cal);

        enableRestrict = true;
    }

    // === Lock Management ===
    function lockContract() external onlyRole(ADMIN_ROLE) {
        contractLocked = true;
    }

    function unlockContract() external onlyRole(ADMIN_ROLE) {
        contractLocked = false;
    }

    function lockWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        walletLocked[wallet] = true;
    }

    function unlockWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        walletLocked[wallet] = false;
    }

    function lockToken(uint256 tokenId) external onlyRole(ADMIN_ROLE) {
        tokenLocked[tokenId] = true;
    }

    function unlockToken(uint256 tokenId) external onlyRole(ADMIN_ROLE) {
        tokenLocked[tokenId] = false;
    }

    function isLocked(
        address wallet,
        uint256 tokenId
    ) public view returns (bool) {
        return contractLocked || walletLocked[wallet] || tokenLocked[tokenId];
    }

    // === CAL Management ===
    function setCAL(address _cal) external onlyRole(ADMIN_ROLE) {
        CAL = IContractAllowListProxy(_cal);
    }

    function setCALLevel(uint256 level) external onlyRole(ADMIN_ROLE) {
        require(level <= 2, "Invalid level");
        CALLevel = level;
    }

    function addLocalContractAllowList(
        address transferer
    ) external onlyRole(ADMIN_ROLE) {
        localAllowedAddresses.add(transferer);
        emit LocalCalAdded(msg.sender, transferer);
    }

    function removeLocalContractAllowList(
        address transferer
    ) external onlyRole(ADMIN_ROLE) {
        localAllowedAddresses.remove(transferer);
        emit LocalCalRemoved(msg.sender, transferer);
    }

    function getLocalContractAllowList()
        external
        view
        returns (address[] memory)
    {
        return localAllowedAddresses.values();
    }

    function setTokenCALLevel(
        uint256 tokenId,
        uint256 level
    ) external onlyRole(ADMIN_ROLE) {
        require(level <= 2, "Invalid level");
        tokenCALLevel[tokenId] = level;
        emit TokenSecurityLevelChanged(
            tokenId,
            level == 0 ? NFTSecurityLevel.NONE : NFTSecurityLevel.CAL_ONLY
        );
    }

    function setWalletCALLevel(uint256 level) external onlyRole(ADMIN_ROLE) {
        walletCALLevel[msg.sender] = level;
    }

    function _getCALLevel(
        address holder,
        uint256 tokenId
    ) internal view returns (uint256) {
        if (tokenCALLevel[tokenId] > 0) {
            return tokenCALLevel[tokenId];
        }
        if (walletCALLevel[holder] > 0) {
            return walletCALLevel[holder];
        }
        return CALLevel;
    }

    function setDefaultSecurityLevel(
        NFTSecurityLevel newLevel
    ) external onlyRole(ADMIN_ROLE) {
        require(
            newLevel == NFTSecurityLevel.FULL ||
                newLevel == NFTSecurityLevel.NONE ||
                newLevel == NFTSecurityLevel.CAL_ONLY,
            "Invalid security level"
        );
        defaultNFTSecurityLevel = newLevel;
        emit SecurityLevelUpdated(newLevel);
    }

    function setTokenSecurityLevel(
        uint256 tokenId,
        NFTSecurityLevel level
    ) external onlyRole(ADMIN_ROLE) {
        require(
            ownerOf(tokenId) == msg.sender || hasRole(ADMIN_ROLE, msg.sender),
            "Not authorized"
        );
        tokenSecurityLevels[tokenId] = level;
        emit TokenSecurityLevelChanged(tokenId, level);
    }

    function setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) public onlyRole(ADMIN_ROLE) {
        require(receiver != address(0), "Invalid royalty receiver");
        require(
            feeNumerator <= MAX_ROYALTY_RATE,
            "Royalty rate exceeds maximum"
        );
        defaultRoyaltyRate = feeNumerator;
        _setDefaultRoyalty(receiver, feeNumerator);
        emit CreatorEarningsConfigured(receiver, feeNumerator);
    }

    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) public onlyRole(ADMIN_ROLE) {
        require(receiver != address(0), "Invalid royalty receiver");
        require(
            feeNumerator <= MAX_ROYALTY_RATE,
            "Royalty rate exceeds maximum"
        );
        defaultRoyaltyRate = feeNumerator;
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
        emit RoyaltyEnforced(tokenId, receiver, feeNumerator);
    }

    function getDefaultRoyaltyRate() external view returns (uint96) {
        return defaultRoyaltyRate;
    }

    function getTokenRoyaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    ) external view returns (address receiver, uint256 royaltyAmount) {
        return royaltyInfo(tokenId, salePrice);
    }

    // === Allow List Checks ===
    function _isAllowed(
        address operator,
        address tokenOwner
    ) internal view returns (bool) {
        if (!enableRestrict) return true;
        if (operator == tokenOwner) return true;
        uint256 level = _getCALLevel(tokenOwner, 0);
        return
            localAllowedAddresses.contains(operator) ||
            CAL.isAllowed(operator, level);
    }

    function checkIsAllowed(
        address operator,
        address tokenOwner
    ) public view returns (bool) {
        return _isAllowed(operator, tokenOwner);
    }

    // === Transfer Management ===
    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override {
        require(_isAllowed(operator, msg.sender), "Operator not allowed");
        super.setApprovalForAll(operator, approved);
        emit SetApprovalForAllAttempt(msg.sender, operator, approved, true, "");
    }

    function approve(
        address spender,
        uint256 id
    ) public payable virtual override {
        address owner = ownerOf(id);

        NFTSecurityLevel level = tokenSecurityLevels[id] !=
            NFTSecurityLevel.NONE
            ? tokenSecurityLevels[id]
            : defaultNFTSecurityLevel;

        if (
            level == NFTSecurityLevel.CAL_ONLY || level == NFTSecurityLevel.FULL
        ) {
            require(_isAllowed(spender, owner), "Spender not allowed by CAL");
        }

        super.approve(spender, id);
        emit ApprovalAttempt(owner, spender, id, true, "");
    }

    // === Transfer Functions ===
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable virtual override nonReentrant {
        if (msg.value > 0) {
            _processRoyalty(from, to, tokenId, msg.value);
        }
        
        super.transferFrom(from, to, tokenId);
    }

    function _processRoyalty(
        address from,
        address to,
        uint256 tokenId,
        uint256 paymentAmount
    ) internal {
        (address receiver, uint256 royaltyAmount) = royaltyInfo(tokenId, paymentAmount);
        
        if (royaltyAmount > 0) {
            (bool success, ) = receiver.call{value: royaltyAmount}("");
            require(success, "Royalty transfer failed");

            uint256 excess = paymentAmount - royaltyAmount;
            if (excess > 0) {
                (bool refundSuccess, ) = payable(msg.sender).call{value: excess}("");
                require(refundSuccess, "Refund failed");
            }

            emit RoyaltyPaid(
                address(this),
                tokenId,
                receiver,
                from,
                to,
                royaltyAmount
            );
        }
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) public payable virtual override nonReentrant {
        if (msg.value > 0) {
            _processRoyalty(from, to, tokenId, msg.value);
        }
        
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable virtual override nonReentrant {
        if (msg.value > 0) {
            _processRoyalty(from, to, tokenId, msg.value);
        }
        
        super.safeTransferFrom(from, to, tokenId);
    }


    /**
     * @dev Returns allowed contract level for a given token
     * @param tokenId Token ID to check
     */
    function contractLevel(uint256 tokenId) external view returns (uint256) {
        return _getCALLevel(ownerOf(tokenId), tokenId);
    }

    /**
     * @dev Returns the base contract level
     */
    function defaultContractLevel() external view returns (uint256) {
        return CALLevel;
    }

    // === Interface Support ===
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(DN404Mirror, AccessControl, ERC2981)
        returns (bool)
    {
        return
            interfaceId == INTERFACE_ID_ERC721C ||
            interfaceId == INTERFACE_ID_CONTRACT_LEVEL ||
            interfaceId == _SEAPORT_HOOK_INTERFACE ||
            DN404Mirror.supportsInterface(interfaceId) ||
            AccessControl.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    // === Utility Functions ===
    receive() external payable virtual override {}

    function withdrawETH() external onlyRole(ADMIN_ROLE) {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "ETH withdrawal failed");
    }
}