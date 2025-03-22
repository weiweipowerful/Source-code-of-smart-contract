// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Import necessary OpenZeppelin contracts for ERC721 functionality, security, and ownership
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import '@openzeppelin/contracts/finance/PaymentSplitter.sol';
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// @contact [email protected]

/**
 * @title PixelPlumesTokens
 * @dev An ERC721 token with presale, public sale, and payment splitting functionality.
 *      This contract is designed to mint and distribute PixelPlumesTokens NFTs.
 */
contract PixelPlumesTokens is
    ERC721Enumerable, // Enables enumeration of token IDs for ERC721 tokens
    Ownable, // Restricts certain functions to the contract owner
    ReentrancyGuard, // Prevents reentrancy attacks on functions
    PaymentSplitter // Handles payment splitting between team members
{
    using Strings for uint256;
    using Counters for Counters.Counter;

    // Merkle root for verifying presale eligibility
    bytes32 public root;

    // Address of OpenSea proxy registry for whitelisting
    address proxyRegistryAddress;

    // Maximum supply of tokens that can ever be minted
    uint256 public constant maxSupply = 44444;

    // Base URI for metadata storage
    string public baseURI;
    string public notRevealedUri = "ipfs://QmYQBaQhsmfpRXoXPvH34SMNPr3HEpR5gYWCrS4ANgippD/hidden.json";
    string public baseExtension = ".json";

    // Contract state variables to control sale phases
    bool public paused = false; // Pauses all minting when true
    bool public revealed = false; // Controls whether metadata is revealed
    bool public presaleM = false; // Controls the presale phase
    bool public publicM = false; // Controls the public sale phase

    // Limit for presale minting
    uint256 presaleAmountLimit = 10;

    // Tracks the number of tokens claimed by each presale address
    mapping(address => uint256) public _presaleClaimed;

    // Price per mint in Wei (0.005 ETH in this case) or 5000000000000000
    uint256 public immutable mintPrice = 5000000000000000;

    // Counter to keep track of minted tokens
    Counters.Counter private _tokenIds;

    // Team shares
    uint256[] private _teamShares = [30,10,10,30,20];
    address[] private _team = [
        0x05c23b2A154F329579cE4AE3a66EbBdD1A621344,
        0x316EeBED297699D96B340Dc7f8C2Bc46f8c8Ee79,
        0xaa679Cc3546B394DBE25a4Cf137A7d0A67B859ba,
        0x703fb40278fCa703d80823Ce67eBE77e89481399,
        0x4C8883AD675D4726D1Bd3A91fC9D60833ad6bBF5
    ];

    /***
     * Rinkeby: 0xf57b2c51ded3a29e6891aba85459d600256cf317
     * Mainnet: 0xa5409ec958c83c3f309868babaca7c86dcb077c1
     */
    /**
     * @dev Contract constructor
     * @param uri The base URI for token metadata
     * @param merkleroot The Merkle root for presale whitelisting
     * @param _proxyRegistryAddress Address of OpenSea proxy for gasless listings
     */
    constructor(string memory uri, bytes32 merkleroot, address _proxyRegistryAddress)
        ERC721("PixelPlumesTokens", "PPT")
        PaymentSplitter(_team, _teamShares) // Split the payment based on the teamshares percentages
        ReentrancyGuard() // A modifier that can prevent reentrancy during certain functions
    {
        root = merkleroot;
        proxyRegistryAddress = _proxyRegistryAddress;
        setBaseURI(uri); // Set the initial base URI for metadata
    }

    // OWNER-ONLY FUNCTIONS

    /**
     * @dev Allows the owner to set the base URI for metadata
     * @param _tokenBaseURI The new base URI to set
     */
    function setBaseURI(string memory _tokenBaseURI) public onlyOwner {
        baseURI = _tokenBaseURI;
    }

    /**
     * @dev Internal function to return the base URI for token metadata
     * @return The current base URI
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Allows the owner to reveal the token metadata (sets `revealed` to true)
     * Once revealed, metadata cannot be hidden again.
     */
    function reveal() public onlyOwner {
        revealed = true;
    }

    /**
     * @dev Allows the owner to set the Merkle root for presale whitelisting
     * @param merkleroot The new Merkle root to set
     */
    function setMerkleRoot(bytes32 merkleroot)
    onlyOwner
    public
    {
        root = merkleroot;
    }

    // Prevent contract accounts from interacting
    modifier onlyAccounts () {
        require(msg.sender == tx.origin, "Not allowed origin");
        _;
    }

    // Validates the Merkle proof for presale eligibility
    modifier isValidMerkleProof(bytes32[] calldata _proof) {
        require(MerkleProof.verify(
            _proof,
            root,
            keccak256(abi.encodePacked(msg.sender))
            ) == true, "Not allowed origin");
        _;
    }

    /**
     * @dev Toggles the paused state of the contract
     * Pausing prevents any further minting operations.
     */
    function togglePause() public onlyOwner {
        paused = !paused;
    }

    /**
     * @dev Toggles the presale state of the contract
     * When presale is enabled, only whitelisted addresses can mint.
     */
    function togglePresale() public onlyOwner {
        presaleM = !presaleM;
    }

    /**
     * @dev Toggles the public sale state of the contract
     * When public sale is enabled, any address can mint.
     */
    function togglePublicSale() public onlyOwner {
        publicM = !publicM;
    }

    // MINTING FUNCTIONS

    /**
     * @dev Allows whitelisted addresses to mint during presale.
     * @param account The address of the minter
     * @param _amount The number of tokens to mint
     * @param _proof The Merkle proof to validate the address
     */
    function presaleMint(address account, uint256 _amount, bytes32[] calldata _proof)
    external
    payable
    isValidMerkleProof(_proof) // Ensure the address is whitelisted
    onlyAccounts // Prevents contracts from interacting
    {
        require(msg.sender == account,          "PPT: Not allowed");
        require(presaleM,                       "PPT: Presale is OFF");
        require(!paused,                        "PPT: Contract is paused");
        require(
            _amount <= presaleAmountLimit,      "PPT: You can't mint so much tokens");
        require(
            _presaleClaimed[msg.sender] + _amount <= presaleAmountLimit,  "PPT: You can't mint so much tokens");


        uint current = _tokenIds.current();

        require(
            current + _amount <= maxSupply,
            "PPT: max supply exceeded"
        );
        require(
            mintPrice * _amount <= msg.value,
            "PPT: Not enough ethers sent"
        );

        _presaleClaimed[msg.sender] += _amount;

        for (uint i = 0; i < _amount; i++) {
            mintInternal();
        }
    }

    /**
     * @dev Allows the public to mint during public sale
     * @param _amount The number of tokens to mint
     */
    function publicSaleMint(uint256 _amount)
    external
    payable
    onlyAccounts
    {
        require(publicM, "PPT: PublicSale is OFF");
        require(!paused, "PPT: Contract is paused");
        require(_amount > 0, "PPT: zero amount");

        uint current = _tokenIds.current();

        require(
            current + _amount <= maxSupply,
            "RBT: Max supply exceeded"
        );
        require(
            mintPrice * _amount <= msg.value,
            "RBT: Not enough ethers sent"
        );

        for (uint i = 0; i < _amount; i++) {
            mintInternal();
        }
    }

    /**
     * @dev Internal function to mint a token
     * This increments the token counter and safely mints the token.
     */
    function mintInternal() internal nonReentrant {
        _tokenIds.increment();

        uint256 tokenId = _tokenIds.current();
        _safeMint(msg.sender, tokenId);
    }

    // METADATA FUNCTIONS

    /**
     * @dev Returns the URI for a given token ID
     * @param tokenId The ID of the token to query
     * @return The URI for the token's metadata
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        if (revealed == false) {
            return notRevealedUri;
        }

        string memory currentBaseURI = _baseURI();

        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        baseExtension
                    )
                )
                : "";
    }

    /**
     * @dev Allows the owner to set the file extension for metadata URIs
     * @param _newBaseExtension The new file extension (e.g., ".json")
     */
    function setBaseExtension(string memory _newBaseExtension)
        public
        onlyOwner
    {
        baseExtension = _newBaseExtension;
    }

    /**
     * @dev Allows the owner to set the URI for hidden tokens before reveal
     * @param _notRevealedURI The new hidden token URI
     */
    function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
        notRevealedUri = _notRevealedURI;
    }

    /**
     * @dev Overrides the isApprovedForAll function to whitelist OpenSea proxy contracts.
     * This allows gasless listings on OpenSea.
     */
    function isApprovedForAll(address owner, address operator)
        override
        public
        view
        returns (bool)
    {
        // Whitelist OpenSea proxy contract for easy trading.
        ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
        if (address(proxyRegistry.proxies(owner)) == operator) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }
}



/**
  @title An OpenSea delegate proxy contract which we include for whitelisting.
  @author OpenSea
*/
contract OwnableDelegateProxy {}

/**
  @title An OpenSea proxy registry contract which we include for whitelisting.
  @author OpenSea
*/
contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}