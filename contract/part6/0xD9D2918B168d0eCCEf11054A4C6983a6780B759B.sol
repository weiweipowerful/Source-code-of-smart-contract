// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "erc721a/contracts/ERC721A.sol";

contract NudleDudle is ERC721A, Ownable {
    using Strings for uint256;

    // ================== VARAIBLES =======================

    bytes32 public merkleRootBL;
    bool public revealed = true;

    enum SaleState {
        PAUSE, // 0
        WHITELIST_SALE, // 1
        PUBLIC_SALE // 2
    }
    SaleState public saleState = SaleState.PAUSE;

    string private uriPrefix = "";
    string private uriSuffix = ".json";
    string private hiddenMetadataUri;

    uint256 public wlPrice = 0.001 ether;
    uint256 public salePrice = 0.001 ether;

    uint256 public maxFree = 5;
    uint256 public maxWLTx = 10;
    uint256 public maxTx = 20;
    uint256 public limitedFree = 2000;

    uint256 public maxSupply = 5555;

    uint256 public FREE_MINTED = 0;
    mapping(address => uint256) public CLAIMED;

    mapping(address => uint256) public MINT_COUNT;
    mapping(address => uint256) public WL_MINT_COUNT;

    // ================== CONTRUCTOR =======================

    constructor() ERC721A("Nudle Dudle", "NudleDudle") {
        setHiddenMetadataUri("ipfs://__CID__/hidden.json");
    }

    // ================== MINT FUNCTIONS =======================

    /**
     * @notice Public Mint
     */
    function publicMint(uint256 _quantity) external payable {
        // Normal requirements
        require(saleState == SaleState.PUBLIC_SALE, "Wait for public mint");
        require(_quantity > 0, "Invalid mint amount!");
        require(totalSupply() + _quantity <= maxSupply, "Sold out!");
        require(
            MINT_COUNT[msg.sender] + _quantity <= maxTx,
            "Max mint per wallet exceeded!"
        );
        if (FREE_MINTED >= limitedFree) {
            require(
                msg.value >= salePrice * _quantity,
                "Please send the exact amount."
            );
        } else {
            if (
                !(CLAIMED[msg.sender] >= maxFree) &&
                FREE_MINTED + _quantity <= maxSupply
            ) {
                if (_quantity <= maxFree - CLAIMED[msg.sender]) {
                    require(msg.value >= 0, "Please send the exact amount.");
                } else {
                    require(
                        msg.value >=
                            wlPrice *
                                (_quantity - (maxFree - CLAIMED[msg.sender])),
                        "Please send the exact amount."
                    );
                }
                FREE_MINTED += _quantity;
                CLAIMED[msg.sender] += _quantity;
            } else {
                require(
                    msg.value >= wlPrice * _quantity,
                    "Please send the exact amount."
                );
            }
        }

        // Mint
        _safeMint(msg.sender, _quantity);

        // Mapping update
        MINT_COUNT[msg.sender] += _quantity;
    }

    /**
     * @notice Whitelist Mint
     */
    function whitelistMint(
        uint256 _quantity,
        bytes32[] calldata _merkleProof
    ) external payable {
        // Verify whitelist requirements
        require(
            saleState == SaleState.WHITELIST_SALE,
            "Wait for whitelist mint"
        );
        require(isWhitelist(_merkleProof), "Address is not whitelisted!");

        // Normal requirements
        require(_quantity > 0, "Invalid mint amount!");
        require(totalSupply() + _quantity <= maxSupply, "Sold out!");
        require(
            WL_MINT_COUNT[msg.sender] + _quantity <= maxWLTx,
            "Max mint per wallet exceeded!"
        );
        if (FREE_MINTED >= limitedFree) {
            require(
                msg.value >= salePrice * _quantity,
                "Please send the exact amount."
            );
        } else {
            if (
                !(CLAIMED[msg.sender] >= maxFree) &&
                FREE_MINTED + _quantity <= maxSupply
            ) {
                if (_quantity <= maxFree - CLAIMED[msg.sender]) {
                    require(msg.value >= 0, "Please send the exact amount.");
                } else {
                    require(
                        msg.value >=
                            wlPrice *
                                (_quantity - (maxFree - CLAIMED[msg.sender])),
                        "Please send the exact amount."
                    );
                }
                FREE_MINTED += _quantity;
                CLAIMED[msg.sender] += _quantity;
            } else {
                require(
                    msg.value >= wlPrice * _quantity,
                    "Please send the exact amount."
                );
            }
        }

        // Mint
        _safeMint(msg.sender, _quantity);

        // Mapping update
        WL_MINT_COUNT[msg.sender] += _quantity;
    }

    /**
     * @notice Team Mint
     */
    function teamMint(uint256 _quantity) external onlyOwner {
        require(totalSupply() + _quantity <= maxSupply, "Sold out");
        _safeMint(msg.sender, _quantity);
    }

    /**
     * @notice airdrop
     */
    function airdrop(address _to, uint256 _quantity) external onlyOwner {
        require(saleState != SaleState.PAUSE, "The contract is paused!");
        require(_quantity + totalSupply() <= maxSupply, "Sold out");
        _safeMint(_to, _quantity);
    }

    /**
     * @notice Check if the address is in the whitelist or not
     */
    function isWhitelist(
        bytes32[] calldata _merkleProof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (MerkleProof.verify(_merkleProof, merkleRootBL, leaf)) {
            return true;
        }
        return false;
    }

    // ================== SETUP FUNCTIONS =======================

    function setRevealed(bool _state) public onlyOwner {
        revealed = _state;
    }

    function setState(SaleState _state) external onlyOwner {
        saleState = _state;
    }

    function setWhitelist(bytes32 _merkleRoot) external onlyOwner {
        merkleRootBL = _merkleRoot;
    }

    function setSalePrice(uint256 _newPrice) external onlyOwner {
        salePrice = _newPrice;
    }

    function setWlPrice(uint256 _newPrice) external onlyOwner {
        wlPrice = _newPrice;
    }

    function setMaxFree(uint256 _maxFree) public onlyOwner {
        maxFree = _maxFree;
    }

    function setMaxTx(uint256 _maxTx) public onlyOwner {
        maxTx = _maxTx;
    }

    function setMaxWlTx(uint256 _maxBLTx) public onlyOwner {
        maxWLTx = _maxBLTx;
    }

    function setLimitedFree(uint256 _limitedFree) public onlyOwner {
        limitedFree = _limitedFree;
    }

    function setMaxSupply(uint256 _maxSupply) public onlyOwner {
        maxSupply = _maxSupply;
    }

    function setHiddenMetadataUri(
        string memory _hiddenMetadataUri
    ) public onlyOwner {
        hiddenMetadataUri = _hiddenMetadataUri;
    }

    function setUriPrefix(string memory _uriPrefix) public onlyOwner {
        uriPrefix = _uriPrefix;
    }

    function setUriSuffix(string memory _uriSuffix) public onlyOwner {
        uriSuffix = _uriSuffix;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return uriPrefix;
    }

    function walletOfOwner(
        address _owner
    ) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
        uint256 currentTokenId = 1;
        uint256 ownedTokenIndex = 0;

        while (
            ownedTokenIndex < ownerTokenCount && currentTokenId <= maxSupply
        ) {
            address currentTokenOwner = ownerOf(currentTokenId);
            if (currentTokenOwner == _owner) {
                ownedTokenIds[ownedTokenIndex] = currentTokenId;
                ownedTokenIndex++;
            }
            currentTokenId++;
        }
        return ownedTokenIds;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view virtual override returns (string memory) {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        if (revealed == false) {
            return hiddenMetadataUri;
        }
        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        _tokenId.toString(),
                        uriSuffix
                    )
                )
                : "";
    }

    function withdraw() external onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "Transfer failed.");
    }
}