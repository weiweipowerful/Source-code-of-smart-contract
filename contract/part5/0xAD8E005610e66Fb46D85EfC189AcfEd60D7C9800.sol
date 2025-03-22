// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.28;

/*

  .:                                                                                            :.  
  :*+.                                                                                        .+*-  
  -##*=.                                                                                    .=###-  
  :*###*-.                                                                                .-*####-  
  :*#####*-                                                                              :*######-  
  -########+:                                                                          :+########-  
  :##########+.                                                                      .+##########-  
  :############=.                                                                  .=*###########-  
  :#############*=.                                                              .-*#############-  
  :###############*-                                                            -**##############-  
  :#####*=*#########*:                                                        :*##*######*=*#####-  
  :#####*: :+*########+:                                                    .=*########+: :*#####-  
  :#####*:   .+#########+.                                                .+*########*:   :*#####-  
  -#####*:     :+*#######*=.                                            .-*#######*+:     :*#####-  
  -#####*:       :+########*-.                                         -*########*-.      :*#####-  
  :*####*:         -*########*:                                      :*########*-.        :*#####-  
  :*####*:          .-*###*####+:                                  .+########*=.          :*#####-  
  :*####*+.           .=####*###*+.                              .=*########=.           .=*#####-  
  :*######*=.           .=*#######*=.                          .=*###*###*=.           .-*#######-  
  :*########*-            .+*#######*-.                       -*#######*+:            :+########*:  
   .=*########*:            .+########*-                    :+*#######+.            :+*########+.   
     :+*########+.            :+########*:                .+########+:            .+########*+:     
      .:+########*+.            :+#######*=:            .=*#######+:.           .=*########+:       
         -*##*######=.            -*#######*=.        .=*#######*-            .=#########*-.        
          .-*########*-.           .-*#######*-      :*#######*=.            -*########*=.          
            .=#########*-             -*######*.    .*######*-.            -*#########=.            
      .-=-    .=*########+:            .=*####*.    .+####*=.            :+#########+.    :=-.      
     -*#*-      :+#########+:           .+####*.    .*#**#+.           .+#########+:      -*#*-     
   :*###*-        :+########*+.         .+####*:    .+####*.         .=*########*:        :*###*-   
  .+####*-          -*#########=.       .+####*:    .+####*.       .-#########*=          -*####+.  
  .+####*-           .-*#######*.       .+####*:    .+####*.       .+#######*=.           :*####+.  
  .+#*##*=.            .=######*.       .+####*:    .+####*.       .+######+.             =*####+.  
  .=######*:             .+*##*+.       .+####*:    .+####*.       .+###*+:             :**#####+.  
   .-#######+:             :+#*+.       .+####*:    .+####*.       .+##+:             :+#######=.   
     .=*#####*+.             :++.       .+####*:    .+####*.       .+*-             .=*#####*+.     
       :+######*=.             .        .+####*:    .+####*.       ..             .-*######*:       
         -*######*-                     .+####*.    .+####*.                     -*######*-.        
          .=*######*:                   .+####*.    .+####*.                   :+######*=.          
            .=*######=.                 .+####*:    .+####*.                 .=######*+.            
              .+######*=.               .+####*:    .+####+.               .=*######*:              
                -**#####*-              .+####*:    .+####+.              -*######*=                
                 .-*######*:             .-*##*:    .+##*=.             :+######*-.                 
                   .+######*+:             .=**:    .+#+.             .+######*+.                   
                     :+######*=.             .-.    .-:             .=*######+:                     
                       :*######*=.                                .-*######*-                       
                        .=*#####**-                              :+######*=.                        
                          .+#######*:                          .*#######+:                          
                            .+*#####*=:                      .=*######*:                            
                              -*#######+.                  .=*#######=                              
                               .=*######*-.              .-*######*=.                               
                                 .+####*##*-            :*#######+.                                 
                                   :+#######+.        .+*#####**-                                   
                                     -*#######=.    .=########-.                                    
                                      .=*######*=..-*#######=.                                      
                                        .+#######**####*##+.                                        
                                          :+############*:                                          
                                            -*#########=.                                           
                                             .=*####*=.                                             
                                               :+##+:                                               
                                                 ::                                                 
           __     __   ______   _______   ______   ______   __    __   ______   ________ 
          |  \   |  \ /      \ |       \ |      \ /      \ |  \  |  \ /      \ |        \
          | $$   | $$|  $$$$$$\| $$$$$$$\ \$$$$$$|  $$$$$$\| $$\ | $$|  $$$$$$\| $$$$$$$$
          | $$   | $$| $$__| $$| $$__| $$  | $$  | $$__| $$| $$$\| $$| $$   \$$| $$__    
           \$$\ /  $$| $$    $$| $$    $$  | $$  | $$    $$| $$$$\ $$| $$      | $$  \   
            \$$\  $$ | $$$$$$$$| $$$$$$$\  | $$  | $$$$$$$$| $$\$$ $$| $$   __ | $$$$$   
             \$$ $$  | $$  | $$| $$  | $$ _| $$_ | $$  | $$| $$ \$$$$| $$__/  \| $$_____ 
              \$$$   | $$  | $$| $$  | $$|   $$ \| $$  | $$| $$  \$$$ \$$    $$| $$     \
               \$     \$$   \$$ \$$   \$$ \$$$$$$ \$$   \$$ \$$   \$$  \$$$$$$  \$$$$$$$$
                                                                                                       
*/

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title Genesis NFT Collection
/// @notice Manages minting and distribution of Genesis NFTs with phase-based whitelisting
/// @dev Implements ERC721Enumerable with ownership and reentrancy protection
contract Genesis is ERC721A, ERC2981, Ownable, ReentrancyGuard {
  using MerkleProof for bytes32[];

  /// @notice Custom errors for the Genesis contract
  error InvalidPaymentReceiver();
  error MintingClosed();
  error InvalidPayment();
  error ExceedsMaxSupply();
  error ExceedsWalletLimit();
  error NotWhitelisted();
  error TransfersLocked();
  error InvalidRoyaltyBPS();
  error InvalidPhase();
  error InvalidPhaseTransition();
  
  /// @dev Events for important state changes
  event PhaseUpdated(Phase currentPhase);
  event BaseURIUpdated(string newBaseURI);
  event RoyaltyUpdated(uint96 newRoyaltyBPS, address newReceiver);
  event TransferStateUpdated(bool enabled);
  
  /// @notice Maximum supply of Genesis NFTs
  uint256 public constant MAX_SUPPLY = 3600;

  /// @notice Price in wei for OG mints
  uint256 public constant OG_PRICE = 0.029 ether;

  /// @notice Price in wei for regular mints
  uint256 public constant MINT_PRICE = 0.033 ether;

  /// @notice Maximum mints per wallet during public phase
  uint256 public constant MAX_MINTS_PER_WALLET = 2;

  /// @notice Maximum mints per wallet during OG phase
  uint256 public constant MAX_WL_MINTS = 1;

  /// @notice Initial supply minted to owner
  uint256 public constant INITIAL_OWNER_MINT = 100;

  /// @notice Initial royalty percentage in basis points (5%)
  uint96 public constant INITIAL_ROYALTY_BPS = 500;

  /// @notice Address that receives payment for mints
  address public paymentReceiver;

  /// @notice Base URI for token metadata
  string private baseURI;

  /// @notice Merkle root for OG wallets
  bytes32 public ogPhaseMerkle;

  /// @notice Merkle root for WL wallets
  bytes32 public wlPhaseMerkle;

  /// @notice Mapping of addresses to their total minted tokens
  mapping(address => uint256) public mintedPerWallet;

  /// @notice Whether token transfers are enabled
  bool public transfersEnabled;

  /// @notice Current minting phase
  enum Phase {
      LOCKED,      // No minting allowed
      WL_ONLY,     // Only OG/allowlist can mint
      PUBLIC       // Public minting active
  }

  /// @notice Current phase of the contract
  Phase public currentPhase;

  /// @notice Initializes the Genesis NFT contract
  /// @param _paymentReceiver Address to receive mint payments
  /// @param _initialBaseURI Initial base URI for token metadata
  /// @dev Sets initial values and validates payment receiver
  constructor(
    address _paymentReceiver,
    string memory _initialBaseURI
  ) ERC721A("GenesisPortal", "GP") Ownable(msg.sender) {
    if (_paymentReceiver == address(0)) revert InvalidPaymentReceiver();
    paymentReceiver = _paymentReceiver;
    baseURI = _initialBaseURI;
    transfersEnabled = false;
    currentPhase = Phase.LOCKED;
    
    // Set default royalty to 5%
    _setDefaultRoyalty(_paymentReceiver, INITIAL_ROYALTY_BPS);
    
    // Mint initial supply to owner
    _mint(msg.sender, INITIAL_OWNER_MINT);
  }

  /// @notice Checks if an address is whitelisted for OG phase
  /// @param proof Merkle proof for verification
  /// @return bool Whether the address is whitelisted
  function isOGWhitelisted(bytes32[] calldata proof) public view returns (bool) {
    return MerkleProof.verify(
        proof,
        ogPhaseMerkle,
        keccak256(abi.encodePacked(msg.sender))
    );
  }

  /// @notice Checks if an address is whitelisted for WL phase
  /// @param proof Merkle proof for verification
  /// @return bool Whether the address is whitelisted
  function isWLWhitelisted(bytes32[] calldata proof) public view returns (bool) {
    return MerkleProof.verify(
        proof,
        wlPhaseMerkle,
        keccak256(abi.encodePacked(msg.sender))
    );
  }

  /// @notice Mints tokens during OG phase
  /// @param proof Merkle proof for verification
  function mintOG(bytes32[] calldata proof) external payable nonReentrant {
    if (currentPhase != Phase.WL_ONLY) revert MintingClosed();
    if (!isOGWhitelisted(proof)) revert NotWhitelisted();
    uint minted = mintedPerWallet[msg.sender];
    if (minted >= MAX_WL_MINTS) revert ExceedsWalletLimit();
    if (_totalMinted() + 1 > MAX_SUPPLY) revert ExceedsMaxSupply();
    if (msg.value != OG_PRICE) revert InvalidPayment();

    mintedPerWallet[msg.sender] = minted + 1;
    _mint(msg.sender, 1);
  }

  /// @notice Mints tokens during WL phase
  /// @param proof Merkle proof for verification
  function mintWL(bytes32[] calldata proof) external payable nonReentrant {
    if (currentPhase != Phase.WL_ONLY) revert MintingClosed();
    if (!isWLWhitelisted(proof)) revert NotWhitelisted();
    uint minted = mintedPerWallet[msg.sender];
    if (minted >= MAX_WL_MINTS) revert ExceedsWalletLimit();
    if (_totalMinted() + 1 > MAX_SUPPLY) revert ExceedsMaxSupply();
    if (msg.value != MINT_PRICE) revert InvalidPayment();

    mintedPerWallet[msg.sender] = minted + 1;
    _mint(msg.sender, 1);
  }

  /// @notice Mints tokens during public phase
  /// @param quantity Number of tokens to mint
  function mint(uint256 quantity) external payable nonReentrant {
    if (currentPhase != Phase.PUBLIC) revert MintingClosed();
    uint256 walletMints = mintedPerWallet[msg.sender];
    if (walletMints + quantity > MAX_MINTS_PER_WALLET) revert ExceedsWalletLimit();
    if (_totalMinted() + quantity > MAX_SUPPLY) revert ExceedsMaxSupply();
    if (msg.value != MINT_PRICE * quantity) revert InvalidPayment();

    mintedPerWallet[msg.sender] = walletMints + quantity;
    _mint(msg.sender, quantity);
  }

  /// @notice Updates the base URI for token metadata
  /// @param newBaseURI New base URI string
  function setBaseURI(string memory newBaseURI) external onlyOwner {
    baseURI = newBaseURI;
    emit BaseURIUpdated(newBaseURI);
  }

  /// @notice Updates royalty information and payment receiver
  /// @param receiver New receiver address for both royalties and withdrawals
  /// @param feeNumerator New royalty percentage (in basis points)
  function setRoyaltyInfo(address receiver, uint96 feeNumerator) external onlyOwner {
    if (receiver == address(0)) revert InvalidPaymentReceiver();
    if (feeNumerator > 1000) revert InvalidRoyaltyBPS();
    
    _setDefaultRoyalty(receiver, feeNumerator);
    emit RoyaltyUpdated(feeNumerator, receiver);
  }

  /// @notice Toggles whether tokens can be transferred
  /// @param _enabled New transfer state
  function setTransfersEnabled(bool _enabled) external onlyOwner {
    transfersEnabled = _enabled;
    emit TransferStateUpdated(_enabled);
  }

  /// @notice Sets the merkle roots for whitelist phases
  /// @param _ogRoot Merkle root for OG phase
  /// @param _wlRoot Merkle root for WL phase
  function setMerkleRoots(bytes32 _ogRoot, bytes32 _wlRoot) external onlyOwner {
    ogPhaseMerkle = _ogRoot;
    wlPhaseMerkle = _wlRoot;
  }

  /// @notice Sets the current minting phase
  /// @param newPhase New phase to set
  function setPhase(Phase newPhase) external onlyOwner {
    if (uint8(newPhase) > uint8(Phase.PUBLIC)) revert InvalidPhase();
    if (newPhase == Phase.PUBLIC && currentPhase == Phase.LOCKED) revert InvalidPhaseTransition();
    currentPhase = newPhase;
    emit PhaseUpdated(newPhase);
  }

  /// @notice Withdraws contract balance to payment receiver
  function withdraw() external onlyOwner {
    (bool success, ) = paymentReceiver.call{value: address(this).balance}("");
    require(success, "Transfer failed");
  }

  function _baseURI() internal view override returns (string memory) {
    return baseURI;
  }

  function _beforeTokenTransfers(
    address from,
    address to,
    uint256 startTokenId,
    uint256 quantity
  ) internal override {
    if (!transfersEnabled && from != address(0)) revert TransfersLocked();
    super._beforeTokenTransfers(from, to, startTokenId, quantity);
  }

  /// @notice ERC721A, ERC2981 support
  function supportsInterface(bytes4 interfaceId)
      public
      view
      override(ERC721A, ERC2981)
      returns (bool)
  {
      return ERC721A.supportsInterface(interfaceId) || 
        ERC2981.supportsInterface(interfaceId);
  }
}