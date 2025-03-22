//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * A smart contract for minting soulbound AlloPatron NFTs on a bonding curve
 * @author Allo.capital
 * @custom:coauthor @ghostffcode
 */
contract AlloPatronNFT is Ownable, Pausable, ReentrancyGuard, ERC721 {
    uint256 public constant MULTIPLIER = 1013370;
    uint256 public constant PRECISION = 1e6;
    uint256 public constant ADMIN_MINT_LIMIT = 60;

    uint256 public price;
    address payable public manager;
    string public baseURI;
    string public contractURI;
    uint256 public goLiveTimestamp;
    uint256 public counter = 0;
    uint256 public adminMintCounter = 0;
    mapping(uint256 => string) public tokens;
    mapping(uint256 => uint256) public tokenIdToType;

    event Initialized(uint256 startingPrice, string[] URIs);
    event TokenGroupAdded(uint256 indexed groupId, string indexed URI);
    event TokensMinted(address indexed to, uint256 price, uint256 count);

    modifier canMint() {
        require(block.timestamp >= goLiveTimestamp, "Mint is not open yet");
        _;
    }

    constructor(
        address _owner,
        address payable _manager,
        string memory _name,
        string memory _symbol,
        string memory _tokensBaseURI,
        string memory _contractURI,
        string[] memory URIs,
        uint256 basePrice,
        uint256 _goLiveTimestamp
    ) Ownable(_owner) ERC721(_name, _symbol) {
        baseURI = _tokensBaseURI;
        contractURI = _contractURI;
        manager = _manager;
        goLiveTimestamp = _goLiveTimestamp;
        price = basePrice;

        for (uint256 i = 0; i < URIs.length; i++) {
            uint256 id = i + 1;
            tokens[id] = URIs[i];

            emit TokenGroupAdded(id, URIs[i]);
        }

        emit Initialized(basePrice, URIs);
    }

    function updateContractURI(string memory _newContractURI) public onlyOwner {
        contractURI = _newContractURI;
    }

    function updateManager(address payable _newManager) public onlyOwner {
        manager = _newManager;
    }

    function togglePauseStatus() public onlyOwner {
        paused() ? _unpause() : _pause();
    }

    /**
     * Function that allows anyone to mint tokens based on variantsID
     *
     * @param variants (uint256) - the list of variants ID for the tokens to be minted
     */
    function mint(uint256[] memory variants) public payable nonReentrant canMint whenNotPaused {
        uint256 variantsCount = variants.length;
        require(variantsCount > 0, "You need to mint at least 1 NFT");
        uint256 leftOver = msg.value;

        for (uint256 i = 0; i < variantsCount; i++) {
            leftOver -= _handleMint(variants[i], leftOver, i == variantsCount - 1);
        }

        emit TokensMinted(msg.sender, msg.value - leftOver, variantsCount);
    }

    /**
     * Function that allows the owner to mint tokens to a specific address
     *
     * @param variantIds (uint256[]) - the variant IDs for the tokens to be minted
     * @param to (address[]) - the addresses to mint the tokens to
     */
    function mintTo(
        uint256[] calldata variantIds,
        address[] calldata to
    ) public nonReentrant canMint whenNotPaused onlyOwner {
        require(variantIds.length == to.length, "Variant IDs and addresses length mismatch");
        require(adminMintCounter < ADMIN_MINT_LIMIT, "Admin mint limit reached");
        require(adminMintCounter + variantIds.length <= ADMIN_MINT_LIMIT, "Admin mint limit reached");

        for (uint256 i = 0; i < variantIds.length; i++) {
            _mintTo(variantIds[i], to[i]);
        }
    }

    /**
     * Function that allows the owner to mint tokens to a specific address
     *
     * @param variantId (uint256) - the variant ID for the token to be minted
     * @param to (address) - the address to mint the token to
     */
    function _mintTo(uint256 variantId, address to) internal {
        require(adminMintCounter < ADMIN_MINT_LIMIT, "Admin mint limit reached");
        adminMintCounter += 1;
        counter += 1;

        tokenIdToType[counter] = variantId;
        _mint(to, counter);
    }

    /**
     * Function that handles the minting of tokens
     *
     * @param variantId (uint256) - the variant ID for the token to be minted
     * @param totalBalance (uint256) - the total balance of the user
     * @param canRefund (bool) - whether the user can get a refund
     */
    function _handleMint(uint256 variantId, uint256 totalBalance, bool canRefund) internal returns (uint256 lastPrice) {
        require(bytes(tokens[variantId]).length > 0, "Variant does not exist");
        require(totalBalance >= price, "Not enough ETH to buy");

        (bool success, ) = manager.call{ value: price }("");
        require(success, "could not send");

        lastPrice = price;
        price = (price * MULTIPLIER) / PRECISION;
        counter += 1;

        _mint(msg.sender, counter);
        tokenIdToType[counter] = variantId;

        if (canRefund) {
            uint256 refundBalance = totalBalance - lastPrice;

            if (refundBalance > 0) {
                (bool isRefundSuccessful, ) = msg.sender.call{ value: refundBalance }("");
                require(isRefundSuccessful, "could not refund");
            }
        }
    }

    /**
     * Function that returns the base URI of the tokens
     *
     * @return (string) - the base URI of the tokens
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * Function that get the URI of a token
     *
     * @param tokenId (uint256) - the token ID
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        string memory base = _baseURI();
        return bytes(base).length > 0 ? string.concat(base, tokens[tokenIdToType[tokenId]]) : "";
    }

    /**
     * Function that allows the owner to withdraw the Ether in the contract
     */
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = manager.call{ value: balance }("");
        require(success, "Failed to withdraw");
    }

    /**
     * Function that prevents the transfer of tokens
     */
    function transferFrom(address from, address to, uint256 tokenId) public override {
        revert("This NFT is soulbound and cannot be transferred");
    }

    /**
     * Function that prevents the approval of tokens
     */
    function approve(address to, uint256 tokenId) public override {
        revert("This NFT is soulbound and cannot be approved for transfer");
    }

    /**
     * Function that prevents the approval of tokens for all
     */
    function setApprovalForAll(address operator, bool approved) public override {
        revert("This NFT is soulbound and cannot be approved for transfer");
    }

    /**
     * Function that allows the contract to receive ETH
     */
    receive() external payable {}
}