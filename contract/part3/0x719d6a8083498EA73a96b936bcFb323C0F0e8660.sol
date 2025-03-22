// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

// Use the SafeERC20 for IERC20 tokens
using SafeERC20 for IERC20;

contract AlkimiV2 is ERC721, Ownable2Step, ReentrancyGuard {
  using Address for address;

  // ------------ Variables {{{
  uint8     private constant TOTAL_ADMINS = 2;
  uint32    public  validatorVersionCount;
  uint256   private _totalMinted;
  address   private _treasuryWallet; // Address of the treasury wallet
  address[] private _admins; // Array to store admin addresses
  uint256   private maxReclaimFee = 0.01 ether; // Max reclaim fee is 0.01 ether
  uint256   public  reclaimFee = 0.005 ether; // Initial reclaim fee

  // Validator status enum
  enum ValidatorStatus {Invalid, Inactive, Active}
  // Request approval status
  enum RequestStatus { Invalid, Pending, Approved, Rejected }

  struct ValidatorVersion {
    string          version;
    address         underlying;
    uint256         collateral;
    uint256         ts;
    uint256         minted;
    string          activeURI;
    string          inactiveURI;
  }

  struct UserRequest {
    address       user;
    RequestStatus status;
    string        reason; // rejection reason
  }

  mapping(uint256 tokenId => ValidatorStatus validatorStatus) public nftValidatorStatus;
  mapping(uint256 valVerIdx => ValidatorVersion validatorVer) public validatorVersions;
  mapping(uint256 tokenId => string tokenUri) private _tokenURIs; // Mapping to store individual NFT URIs
  mapping(address adminAddr => bool flag) private _isAdmin;
  mapping(uint256 tokenId => bool flag) public reclaimable; // Mapping to store reclaimable flag for NFTs
  mapping(uint256 tokenId => uint256 valVerIdx ) public nftToValidatorVersion; // tokenId -> Validatorversion
  mapping(uint256 tokenId => UserRequest stReq) public approvalRequests;
  mapping(uint256 tokenId => UserRequest stReq) public reclaimRequests; // Mapping between tokenId and struct

  // ------------ Variables }}}

  // ------------ Errors {{{
  /**
   * @notice Error emitted when a token ID does not exist.
   * @param tokenId The ID of the token that does not exist.
   */
  error TokenIDDoesNotExist(uint256 tokenId);
  /**
   * @notice Error emitted when an address is unauthorized.
   * @param sender The address that attempted the unauthorized action.
   */
  error UnauthorizedAdmin(address sender);
  /**
   * @notice Error emitted when an incorrect validator version index is used.
   * @param validatorVerIdx The invalid validator version index.
   */
  error WrongValidatorVersionIndex(uint256 validatorVerIdx);
  /**
   * @notice Error emitted when the caller is not the owner of the specified NFT.
   * @param sender The address attempting the operation.
   * @param tokenId The ID of the NFT being accessed.
   */
  error NotNFTOwner(address sender, uint256 tokenId);
  /// @notice Error emitted when a request to create a validator node fails.
  error validatorNodeRequestFailed();
  /**
   * @notice Error emitted when an invalid address is used.
   * @param addr The address that was invalid.
   */
  error InvalidAddress(address addr);
  /// @notice Error emitted when the maximum number of admins has been reached.
  error MaxAdminsReached();
  /**
   * @notice Error emitted when an address is already registered as an admin.
   * @param admin The address that is already an admin.
   */
  error AdminAlreadyAdded(address admin);
  /**
   * @notice Error emitted when the specified address is not an admin.
   * @param admin The address that attempted an admin-only operation.
   */
  error NotAnAdmin(address admin);
  /**
   * @notice Error emitted when the new fee specified exceeds the maximum allowable reclaim fee.
   * @param attemptedFee The fee that was attempted to be set.
   * @param maxFee The maximum allowable fee.
   */
  error FeeExceedsMaximum(uint256 attemptedFee, uint256 maxFee);
  /**
   * @notice Error emitted when the new total supply is set to less than the number already minted.
   * @param attemptedTotalSupply The new total supply attempted to be set.
   * @param minted The number of items already minted.
   */
  error TotalSupplyLessThanMinted(uint256 attemptedTotalSupply, uint256 minted);
  /**
   * @notice Error emitted when a specified version ID is invalid because it exceeds the number of validator versions.
   * @param versionId The invalid version ID provided.
   * @param maxValidId The maximum valid version ID, based on the count of validator versions.
   */
  error InvalidVersionMapping(uint256 versionId, uint256 maxValidId);
  /**
   * @notice Error emitted when the attempted minting exceeds the total supply for the validator version.
   * @param validatorVerIdx The index of the validator version being accessed.
   * @param attemptedMint The total number of NFTs attempted to be minted.
   * @param totalSupply The total supply available for that validator version.
   */
  error MintingExceedsTotalSupply(uint256 validatorVerIdx, uint256 attemptedMint, uint256 totalSupply);
  /// @notice Error emitted when an operation is attempted on an NFT with an invalid validator status.
  error InvalidValidatorStatus();
  /**
   * @notice Error emitted when minting of NFTs fails.
   * @param validatorVerIdx Index of the validator version used for minting.
   * @param user The address of the user attempting the mint.
   * @param noOfNFTs The number of NFTs attempted to be minted.
   * @param uri The intended URI for the NFTs being minted.
   * @param status The intended status of the NFTs being minted.
   */
  error MintingFailed(uint256 validatorVerIdx, address user, uint256 noOfNFTs, string uri, ValidatorStatus status);
  /**
   * @notice Error emitted when the allowance for the contract to spend tokens on behalf of the sender is insufficient.
   * @param sender The address of the token holder.
   * @param spender The contract attempting to spend the tokens.
   * @param requiredCollateral The amount of collateral required but not permitted by allowance.
   * @param currentAllowance The current allowance amount that is insufficient.
   */
  error InsufficientAllowance(address sender, address spender, uint256 requiredCollateral, uint256 currentAllowance);
  /**
   * @notice Error emitted when the request status is not as expected.
   * @param tokenId The ID of the token for which the request status is incorrect.
   * @param currentStatus The current status of the request.
   * @param expectedStatus The expected status that was not met.
   */
  error IncorrectRequestStatus(uint256 tokenId, RequestStatus currentStatus, RequestStatus expectedStatus);
  /**
   * @notice Error emitted when an operation is attempted on a token that is not reclaimable.
   * @param tokenId The ID of the token which is not reclaimable.
   */
  error NotReclaimable(uint256 tokenId);
  /**
   * @notice Error emitted when the amount of ether sent does not match the required reclaim fee.
   * @param sentAmount The amount of ether sent.
   * @param requiredAmount The reclaim fee required.
   */
  error IncorrectReclaimFeeSent(uint256 sentAmount, uint256 requiredAmount);
  /**
   * @notice Error emitted when the transfer of Ether fails.
   * @param to The recipient address of the Ether.
   * @param amount The amount of Ether attempted to be transferred.
   */
  error EtherTransferFailed(address to, uint256 amount);
  /**
   * @notice Error emitted when the function argument is Invalid.
   * @param parameter Name of the parameter that is Invalid
   */
  error InvalidArg(string parameter);

  // ------------ Errors }}}

  // ------------ Modifiers {{{

  // Modifier to check if a token ID exists
  modifier tokenIDExists(uint256 tokenId) {
    if (!_tokenExists(tokenId)) {
      revert TokenIDDoesNotExist(tokenId);
    }
    _;
  }
  modifier onlyAdmin() {
    if (!_isAdmin[_msgSender()] && owner() != _msgSender()) {
      revert UnauthorizedAdmin(_msgSender());
    }
    _;
  }

  // ------------ Modifiers }}}

  // ------------ EVENTS {{{
  event AdminAdded(address indexed admin);
  event AdminRemoved(address indexed admin);
  event NFTMinted(address indexed minter, uint256 indexed tokenId, uint256 indexed validatorVerIdx);
  event NFTBurned(address indexed burner, uint256 indexed tokenId);
  event TreasuryWalletSet(address indexed newTreasuryWallet);
  event ValidatorVersionAdded(address indexed caller, string version, uint256 indexed validatorVerIdx, address underlying, uint256 collateral, uint256 ts);
  event ValidatorTSUpdated(address indexed caller, uint256 indexed validatorVerIdx, uint256 newTs);
  event ValidatorURIUpdated(address indexed updater, uint256 indexed validatorVerIdx, string activeURI, string inactiveURI);
  event ValidatorNodeRequested(address indexed caller, uint256 indexed tokenId, uint256 validatorVerIdx);
  event ValidatorNodeApproved(address admin, uint256 indexed tokenId, address indexed user, uint256 validatorVerIdx);
  event ValidatorNodeRejected(address admin, uint256 indexed tokenId, address indexed user, uint256 validatorVerIdx);
  event ValidatorNodeRejectedReclaimCompleted(address indexed user, uint256 tokenId);
  event ReclaimRequested(address indexed caller, uint256 tokenId, uint256 validatorVerIdx);
  event ReclaimApproved(address indexed admin, uint256 tokenId, uint256 validatorVerIdx);
  event ReclaimRejected(address indexed admin, uint256 tokenId, uint256 validatorVerIdx);
  event ReclaimCompleted(address indexed user, uint256 tokenId);
  event ReclaimFeeUpdated(address indexed admin, uint256 newFee);
  event NFTStatusChanged(address indexed user, uint256 indexed tokenId, ValidatorStatus status);
  // ------------ EVENTS }}}

  constructor() ERC721("AlkimiValidatorNetwork", "AVN") Ownable(_msgSender()){}

  /**
   * @notice Returns the total number of NFTs that have been minted.
   * @dev This function returns the value of `_totalMinted`, which represents the total supply of minted NFTs.
   * The `_totalMinted` variable is updated every time a new NFT is minted.
   * @return totalMinted The total number of minted NFTs.
   */
  function totalSupply() public view returns (uint256) {
    return _totalMinted;
  }

  /**
   * @notice Checks if a token exists by verifying its ownership.
   * @dev This internal function checks whether a given token ID is associated with an owner.
   * It determines if the token exists by checking if the token is owned by a non-zero address.
   * @param tokenId The ID of the token to check for existence.
   * @return exists True if the token exists (i.e., is owned by a non-zero address), otherwise false.
   */
  function _tokenExists(uint256 tokenId) internal view returns (bool) {
    return ownerOf(tokenId) != address(0);
  }

  /**
   * @notice Adds a new admin to the contract.
   * @dev This function allows the contract owner to add a new admin address. The number of admins is limited by `TOTAL_ADMINS`, and the new admin 
   *      cannot be the current owner, an already added admin, or the zero address.
   * @param admin The address of the new admin to be added.
   * 
   * Requirements:
   * - The caller must be the contract owner.
   * - The new admin address must not be the contract owner.
   * - The new admin address must not already be listed as an admin.
   * - The new admin address must not be the zero address.
   * - The total number of admins must be less than `TOTAL_ADMINS`.
   * 
   * Emits:
   * - {AdminAdded} event indicating the addition of a new admin.
   * 
   * Reverts:
   * - {MaxAdminsReached} if the number of admins has reached the maximum limit.
   * - {AdminAlreadyAdded} if the admin address is already listed.
   * - {InvalidAddress} if the provided address is zero or is the owner.
   */
  function addAdmin(address admin) external onlyOwner {
    if (admin == address(0) || admin == owner()) {
      revert InvalidAddress(admin);
    }

    if (_isAdmin[admin]) {
      revert AdminAlreadyAdded(admin);
    }

    if (_admins.length >= TOTAL_ADMINS) {
      revert MaxAdminsReached();
    }

    _admins.push(admin); // Add admin address to the admins array
    _isAdmin[admin] = true;
    emit AdminAdded(admin);
  }

  /**
   * @notice Removes an existing admin from the contract.
   * @dev This function allows the contract owner to remove an existing admin address. The removed admin is replaced by the last element in the array, and then the last element is removed to maintain array order.
   * @param admin The address of the admin to be removed.
   * 
   * Requirements:
   * - The caller must be the contract owner.
   * - The address to be removed must be an existing admin.
   * 
   * Emits:
   * - {AdminRemoved} event indicating the removal of an admin.
   * 
   * Reverts:
   * - {NotAnAdmin} if the provided address is not listed as an admin.
   */
  function removeAdmin(address admin) external onlyOwner {
    if (!_isAdmin[admin]) {
      revert NotAnAdmin(admin);
    }
    uint256 index = (_admins[0] == admin) ? 0 : 1;
    _admins[index] = _admins[_admins.length - 1]; // Replace removed admin with the last element
    _admins.pop(); // Remove the last element (replaced element)
    _isAdmin[admin] = false;
    emit AdminRemoved(admin);
  }

  /**
   * @notice Returns the list of current admin addresses.
   * @dev This function returns the array of admin addresses currently managed by the contract.
   * @return admins An array of addresses representing the current admins.
   * 
   * Requirements:
   * - The caller must be the contract owner.
   */

  function getAdmins() external view onlyOwner returns (address[] memory) {
    return _admins; // Simply return the admins array
  }

  /**
   * @notice Sets the reclaim fee amount in Wei.
   * @dev This function allows an admin to update the reclaim fee. The fee is provided in Wei (1 Ether = 10^18 Wei).
   * @param newFeeInWei The new fee amount to be set, specified in Wei.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The new fee must not exceed the `maxReclaimFee`.
   * 
   * Emits:
   * - {ReclaimFeeUpdated} event indicating the fee update with the new fee in Wei.
   * 
   * Reverts:
   * - {FeeExceedsMaximum} if the new fee exceeds the maximum allowed `maxReclaimFee`.
   */
  function setReclaimFee(uint256 newFeeInWei) external onlyAdmin {
    // Ensure the new fee does not exceed the maxReclaimFee
    if (newFeeInWei > maxReclaimFee) {
      revert FeeExceedsMaximum(newFeeInWei, maxReclaimFee);
    }
    // Update the reclaim fee
    reclaimFee = newFeeInWei;
    
    // Emit the event with the new fee in wei
    emit ReclaimFeeUpdated(_msgSender(), newFeeInWei);
  }

  /**
   * @notice Adds a new validator version with specified parameters.
   * @dev This function allows the admin to create and add a new validator version to the contract. The new version is initialized with a version string, underlying token address, collateral amount, total supply, and URIs for both active and inactive states.
   * @param version The version string for the new validator.
   * @param underlying The address of the underlying token used for collateral.
   * @param collateral The amount of collateral required for the validator, in the underlying token's smallest unit (e.g., Wei for Ether-based tokens).
   * @param ts The total supply of the validator version.
   * @param activeURI The URI to be used for the active state of NFTs.
   * @param inactiveURI The URI to be used for the inactive state of NFTs.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `version` string must not be empty.
   * - The `underlying` token address must not be the zero address.
   * - The `collateral` must be greater than zero.
   * - The total supply (`ts`) must be greater than zero.
   * - The `activeURI` and `inactiveURI` must not be empty.
   * 
   * Emits:
   * - {ValidatorVersionAdded} event indicating the addition of a new validator version.
   * 
   * Reverts:
   * - {InvalidAddress} if the `underlying` address is the zero address.
   * - {InvalidArg} if the arguments to the functions is Invalid.
   */
  function addValidatorVersion(
      string calldata   version,
      address           underlying,
      uint256           collateral,
      uint256           ts,
      string calldata   activeURI,
      string calldata   inactiveURI
  ) external onlyAdmin {
    if (bytes(version).length == 0) {
      revert InvalidArg("version");
    }
    if (underlying == address(0)) {
      revert InvalidAddress(underlying);
    }
    if (collateral == 0) {
      revert InvalidArg("collateral");
    }
    if (ts == 0) {
      revert InvalidArg("ts");
    }
    if (bytes(activeURI).length == 0) {
      revert InvalidArg("activeURI");
    }
    if (bytes(inactiveURI).length == 0) {
      revert InvalidArg("inactiveURI");
    }

    validatorVersions[validatorVersionCount].version = version;
    validatorVersions[validatorVersionCount].underlying = underlying;
    validatorVersions[validatorVersionCount].collateral = collateral;
    validatorVersions[validatorVersionCount].ts = ts;
    validatorVersions[validatorVersionCount].minted = 0;
    validatorVersions[validatorVersionCount].activeURI = activeURI;
    validatorVersions[validatorVersionCount].inactiveURI = inactiveURI;
    emit ValidatorVersionAdded(_msgSender(), version, validatorVersionCount, underlying, collateral, ts);
    validatorVersionCount += 1;
  }

  /**
   * @notice Updates the total supply (TS) for an existing validator version.
   * @dev This function allows an admin to modify the total supply for a specific validator version. It ensures that the new total supply is not less than the number of NFTs that have already been minted for that version.
   * @param validatorVerIdx The index of the validator version to update.
   * @param newTs The new total supply for the validator version.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The validator version index must be valid.
   * - The new total supply must be greater than or equal to the number of minted NFTs.
   * 
   * Emits:
   * - {ValidatorTSUpdated} event indicating that the total supply was updated.
   * 
   * Reverts:
   * - {WrongValidatorVersionIndex} if the validator version index is invalid.
   * - {TotalSupplyLessThanMinted} if the new total supply is less than the number of minted NFTs.
   */
  function updateTotalSupplyForValidatorVersion(uint256 validatorVerIdx, uint256 newTs) external onlyAdmin {
    if (validatorVerIdx >= validatorVersionCount) {
      revert WrongValidatorVersionIndex(validatorVerIdx);
    }

    if (validatorVersions[validatorVerIdx].minted > newTs) {
      revert TotalSupplyLessThanMinted(newTs, validatorVersions[validatorVerIdx].minted);
    }

    // NOTE: ONLY TS and URI can be changed. For others, Admin should create a new validator version
    validatorVersions[validatorVerIdx].ts = newTs;
    emit ValidatorTSUpdated(_msgSender(), validatorVerIdx, newTs);
  }

  /**
   * @notice Updates the URIs for an existing validator version.
   * @dev This function allows the admin to update the URIs for both the active and inactive states of a validator version. Only the URIs and total supply (TS) can be updated using this function; any other changes require creating a new validator version.
   * @param validatorVerIdx The index of the validator version to update.
   * @param activeURI The new URI for the active state.
   * @param inactiveURI The new URI for the inactive state.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The validator version index (`validatorVerIdx`) must be valid.
   * - The `activeURI` and `inactiveURI` must not be empty.
   * 
   * Emits:
   * - {ValidatorURIUpdated} event indicating that the URIs were updated for the specified validator version.
   * 
   * Reverts:
   * - {WrongValidatorVersionIndex} if the validator version index is invalid.
   * - {InvalidArg} if the `activeURI` or `inactiveURI` is empty.
   */
  function updateURIValidatorVersion(uint256 validatorVerIdx, string calldata activeURI, string calldata inactiveURI) external onlyAdmin {
    if (validatorVerIdx >= validatorVersionCount) {
      revert WrongValidatorVersionIndex(validatorVerIdx);
    }
    if (bytes(activeURI).length == 0) {
      revert InvalidArg("activeURI");
    }
    if (bytes(inactiveURI).length == 0) {
      revert InvalidArg("inactiveURI");
    }

    // NOTE: ONLY TS and URI can be changed. For others, Admin should create a new validator version
    validatorVersions[validatorVerIdx].activeURI = activeURI;
    validatorVersions[validatorVerIdx].inactiveURI = inactiveURI;
    emit ValidatorURIUpdated(_msgSender(), validatorVerIdx, activeURI, inactiveURI);
  }

  /**
   * @notice Retrieves all validator versions in the contract.
   * @dev This function returns an array containing all validator versions, allowing users to view the details of each version stored in the contract.
   * @return versions An array of `ValidatorVersion` structs representing all the validator versions.
   * 
   * Requirements:
   * - None.
   * 
   * Emits:
   * - None.
   * 
   * Reverts:
   * - None.
   */
  function getAllValidatorVersions() external view returns (ValidatorVersion[] memory) {
    ValidatorVersion[] memory versions = new ValidatorVersion[](validatorVersionCount);
    for (uint256 i = 0; i < validatorVersionCount; i++) {
      versions[i] = validatorVersions[i];
    }
    return versions;
  }

  /**
   * @notice Retrieves the validator version details associated with a specific NFT.
   * @dev This function allows users to get the details of the validator version linked to a given NFT. It checks that the token ID is valid and that the NFT is associated with a valid validator version.
   * @param tokenId The ID of the NFT whose validator version details are being queried.
   * @return validatorVersion The `ValidatorVersion` struct associated with the NFT.
   * 
   * Requirements:
   * - The token ID must exist.
   * - The validator version index associated with the NFT must be valid.
   * 
   * Emits:
   * - None.
   * 
   * Reverts:
   * - {InvalidVersionMapping} if the validator version index associated with the token ID is invalid.
   */
  // NOTE : No set provided for nftToValidatorVersion. A NFT minted cannot be changed to a new validator version
  function getValidatorVersionDetailsForNFT(uint256 tokenId) external view tokenIDExists(tokenId) returns (ValidatorVersion memory) {
    uint256 versionId = nftToValidatorVersion[tokenId];

    if (versionId >= validatorVersionCount) {
      revert InvalidVersionMapping(versionId, validatorVersionCount - 1);
    }

    return validatorVersions[versionId];
  }

  /**
   * @notice Sets the status of multiple NFTs to Active and updates their token URIs.
   * @dev This function allows the admin to mark multiple NFTs as active. It updates the status of each NFT to `Active` and sets the token URI to the active URI specified for the validator version associated with each NFT.
   * @param tokenIds An array of NFT IDs whose validator statuses are being set to active.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The array of token IDs must not be empty.
   * - Each NFT must exist in the contract.
   * 
   * Emits:
   * - {NFTStatusChanged} event for each NFT whose status is updated.
   * 
   * Reverts:
   * - {InvalidArg} if the array of token IDs is empty.
   * - {TokenIDDoesNotExist} if any token ID does not exist in the contract.
   */
  function setNFTValidatorStatusesActive(uint256[] calldata tokenIds) external onlyAdmin {
    if (tokenIds.length == 0) {
      revert InvalidArg("tokenIds");
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];

      // Ensure the token ID exists
      if (!_tokenExists(tokenId)) {
        revert TokenIDDoesNotExist(tokenId);
      }

      // Set the NFT validator status to Active
      nftValidatorStatus[tokenId] = ValidatorStatus.Active;

      // Set the token URI to the active URI of the corresponding validator version
      _tokenURIs[tokenId] = validatorVersions[nftToValidatorVersion[tokenId]].activeURI;
      emit NFTStatusChanged(ownerOf(tokenId), tokenId, ValidatorStatus.Active);
    }
  }

  /**
   * @notice Sets the status of multiple NFTs to Inactive and updates their token URIs.
   * @dev This function allows the admin to mark multiple NFTs as inactive. It updates the status of each NFT to `Inactive` and sets the token URI to the inactive URI specified for the validator version associated with each NFT.
   * @param tokenIds An array of NFT IDs whose validator statuses are being set to inactive.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The array of token IDs must not be empty.
   * - Each NFT must exist in the contract.
   * 
   * Emits:
   * - {NFTStatusChanged} event for each NFT whose status is updated.
   * 
   * Reverts:
   * - {InvalidArg} if the array of token IDs is empty.
   * - {TokenIDDoesNotExist} if any token ID does not exist.
   */
  function setNFTValidatorStatusesInactive(uint256[] calldata tokenIds) external onlyAdmin {
    if (tokenIds.length == 0) {
      revert InvalidArg("tokenIds");
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];

      // Ensure the token ID exists
      if (!_tokenExists(tokenId)) {
        revert TokenIDDoesNotExist(tokenId);
      }

      // Set the NFT validator status to Inactive
      nftValidatorStatus[tokenId] = ValidatorStatus.Inactive;

      // Set the token URI to the inactive URI of the corresponding validator version
      _tokenURIs[tokenId] = validatorVersions[nftToValidatorVersion[tokenId]].inactiveURI;
      emit NFTStatusChanged(ownerOf(tokenId), tokenId, ValidatorStatus.Inactive);
    }
  }

  /**
   * @notice Sets the status of an NFT validator to Inactive and updates the token URI.
   * @dev This function allows the owner of an NFT to mark it as inactive. It updates the NFT's validator status to `Inactive` and sets the token URI to the inactive URI specified for the validator version associated with the NFT.
   * @param tokenId The ID of the NFT whose validator status is being set to inactive.
   * 
   * Requirements:
   * - The caller must be the owner of the NFT.
   * - The NFT must exist in the contract.
   * 
   * Emits:
   * - {NFTStatusChanged} event indicating the NFT's status was updated to inactive.
   * - {ValidatorNodeRequested} event indicating the NFT has been set to inactive and must go through the approval process again.
   * 
   * Reverts:
   * - {NotNFTOwner} if the caller is not the owner of the NFT.
   * - {TokenIDDoesNotExist} if the token ID does not exist in the contract.
   */
  function setNFTValidatorStatusInactive(uint256 tokenId) external {
    // caller must be the owner
    if (ownerOf(tokenId) != _msgSender()) {
      revert NotNFTOwner(_msgSender(), tokenId);
    }

    // Ensure the token ID exists
    if (!_tokenExists(tokenId)) {
      revert TokenIDDoesNotExist(tokenId);
    }

    // Set the NFT validator status to Inactive
    nftValidatorStatus[tokenId] = ValidatorStatus.Inactive;
    // Set the token URI to the inactive URI of the corresponding validator version
    _tokenURIs[tokenId] = validatorVersions[nftToValidatorVersion[tokenId]].inactiveURI;

    // add the user to the approval list... he has to go through the approval process again  
    approvalRequests[tokenId].user = _msgSender();
    approvalRequests[tokenId].status = RequestStatus.Pending;
    approvalRequests[tokenId].reason = "";
    emit NFTStatusChanged(_msgSender(), tokenId, ValidatorStatus.Inactive);
    emit ValidatorNodeRequested(_msgSender(), tokenId, nftToValidatorVersion[tokenId]);
  }

  /**
   * @notice Admin function to mint a specified number of NFTs for a user.
   * @dev This function allows an admin to mint NFTs for a specific user from a particular validator version. It ensures that the total number of minted NFTs does not exceed the total supply for the validator version.
   * @param validatorVerIdx The index of the validator version from which the NFTs are to be minted.
   * @param user The address of the user receiving the NFTs.
   * @param noOfNFTs The number of NFTs to mint for the user.
   * @param uri The URI for the metadata associated with the minted NFTs.
   * @param status The status of the validator for the minted NFTs.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `validatorVerIdx` must be a valid index.
   * - The `uri` must not be empty.
   * - The `noOfNFTs` must be greater than zero.
   * - The `user` must not be the zero address.
   * - The `status` must not be `Invalid`.
   * 
   * Emits:
   * - None.
   * 
   * Reverts:
   * - {WrongValidatorVersionIndex} if the validator version index is invalid.
   * - {InvalidArg} if the `uri` or `noOfNFTs` is invalid.
   * - {InvalidAddress} if the `user` is the zero address.
   * - {InvalidValidatorStatus} if the validator status is `Invalid`.
   * - {MintingExceedsTotalSupply} if minting the requested number of NFTs exceeds the total supply for the validator version.
   * - {MintingFailed} if the minting operation fails.
   */
  function adminMint(uint256 validatorVerIdx, address user, uint256 noOfNFTs, string calldata uri, ValidatorStatus status) external nonReentrant onlyAdmin {
    if (validatorVerIdx >= validatorVersionCount) {
      revert WrongValidatorVersionIndex(validatorVerIdx);
    }
    if (bytes(uri).length == 0) {
      revert InvalidArg("uri");
    }
    if (noOfNFTs == 0) {
      revert InvalidArg("noOfNFTs");
    }
    if (user == address(0)) {
      revert InvalidAddress(user);
    }
    if (status == ValidatorStatus.Invalid) {
      revert InvalidValidatorStatus();
    }

    uint256 totalMintReq = validatorVersions[validatorVerIdx].minted + noOfNFTs;
    if (totalMintReq > validatorVersions[validatorVerIdx].ts) {
      revert MintingExceedsTotalSupply(validatorVerIdx, totalMintReq, validatorVersions[validatorVerIdx].ts);
    }

    bool success = _internalMint(validatorVerIdx, user, noOfNFTs, uri, status);
    if (!success) {
      revert MintingFailed(validatorVerIdx, user, noOfNFTs, uri, status);
    }
  }

  /**
   * @notice Admin function to mint NFTs for multiple users.
   * @dev This function allows the admin to mint 1 NFT per user from the specified validator version. It checks that the total supply is not exceeded and ensures each user receives exactly 1 NFT.
   * @param validatorVerIdx The index of the validator version to mint from.
   * @param users Array of user addresses, each of whom will receive 1 NFT.
   * @param uri The URI for the metadata associated with the NFTs.
   * @param status The status of the validator for the minted NFTs.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `validatorVerIdx` must be valid.
   * - The `uri` must not be empty.
   * - The `users` array must not be empty.
   * - The `status` must not be `Invalid`.
   * - Each `user` address must not be the zero address.
   * - The total number of NFTs being minted must not exceed the total supply for the validator version.
   * 
   * Emits:
   * - None.
   * 
   * Reverts:
   * - {WrongValidatorVersionIndex} if the validator version index is invalid.
   * - {InvalidArg} if the `uri` is empty or `users` array is empty.
   * - {InvalidValidatorStatus} if the validator status is `Invalid`.
   * - {MintingExceedsTotalSupply} if minting the requested number of NFTs exceeds the total supply for the validator version.
   * - {InvalidAddress} if any `user` is the zero address.
   * - {MintingFailed} if the minting operation fails for any user.
   */
  function adminMint(uint256 validatorVerIdx, address[] calldata users, string calldata uri, ValidatorStatus status) 
      external nonReentrant onlyAdmin 
  {
    if (validatorVerIdx >= validatorVersionCount) {
      revert WrongValidatorVersionIndex(validatorVerIdx);
    }

    if (bytes(uri).length == 0) {
      revert InvalidArg("uri");
    }

    if (users.length == 0) {
      revert InvalidArg("users");
    }

    if (status == ValidatorStatus.Invalid) {
      revert InvalidValidatorStatus();
    }

    uint256 totalMintReq = validatorVersions[validatorVerIdx].minted + users.length;
    if (totalMintReq > validatorVersions[validatorVerIdx].ts) {
      revert MintingExceedsTotalSupply(validatorVerIdx, totalMintReq, validatorVersions[validatorVerIdx].ts);
    }

    for (uint256 i = 0; i < users.length; i++) {
      address user = users[i];
      if (user == address(0)) {
        revert InvalidAddress(user);
      }

      // Mint 1 NFT per user
      bool success = _internalMint(validatorVerIdx, user, 1, uri, status);
      if (!success) {
        revert MintingFailed(validatorVerIdx, user, 1, uri, status);
      }
    }
  }

  /**
   * @notice Internal function to mint NFTs for a user from a specific validator version.
   * @dev This function mints the specified number of NFTs to a user, verifies the mint was successful, and updates the minted count for the validator version.
   * It assigns the NFT metadata URI, updates the validator status, and handles approval requests if the status is not active.
   * @param validatorVerIdx The index of the validator version from which the NFTs are being minted.
   * @param user The address of the user receiving the NFTs.
   * @param noOfNFTs The number of NFTs to mint for the user.
   * @param uri The URI for the metadata associated with the minted NFTs.
   * @param status The status of the validator for the minted NFTs.
   * @return success Returns `true` if the minting was successful, otherwise returns `false`.
   */
  function _internalMint(uint256 validatorVerIdx, address user, uint256 noOfNFTs, string memory uri, ValidatorStatus status) private returns (bool) {
    if (validatorVerIdx >= validatorVersionCount) {
      // Invalid validator version
      return false;
    }
    if (bytes(uri).length == 0) {
      return false;
    }
    if (validatorVersions[validatorVerIdx].minted >= validatorVersions[validatorVerIdx].ts) {
      // Cannot mint more than ts
      return false;
    }

    for (uint256 i = 0; i < noOfNFTs; i++) {
      // Get the user's balance before mint
      uint256 previousBalance = balanceOf(user);

      _safeMint(user, _totalMinted); // mint the NFT to the user

      // Validate successful mint
      if (balanceOf(user) != previousBalance + 1) {
        return false;
      }

      validatorVersions[validatorVerIdx].minted++;
      _tokenURIs[_totalMinted] = uri;

      reclaimable[_totalMinted] = true;
      nftToValidatorVersion[_totalMinted] = validatorVerIdx;
      nftValidatorStatus[_totalMinted] = status;

      emit NFTMinted(user, _totalMinted, validatorVerIdx);

      // Only add to approvalRequests if the status is not active
      if (status != ValidatorStatus.Active) {
        approvalRequests[_totalMinted].user = user;
        approvalRequests[_totalMinted].status = RequestStatus.Pending;
        approvalRequests[_totalMinted].reason = "";
        emit ValidatorNodeRequested(user, _totalMinted, validatorVerIdx);
      }

      _totalMinted++;  // Increment the total minted count
    }
    return true;
  }

  /**
   * @notice Internal function to update the ownership of an NFT with a soulbound transfer restriction.
   * @dev This function overrides the base `_update` function to enforce the soulbound property, preventing transfers by disallowing updates if both `from` and `to` addresses are non-zero.
   * @param to The address to which the token is being updated (new owner).
   * @param tokenId The ID of the token being updated.
   * @param auth The authorized address responsible for initiating the update.
   * @return previousOwner Returns the previous owner of the token before the update.
   * 
   * Reverts:
   * - If both `from` and `to` addresses are non-zero, indicating a soulbound transfer attempt.
   */
  function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
    // Restricts the transfer of Soulbound tokens
    address from = _ownerOf(tokenId);
    if (from != address(0) && to != address(0)) {
      revert("Soulbound: Transfer failed");
    }

    return super._update(to, tokenId, auth);
  }

  /**
   * @notice Sets the treasury wallet address.
   * @dev This function allows the contract owner to update the treasury wallet address. The new address must not be the zero address.
   * @param walletAddr The new address for the treasury wallet.
   * 
   * Requirements:
   * - The caller must be the contract owner.
   * - The `walletAddr` must not be the zero address.
   * 
   * Emits:
   * - {TreasuryWalletSet} event indicating the treasury wallet address was updated.
   * 
   * Reverts:
   * - {InvalidAddress} if the provided `walletAddr` is the zero address.
   */
  function setTreasuryWallet(address walletAddr) external onlyOwner {
    if (walletAddr == address(0)) {
      revert InvalidAddress(walletAddr);
    }
    _treasuryWallet = walletAddr;
    emit TreasuryWalletSet(walletAddr);
  }

  /**
   * @notice Retrieves the current treasury wallet address.
   * @dev This function allows only the contract owner to retrieve the treasury wallet address.
   * @return treasuryWallet The address of the current treasury wallet.
   */
  function getTreasuryWallet() external view onlyOwner returns (address) {
    return _treasuryWallet;
  }

  /**
   * @notice Sets the token URIs for multiple NFTs.
   * @dev This function allows an admin to update the metadata URI for a batch of NFTs. Each token in the `tokenIds` array must exist in the contract.
   * @param tokenIds An array of token IDs for which the URIs will be updated.
   * @param uriStr The new URI to set for all the provided tokens.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `tokenIds` array must not be empty.
   * - The `uriStr` must not be empty.
   * - Each token in the `tokenIds` array must exist.
   * 
   * Emits:
   * - None.
   * 
   * Reverts:
   * - {InvalidArg} if the `uriStr` is empty or `tokenIds` array is empty.
   * - {TokenIDDoesNotExist} if any token ID in the array does not exist.
   */
  function setTokenURIs(uint256[] calldata tokenIds, string calldata uriStr) external onlyAdmin {
    if (tokenIds.length == 0) {
      revert InvalidArg("tokenIds");
    }
    if (bytes(uriStr).length == 0) {
      revert InvalidArg("uriStr");
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      if (!_tokenExists(tokenIds[i])) {
        revert TokenIDDoesNotExist(tokenIds[i]);
      }

      _tokenURIs[tokenIds[i]] = uriStr;
    }
  }

  /**
   * @notice Returns the metadata URI for a specific token.
   * @dev If the token URI is set in the `_tokenURIs` mapping, it returns that value. Otherwise, it returns the inactive URI associated with the validator version of the token.
   * @param tokenId The ID of the token for which the URI is requested.
   * @return uri The metadata URI for the specified token.
   * 
   * Requirements:
   * - The `tokenId` must exist.
   */
  function tokenURI(uint256 tokenId) public view virtual override tokenIDExists(tokenId) returns (string memory) {
    // Override tokenURI to return the URI from mapping (if not set)
    if (bytes(_tokenURIs[tokenId]).length > 0) {
      return _tokenURIs[tokenId];
    } else {
      return validatorVersions[nftToValidatorVersion[tokenId]].inactiveURI;
    }
  }

  // ----------------- APPROVAL {{{

  /**
   * @notice Allows users to request the minting of validator node NFTs by providing the required collateral.
   * @dev This function mints NFTs for users from a specific validator version, provided the collateral is successfully transferred to the treasury wallet.
   *      It ensures that the minting does not exceed the total supply for the specified validator version. The function reverts if the transfer or minting process fails.
   * @param validatorVerIdx The index of the validator version from which the NFTs are to be minted.
   * @param noOfNFTs The number of NFTs to mint.
   * 
   * Requirements:
   * - `validatorVerIdx` must be valid and less than the total count of validator versions.
   * - `noOfNFTs` must be greater than 0.
   * - The total minted NFTs must not exceed the validator version's total supply (`ts`).
   * - The treasury wallet must be set.
   * - The user must have approved sufficient token allowance for the collateral transfer.
   * 
   * Emits:
   * - {NFTMinted} event for each minted NFT.
   * - {ValidatorNodeRequested} event for each minted NFT with status inactive.
   * 
   * Reverts:
   * - {WrongValidatorVersionIndex} if the validator version index is invalid.
   * - {InvalidArg} if the number of NFTs is zero or less.
   * - {MintingExceedsTotalSupply} if minting exceeds the total supply for the validator version.
   * - {InvalidAddress} if the treasury wallet is not set.
   * - {InsufficientAllowance} if the user does not have enough allowance for the collateral transfer.
   * - {validatorNodeRequestFailed} if the minting operation fails.
   */
  // Function for users to request a validator node
  function validatorNodeRequest(uint256 validatorVerIdx, uint256 noOfNFTs) external nonReentrant {
    if (validatorVerIdx >= validatorVersionCount) {
      revert WrongValidatorVersionIndex(validatorVerIdx);
    }

    if (noOfNFTs == 0) {
      revert InvalidArg("noOfNFTs");
    }

    uint256 totalMintReq = validatorVersions[validatorVerIdx].minted + noOfNFTs;
    if (totalMintReq > validatorVersions[validatorVerIdx].ts) {
      revert MintingExceedsTotalSupply(validatorVerIdx, totalMintReq, validatorVersions[validatorVerIdx].ts);
    }

    if (_treasuryWallet == address(0)) {
      revert InvalidAddress(_treasuryWallet);
    }

    address underlyingToken = validatorVersions[validatorVerIdx].underlying;
    uint256 collateral = validatorVersions[validatorVerIdx].collateral * noOfNFTs;

    // Transfer tokens from the user to the treasury wallet
    uint256 allowance = IERC20(underlyingToken).allowance(_msgSender(), address(this));
    if (allowance < collateral) {
      revert InsufficientAllowance(_msgSender(), address(this), collateral, allowance);
    }

    // transfer collateral
    IERC20(underlyingToken).safeTransferFrom(_msgSender(), _treasuryWallet, collateral);

    // Perform minting
    bool mintSuccess = _internalMint(validatorVerIdx, _msgSender(), noOfNFTs, validatorVersions[validatorVerIdx].inactiveURI, ValidatorStatus.Inactive);
    // Check if both operations were successful
    if (!mintSuccess) {
      revert validatorNodeRequestFailed();
    }
  }

  /**
   * @notice Approves and processes validator node NFT requests.
   * @dev This function updates the metadata URI and sets the status of NFTs to active for tokens with pending approval requests. After processing, it emits an event and deletes the approval request.
   * @param tokenIds An array of token IDs to be approved.
   * @param uriStr The new URI to set for each approved token.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `tokenIds` array must not be empty.
   * - Each token ID must have a pending approval request.
   * - The `uriStr` must not be empty.
   * 
   * Emits:
   * - {ValidatorNodeApproved} event for each approved token request.
   * 
   * Reverts:
   * - {InvalidArg} if the `uriStr` is empty or `tokenIds` array is empty.
   * - {IncorrectRequestStatus} if any token ID does not have a pending approval request.
   */
  function approveValidatorNodeRequests(uint256[] calldata tokenIds, string calldata uriStr) external onlyAdmin {
    if (tokenIds.length == 0) {
      revert InvalidArg("tokenIds");
    }
    if (bytes(uriStr).length == 0) {
      revert InvalidArg("uriStr");
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      if (approvalRequests[tokenId].status != RequestStatus.Pending) {
        revert IncorrectRequestStatus(tokenId, approvalRequests[tokenId].status, RequestStatus.Pending);
      }

      // Update the uriStr for each token
      _tokenURIs[tokenId] = uriStr;

      // Set the NFT status to active
      nftValidatorStatus[tokenId] = ValidatorStatus.Active;

      // Emit event for each approval
      emit ValidatorNodeApproved(_msgSender(), tokenId, approvalRequests[tokenId].user, nftToValidatorVersion[tokenId]);

      // Delete the approval request after processing
      delete approvalRequests[tokenId];
    }
  }

  /**
   * @notice Rejects pending validator node NFT requests and records the reason for rejection.
   * @dev This function updates the status of NFTs with pending approval requests to rejected and records the provided reason for each rejection.
   * @param tokenIds An array of token IDs whose approval requests are to be rejected.
   * @param reason The reason for rejecting the approval requests for the provided token IDs.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `tokenIds` array must not be empty.
   * - Each token ID in the `tokenIds` array must have a pending approval request.
   * - The `reason` must not be an empty string.
   * 
   * Emits:
   * - {ValidatorNodeRejected} event for each rejected token request.
   * 
   * Reverts:
   * - {InvalidArg} if the `reason` is an empty string or `tokenIds` array is empty.
   * - {IncorrectRequestStatus} if any token ID does not have a pending approval request.
   */
  function rejectValidatorNodeRequests(uint256[] calldata tokenIds, string calldata reason) external onlyAdmin {
    if (tokenIds.length == 0) {
      revert InvalidArg("tokenIds");
    }
    if (bytes(reason).length == 0) {
      revert InvalidArg("reason");
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      
      if (approvalRequests[tokenId].status != RequestStatus.Pending) {
        revert IncorrectRequestStatus(tokenId, approvalRequests[tokenId].status, RequestStatus.Pending);
      }

      // Update the request status to Rejected
      approvalRequests[tokenId].status = RequestStatus.Rejected;
      
      // Set the rejection reason for each token
      approvalRequests[tokenId].reason = reason;
      
      // Emit event for each token ID rejection
      emit ValidatorNodeRejected(_msgSender(), tokenId, approvalRequests[tokenId].user, nftToValidatorVersion[tokenId]);
    }
  }

  /**
   * @notice Retrieves the status and reason for a validator node NFT request.
   * @dev This function allows users to check the current status of their request and the reason if it was rejected. It returns the status and rejection reason associated with the specified token ID.
   * @param tokenId The ID of the token for which the request status is being queried.
   * @return status The current status of the request (Pending, Approved, or Rejected).
   * @return reason The reason for rejection if the status is Rejected, or an empty string if the request is Pending or Approved.
   * 
   * Requirements:
   * - The `tokenId` must exist.
   */
  function getValidatorNodeRequestStatus(uint256 tokenId) external view returns (RequestStatus, string memory) {
    return (approvalRequests[tokenId].status, approvalRequests[tokenId].reason);
  }

  /**
   * @notice Allows the owner of a rejected validator node NFT to reclaim the collateral.
   * @dev This function enables users to reclaim collateral for NFTs that have been rejected. It burns the NFT, resets related state, and transfers the collateral back to the owner.
   * @param tokenId The ID of the token for which the collateral is being reclaimed.
   * 
   * Requirements:
   * - The request status of the NFT must be `Rejected`.
   * - The caller must be the owner of the NFT.
   * - The NFT must be marked as reclaimable.
   * 
   * Emits:
   * - {NFTBurned} event indicating the token has been burned.
   * - {ValidatorNodeRejectedReclaimCompleted} event indicating the collateral has been transferred back to the owner.
   * 
   * Reverts:
   * - {IncorrectRequestStatus} if the request status is not `Rejected`.
   * - {NotNFTOwner} if the caller is not the owner of the NFT.
   * - {NotReclaimable} if the NFT is not marked as reclaimable.
   * - If the collateral transfer fails.
   */
  function reclaimValidatorNodeRequestRejectedCollateral(uint256 tokenId) external nonReentrant {
    if (approvalRequests[tokenId].status != RequestStatus.Rejected) {
      revert IncorrectRequestStatus(tokenId, approvalRequests[tokenId].status, RequestStatus.Rejected);
    }
    if (ownerOf(tokenId) != _msgSender()) {
      revert NotNFTOwner(_msgSender(), tokenId);
    }
    if (!reclaimable[tokenId]) {
      revert NotReclaimable(tokenId);
    }

    // Get the collateral details
    uint256 valIdx = nftToValidatorVersion[tokenId];
    uint256 collateral = validatorVersions[valIdx].collateral;
    address underlyingToken = validatorVersions[valIdx].underlying;

    // Burn the NFT before transferring collateral
    _burn(tokenId);
    emit NFTBurned(_msgSender(), tokenId);

    // Reset values
    reclaimable[tokenId] = false;
    nftToValidatorVersion[tokenId] = type(uint256).max;
    nftValidatorStatus[tokenId] = ValidatorStatus.Invalid;
    delete approvalRequests[tokenId];

    // transfer collateral
    IERC20(underlyingToken).safeTransfer(_msgSender(), collateral);

    emit ValidatorNodeRejectedReclaimCompleted(_msgSender(), tokenId);
  }

  // ----------------- APPROVAL }}}

  // ----------------- RECLAIM {{{

  /**
   * @notice Sets the reclaimable status for a list of NFT tokens.
   * @dev This function allows the admin to update the reclaimable flag for multiple token IDs. It verifies that each token ID exists before updating its status.
   * @param tokenIds An array of token IDs for which the reclaimable status is being set.
   * @param flag The reclaimable status to set for the provided token IDs (true or false).
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `tokenIds` array must not be empty.
   * - Each token ID in the `tokenIds` array must exist.
   * 
   * Reverts:
   * - {InvalidArg} if the `tokenIds` array is empty.
   * - {TokenIDDoesNotExist} if any token ID does not exist.
   */
  function setReclaimable(uint256[] calldata tokenIds, bool flag) external onlyAdmin {
    if (tokenIds.length == 0) {
      revert InvalidArg("tokenIds");
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      if (!_tokenExists(tokenIds[i])) {
        revert TokenIDDoesNotExist(tokenIds[i]);
      }
      reclaimable[tokenIds[i]] = flag;
    }
  }

  /**
   * @notice Initiates a reclaim request for the collateral associated with a specific NFT.
   * @dev This function allows the owner of a reclaimable NFT to request the return of collateral by sending the required reclaim fee.
   *      It verifies ownership, ensures the reclaim request is not already pending or approved, and processes the request if the correct fee is provided.
   * @param tokenId The ID of the token for which the reclaim request is being made.
   * 
   * Requirements:
   * - The token ID must exist.
   * - The caller must be the owner of the NFT.
   * - The NFT must be marked as reclaimable.
   * - The reclaim request must not be in `Pending` or `Approved` state.
   * - The correct reclaim fee must be sent with the request.
   * 
   * Emits:
   * - {ReclaimRequested} event indicating a new reclaim request has been made.
   * 
   * Reverts:
   * - {NotNFTOwner} if the caller is not the owner of the NFT.
   * - {NotReclaimable} if the NFT is not marked as reclaimable.
   * - If a reclaim request is already in `Pending` or `Approved` state.
   * - {IncorrectReclaimFeeSent} if the incorrect reclaim fee is provided.
   */
  function requestReclaimCollateral(uint256 tokenId) external payable tokenIDExists(tokenId) {
    if (ownerOf(tokenId) != _msgSender()) {
      revert NotNFTOwner(_msgSender(), tokenId);
    }

    if (!reclaimable[tokenId]) {
      revert NotReclaimable(tokenId);
    }

    require(reclaimRequests[tokenId].status != RequestStatus.Pending, "Reclaim already in Pending state");
    require(reclaimRequests[tokenId].status != RequestStatus.Approved, "Reclaim already in Approved state");

    // NOTE: If the earlier request is in Rejected state, the use must be able to go through the reclaim again

    // Check if the correct reclaim fee is sent
    if (msg.value != reclaimFee) {
      revert IncorrectReclaimFeeSent(msg.value, reclaimFee);
    }

    // Set reclaim request details
    reclaimRequests[tokenId].user = _msgSender();
    reclaimRequests[tokenId].status = RequestStatus.Pending;
    reclaimRequests[tokenId].reason = "";

    // Emit reclaim requested event
    emit ReclaimRequested(_msgSender(), tokenId, nftToValidatorVersion[tokenId]);
  }

  /**
   * @notice Approves pending reclaim requests for a list of NFT tokens.
   * @dev This function allows the admin to approve reclaim requests for multiple tokens. It updates the status of each request to `Approved`
   *      if the request is pending and the token exists. It emits an event for each approved request.
   * @param tokenIds An array of token IDs whose reclaim requests are to be approved.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `tokenIds` array must not be empty.
   * - Each token ID in the `tokenIds` array must exist.
   * - Each reclaim request associated with the token ID must be in the `Pending` state.
   * 
   * Emits:
   * - {ReclaimApproved} event for each token ID whose reclaim request is approved.
   * 
   * Reverts:
   * - {InvalidArg} if the `tokenIds` array is empty.
   * - {TokenIDDoesNotExist} if any token ID does not exist.
   * - {IncorrectRequestStatus} if any reclaim request is not in the `Pending` state.
   */
  function approveReclaimRequests(uint256[] calldata tokenIds) external onlyAdmin {
    if (tokenIds.length == 0) {
      revert InvalidArg("tokenIds");
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];

      // Check if the token exists
      if (!_tokenExists(tokenId)) {
        revert TokenIDDoesNotExist(tokenId);
      }

      if (reclaimRequests[tokenId].status != RequestStatus.Pending) {
        revert IncorrectRequestStatus(tokenId, reclaimRequests[tokenId].status, RequestStatus.Pending);
      }

      // Approve the reclaim request by updating its status
      reclaimRequests[tokenId].status = RequestStatus.Approved;
      emit ReclaimApproved(_msgSender(), tokenId, nftToValidatorVersion[tokenId]);
    }
  }

  /**
   * @notice Claims back the collateral for a specific NFT by the owner, provided that the reclaim request is approved.
   * @dev This function allows the owner of an NFT to reclaim the collateral if the reclaim request is approved and the NFT is marked as reclaimable. The NFT is burned before the collateral is transferred back to the user.
   * @param tokenId The ID of the NFT for which the collateral is being reclaimed.
   * 
   * Requirements:
   * - The caller must be the owner of the NFT.
   * - The NFT must be marked as reclaimable.
   * - The reclaim request for the NFT must be approved.
   * 
   * Emits:
   * - {NFTBurned} event indicating the NFT has been burned.
   * - {ReclaimCompleted} event indicating the collateral has been transferred to the owner.
   * 
   * Reverts:
   * - {NotNFTOwner} if the caller is not the owner of the NFT.
   * - {NotReclaimable} if the NFT is not marked as reclaimable.
   * - {IncorrectRequestStatus} if the reclaim request is not approved.
   * - If the collateral transfer fails.
   */
  function reclaimCollateral(uint256 tokenId) external nonReentrant tokenIDExists(tokenId) {
    // Function for users to reclaim collateral
    if (ownerOf(tokenId) != _msgSender()) {
        revert NotNFTOwner(_msgSender(), tokenId);
    }
    if (!reclaimable[tokenId]) {
        revert NotReclaimable(tokenId);
    }
    if (reclaimRequests[tokenId].status != RequestStatus.Approved) {
        revert IncorrectRequestStatus(tokenId, reclaimRequests[tokenId].status, RequestStatus.Approved);
    }

    // Get the validator version for the NFT
    uint256 validatorIdx = nftToValidatorVersion[tokenId];
    address underlyingToken = validatorVersions[validatorIdx].underlying;
    uint256 collateral = validatorVersions[validatorIdx].collateral;

    // Burn the NFT before transferring collateral
    _burn(tokenId);
    emit NFTBurned(_msgSender(), tokenId);

    // Reset values
    reclaimable[tokenId] = false;
    nftToValidatorVersion[tokenId] = type(uint256).max;
    nftValidatorStatus[tokenId] = ValidatorStatus.Invalid;

    // delete the record once everything is settled
    delete reclaimRequests[tokenId];

    // transfer collateral
    IERC20(underlyingToken).safeTransfer(_msgSender(), collateral);

    emit ReclaimCompleted(_msgSender(), tokenId);
  }

  /**
   * @notice Rejects reclaim requests for multiple NFTs and sets the reason for rejection for each one.
   * @dev This function allows the admin to reject reclaim requests for an array of token IDs. It updates the request status
   *      to `Rejected` and records the reason for rejection for each token. The reclaimable flag for the NFTs is not automatically
   *      set to `False` and must be managed manually if needed.
   * @param tokenIds An array of token IDs whose reclaim requests are being rejected.
   * @param reason A string providing the reason for rejecting the reclaim requests.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `tokenIds` array must not be empty.
   * - Each reclaim request must be in the `Pending` state.
   * - The `reason` must not be an empty string.
   * 
   * Emits:
   * - {ReclaimRejected} event for each token ID indicating the rejection of the reclaim request.
   * 
   * Reverts:
   * - {InvalidArg} if the `reason` is an empty string or `tokenIds` array is empty.
   * - {IncorrectRequestStatus} if any reclaim request is not in the `Pending` state.
   */
  function rejectReclaimRequests(uint256[] calldata tokenIds, string calldata reason) external onlyAdmin {
    if (tokenIds.length == 0) {
      revert InvalidArg("tokenIds");
    }
    if (bytes(reason).length == 0) {
      revert InvalidArg("reason");
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];

      // Check if token ID exists and the reclaim request is in Pending status
      if (reclaimRequests[tokenId].status != RequestStatus.Pending) {
        revert IncorrectRequestStatus(tokenId, reclaimRequests[tokenId].status, RequestStatus.Pending);
      }

      // Reject the reclaim request and set the reason
      reclaimRequests[tokenId].status = RequestStatus.Rejected;
      reclaimRequests[tokenId].reason = reason;

      // NOTE: The request is rejected but the reclaimable flag is not set to False. This has to be done manually by Admin if required

      // Emit event for each token ID
      emit ReclaimRejected(_msgSender(), tokenId, nftToValidatorVersion[tokenId]);
    }
  }

  /**
   * @notice Retrieves the status and reason of a reclaim request for a specific NFT.
   * @dev This function provides the current status and reason for a reclaim request associated with a given token ID. 
   *      It is a read-only function and does not modify the contract state.
   * @param tokenId The ID of the token for which the reclaim request status is being queried.
   * @return status The current status of the reclaim request (e.g., Pending, Approved, Rejected).
   * @return reason The reason provided for the reclaim request status, such as the reason for rejection if applicable.
   * 
   * Requirements:
   * - The token ID must exist.
   */
  function getReclaimRequestStatus(uint256 tokenId) external view returns (RequestStatus, string memory) {
    return (reclaimRequests[tokenId].status, reclaimRequests[tokenId].reason);
  }
  // ----------------- RECLAIM }}}

  // ----------------- RESCUE {{{

  /**
   * @notice Withdraws all Ether from the contract and transfers it to a specified address.
   * @dev This function allows the admin to rescue all Ether from the contract. The entire Ether balance is transferred to the specified address.
   * @param to The address to which the Ether will be sent.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `to` address must not be the zero address.
   * - The Ether transfer must be successful.
   * 
   * Reverts:
   * - {InvalidAddress} if the `to` address is the zero address.
   * - {EtherTransferFailed} if the Ether transfer fails.
   */
  function rescue(address to) public nonReentrant onlyAdmin {
    if (to == address(0)) {
      revert InvalidAddress(to);
    }
    // withdraw accidentally sent native currency. Can also be used to withdraw reclaim fees
    uint256 amount = address(this).balance;
    (bool success, ) = payable(to).call{value: amount}("");
    if (!success) {
      revert EtherTransferFailed(to, amount);
    }
  }

  /**
   * @notice Withdraws all ERC20 tokens from the contract and transfers them to a specified address.
   * @dev This function allows the admin to rescue ERC20 tokens that were accidentally sent to the contract. All tokens of the specified type held by the contract are transferred to the specified address.
   * @param token The address of the ERC20 token to be rescued.
   * @param to The address to which the ERC20 tokens will be sent.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `token` address must not be the zero address.
   * - The `to` address must not be the zero address.
   * - The contract must hold a balance of the specified token.
   * 
   * Reverts:
   * - {InvalidAddress} if the `token` or `to` address is the zero address.
   */
  function rescueToken(address token, address to) public nonReentrant onlyAdmin {
    // withdraw accidentally sent erc20 tokens
    if (token == address(0)) {
      revert InvalidAddress(token);
    }

    if (to == address(0)) {
      revert InvalidAddress(to);
    }

    uint256 amount = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransfer(to, amount);
  }

  /**
   * @notice Withdraws an ERC721 NFT from the contract and transfers it to a specified address.
   * @dev This function allows the admin to rescue an NFT that was accidentally sent to the contract. The specified NFT is transferred from the contract to the provided address.
   * @param receiver The address to which the NFT will be sent.
   * @param nft The address of the ERC721 NFT contract.
   * @param id The ID of the NFT to be rescued.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The `receiver` address must not be the zero address.
   * - The `nft` contract address must not be the zero address.
   * - The contract must own the NFT with the specified `id`.
   * 
   * Reverts:
   * - {InvalidAddress} if the `receiver` or `nft` address is the zero address.
   * - {NotNFTOwner} if the contract does not own the NFT with the specified `id`.
   */
  function rescueNFT(address receiver, address nft, uint256 id) public nonReentrant onlyAdmin {
    // withdraw accidentally sent nft
    if (receiver == address(0)) {
      revert InvalidAddress(receiver);
    }
    if (nft == address(0)) {
      revert InvalidAddress(nft);
    }

    // Check if the contract owns the NFT
    if (IERC721(nft).ownerOf(id) != address(this)) {
      revert NotNFTOwner(nft, id);
    }

    // Execute the transfer if the ownership check passes
    IERC721(nft).safeTransferFrom(address(this), receiver, id);
  }

  // ----------------- RESCUE }}}

  // ----------------- Ownership Handling {{{

  /**
   * @notice Disables the ability to renounce ownership of the contract.
   * @dev This function is overridden to prevent the contract owner from renouncing ownership.
   *      Calling this function will always revert with the message "RenounceOwnership is disabled".
   */
  function renounceOwnership() public view override onlyOwner {
    revert("RenounceOwnership is disabled");
  }

  // ----------------- Ownership Handling }}}

  // ----------------- Request List Handling {{{

  /**
   * @notice Admin function to update the status and rejection reason for a specific token's approval request.
   * @dev This function allows the admin to update the `status` and `reason` fields in the `approvalRequests` mapping for a given token ID.
   * @param tokenId The ID of the token whose approval request is being updated.
   * @param status The new status to set (e.g., Pending, Approved, Rejected).
   * @param reason The reason for the status update (e.g., rejection reason).
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The token ID must exist in the `approvalRequests`.
   * 
   * Reverts:
   * - If the token ID does not exist.
   */
  function setApprovalRequestStatus(uint256 tokenId, RequestStatus status, string calldata reason) external onlyAdmin {
    if (approvalRequests[tokenId].user == address(0)) {
      revert TokenIDDoesNotExist(tokenId);
    }

    approvalRequests[tokenId].status = status;
    approvalRequests[tokenId].reason = reason;
  }

  /**
   * @notice Admin function to update the status and rejection reason for a specific token's reclaim request.
   * @dev This function allows the admin to update the `status` and `reason` fields in the `reclaimRequests` mapping for a given token ID.
   * @param tokenId The ID of the token whose reclaim request is being updated.
   * @param status The new status to set (e.g., Pending, Approved, Rejected).
   * @param reason The reason for the status update (e.g., rejection reason).
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The token ID must exist in the `reclaimRequests`.
   * 
   * Reverts:
   * - If the token ID does not exist.
   */
  function setReclaimRequestStatus(uint256 tokenId, RequestStatus status, string calldata reason) external onlyAdmin {
    if (reclaimRequests[tokenId].user == address(0)) {
      revert TokenIDDoesNotExist(tokenId);
    }

    reclaimRequests[tokenId].status = status;
    reclaimRequests[tokenId].reason = reason;
  }

  /**
   * @notice Admin function to delete an approval request for a specific token.
   * @dev This function allows the admin to remove an approval request from the `approvalRequests` mapping for a given token ID.
   * @param tokenId The ID of the token whose approval request is to be deleted.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The token ID must exist in the `approvalRequests`.
   * 
   * Reverts:
   * - {TokenIDDoesNotExist} if the token ID does not exist in the `approvalRequests`.
   */
  function deleteApprovalRequest(uint256 tokenId) external onlyAdmin {
    if (approvalRequests[tokenId].user == address(0)) {
      revert TokenIDDoesNotExist(tokenId);
    }
    delete approvalRequests[tokenId];
  }

  /**
   * @notice Admin function to delete a reclaim request for a specific token.
   * @dev This function allows the admin to remove a reclaim request from the `reclaimRequests` mapping for a given token ID.
   * @param tokenId The ID of the token whose reclaim request is to be deleted.
   * 
   * Requirements:
   * - The caller must be an admin.
   * - The token ID must exist in the `reclaimRequests`.
   * 
   * Reverts:
   * - {TokenIDDoesNotExist} if the token ID does not exist in the `reclaimRequests`.
   */
  function deleteReclaimRequest(uint256 tokenId) external onlyAdmin {
    if (reclaimRequests[tokenId].user == address(0)) {
      revert TokenIDDoesNotExist(tokenId);
    }
    delete reclaimRequests[tokenId];
  }

  // ----------------- Request List Handling }}}

}