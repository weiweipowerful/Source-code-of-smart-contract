// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./DN404.sol";
import "./ExtendedDN404Mirror.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MAVILLAIN is DN404, AccessControl, Ownable, ReentrancyGuard {
    // Constants at the top
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");

    bytes4 private constant ERC20_INTERFACE_ID = 0x36372b07;
    bytes4 private constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;

    string private constant TOKEN_NAME = "MUTANT ALIENS VILLAIN";
    string private constant TOKEN_SYMBOL = "$VLN";
    string private constant NFT_NAME = "MUTANT ALIENS VILLAIN";
    string private constant NFT_SYMBOL = "MAV";

    // Error definitions
    error InvalidAirdropParameters();
    error BatchAirdropFailed();
    error FractionalTransferNotAllowed();
    error InvalidPhaseTransition(uint256 current, uint256 requested);
    error InsufficientPayment(uint256 required, uint256 provided);
    error MaxSupplyExceeded(uint256 requested, uint256 remaining);
    error PhaseNotConfigured(uint256 phase);
    error InvalidTimePeriod(uint256 startTime, uint256 endTime);
    error InvalidProof(address user, bytes32 merkleRoot);
    error PhaseNotActive(uint256 phase);
    error PhasePaused(uint256 phase);
    error ExceedsPhaseLimit(uint256 requested, uint256 allowed);
    error InvalidMintRatio(uint256 oldRatio, uint256 newRatio);
    error InvalidOperation(string reason);
    error InvalidPrice();
    error NotLive();
    error PhaseAlreadyExists(uint256 phase);
    error NotAllowlisted(address user);
    error AllowlistAmountExceeded(uint256 requested, uint256 allowed);
    error AllowlistValidationFailed(address user, uint256 phase, string reason);
    error MintValidationFailed(string reason);
    error ExceedsTransactionLimit(uint256 requested, uint256 maximum);
    error InvalidMintAmount(uint256 provided, uint256 maximum, string reason);
    error InvalidPhaseState(uint256 phase, bool isPaused, bool isConfigured);

    struct PhaseConfig {
        uint96 price;
        uint32 maxPerWallet;
        uint32 maxSupplyForPhase;
        bool isConfigured;
        bool isPaused;
        bool requiresAllowlist;
        uint256 totalMinted;
        bytes32 merkleRoot;
        mapping(address => uint256) mintedAmount;
    }

    struct PhaseStatus {
        bool isActive;
        bool isPaused;
        uint256 totalMinted;
        uint96 price;
        uint32 maxPerWallet;
        uint32 maxSupplyForPhase;
        bool requiresAllowlist;
        bytes32 merkleRoot;
    }

    // Events
    event PhaseConfigured(
        uint256 indexed phase,
        uint96 price,
        uint32 maxPerWallet,
        uint32 maxSupplyForPhase,
        bytes32 merkleRoot,
        bool requiresAllowlist
    );

    struct AllowlistValidationParams {
        address user;
        uint256 phase;
        uint256 amount;
        uint256 maxAllowedAmount;
        bytes32[] proof;
    }

    struct MintParams {
        address receiver;
        uint256 amount;
        bool isNFT;
        uint256 maxAllowedAmount;
        bytes32[] proof;
        uint256 phase;
    }

    event MintCompleted(
        address indexed user,
        address indexed receiver,
        uint256 amount,
        uint256 price,
        uint256 indexed phase,
        bool isNFT,
        bool isAllowlist
    );

    event EmergencyRecovery(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    uint256 public maxPerTransaction;

    event PhaseUpdated(uint256 indexed oldPhase, uint256 indexed newPhase);
    event ConfigurationUpdated(string indexed parameter, uint256 newValue);
    event EmergencyAction(string indexed action, uint256 timestamp);
    event WithdrawTest(address indexed to, uint256 amount, uint256 timestamp);
    event PhaseStatusChanged(uint256 indexed phase, bool isPaused);
    event PhaseRemoved(uint256 indexed phase);
    event AirdropCompleted(
        address indexed recipient,
        uint256 amount,
        bool isNFT
    );
    event BatchAirdropCompleted(
        address[] recipients,
        uint256[] amounts,
        bool isNFT
    );
    event ExternalMintCompleted(
        address indexed recipient,
        uint256 amount,
        bool isNFT
    );

    // Immutable state variables
    address public immutable CAL;
    MUTANT_ALIENS_VILLAIN public immutable mirror;

    // Storage variables
    address public withdrawAddress;
    string private _name;
    string private _symbol;
    string private _baseURI;
    address public forwarder;

    uint256 public currentPhase;
    mapping(uint256 => PhaseConfig) public phaseConfigs;
    mapping(uint256 => mapping(address => uint32)) public mintCounts;
    mapping(uint256 => uint256) public phaseTotalMints;

    uint32 public totalMinted;
    uint32 public maxPerWallet = 20000;
    uint32 public maxSupply = 20000;
    uint256 private _mintRatio = 1000;
    bool public live;

    constructor(
        address initialSupplyOwner,
        address contractAllowListProxy,
        address initialWithdrawAddress,
        address initialForwarder
    ) {
        _initializeOwner(msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(AIRDROP_ROLE, msg.sender);

        withdrawAddress = initialWithdrawAddress;

        forwarder = initialForwarder;

        CAL = contractAllowListProxy;

        mirror = new MUTANT_ALIENS_VILLAIN(msg.sender, CAL, withdrawAddress);

        _setSkipNFT(initialSupplyOwner, false);

        _initializeDN404(
            16000 * _unit(),
            initialSupplyOwner,
            address(mirror)
        );
    }

    // ERC20 Core Functions
    function name() public view override returns (string memory) {
        return msg.sender == address(mirror) ? NFT_NAME : TOKEN_NAME;
    }

    function symbol() public view override returns (string memory) {
        return msg.sender == address(mirror) ? NFT_SYMBOL : TOKEN_SYMBOL;
    }

    // Interface support
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl) returns (bool) {
        if (interfaceId == ERC20_INTERFACE_ID) return true;
        if (interfaceId == ERC165_INTERFACE_ID) return true;
        if (interfaceId == ERC721_INTERFACE_ID) return false;
        return AccessControl.supportsInterface(interfaceId);
    }

    // Internal functions
    function _unit() internal view override returns (uint256) {
        return _mintRatio * 10 ** decimals();
    }

    // Modifiers
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    modifier onlyLive() {
        if (!live) revert NotLive();
        _;
    }

    modifier callerIsUser() {
        require(
            tx.origin == msg.sender || msg.sender == forwarder,
            "The caller is another contract and not an authorized forwarder."
        );
        _;
    }

    modifier validatePhase(uint256 phase) {
        PhaseConfig storage config = phaseConfigs[phase];
        if (!config.isConfigured) revert PhaseNotConfigured(phase);
        if (config.isPaused) revert PhasePaused(phase);
        _;
    }

    modifier validateMintRequest(
        uint256 phase,
        uint256 price,
        uint256 amount
    ) {
        if (msg.value != price * amount) revert InvalidPrice();

        uint256 newTotalMinted;
        unchecked {
            newTotalMinted = totalMinted + amount;
        }
        if (newTotalMinted > maxSupply)
            revert MaxSupplyExceeded(amount, maxSupply - totalMinted);

        PhaseConfig storage config = phaseConfigs[phase];
        if (config.maxSupplyForPhase > 0) {
            uint256 newPhaseMinted;
            unchecked {
                newPhaseMinted = phaseTotalMints[phase] + amount;
            }
            if (newPhaseMinted > config.maxSupplyForPhase)
                revert ExceedsPhaseLimit(
                    amount,
                    config.maxSupplyForPhase - phaseTotalMints[phase]
                );
        }

        _;

        unchecked {
            totalMinted = uint32(newTotalMinted);
            phaseTotalMints[phase] += amount;
        }
    }

    modifier validateReceiverMintLimit(
        uint256 phase,
        address minter,
        address receiver,
        uint256 amount
    ) {
        PhaseConfig storage config = phaseConfigs[phase];

        uint256 receiverPhaseMints = mintCounts[phase][receiver];

        uint256 maxPerWalletInPhase = config.maxPerWallet;

        if (receiverPhaseMints + amount > maxPerWalletInPhase) {
            revert ExceedsPhaseLimit(
                amount,
                maxPerWalletInPhase - receiverPhaseMints
            );
        }

        _;

        unchecked {
            mintCounts[phase][receiver] = uint32(receiverPhaseMints + amount);
        }
    }

    function _validateAllowlist(
        AllowlistValidationParams memory params
    ) internal view {
        PhaseConfig storage config = phaseConfigs[params.phase];

        if (!config.requiresAllowlist) {
            return;
        }

        bytes32 leaf = keccak256(
            abi.encodePacked(params.user, params.maxAllowedAmount)
        );

        if (!MerkleProofLib.verify(params.proof, config.merkleRoot, leaf)) {
            revert InvalidProof(params.user, config.merkleRoot);
        }

        uint256 totalMintedInPhase = config.mintedAmount[params.user];
        if (totalMintedInPhase + params.amount > params.maxAllowedAmount) {
            revert AllowlistAmountExceeded(
                params.amount,
                params.maxAllowedAmount - totalMintedInPhase
            );
        }
    }

    function _processMint(MintParams memory params) internal {
        if (params.amount > maxPerTransaction) {
            revert ExceedsTransactionLimit({
                requested: params.amount,
                maximum: maxPerTransaction
            });
        }

        PhaseConfig storage config = phaseConfigs[params.phase];

        _validateAllowlist(
            AllowlistValidationParams({
                user: params.receiver,
                phase: params.phase,
                amount: params.amount,
                maxAllowedAmount: params.maxAllowedAmount,
                proof: params.proof
            })
        );

        uint256 mintAmount = params.isNFT
            ? params.amount * _unit()
            : params.amount * 10 ** decimals();

        _mint(params.receiver, mintAmount);

        unchecked {
            uint256 newTotalMinted = config.totalMinted + params.amount;
            config.totalMinted = newTotalMinted;
            config.mintedAmount[params.receiver] += params.amount;
            totalMinted += uint32(params.amount);
        }

        emit MintCompleted(
            msg.sender,
            params.receiver,
            params.amount,
            config.price,
            params.phase,
            params.isNFT,
            config.requiresAllowlist
        );
    }

    // Public minting functions
    function mint(
        uint256 amount,
        bool isNFT,
        uint256 maxAllowedAmount,
        bytes32[] calldata proof
    )
        external
        payable
        onlyLive
        validatePhase(currentPhase)
        validateMintRequest(
            currentPhase,
            phaseConfigs[currentPhase].price,
            amount
        )
        validateReceiverMintLimit(currentPhase, msg.sender, msg.sender, amount)
        nonReentrant
    {
        PhaseConfig storage config = phaseConfigs[currentPhase];

        if (config.requiresAllowlist) {
            require(proof.length > 0, "Allowlist proof required");
        } else {
            maxAllowedAmount = config.maxPerWallet;
        }

        _processMint(
            MintParams({
                receiver: msg.sender,
                amount: amount,
                isNFT: isNFT,
                maxAllowedAmount: maxAllowedAmount,
                proof: proof,
                phase: currentPhase
            })
        );
    }

    function mintWithReceiver(
        address receiver,
        uint256 amount,
        bool isNFT,
        uint256 maxAllowedAmount,
        bytes32[] calldata proof
    )
        external
        payable
        callerIsUser
        onlyLive
        validatePhase(currentPhase)
        validateMintRequest(
            currentPhase,
            phaseConfigs[currentPhase].price,
            amount
        )
        validateReceiverMintLimit(currentPhase, msg.sender, receiver, amount)
        nonReentrant
    {
        PhaseConfig storage config = phaseConfigs[currentPhase];

        if (config.requiresAllowlist) {
            require(proof.length > 0, "Allowlist proof required");
        } else {
            maxAllowedAmount = config.maxPerWallet;
        }

        _processMint(
            MintParams({
                receiver: receiver,
                amount: amount,
                isNFT: isNFT,
                maxAllowedAmount: maxAllowedAmount,
                proof: proof,
                phase: currentPhase
            })
        );
    }

    // Airdrop functions
    function airdrop(
        address recipient,
        uint256 amount,
        bool isNFT
    ) external onlyRole(AIRDROP_ROLE) {
        if (recipient == address(0) || amount == 0)
            revert InvalidAirdropParameters();

        uint256 mintAmount = isNFT
            ? amount * _unit()
            : amount * 10 ** decimals();
        _mint(recipient, mintAmount);

        emit AirdropCompleted(recipient, amount, isNFT);
    }

    function batchAirdrop(
        address[] calldata recipients,
        uint256[] calldata amounts,
        bool isNFT
    ) external onlyRole(AIRDROP_ROLE) {
        if (recipients.length != amounts.length || recipients.length == 0)
            revert InvalidAirdropParameters();

        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidAirdropParameters();

            uint256 mintAmount = isNFT
                ? amounts[i] * _unit()
                : amounts[i] * 10 ** decimals();
            _mint(recipients[i], mintAmount);
        }

        emit BatchAirdropCompleted(recipients, amounts, isNFT);
    }

    function externalMint(
        address recipient,
        uint256 amount,
        bool isNFT
    ) external onlyRole(MINTER_ROLE) {
        if (recipient == address(0) || amount == 0)
            revert InvalidAirdropParameters();

        uint256 mintAmount = isNFT
            ? amount * _unit()
            : amount * 10 ** decimals();
        _mint(recipient, mintAmount);

        emit ExternalMintCompleted(recipient, amount, isNFT);
    }

    // Admin functions
    function setPhase(uint256 newPhase) external onlyRole(ADMIN_ROLE) {
        if (!phaseConfigs[newPhase].isConfigured)
            revert PhaseNotConfigured(newPhase);

        uint256 oldPhase = currentPhase;
        currentPhase = newPhase;
        emit PhaseUpdated(oldPhase, newPhase);
    }

    function configurePhase(
        uint256 phase,
        uint96 price,
        uint32 phaseMaxPerWallet,
        uint32 maxSupplyForPhase,
        bytes32 merkleRoot,
        bool requiresAllowlist
    ) external onlyRole(ADMIN_ROLE) {
        PhaseConfig storage config = phaseConfigs[phase];
        if (config.isConfigured) revert PhaseAlreadyExists(phase);

        config.price = price;
        config.maxPerWallet = phaseMaxPerWallet;
        config.maxSupplyForPhase = maxSupplyForPhase;
        config.merkleRoot = merkleRoot;
        config.requiresAllowlist = requiresAllowlist;
        config.isConfigured = true;

        emit PhaseConfigured(
            phase,
            price,
            phaseMaxPerWallet,
            maxSupplyForPhase,
            merkleRoot,
            requiresAllowlist
        );
    }

    function resetPhaseConfig(uint256 phase) external onlyRole(ADMIN_ROLE) {
        delete phaseConfigs[phase];
        emit PhaseRemoved(phase);
    }

    function togglePhase(uint256 phase) external onlyRole(ADMIN_ROLE) {
        PhaseConfig storage config = phaseConfigs[phase];
        if (!config.isConfigured) revert PhaseNotConfigured(phase);

        config.isPaused = !config.isPaused;
        emit PhaseStatusChanged(phase, config.isPaused);
    }

    function setBaseURI(
        string calldata baseURI_
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        _baseURI = baseURI_;
    }

    function setPhasePrice(
        uint256 phase,
        uint96 newPrice
    ) external onlyRole(ADMIN_ROLE) {
        if (!phaseConfigs[phase].isConfigured) revert PhaseNotConfigured(phase);
        phaseConfigs[phase].price = newPrice;
        emit ConfigurationUpdated(
            string(abi.encodePacked("price_phase_", LibString.toString(phase))),
            newPrice
        );
    }

    function setMintRatio(uint256 newRatio) external onlyRole(ADMIN_ROLE) {
        if (newRatio == 0) revert InvalidMintRatio(_mintRatio, newRatio);
        _mintRatio = newRatio;
        emit ConfigurationUpdated("mintRatio", newRatio);
    }

    function setMaxPerWallet(
        uint32 _maxPerWallet
    ) external onlyRole(ADMIN_ROLE) {
        maxPerWallet = _maxPerWallet;
        emit ConfigurationUpdated("maxPerWallet", _maxPerWallet);
    }

    function setPhaseMaxPerWallet(
        uint256 phase,
        uint32 newMaxPerWallet
    ) external onlyRole(ADMIN_ROLE) {
        if (!phaseConfigs[phase].isConfigured) revert PhaseNotConfigured(phase);
        phaseConfigs[phase].maxPerWallet = newMaxPerWallet;
        emit ConfigurationUpdated(
            string(
                abi.encodePacked(
                    "maxPerWallet_phase_",
                    LibString.toString(phase)
                )
            ),
            newMaxPerWallet
        );
    }

    function setMaxSupply(uint32 _maxSupply) external onlyRole(ADMIN_ROLE) {
        if (_maxSupply < totalMinted)
            revert InvalidOperation("New max supply below total minted");
        maxSupply = _maxSupply;
        emit ConfigurationUpdated("maxSupply", _maxSupply);
    }

    function setPhaseMaxSupply(
        uint256 phase,
        uint32 newMaxSupply
    ) external onlyRole(ADMIN_ROLE) {
        if (!phaseConfigs[phase].isConfigured) revert PhaseNotConfigured(phase);
        if (newMaxSupply < phaseTotalMints[phase])
            revert InvalidOperation(
                "New phase max supply below phase total minted"
            );
        phaseConfigs[phase].maxSupplyForPhase = newMaxSupply;
        emit ConfigurationUpdated(
            string(
                abi.encodePacked("maxSupply_phase_", LibString.toString(phase))
            ),
            newMaxSupply
        );
    }

    function toggleLive() external onlyRole(ADMIN_ROLE) {
        live = !live;
    }

    function setMerkleRoot(
        uint256 phase,
        bytes32 newRoot
    ) external onlyRole(ADMIN_ROLE) {
        if (!phaseConfigs[phase].isConfigured) revert PhaseNotConfigured(phase);
        if (!phaseConfigs[phase].requiresAllowlist)
            revert InvalidOperation("Phase does not require allowlist");
        phaseConfigs[phase].merkleRoot = newRoot;
        emit ConfigurationUpdated(
            string(
                abi.encodePacked("merkleRoot_phase_", LibString.toString(phase))
            ),
            uint256(newRoot)
        );
    }

    function setMaxPerTransaction(
        uint256 _maxPerTransaction
    ) external onlyRole(ADMIN_ROLE) {
        maxPerTransaction = _maxPerTransaction;
        emit ConfigurationUpdated("maxPerTransaction", _maxPerTransaction);
    }

    // View functions
    function getMerkleRoot(uint256 phase) external view returns (bytes32) {
        if (!phaseConfigs[phase].isConfigured) revert PhaseNotConfigured(phase);
        if (!phaseConfigs[phase].requiresAllowlist)
            revert InvalidOperation("Phase does not require allowlist");
        return phaseConfigs[phase].merkleRoot;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory result) {
        if (bytes(_baseURI).length != 0) {
            result = string(
                abi.encodePacked(_baseURI, LibString.toString(tokenId), ".json")
            );
        }
    }

    function getNextTokenId() public view returns (uint32) {
        DN404Storage storage $ = _getDN404Storage();
        return $.nextTokenId;
    }

    function getAllowlistMintedAmount(
        uint256 phase,
        address user
    ) external view returns (uint256) {
        return phaseConfigs[phase].mintedAmount[user];
    }

    function getPhaseStatus(
        uint256 phase
    ) external view returns (PhaseStatus memory) {
        PhaseConfig storage config = phaseConfigs[phase];
        return
            PhaseStatus({
                isActive: config.isConfigured,
                isPaused: config.isPaused,
                totalMinted: getTotalMintedInPhase(phase),
                price: config.price,
                maxPerWallet: config.maxPerWallet,
                maxSupplyForPhase: config.maxSupplyForPhase,
                requiresAllowlist: config.requiresAllowlist,
                merkleRoot: config.merkleRoot
            });
    }

    // Internal functions
    function getTotalMintedInPhase(
        uint256 phase
    ) internal view returns (uint256) {
        PhaseConfig storage config = phaseConfigs[phase];
        return config.totalMinted;
    }

    // Withdrawal functions
    function withdraw() external nonReentrant onlyOwner {
        require(withdrawAddress != address(0), "Withdraw address not set");
        SafeTransferLib.safeTransferAllETH(withdrawAddress);
        emit EmergencyAction("withdraw", block.timestamp);
    }

    function withdrawAmount(uint256 amount) external nonReentrant onlyOwner {
        require(withdrawAddress != address(0), "Withdraw address not set");
        require(amount > 0, "Amount must be greater than 0");
        require(address(this).balance >= amount, "Insufficient balance");

        SafeTransferLib.safeTransferETH(withdrawAddress, amount);
        emit WithdrawTest(withdrawAddress, amount, block.timestamp);
    }

    function setWithdrawAddress(address _withdrawAddress) public onlyOwner {
        require(_withdrawAddress != address(0), "Invalid address");
        withdrawAddress = _withdrawAddress;
    }

    function getWithdrawAddress() public view returns (address) {
        return withdrawAddress;
    }

    // Emergency functions
    function emergencyPause() external onlyRole(ADMIN_ROLE) {
        live = false;
        emit EmergencyAction("pause", block.timestamp);
    }

    function emergencyTokenRecovery(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (token == address(this))
            revert InvalidOperation("Cannot recover self");
        SafeTransferLib.safeTransfer(token, to, amount);
        emit EmergencyRecovery(token, to, amount);
    }
}