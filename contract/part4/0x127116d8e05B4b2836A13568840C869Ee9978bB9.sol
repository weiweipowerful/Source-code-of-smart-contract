// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.18;

// solhint-disable max-line-length
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { INFTCollectionInitializer } from "../interfaces/internal/collections/INFTCollectionInitializer.sol";

import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import { ERC721BurnableUpgradeable } from "@openzeppelin/contracts-upgradeable-v5/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable-v5/token/ERC721/ERC721Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable-v5/proxy/utils/Initializable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable-v5/access/Ownable2StepUpgradeable.sol";
import "../mixins/shared/Constants.sol";

import { AddressLibrary } from "../libraries/AddressLibrary.sol";
import { CollectionRoyalties } from "../mixins/collections/CollectionRoyalties.sol";
import { NFTCollectionType } from "../mixins/collections/NFTCollectionType.sol";
import { SelfDestructibleCollection } from "../mixins/collections/SelfDestructibleCollection.sol";
import { SequentialMintCollection } from "../mixins/collections/SequentialMintCollection.sol";
import { StringsLibrary } from "../libraries/StringsLibrary.sol";
import { TokenLimitedCollection } from "../mixins/collections/TokenLimitedCollection.sol";
// solhint-enable max-line-length

error NFTCollection_Max_Token_Id_Has_Already_Been_Minted(uint256 maxTokenId);
error NFTCollection_Token_CID_Already_Minted();
error NFTCollection_Token_Creator_Payment_Address_Required();

/**
 * @title A collection of 1:1 NFTs by a single creator.
 * @notice A 10% royalty to the creator is included which may be split with collaborators on a per-NFT basis.
 * @author batu-inal & HardlyDifficult
 */
