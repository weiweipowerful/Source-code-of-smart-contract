// SPDX-License-Identifier: MIT
// Drppr v0.1.2

// ██████╗ ██████╗ ██████╗ ██████╗ ██████╗ 
// ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔══██╗
// ██║  ██║██████╔╝██████╔╝██████╔╝██████╔╝
// ██║  ██║██╔══██╗██╔═══╝ ██╔═══╝ ██╔══██╗
// ██████╔╝██║  ██║██║     ██║     ██║  ██║
// ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝     ╚═╝  ╚═╝.io                                   
//  The easiest way to drop your collection
//
//  Features:
//  - Free x mints per wallet
//  - First x free mints per collection (can be combined with x free per wallet)
//  - Whitelist mints with personal allocation for each wallet
//  - Airdrop, devmint
//  - Backup mint functions for simple integration with external minters
//  - External metadata renderer interface for on-chain collections
//  - Updatable prices and free mint caps
//  - Cuttable supply
//  - Return list of tokens owned by address
//  - Updatable withdraw address

pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import "erc721a-upgradeable/contracts/ERC721A__Initializable.sol";
import "./ERC721A__OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// Struct that consolidates the parameters needed to initialize the contract.
struct InitParams {
    string baseURI;
    uint256 maxSupply;
    uint256 maxFreeSupply;
    uint256 costPublic;
    uint256 maxMintPublic;
    uint256 freePerWallet;
    uint256 platformFee;
    uint256 costWL;
    uint256 maxMintWL;
    address withdrawAddress;
    address treasury;
}

