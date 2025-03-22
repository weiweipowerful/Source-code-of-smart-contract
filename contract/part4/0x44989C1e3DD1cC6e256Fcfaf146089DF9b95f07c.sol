// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC2981 } from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { ERC721C, ERC721OpenZeppelin } from "@limitbreak/creator-token-contracts/contracts/erc721c/ERC721C.sol";

/// @title Scape: NFT collection
contract ScapeNftCollection is ERC721C, IERC2981, Ownable, ReentrancyGuard, Pausable {
  uint32 public immutable MAX_SUPPLY;
  uint16 public immutable MAX_PUBLIC_MINT_PER_TRANSACTION;
  uint16 public immutable MAX_ROYALTY_BASIS_POINTS;
  uint32 public maxWhitelistSupply;
  uint32 public totalSupply;

  struct MintSchedule {
    uint32 whitelistStartTime;
    uint32 whitelistEndTime;
    /// If not all whitelist NFTs are minted during whitelist period
    /// then public mint should start at a specified time
    uint32 publicSaleStartTime;
    uint32 publicSaleEndTime;
  }

  /// Access Control
  address public contractManager;

  uint256 public mintPrice;

  /// Collection
  uint256 public tokenIdIndex;
  string public baseURI;

  /// Whitelist related
  bytes32 public merkleRoot;
  mapping(address => uint256) public hasWhitelistUserMinted;

  MintSchedule public mintSchedule;
  /// Default is OFF
  bool public autoPublicMintSwitchover;

  /// Royalty related
  uint32 public royaltyBasisPoints;
  address public royaltyReceiverAddress;

  error MaxSupplyReached();
  error MaxWhitelistReached();
  error WhitelistProofInvalid();
  error WhitelistMintNotAllowed();
  error PublicMintNotAllowed();
  error MintFundsInvalid();
  error WithdrawalFailed();
  error MintScheduleInvalid();
  error MintAmountInvalid();
  error ReserveMintNotAllowed();
  error RoyaltyInvalid();
  error TokenIdInvalid(uint256 tokenId);
  error AddressInvalid(address account);
  error AutoSwitchoverValueInvalid();
  error MaxWhitelistSupplyInvalid();
  error OwnableUnauthorizedAccount(address account);
  error EnforcedPause();
  error ExpectedPause();
  error ERC721InsufficientApproval(address operator, uint256 tokenId);

  event BaseURIChanged(string indexed baseURI);
  event MerkleRootChanged(bytes32 indexed merkleRoot);
  event MintScheduleChanged(MintSchedule mintSchedule);
  event ContractManagerChanged(address indexed oldManager, address indexed newManager);
  event RoyaltyInfoChanged(
    address indexed oldRoyaltyReceiver,
    address indexed newRoyaltyReceiver,
    uint256 indexed royaltyBasisPoints
  );
  event AutoPublicMintSwitchoverChanged(bool indexed autoPublicMintSwitchover);
  event MintPriceChanged(uint256 indexed mintPrice);
  event MaxWhitelistSupplyChanged(uint256 indexed maxWhitelistSupply);

  /// @notice Checks if the caller is the contract manager or contract owner
  /// @dev Relies on Ownable to verify if `msg.sender` is the contract owner
  modifier managerOrOwner() {
    if (contractManager != msg.sender && owner() != msg.sender) {
      revert OwnableUnauthorizedAccount(msg.sender);
    }
    _;
  }

  /// @notice Initializes the contract with main parameters
  /// @dev Initializes Ownable with `msg.sender` as contract owner
  /// Initializes ERC721 with name and symbol
  /// @param _name Collection name
  /// @param _symbol Collection symbol
  /// @param _maxSupply Maximum possible supply for the collection
  /// @param _maxWhitelistSupply Maximum supply for whitelisted minting
  /// @param _maxPublicMintPerTransaction Maximum public mints per tx
  /// @param _maxRoyaltyBasisPoints Maximum possible royalty basis points
  /// @param _mintPrice Price of a single NFT mint
  /// @param _contractManager Contract manager address
  /// @param _merkleRoot Merkle root defining the whitelist
  /// @param _tokenBaseURI Initial collection URI
  /// @param _mintSchedule Timestamps for MintSchedule
  constructor(
    string memory _name,
    string memory _symbol,
    uint32 _maxSupply,
    uint32 _maxWhitelistSupply,
    uint16 _maxPublicMintPerTransaction,
    uint16 _maxRoyaltyBasisPoints,
    uint256 _mintPrice,
    address _contractManager,
    bytes32 _merkleRoot,
    string memory _tokenBaseURI,
    MintSchedule memory _mintSchedule
  )
    ERC721OpenZeppelin(_name, _symbol)
    /// Owner is deployer
    Ownable()
  {
    MAX_SUPPLY = _maxSupply;
    maxWhitelistSupply = _maxWhitelistSupply;
    MAX_PUBLIC_MINT_PER_TRANSACTION = _maxPublicMintPerTransaction;
    MAX_ROYALTY_BASIS_POINTS = _maxRoyaltyBasisPoints;
    mintPrice = _mintPrice;

    contractManager = _contractManager;
    merkleRoot = _merkleRoot;
    baseURI = _tokenBaseURI;

    mintSchedule = _mintSchedule;
    _validateMintSchedule(mintSchedule);

    royaltyReceiverAddress = msg.sender;
    royaltyBasisPoints = _maxRoyaltyBasisPoints;
  }

  /// @notice Mints an NFT for a whitelisted user
  /// @dev Protected by ReentrancyGuard. Can be paused
  /// @param _mintAmount Number of Nfts to be minted
  /// @param _whitelistedAmount Number of Nfts allowed to minted
  /// @param _merkleProof Merkle proof attesting address eligibility
  function whitelistedMint(
    uint32 _mintAmount,
    uint32 _whitelistedAmount,
    bytes32[] calldata _merkleProof
  ) external payable nonReentrant whenNotPaused {
    /// Allow whitelist mint including startTime and excluding endtime
    if (block.timestamp < mintSchedule.whitelistStartTime || block.timestamp >= mintSchedule.whitelistEndTime) {
      revert WhitelistMintNotAllowed();
    }

    if (tokenIdIndex + _mintAmount > maxWhitelistSupply) {
      revert MaxWhitelistReached();
    }

    uint256 totalAmount = hasWhitelistUserMinted[msg.sender] + _mintAmount;

    if (_mintAmount == 0 || totalAmount > _whitelistedAmount) {
      revert MintAmountInvalid();
    }

    if (msg.value != mintPrice * _mintAmount) {
      revert MintFundsInvalid();
    }

    /// Generate the merkle tree leaf using senders address and whitelisted amount
    bytes32 leaf = keccak256(abi.encode(keccak256(abi.encode(msg.sender, _whitelistedAmount))));

    /// Verify if the user is allowed to claim by checking if leaf is part of merkle root or not
    if (!MerkleProof.verifyCalldata(_merkleProof, merkleRoot, leaf)) {
      revert WhitelistProofInvalid();
    }

    hasWhitelistUserMinted[msg.sender] = totalAmount;

    uint256 tokenIdIndexTemp = tokenIdIndex;

    for (uint256 i; i < _mintAmount; ) {
      unchecked {
        tokenIdIndexTemp += 1;
      }

      _safeMint(msg.sender, tokenIdIndexTemp);

      unchecked {
        i += 1;
      }
    }

    tokenIdIndex = tokenIdIndexTemp;

    unchecked {
      totalSupply += _mintAmount;
    }
  }

  /// @notice Mints one or two NFTs
  /// @dev Protected by ReentrancyGuard. Can be paused
  /// @param _amount Number of NFTs to be minted
  function publicMint(uint32 _amount) external payable nonReentrant whenNotPaused {
    /// Allow public mint including startTime and excluding endtime
    if (block.timestamp >= mintSchedule.publicSaleEndTime) {
      revert PublicMintNotAllowed();
    } else if (block.timestamp < mintSchedule.publicSaleStartTime) {
      /// Allow auto switchover to public mint from whitelist mint
      /// if `autoPublicMintSwitchover` is ON
      if (!autoPublicMintSwitchover || tokenIdIndex < maxWhitelistSupply) {
        revert PublicMintNotAllowed();
      }
    }

    if (tokenIdIndex + _amount > MAX_SUPPLY) {
      revert MaxSupplyReached();
    }

    if (_amount == 0 || _amount > MAX_PUBLIC_MINT_PER_TRANSACTION) {
      revert MintAmountInvalid();
    }

    if (msg.value != mintPrice * _amount) {
      revert MintFundsInvalid();
    }

    uint256 tokenIdIndexTemp = tokenIdIndex;

    for (uint256 i; i < _amount; ) {
      unchecked {
        tokenIdIndexTemp += 1;
      }

      _safeMint(msg.sender, tokenIdIndexTemp);

      unchecked {
        i += 1;
      }
    }

    tokenIdIndex = tokenIdIndexTemp;

    unchecked {
      totalSupply += _amount;
    }
  }

  /// @notice Mints a number of remaining NFTs in batches
  /// @dev Access restricted only to owner
  /// @param _amount Number of NFTs to be minted
  function reserveMint(uint32 _amount) external payable onlyOwner {
    if (tokenIdIndex + _amount > MAX_SUPPLY) {
      revert MaxSupplyReached();
    }

    if (block.timestamp < mintSchedule.publicSaleEndTime) {
      revert ReserveMintNotAllowed();
    }

    uint256 tokenIdIndexTemp = tokenIdIndex;

    for (uint256 i; i < _amount; ) {
      unchecked {
        tokenIdIndexTemp += 1;
      }

      /// Note that we are using _mint here instead of _safeMint
      /// as we are sure that this will be called by
      /// a ERC721Receiver contract
      _mint(owner(), tokenIdIndexTemp);

      unchecked {
        i += 1;
      }
    }

    tokenIdIndex = tokenIdIndexTemp;

    unchecked {
      totalSupply += _amount;
    }
  }

  /// @notice Transfers all the accumulated funds to the contract owner
  /// @dev Access restricted only to manager and owner
  function withdraw() external managerOrOwner {
    (bool success, ) = owner().call{ value: address(this).balance }("");
    if (!success) {
      revert WithdrawalFailed();
    }
  }

  /// @notice Changes the collection URI
  /// @dev Access restricted only to owner
  /// @param _tokenBaseURI New collection URI
  function setBaseURI(string memory _tokenBaseURI) external onlyOwner {
    baseURI = _tokenBaseURI;
    emit BaseURIChanged(_tokenBaseURI);
  }

  /// @notice Changes the whitelist
  /// @dev Access restricted only to owner
  /// @param _merkleRoot New merkle root defining the whitelist
  function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
    merkleRoot = _merkleRoot;
    emit MerkleRootChanged(_merkleRoot);
  }

  /// @notice Allows to set mint price
  /// @dev Access restricted only to owner
  /// @param _mintPrice Mint price in wei
  function setMintPrice(uint256 _mintPrice) external onlyOwner {
    mintPrice = _mintPrice;

    emit MintPriceChanged(_mintPrice);
  }

  /// @notice Allows to set maxWhitelistSupply
  /// @dev Access restricted only to owner
  /// @param _maxWhitelistSupply Max allowed whitelist mints
  function setMaxWhitelistSupply(uint16 _maxWhitelistSupply) external onlyOwner {
    if (_maxWhitelistSupply > MAX_SUPPLY) {
      revert MaxWhitelistSupplyInvalid();
    }
    maxWhitelistSupply = _maxWhitelistSupply;

    emit MaxWhitelistSupplyChanged(_maxWhitelistSupply);
  }

  /// @notice Changes the mint schedule
  /// @dev Access restricted only to owner
  /// @param _mintSchedule New mint schedule
  function setMintSchedule(MintSchedule memory _mintSchedule) external onlyOwner {
    _validateMintSchedule(_mintSchedule);
    mintSchedule = _mintSchedule;

    emit MintScheduleChanged(_mintSchedule);
  }

  /// @notice Changes the royalty information for the collection
  /// @dev Access restricted only to owner
  /// @param _royaltyReceiverAddress Address of the new royalty receiver
  /// @param _royaltyBasisPoints Basis points defining the royalty
  function setRoyaltyInfo(address _royaltyReceiverAddress, uint32 _royaltyBasisPoints) external onlyOwner {
    if (_royaltyReceiverAddress == address(0) || _royaltyBasisPoints > MAX_ROYALTY_BASIS_POINTS) {
      revert RoyaltyInvalid();
    }

    address oldReceiver = royaltyReceiverAddress;
    royaltyReceiverAddress = _royaltyReceiverAddress;
    royaltyBasisPoints = _royaltyBasisPoints;

    emit RoyaltyInfoChanged(oldReceiver, _royaltyReceiverAddress, _royaltyBasisPoints);
  }

  /// @notice Set autoPublicMintSwitchover for public mint
  /// @dev Access restricted only to owner
  function setAutoPublicMintSwitchover(bool _autoPublicMintSwitchover) external onlyOwner {
    if (_autoPublicMintSwitchover == autoPublicMintSwitchover) {
      revert AutoSwitchoverValueInvalid();
    }
    autoPublicMintSwitchover = _autoPublicMintSwitchover;

    emit AutoPublicMintSwitchoverChanged(_autoPublicMintSwitchover);
  }

  /// @notice Pauses minting operations
  /// @dev Access restricted only to manager and owner
  function pauseMint() external managerOrOwner {
    if (paused()) {
      revert EnforcedPause();
    }
    _pause();
  }

  /// @notice Un-pauses minting operations
  /// @dev Access restricted only to owner
  function unPauseMint() external onlyOwner {
    if (!paused()) {
      revert ExpectedPause();
    }
    _unpause();
  }

  /// @notice Changes the contract manager address
  /// @dev Access restricted only to owner
  /// @param _newContractManager The address of the new contract manager
  function changeContractManager(address _newContractManager) external onlyOwner {
    if (_newContractManager == address(0)) {
      revert AddressInvalid(_newContractManager);
    }

    address oldManager = contractManager;
    contractManager = _newContractManager;

    emit ContractManagerChanged(oldManager, contractManager);
  }

  /// @notice Burns a specified token by ID
  /// @dev Using implementation of Openzeppelin/ERC721Burnable
  /// @param _tokenId Token ID
  function burn(uint256 _tokenId) external {
    if (!_isApprovedOrOwner(msg.sender, _tokenId)) {
      revert ERC721InsufficientApproval(msg.sender, _tokenId);
    }
    _burn(_tokenId);

    unchecked {
      totalSupply -= 1;
    }
  }

  /// @notice Calculates the royalty amount and provides the royalty receiver address
  /// @dev Provides compatibility with the ERC-2981 standard
  /// @param _tokenId Token ID
  /// @param _salePrice Price of the sale
  /// @return receiver Address of the royalty receiver
  /// @return royaltyAmount Amount of royalty to be honored
  function royaltyInfo(
    uint256 _tokenId,
    uint256 _salePrice
  ) external view override returns (address receiver, uint256 royaltyAmount) {
    if (_tokenId > tokenIdIndex) {
      revert TokenIdInvalid(_tokenId);
    }

    receiver = royaltyReceiverAddress;

    royaltyAmount = (_salePrice * royaltyBasisPoints) / 10000;
  }

  /// @notice Detects if an interface is implemented by the smart contract
  /// @dev Provides compatibility with the ERC-165 standard
  /// @param _interfaceId Identifier of the interface to verify
  /// @return `true` if the contract implements `_interfaceId` and
  ///  `_interfaceId` is not 0xffffffff, `false` otherwise
  function supportsInterface(bytes4 _interfaceId) public view override(ERC721C, IERC165) returns (bool) {
    return _interfaceId == type(IERC2981).interfaceId || super.supportsInterface(_interfaceId);
  }

  /// @dev Helper function validating a mint schedule
  /// @param _mintSchedule Struct of type MintSchedule
  function _validateMintSchedule(MintSchedule memory _mintSchedule) internal pure {
    if (
      _mintSchedule.whitelistStartTime == 0 ||
      _mintSchedule.whitelistStartTime >= _mintSchedule.whitelistEndTime ||
      _mintSchedule.publicSaleStartTime >= _mintSchedule.publicSaleEndTime ||
      _mintSchedule.whitelistEndTime > _mintSchedule.publicSaleStartTime
    ) {
      revert MintScheduleInvalid();
    }
  }

  /// @dev Overriding the _requireCallerIsContractOwner used by ERC721C
  /// Only callable by owner
  /// It is used by ERC721C standard to authorize functions
  /// we achive this by using `onlyOwner`
  function _requireCallerIsContractOwner() internal view override onlyOwner {}

  /// @dev Overriding the default _baseURI ERC721 which returns empty string
  /// @return Base URI string
  function _baseURI() internal view override returns (string memory) {
    return baseURI;
  }
}