contract NFTCollection is
  INFTCollectionInitializer,
  Initializable,
  Ownable2StepUpgradeable,
  ERC721Upgradeable,
  ERC721BurnableUpgradeable,
  NFTCollectionType,
  SequentialMintCollection,
  TokenLimitedCollection,
  CollectionRoyalties,
  SelfDestructibleCollection
{
  using AddressLibrary for address;
  using AddressUpgradeable for address;

  /**
   * @notice The baseURI to use for the tokenURI, if undefined then `ipfs://` is used.
   */
  string private baseURI_;

  /**
   * @notice Stores hashes minted to prevent duplicates.
   * @dev 0 means not yet minted, set to 1 when minted.
   * For why using uint is better than using bool here:
   * github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.3/contracts/security/ReentrancyGuard.sol#L23-L27
   */
  mapping(string => uint256) private cidToMinted;

  /**
   * @dev Stores an optional alternate address to receive creator revenue and royalty payments.
   * The target address may be a contract which could split or escrow payments.
   */
  mapping(uint256 => address payable) private tokenIdToCreatorPaymentAddress;

  /**
   * @dev Stores a CID for each NFT.
   */
  mapping(uint256 => string) private _tokenCIDs;

  /**
   * @notice Emitted when the owner changes the base URI to be used for NFTs in this collection.
   * @param baseURI The new base URI to use.
   */
  event BaseURIUpdated(string baseURI);

  /**
   * @notice Emitted when a new NFT is minted.
   * @param creator The address of the collection owner at this time this NFT was minted.
   * @param tokenId The tokenId of the newly minted NFT.
   * @param indexedTokenCID The CID of the newly minted NFT, indexed to enable watching for mint events by the tokenCID.
   * @param tokenCID The actual CID of the newly minted NFT.
   */
  event Minted(address indexed creator, uint256 indexed tokenId, string indexed indexedTokenCID, string tokenCID);

  /**
   * @notice Emitted when the payment address for creator royalties is set.
   * @param fromPaymentAddress The original address used for royalty payments.
   * @param toPaymentAddress The new address used for royalty payments.
   * @param tokenId The NFT which had the royalty payment address updated.
   */
  event TokenCreatorPaymentAddressSet(
    address indexed fromPaymentAddress,
    address indexed toPaymentAddress,
    uint256 indexed tokenId
  );

  /// @notice Initialize the template's immutable variables.
  constructor() NFTCollectionType(NFT_COLLECTION_TYPE) reinitializer(type(uint64).max) {
    __ERC721_init_unchained("NFT Collection Implementation", "NFT");

    // Using reinitializer instead of _disableInitializers allows initializing of OZ mixins, describing the template.
  }

  /**
   * @notice Called by the contract factory on creation.
   * @param _creator The creator of this collection.
   * @param _name The collection's `name`.
   * @param _symbol The collection's `symbol`.
   */
  function initialize(address payable _creator, string calldata _name, string calldata _symbol) external initializer {
    __ERC721_init_unchained(_name, _symbol);
    __Ownable_init_unchained(_creator);
    // maxTokenId defaults to 0 but may be assigned later on.
  }

  /**
   * @notice Mint an NFT defined by its metadata path.
   * @dev This is only callable by the collection creator/owner.
   * @param tokenCID The CID for the metadata json of the NFT to mint.
   * @return tokenId The tokenId of the newly minted NFT.
   */
  function mint(string calldata tokenCID) external returns (uint256 tokenId) {
    tokenId = _mint(tokenCID);
  }

  /**
   * @notice Mint an NFT defined by its metadata path and approves the provided operator address.
   * @dev This is only callable by the collection creator/owner.
   * It can be used the first time they mint to save having to issue a separate approval
   * transaction before listing the NFT for sale.
   * @param tokenCID The CID for the metadata json of the NFT to mint.
   * @param operator The address to set as an approved operator for the creator's account.
   * @return tokenId The tokenId of the newly minted NFT.
   */
  function mintAndApprove(string calldata tokenCID, address operator) external returns (uint256 tokenId) {
    tokenId = _mint(tokenCID);
    setApprovalForAll(operator, true);
  }

  /**
   * @notice Mint an NFT defined by its metadata path and have creator revenue/royalties sent to an alternate address.
   * @dev This is only callable by the collection creator/owner.
   * @param tokenCID The CID for the metadata json of the NFT to mint.
   * @param tokenCreatorPaymentAddress The royalty recipient address to use for this NFT.
   * @return tokenId The tokenId of the newly minted NFT.
   */
  function mintWithCreatorPaymentAddress(
    string calldata tokenCID,
    address payable tokenCreatorPaymentAddress
  ) public returns (uint256 tokenId) {
    if (tokenCreatorPaymentAddress == address(0)) {
      revert NFTCollection_Token_Creator_Payment_Address_Required();
    }
    tokenId = _mint(tokenCID);
    tokenIdToCreatorPaymentAddress[tokenId] = tokenCreatorPaymentAddress;
    emit TokenCreatorPaymentAddressSet(address(0), tokenCreatorPaymentAddress, tokenId);
  }

  /**
   * @notice Mint an NFT defined by its metadata path and approves the provided operator address.
   * @dev This is only callable by the collection creator/owner.
   * It can be used the first time they mint to save having to issue a separate approval
   * transaction before listing the NFT for sale.
   * @param tokenCID The CID for the metadata json of the NFT to mint.
   * @param tokenCreatorPaymentAddress The royalty recipient address to use for this NFT.
   * @param operator The address to set as an approved operator for the creator's account.
   * @return tokenId The tokenId of the newly minted NFT.
   */
  function mintWithCreatorPaymentAddressAndApprove(
    string calldata tokenCID,
    address payable tokenCreatorPaymentAddress,
    address operator
  ) external returns (uint256 tokenId) {
    tokenId = mintWithCreatorPaymentAddress(tokenCID, tokenCreatorPaymentAddress);
    setApprovalForAll(operator, true);
  }

  /**
   * @notice Mint an NFT defined by its metadata path and have creator revenue/royalties sent to an alternate address
   * which is defined by a contract call, typically a proxy contract address representing the payment terms.
   * @dev This is only callable by the collection creator/owner.
   * @param tokenCID The CID for the metadata json of the NFT to mint.
   * @param paymentAddressFactory The contract to call which will return the address to use for payments.
   * @param paymentAddressCall The call details to send to the factory provided.
   * @return tokenId The tokenId of the newly minted NFT.
   */
  function mintWithCreatorPaymentFactory(
    string calldata tokenCID,
    address paymentAddressFactory,
    bytes calldata paymentAddressCall
  ) public returns (uint256 tokenId) {
    address payable tokenCreatorPaymentAddress = paymentAddressFactory.callAndReturnContractAddress(paymentAddressCall);
    tokenId = mintWithCreatorPaymentAddress(tokenCID, tokenCreatorPaymentAddress);
  }

  /**
   * @notice Mint an NFT defined by its metadata path and have creator revenue/royalties sent to an alternate address
   * which is defined by a contract call, typically a proxy contract address representing the payment terms.
   * @dev This is only callable by the collection creator/owner.
   * It can be used the first time they mint to save having to issue a separate approval
   * transaction before listing the NFT for sale.
   * @param tokenCID The CID for the metadata json of the NFT to mint.
   * @param paymentAddressFactory The contract to call which will return the address to use for payments.
   * @param paymentAddressCall The call details to send to the factory provided.
   * @param operator The address to set as an approved operator for the creator's account.
   * @return tokenId The tokenId of the newly minted NFT.
   */
  function mintWithCreatorPaymentFactoryAndApprove(
    string calldata tokenCID,
    address paymentAddressFactory,
    bytes calldata paymentAddressCall,
    address operator
  ) external returns (uint256 tokenId) {
    tokenId = mintWithCreatorPaymentFactory(tokenCID, paymentAddressFactory, paymentAddressCall);
    setApprovalForAll(operator, true);
  }

  /**
   * @notice Allows the collection creator to destroy this contract only if no NFTs have been minted yet or the minted
   * NFTs have been burned.
   */
  function selfDestruct() external onlyOwner {
    _selfDestruct();
  }

  /**
   * @notice Allows the owner to assign a baseURI to use for the tokenURI instead of the default `ipfs://`.
   * @param baseURIOverride The new base URI to use for all NFTs in this collection.
   */
  function updateBaseURI(string calldata baseURIOverride) external onlyOwner {
    baseURI_ = baseURIOverride;

    emit BaseURIUpdated(baseURIOverride);
  }

  /**
   * @notice Allows the owner to set a max tokenID.
   * This provides a guarantee to collectors about the limit of this collection contract, if applicable.
   * @dev Once this value has been set, it may be decreased but can never be increased.
   * This max may be more than the final `totalSupply` if 1 or more tokens were burned.
   * @param _maxTokenId The max tokenId to set, all NFTs must have a tokenId less than or equal to this value.
   */
  function updateMaxTokenId(uint32 _maxTokenId) external onlyOwner {
    _updateMaxTokenId(_maxTokenId);
  }

  /// @inheritdoc ERC721Upgradeable
  function _update(
    address to,
    uint256 tokenId,
    address auth
  ) internal override(ERC721Upgradeable, SequentialMintCollection) returns (address from) {
    if (to == address(0)) {
      // On burn clean up
      delete cidToMinted[_tokenCIDs[tokenId]];
      delete tokenIdToCreatorPaymentAddress[tokenId];
      delete _tokenCIDs[tokenId];
    }

    from = super._update(to, tokenId, auth);
  }

  function _mint(string calldata tokenCID) private onlyOwner returns (uint256 tokenId) {
    StringsLibrary.validateStringNotEmpty(tokenCID);
    if (cidToMinted[tokenCID] != 0) {
      revert NFTCollection_Token_CID_Already_Minted();
    }
    // If the mint will exceed uint32, the addition here will overflow. But it's not realistic to mint that many tokens.
    tokenId = ++latestTokenId;
    if (maxTokenId != 0 && tokenId > maxTokenId) {
      revert NFTCollection_Max_Token_Id_Has_Already_Been_Minted(maxTokenId);
    }
    cidToMinted[tokenCID] = 1;
    _tokenCIDs[tokenId] = tokenCID;
    _safeMint(msg.sender, tokenId);
    emit Minted(msg.sender, tokenId, tokenCID, tokenCID);
  }

  /**
   * @notice The base URI used for all NFTs in this collection.
   * @dev The `tokenCID` is appended to this to obtain an NFT's `tokenURI`.
   *      e.g. The URI for a token with the `tokenCID`: "foo" and `baseURI`: "ipfs://" is "ipfs://foo".
   * @return uri The base URI used by this collection.
   */
  function baseURI() external view returns (string memory uri) {
    uri = _baseURI();
  }

  /**
   * @notice Checks if the creator has already minted a given NFT using this collection contract.
   * @param tokenCID The CID to check for.
   * @return hasBeenMinted True if the creator has already minted an NFT with this CID.
   */
  function getHasMintedCID(string calldata tokenCID) external view returns (bool hasBeenMinted) {
    hasBeenMinted = cidToMinted[tokenCID] != 0;
  }

  /**
   * @inheritdoc CollectionRoyalties
   */
  function getTokenCreatorPaymentAddress(
    uint256 tokenId
  ) public view override returns (address payable creatorPaymentAddress) {
    creatorPaymentAddress = tokenIdToCreatorPaymentAddress[tokenId];
    if (creatorPaymentAddress == address(0)) {
      creatorPaymentAddress = payable(owner());
    }
  }

  /// @inheritdoc IERC165
  function supportsInterface(
    bytes4 interfaceId
  ) public view override(ERC721Upgradeable, CollectionRoyalties) returns (bool interfaceSupported) {
    interfaceSupported = super.supportsInterface(interfaceId);
  }

  /// @inheritdoc IERC721Metadata
  function tokenURI(uint256 tokenId) public view override returns (string memory uri) {
    _requireOwned(tokenId);

    uri = string.concat(_baseURI(), _tokenCIDs[tokenId]);
  }

  function _baseURI() internal view override returns (string memory uri) {
    uri = baseURI_;
    if (bytes(uri).length == 0) {
      uri = "ipfs://";
    }
  }

  function totalSupply()
    public
    view
    override(SelfDestructibleCollection, SequentialMintCollection)
    returns (uint256 supply)
  {
    supply = super.totalSupply();
  }
}