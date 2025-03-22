// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/IERC4906.sol";

/**
 * @dev Implementation of the NFT Royalty Standard, a standardized way to retrieve royalty payment information.
 *
 * Royalty information can be specified globally for all token ids via {_setDefaultRoyalty}, and/or individually for
 * specific token ids via {_setTokenRoyalty}. The latter takes precedence over the first.
 *
 * Royalty is specified as a fraction of sale price. {_feeDenominator} is overridable but defaults to 10000, meaning the
 * fee is specified in basis points by default.
 *
 * IMPORTANT: ERC-2981 only specifies a way to signal royalty information and does not enforce its payment. See
 * https://eips.ethereum.org/EIPS/eip-2981#optional-royalty-payments[Rationale] in the EIP. Marketplaces are expected to
 * voluntarily pay royalties together with sales, but note that this standard is not yet widely supported.
 *
 * _Available since v4.5._
 */
abstract contract ERC2981 is IERC2981, ERC165 {
    struct RoyaltyInfo {
        address receiver;
        uint96 royaltyFraction;
    }

    RoyaltyInfo private _defaultRoyaltyInfo;
    mapping(uint256 => RoyaltyInfo) private _tokenRoyaltyInfo;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, ERC165) returns (bool) {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @inheritdoc IERC2981
     */
    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) public view virtual override returns (address, uint256) {
        RoyaltyInfo memory royalty = _tokenRoyaltyInfo[_tokenId];

        if (royalty.receiver == address(0)) {
            royalty = _defaultRoyaltyInfo;
        }

        uint256 royaltyAmount = (_salePrice * royalty.royaltyFraction) /
            _feeDenominator();

        return (royalty.receiver, royaltyAmount);
    }

    /**
     * @dev The denominator with which to interpret the fee set in {_setTokenRoyalty} and {_setDefaultRoyalty} as a
     * fraction of the sale price. Defaults to 10000 so fees are expressed in basis points, but may be customized by an
     * override.
     */
    function _feeDenominator() internal pure virtual returns (uint96) {
        return 10000;
    }

    /**
     * @dev Sets the royalty information that all ids in this contract will default to.
     *
     * Requirements:
     *
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function _setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) internal virtual {
        require(
            feeNumerator <= _feeDenominator(),
            "ERC2981: royalty fee will exceed salePrice"
        );
        require(receiver != address(0), "ERC2981: invalid receiver");

        _defaultRoyaltyInfo = RoyaltyInfo(receiver, feeNumerator);
    }

    /**
     * @dev Removes default royalty information.
     */
    function _deleteDefaultRoyalty() internal virtual {
        delete _defaultRoyaltyInfo;
    }

    /**
     * @dev Sets the royalty information for a specific token id, overriding the global default.
     *
     * Requirements:
     *
     * - `tokenId` must be already minted.
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function _setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) internal virtual {
        require(
            feeNumerator <= _feeDenominator(),
            "ERC2981: royalty fee will exceed salePrice"
        );
        require(receiver != address(0), "ERC2981: Invalid parameters");

        _tokenRoyaltyInfo[tokenId] = RoyaltyInfo(receiver, feeNumerator);
    }

    /**
     * @dev Resets royalty information for the token id back to the global default.
     */
    function _resetTokenRoyalty(uint256 tokenId) internal virtual {
        delete _tokenRoyaltyInfo[tokenId];
    }
}