// Diverts tokenURI calls to external contract if useRenderer if true
interface IRenderer {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

/**
 * @title A contract for creating a limited supply of ERC721 tokens with a whitelist and public minting functionality.
 * @dev Inherits ERC721AInitializable, ERC721AUpgradeable and ERC721AOwnableUpgradeable.
 */
contract Drppr721 is ERC721A__Initializable, ERC721AUpgradeable, ERC721A__OwnableUpgradeable {
    IRenderer public renderer; // renderer contract for external matadata serving
    bool public useRenderer; // defines if an external renderer contract should be used
    mapping(address => uint256) public mintedByAddress; // Mapping to keep track of the number of free tokens minted by an address
    mapping(address => uint256) public mintedByAddressWL; // Mapping to keep track of the number of tokens minted by a whitelisted address
    string public baseURI; // Base URI for token metadata
    bool public isPublicMintEnabled; // Flag to enable or disable public minting
    uint256 public maxSupply; // Maximum supply of tokens
    uint256 public maxFreeSupply; // Maximum supply of free tokens
    uint256 public costPublic; // Cost to mint a token for the public
    uint256 public maxMintPublic; // Maximum number of tokens a user can mint
    uint256 public freePerWallet; // Number of free tokens per wallet
    address internal withdrawAddress; // Address where funds will be withdrawn to
    address internal treasury; // Platform treasury address
    uint256 internal platformFee; // Fee charged by the platform
    bool public isWLmintEnabled; // Flag to enable or disable whitelist minting
    uint256 public costWL; // Cost to mint a token for a whitelisted user
    uint256 public maxMintWL; // Maximum amount a whitelisted user can mint
    bytes32 public whitelistRoot; // Merkle root for the whitelist

    /**
     * @notice Initializes the contract.
     * @param name - Name of the token.
     * @param symbol - Symbol of the token.
     * @param params - Parameters needed to initialize the contract.
     * @dev Function can only be called once.
     */
    function initialize(
        string memory name,
        string memory symbol,
        InitParams memory params
    ) public initializerERC721A {
        __ERC721A_init(name, symbol);
        baseURI = params.baseURI;
        maxSupply = params.maxSupply;
        maxFreeSupply = params.maxFreeSupply;
        costPublic = params.costPublic;
        maxMintPublic = params.maxMintPublic;
        freePerWallet = params.freePerWallet;
        platformFee = params.platformFee;
        costWL = params.costWL;
        maxMintWL = params.maxMintWL;
        withdrawAddress = params.withdrawAddress;
        treasury = params.treasury;
        
        __Ownable_init();
    }

    /**
     * @notice Allows a user to mint tokens.
     * @param _quantity - The number of tokens to mint.
     * @dev User must send the correct amount of ether. Can only be called by a wallet (not a contract). Public minting must be enabled.
     */
    function mint(uint _quantity) external payable {
        require(tx.origin == msg.sender, "No contracts");
        require(isPublicMintEnabled, "Not yet");
        require(totalSupply() + _quantity <= maxSupply, "Too late");
        require(_quantity <= maxMintPublic, "Too many");

        uint256 _cost = getCost(msg.sender, _quantity);
        require(msg.value >= _cost, "Insufficient Ether sent");

        if (canClaim(msg.sender)) {
            uint256 freeTokensLeft = freePerWallet - mintedByAddress[msg.sender];
            uint256 freeTokensToMint = (_quantity < freeTokensLeft) ? _quantity : freeTokensLeft;
            mintedByAddress[msg.sender] += freeTokensToMint;
        }
        _safeMint(msg.sender, _quantity);
    }     

    /**
     * @notice Allows a whitelisted user to mint a specified number of tokens.
     * @dev Mints a specified number of tokens to the sender's address, provided they are whitelisted.
     * @param _quantity The number of tokens to mint.
     * @param _merkleProof The Merkle proof validating the sender's address is whitelisted.
     */
    function mintWL(uint _quantity, bytes32[] calldata _merkleProof) external payable {
        require(isWLmintEnabled, "Whitelist minting not enabled");
        require(tx.origin == msg.sender, "No contracts");
        require(isWhitelisted(msg.sender, _merkleProof, _quantity), "Not whitelisted");
        require(totalSupply() + _quantity <= maxSupply, "Too late");
        require(mintedByAddressWL[msg.sender] == 0, "Already claimed");
        require(msg.value >= costWL * _quantity, "Insufficient Ether sent");

        mintedByAddressWL[msg.sender] += _quantity;
        _safeMint(msg.sender, _quantity);
    }

    /**
    * @dev Allows a user to mint tokens for free if they are eligible. Use for simple integration with external minters.
    * @param _quantity The number of tokens to mint.
    */
    function mintFree(uint _quantity) external {
        require(isPublicMintEnabled, "Public minting not enabled");
        require(canClaim(msg.sender), "Not eligible for free mint");
        require(totalSupply() + _quantity <= maxSupply, "Max supply exceeded");
        require(mintedByAddress[msg.sender] + _quantity <= freePerWallet, "Exceeds free mint limit");

        mintedByAddress[msg.sender] += _quantity;
        _safeMint(msg.sender, _quantity);
    }

    /**
    * @dev Allows a user to mint tokens by paying the specified cost. Use for simple integration with external minters.
    * @param _quantity The number of tokens to mint.
    */
    function mintPaid(uint _quantity) external payable {
        require(isPublicMintEnabled, "Public minting not enabled");
        require(totalSupply() + _quantity <= maxSupply, "Max supply exceeded");
        require(msg.value >= costPublic * _quantity, "Insufficient Ether sent");

        _safeMint(msg.sender, _quantity);
    }

    /**
     * @notice Defines the starting token ID.
     * @return The starting token ID.
     */
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /**
     * @notice Allows the owner to airdrop tokens to a recipient.
     * @param _quantity - The number of tokens to airdrop.
     * @param _recipient - The address of the recipient.
     * @dev Only the owner can call this function. Cannot mint more tokens than the maximum supply.
     */
    function airdrop(uint256 _quantity, address _recipient) external onlyOwner {
        require(totalSupply() + _quantity <= maxSupply, "Too many");
        _mint(_recipient, _quantity);
    }

    /**
     * @notice Allows the owner to mint tokens.
     * @param _quantity - The number of tokens to mint.
     * @dev Only the owner can call this function. Cannot mint more tokens than the maximum supply.
     */
    function devMint(uint256 _quantity) external onlyOwner {
        require(totalSupply() + _quantity <= maxSupply, "Too many");
        _mint(msg.sender, _quantity);
    }

    /**
     * @notice Checks if an address can claim a free token.
     * @param _address - The address to check.
     * @return True if the address can claim a free token, false otherwise.
     */
    function canClaim(address _address) internal view returns (bool) {
        return mintedByAddress[_address] < freePerWallet && totalSupply() < maxFreeSupply;
    }

    /**
     * @notice Returns the cost to mint a number of tokens for a specific address.
     * @param _address - The address that wants to mint the tokens.
     * @param _count - The number of tokens to mint.
     * @return The cost to mint the tokens.
     */
    function getCost(address _address, uint256 _count) internal view returns (uint256) {
        if (canClaim(_address)) {
            uint256 freeTokensLeft = freePerWallet - mintedByAddress[_address];
            uint256 maxFreeTokensAvailable = maxFreeSupply - totalSupply();
            freeTokensLeft = freeTokensLeft < maxFreeTokensAvailable ? freeTokensLeft : maxFreeTokensAvailable;
            
            uint256 paidTokens = _count > freeTokensLeft ? _count - freeTokensLeft : 0;
            return paidTokens * costPublic;
        }
        return _count * costPublic;
    }

    /**
     * @notice Checks if an address is whitelisted.
     * @param _wallet - The address to check.
     * @param _merkleProof - The Merkle proof that the address is whitelisted.
     * @return True if the address is whitelisted, false otherwise.
     */
    function isWhitelisted(address _wallet, bytes32[] calldata _merkleProof, uint256 _quantity) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(_wallet, _quantity));
        return MerkleProof.verify(_merkleProof, whitelistRoot, leaf);
    }

    /**
     * @notice Allows the owner to set the Merkle root for the whitelist.
     * @param _merkleRoot - The new Merkle root for the whitelist.
     * @dev Only the owner can call this function.
     */
    function setWhitelistRoot(bytes32 _merkleRoot) public onlyOwner {
        whitelistRoot = _merkleRoot;
    }

   /**
     * @notice Allows the owner to enable or disable whitelist minting.
     * @dev Only the owner can call this function.
     */
    function setWLmintEnabled() public onlyOwner {
        isWLmintEnabled = !isWLmintEnabled;
    }

    /**
     * @notice Allows the owner to enable or disable public minting.
     * @dev Only the owner can call this function.
     */
    function setPublicMintEnabled() public onlyOwner {
        isPublicMintEnabled = !isPublicMintEnabled;
    }

    /**
    * @dev Sets the base URI for computing {tokenURI}. If the base URI is set,
    * it will be concatenated with the token ID and ".json" to generate the full token URI.
    * This is used when not using a renderer contract for token URIs.
    * @param _baseURI The new base URI to set.
    */
    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }
    
    /**
    * @dev Sets the address of the renderer contract that provides token URI logic.
    * This renderer contract is used when {useRenderer} is true.
    * The renderer contract should implement the IRenderer interface.
    * @param newRenderer The address of the new renderer contract.
    */
    function setRenderer(address newRenderer) external onlyOwner {
        renderer = IRenderer(newRenderer);
    }

    /**
    * @dev Enables or disables the use of the renderer contract for generating token URIs.
    * When set to true, the contract will use {renderer} for token URI logic.
    * When set to false, it will use the base URI set via {setBaseURI}.
    * @param use A boolean indicating whether to use the renderer contract for token URIs.
    */
    function setUseRenderer(bool use) external onlyOwner {
        useRenderer = use;
    }

    /**
     * @notice Allows the owner to set the cost of public minting.
     * @param _newCostPublic - The new cost of public minting.
     * @dev Only the owner can call this function.
     */
    function setCostPublic(uint256 _newCostPublic) public onlyOwner {
        costPublic = _newCostPublic;
    }

    /**
     * @notice Allows the owner to set the cost of whitelist minting.
     * @param _newCostWL - The new cost of whitelist minting.
     * @dev Only the owner can call this function.
     */
    function setCostWL(uint256 _newCostWL) public onlyOwner {
        costWL = _newCostWL;
    }

    /**
     * @notice Allows the owner to set the maximum number of tokens that can be minted publicly at once.
     * @param _newMaxMintPublic - The new maximum number of tokens that can be minted publicly at once.
     * @dev Only the owner can call this function.
     */
    function setMaxMintPublic(uint256 _newMaxMintPublic) public onlyOwner {
        maxMintPublic = _newMaxMintPublic;
    }

    /**
     * @notice Sets the amount of free tokens each wallet can receive
     * @param _newFreePerWallet The new amount of free tokens each wallet can receive
     * @dev Can only be called by the contract owner
     */
    function setFreePerWallet(uint256 _newFreePerWallet) public onlyOwner {
        freePerWallet = _newFreePerWallet;
    }

    /**
     * @notice Sets the maximum supply of free tokens
     * @param _maxFreeSupply The new maximum supply of free tokens
     * @dev Can only be called by the contract owner
     */
    function setMaxFreeSupply(uint256 _maxFreeSupply) public onlyOwner {
        maxFreeSupply = _maxFreeSupply;
    }

    /**
     * @notice Sets the withdraw address
     * @param _newWithdrawAddress The new withdraw address
     * @dev Can only be called by the contract owner
     */
    function setWithdrawAddress(address _newWithdrawAddress) public onlyOwner {
        withdrawAddress = _newWithdrawAddress;
    }

    /**
     * @notice Allows the owner to withdraw all collected funds
     * @dev Can only be called by the contract owner. The withdrawn amount is split between the platform and the withdrawal address based on the platform fee
     */
    function withdrawAll() public payable onlyOwner {
        uint256 balance = address(this).balance; 
        require(balance > 0, "No balance to withdraw");
        uint256 feeAmount = (balance * platformFee) / 100; 
        (bool success, ) = payable(treasury).call{value: feeAmount}("");
        require(success, "Failed to transfer fees");
        (success, ) = payable(withdrawAddress).call{value: balance - feeAmount}("");
        require(success, "Failed to transfer to withdrawal address");
    }

    /**
     * @notice Returns the token URI for a given token. If external renderer is used, fetches tokenURI from there.
     * @param _tokenId The ID of the token
     * @return The full URI of the token
     */
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "Token not found");

        if (!useRenderer) {
            return string(abi.encodePacked(baseURI, _toString(_tokenId), ".json"));
        } else {
            return renderer.tokenURI(_tokenId);
        }
    }

    /**
     * @notice Reduces the maximum supply of tokens
     * @param _newMaxSupply The new maximum supply of tokens
     * @dev Can only be called by the contract owner. The new maximum supply must be less than the current maximum supply and greater than or equal to the current supply
     */
    function decreaseMaxSupply(uint256 _newMaxSupply) public onlyOwner {
        require(_newMaxSupply < maxSupply, "Supply can only decrease");
        require(_newMaxSupply >= totalSupply(), "Can't be less than current supply");
        maxSupply = _newMaxSupply;
    }

    /**
     * @notice Returns all the tokens owned by a particular address
     * @param _address The address to look up
     * @return An array of token IDs owned by the address
     */
    function tokensOfOwner(address _address) public virtual view returns (uint256[] memory) {
        uint256 _balance = balanceOf(_address);
        uint256[] memory _tokens = new uint256[] (_balance);
        uint256 _index;
        uint256 _loopThrough = totalSupply();
        for (uint256 i = 0; i < _loopThrough; i++) {
            bool _exists = _exists(i);
            if (_exists) {
                if (ownerOf(i) == _address) { _tokens[_index] = i; _index++; }
            }
            else if (!_exists && _tokens[_balance - 1] == 0) { _loopThrough++; }
        }
        return _tokens;
    }
}