// SPDX-License-Identifier: MIT

/**
 * @title CommunityCollection.sol. NFT collection for input controlled token types, in this case using
 * a merkle tree.
 *
 * @author omnus (https://omn.us) for bywassies (https://bywassies.com)
 */

pragma solidity 0.8.24;

// ERC721CC is a fork of ERC721A from Chiru labs with additional features.
import {ERC721CC} from "../ERC721CC/ERC721CC.sol";
// The CommunityCollection interface.
import {ICommunityCollection} from "./ICommunityCollection.sol";
// OZs ownable implementation.
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// The MerkleProof library provides methods to validate leaves and proofs against the merkle root.
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract CommunityCollection is ERC721CC, ICommunityCollection, Ownable {
  // bytes14 confirmation required on certain state changing method to avoid being called
  // be accident.
  bytes14 internal constant CONFIRMATION_BYTES = 0x6C6F636B6564666F726576657221;

  // We store that addresses have minted, ensuring that any address can only mint once.
  // Later versions can potentially including allowances greater than one and tracking
  // against that allowance.
  mapping(address => mapping(uint256 => bool)) internal addressHasMinted;

  // The merkle root is set on the initialise and can be updated by the owner as required.
  bytes32 internal merkleRoot;

  /**
   * --------------
   * INITIALISATION
   * --------------
   */

  /**
   * @dev constructor
   *
   * The constructor is only called when the contract template is deployed. It is NOT called
   * when clones are instantiated. For this reason all setup logic must be executed in the `initialise`
   * method.
   */
  constructor() Ownable(msg.sender) {
    renounceOwnership();
  }

  /**
   * @dev initialise
   *
   * This method is called by the factory when creating a clone. It handles the initial setup of the
   * ERC-721 collection.
   *
   * This method also receives the bytes argument `initialArgs_`. This allows subsequent versions of this
   * contract to require new initialise arguments without the factory needing to change in order to supply
   * these arguments.
   *
   * @param name_ The name of this collection, typicaly a short string
   * @param symbol_ The symbol for this collection, commonly a short string in capital letters.
   * @param baseURI_ The base URI for this collection. URIs will be formed from this string, plus the URI suffix.
   * @param switches_ Array of collection control booleans:
   *        [0] uniqueMetadata: If the collection has unique metadata for each NFT. If this is true the baseURI
   *            is suffixed. If false the baseURI is returned for all.
   *        [1] transferable: Is this collection transferable? If false this collection is 'soulbound'
   *        [2] burnable: Is this collection burnable? If false this collection cannot be burned.
   * @param maxSupply_ The maximum number of tokens that can be minted in this collection. 0 = unlimited.
   * @param initialArgs_ A bytes parameter than can contain further, as of yet undefined, parameters.
   */
  function initialise(
    string calldata name_,
    string calldata symbol_,
    string calldata baseURI_,
    uint256 maxSupply_,
    bool[] calldata switches_,
    bytes calldata initialArgs_
  ) external {
    _initialiseERC721CC(
      name_,
      symbol_,
      baseURI_,
      maxSupply_,
      switches_,
      initialArgs_
    );
    // CommunityCollections are created via the CommunityCollectionFactory.
    // We want to initialise the owner to the caller of the CommunityCollectionFactory.
    _transferOwnership(tx.origin);
  }

  /**
   * ---------
   * MODIFIERS
   * ---------
   */

  /**
   * @dev onlyWhenURIUnlocked
   *
   * This modifier will revert if the URI is locked
   */
  modifier onlyWhenURIUnlocked() {
    if (lockedURI) {
      revert("URI is locked");
    }
    _;
  }

  /**
   * @dev onlyWhenMintingUnlocked
   *
   * This modifier will revert if minting is locked
   */
  modifier onlyWhenMintingUnlocked() {
    if (lockedMinting) {
      revert("Minting is locked forever");
    }
    _;
  }

  /**
   * -------------------
   * VIEW METHOD GETTERS
   * -------------------
   */

  /**
   * @dev getMerkleRoot
   *
   * External function to return the current merkle root
   */
  function getMerkleRoot() external view returns (bytes32) {
    return (merkleRoot);
  }

  /**
   * @dev getAddressHasMinted
   *
   * External function to return if the address has minted on the queried collection.
   */
  function getAddressHasMinted(
    address minter_,
    uint256 tokenTypeId_
  ) external view returns (bool) {
    return addressHasMinted[minter_][tokenTypeId_];
  }

  /**
   * @dev getAllTokenTypes
   *
   * External function to return full array of token types
   */
  function getAllTokenTypes() external view returns (uint16[] memory) {
    return (tokenIdToTypeId);
  }

  /**
   * -------
   * UPDATES
   * -------
   */

  /**
   * @dev updateMerkleRoot
   *
   * An onlyAdmin method that allows the owner to update the root for the merkle tree.
   *
   * @param newMerkleRoot_ The new bytes32 merkle root.
   */
  function updateMerkleRoot(bytes32 newMerkleRoot_) external onlyOwner {
    merkleRoot = newMerkleRoot_;
    emit MerkleRootUpdated(newMerkleRoot_);
  }

  /**
   * @dev updateUniqueMetadata
   *
   * onlyOwner method to update a the unique metadata boolean
   *
   * @param uniqueMetadata_: whether this collection has unique metadata (or not)
   */
  function updateUniqueMetadata(
    bool uniqueMetadata_
  ) external onlyOwner onlyWhenURIUnlocked {
    uniqueMetadata = uniqueMetadata_;
    emit UniqueMetadataBoolUpdated();
  }

  /**
   * @dev updateBaseURI
   *
   * onlyOwner method to update an unlocked URI
   *
   * @param uri_: the new URI
   */
  function updateBaseURI(
    string calldata uri_
  ) external onlyOwner onlyWhenURIUnlocked {
    string memory oldURI = baseURI;
    baseURI = uri_;
    emit URIUpdated(oldURI, uri_);
  }

  /**
   * @dev updateURISuffixes
   *
   * onlyOwner method to update an unlocked URI suffix(es)
   *
   * @param uriSuffixes_: the new URI suffixes
   */
  function updateURISuffixes(
    URISuffixes[] calldata uriSuffixes_
  ) external onlyOwner onlyWhenURIUnlocked {
    for (uint256 i = 0; i < uriSuffixes_.length; ) {
      string memory oldSuffixURI = uriSuffix[uriSuffixes_[i].tokenTypeId];
      uriSuffix[uriSuffixes_[i].tokenTypeId] = uriSuffixes_[i].suffix;
      emit URISuffixUpdated(oldSuffixURI, uriSuffixes_[i].suffix);
      unchecked {
        i++;
      }
    }
  }

  /**
   * @dev lockURI
   *
   * onlyOwner method to lock the URI
   *
   * @param confirm_ confirmation value to prevent erroneous locking
   */
  function lockURI(bytes14 confirm_) external onlyOwner {
    if (confirm_ != CONFIRMATION_BYTES) {
      revert("Incorrect confirmation");
    }
    lockedURI = true;
    emit URILocked();
  }

  /**
   * @dev lockMinting
   *
   * onlyOwner method to lock minting forever
   *
   * @param confirm_ confirmation value to prevent erroneous locking
   */
  function lockMinting(bytes14 confirm_) external onlyOwner {
    if (confirm_ != CONFIRMATION_BYTES) {
      revert("Incorrect confirmation");
    }
    lockedMinting = true;
    emit MintingLocked();
  }

  /**
   * ----------------
   * TOKEN OPERATIONS
   * ----------------
   */

  /**
   * @dev communityMint
   *
   * Validate caller eligiblity and mint
   *
   * @param mintRequests_ An array of mint requests. These include the
   * token type identifier and the corresponding proof.
   */
  function communityMint(
    MintRequest[] calldata mintRequests_
  ) external onlyWhenMintingUnlocked {
    if (mintRequests_.length == 0) {
      revert("Must mint something");
    }

    for (uint256 i = 0; i < mintRequests_.length; ) {
      _addressHasMintedCheck(msg.sender, mintRequests_[i].tokenTypeId);

      _merkleTreeCheck(
        mintRequests_[i].proof,
        keccak256(abi.encodePacked(msg.sender, mintRequests_[i].tokenTypeId))
      );

      _recordAddressMinted(msg.sender, mintRequests_[i].tokenTypeId);

      unchecked {
        i++;
      }
    }

    // Pass all the requests to mint, so we mint in one batch and take advantage of ERC721A:
    _mint(msg.sender, mintRequests_.length, mintRequests_);
  }

  /**
   * @dev _addressHasMintedCheck
   *
   * An internal method to check if an address has already minted. It will revert if it has.
   *
   * @param minter_ The minter address being checked.
   * @param tokenTypeId_ The token type being checked.
   */
  function _addressHasMintedCheck(
    address minter_,
    uint256 tokenTypeId_
  ) internal view {
    if (addressHasMinted[minter_][tokenTypeId_]) {
      revert("Address has already minted");
    }
  }

  /**
   * @dev _merkleTreeCheck
   *
   * An internal method to check if a leaf hash and proof pass the merkle check. It will revert if it does not.
   *
   * @param proof_ The provided proof
   * @param leafHash_ The leaf hash being checked.
   */
  function _merkleTreeCheck(
    bytes32[] calldata proof_,
    bytes32 leafHash_
  ) internal view {
    // Cannot mint using a merkle tree if we have a blank root:
    if (merkleRoot == bytes32(0)) {
      revert("No root set");
    }

    if (!addressIsInMerkleTree(proof_, leafHash_)) {
      revert("Address not in the list");
    }
  }

  /**
   * @dev addressIsInMerkleTree
   *
   * An public method to check if an address and proof pass the merkle check. It returns this as a bool.
   *
   * @param proof_ The provided proof
   * @param leafHash_ The leaf hash being checked.
   */
  function addressIsInMerkleTree(
    bytes32[] calldata proof_,
    bytes32 leafHash_
  ) public view returns (bool) {
    return (MerkleProof.verify(proof_, merkleRoot, leafHash_));
  }

  /**
   * @dev _recordAddressMinted
   *
   * An internal method to update the status of an address in the `addressHasMinted` mapping.
   *
   * @param minter_ The address which has minted.
   * @param tokenTypeId_ The token type being checked.
   */
  function _recordAddressMinted(
    address minter_,
    uint256 tokenTypeId_
  ) internal {
    addressHasMinted[minter_][tokenTypeId_] = true;
  }

  /**
   * @dev fixedMint
   *
   * Owner only fixed amount mint function
   *
   * @param mintRequests_ An array of mint requests.
   */
  function fixedMint(
    MintRequest[] calldata mintRequests_
  ) external onlyWhenMintingUnlocked onlyOwner {
    if (mintRequests_.length == 0) {
      revert("Must mint something");
    }

    // Pass all the requests to mint, so we mint in one batch and take advantage of ERC721A:
    _mint(msg.sender, mintRequests_.length, mintRequests_);
  }

  /**
   * @dev burn
   *
   * Burn tokens!
   *
   * @param tokenId_: the tokenId to burn (note - owner / auth checks performed in ERC721Sub)
   */
  function burn(uint256 tokenId_) external {
    _burn(tokenId_, true);
  }

  /**
   * --------------------------
   * NO RANDOM ETH, NO FALLBACK
   * --------------------------
   */

  receive() external payable onlyOwner {}

  fallback() external {
    revert("No fallback here");
  }
}