contract GenesisNFT is
    ERC721A,
    ERC2981,
    Ownable,
    Pausable,
    ReentrancyGuard,
    IERC4906
{
    using Strings for uint256;

    uint256 public MAX_SUPPLY = 5000;
    uint256 public tradeTimeStamp;
    string private baseTokenURI;
    uint96 public royaltyPercentage; //Percentage of royalties (in basis points)
    bool public burnEnabled = false; //Indicates whether token burn is enabled(Defaults to `false`)
    mapping(address => bool) public tradeWhitelist; //Mapping to manage trade whitelist

    //EVENTS
    // Emitted when Ether is withdrawn from the contract
    event Withdrawal(address owner, uint256 amount);
    // Emitted when tokens are pre-minted for an address
    event Premint(address to, uint256 quantity);
    // Emitted when the trade timelock is updated
    event TradeTimelockUpdated(uint256 newTimelock);
    // Emitted to log the reception of Ether
    event Received(address sender, uint amount);
    //Emitted when an address is added to or removed from the trade whitelist.
    event TradeWhitelistUpdated(address indexed _address, bool _whitelist);

    /**
     * @dev Constructor function to initialize the contract with initial parameters.
     * @param _name Name of the NFT collection.
     * @param _symbol Symbol of the NFT collection.
     * @param _baseTokenURI Base URI for the token metadata.
     * @param _tradeTimeStamp Timestamp which trade lock period ends.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI,
        uint256 _tradeTimeStamp
    ) Ownable(msg.sender) ERC721A(_name, _symbol) {
        require(
            _tradeTimeStamp > block.timestamp,
            "Trade timestamp should be in the future"
        );
        baseTokenURI = _baseTokenURI;
        tradeTimeStamp = _tradeTimeStamp;
        _setDefaultRoyalty(msg.sender, royaltyPercentage);
    }

    // GET FUNCTIONS
    /**
     * @dev Returns the total number of NFTs minted by a user.
     * @param _user Address of the user.
     * @return uint256 Total number of NFTs minted by the user.
     */
    function getUserNFTMinted(address _user) external view returns (uint256) {
        return super._numberMinted(_user);
    }
    /**
     * @dev Returns the total number of NFTs minted in the contract.
     * @return uint256 Total number of NFTs minted.
     */
    function getTotalMinted() external view returns (uint256) {
        return super._totalMinted();
    }
    /**
     * @dev Returns the base URI for the token metadata.
     * @return string Base URI for the token metadata.
     */
    function baseURI() external view returns (string memory) {
        return _baseURI();
    }
    /**
     * @dev To get the token URI of the token as `_tokenId`.
     **/
    function tokenURI(
        uint256 _tokenId
    ) public view virtual override(ERC721A) returns (string memory) {
        require(_exists(_tokenId), "URI query for nonexistent token");

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        _tokenId.toString(),
                        ".json"
                    )
                )
                : "";
    }
    /**
     * @dev Allows the contract owner to premint NFTs to a specified address.
     * @param _to Address to which NFTs will be minted.
     * @param _quantity Number of NFTs to mint.
     */
    function premint(
        address _to,
        uint256 _quantity
    ) external nonReentrant whenNotPaused onlyOwner {
        require(_quantity + _totalMinted() <= MAX_SUPPLY, "Max limit reached");
        _mint(_to, _quantity);
        emit Premint(_to, _quantity);
    }
    /**
     * @dev Modifier to check if token transfer is allowed using timelock.
     */
    modifier tokenTransferAllowed(address operator) {
        require(
            block.timestamp >= tradeTimeStamp || tradeWhitelist[operator],
            "Trade is locked"
        );
        _;
    }
    /**
     * @dev Override approve function to add custom logic.
     * @param to The address to approve for token transfer.
     * @param tokenId The ID of the token to approve.
     */
    function approve(
        address to,
        uint256 tokenId
    ) public payable virtual override tokenTransferAllowed(to) {
        require(_exists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender, "Invalid Owner");
        super.approve(to, tokenId);
    }
    /**
     * @dev Override setApprovalForAll function to add custom logic
     * @param operator The address to approve as an operator.
     * @param approved The approval status to set.
     */
    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override tokenTransferAllowed(operator) {
        super.setApprovalForAll(operator, approved);
    }
    /**
     * @dev Burns a specified token and resets its royalty information.
     * @param tokenId The ID of the token to be burn.
     */
    function burn(uint256 tokenId) external {
        require(burnEnabled, "Burning is disabled");
        _burn(tokenId, true);
        _resetTokenRoyalty(tokenId);
    }
    // ADMIN FUNCTIONS
    /**
     * @dev Adds or removes an address from the trade whitelist.
     * @param _address The address to be updated.
     * @param _whitelist A boolean flag to add (true) or remove (false) the address.
     */
    function updateTradeWhitelist(
        address _address,
        bool _whitelist
    ) external onlyOwner {
        tradeWhitelist[_address] = _whitelist;
        emit TradeWhitelistUpdated(_address, _whitelist);
    }
    /**
     * @dev To enable or disable the token burning.
     * @param _enabled A boolean indicating whether token burn is enabled or not.
     */
    function setBurnEnabled(bool _enabled) external onlyOwner {
        burnEnabled = _enabled;
    }
    /**
     * @dev Withdraws the entire balance of the contract to the owner's address.
     */
    function withdrawFunds() external nonReentrant onlyOwner {
        uint256 amount = address(this).balance;

        require(amount > 0, "No balance");

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed.");
        emit Withdrawal(msg.sender, amount);
    }
    /**
     * @dev Allows the contract owner to update the timestamp .
     * @param _newTradeTimeStamp New timestamp for the trade.
     */
    function updateTradeTimeStamp(
        uint256 _newTradeTimeStamp
    ) external onlyOwner {
        require(
            _newTradeTimeStamp > block.timestamp,
            "New Tier1 timestamp should be in the future"
        );
        tradeTimeStamp = _newTradeTimeStamp;
    }

    /**
     * @dev Allows the contract owner to set the base URI for the token metadata.
     * @param _baseTokenURI New base URI for the token metadata.
     */
    function setBaseURI(string memory _baseTokenURI) external onlyOwner {
        baseTokenURI = _baseTokenURI;
        emit BatchMetadataUpdate(0, MAX_SUPPLY);
    }
    /**
     * @dev Pauses the minting process.
     */
    /**
     * @dev To pause the mint
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the minting process.
     */
    /**
     * @dev To unpause the mint
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // INTERNAL FUNCTIONS
    /**
     * @dev To change the starting token ID.
     */
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }
    /**
     * @dev Returns the base URI for the token metadata.
     * @return string Base URI for the token metadata.
     */
    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    /**
     * @dev Returns whether the contract supports a specific interface.
     * @param interfaceId Interface ID to check.
     * @return bool Whether the contract supports the interface.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721A, ERC2981, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    // Metadata update functions

    /**
     * @dev Triggers a metadata update event for a specific token.
     * @param tokenId The ID of the token for which metadata is updated.
     */
    function updateTokenMetadata(uint256 tokenId) external onlyOwner {
        emit MetadataUpdate(tokenId);
    }

    /**
     * @dev Triggers a batch metadata update event for a range of tokens.
     * @param fromTokenId The ID of the first token in the range.
     * @param toTokenId The ID of the last token in the range.
     */
    function updateBatchTokenMetadata(
        uint256 fromTokenId,
        uint256 toTokenId
    ) external onlyOwner {
        emit BatchMetadataUpdate(fromTokenId, toTokenId);
    }
    ////////////////
    // royalty
    ////////////////
    /**
     * @dev See {ERC2981-_setDefaultRoyalty}.
     */
    function setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @dev See {ERC2981-_deleteDefaultRoyalty}.
     */
    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    /**
     * @dev See {ERC2981-_setTokenRoyalty}.
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    /**
     * @dev See {ERC2981-_resetTokenRoyalty}.
     */
    function resetTokenRoyalty(uint256 tokenId) external onlyOwner {
        _resetTokenRoyalty(tokenId);
    }
    // The receive function is triggered when Ether is sent to the contract
    receive() external payable {
        // Emit an event to log the transaction details
        emit Received(msg.sender, msg.value);
    }
}