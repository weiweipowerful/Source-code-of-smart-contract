// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// TO DO: Explain the reason/advantadge to use ERC721URIStorage instead of ERC721 itself
contract NFT is ERC721URIStorage {
    uint256 private _tokenIds;
    bool public _isTransferContract;

    mapping(address => bool) private _operator;
    mapping(address => bool) private _contractAddrerss;
    mapping(uint256 => DataToken) private _dataTokens;
    mapping(string => uint256) private eventType;

    string public _baseUri = "";

    struct DataToken {
        uint256 tokenId;
        address creator;
        string ipfsId;
        uint256 package;
        uint256 numberTransfer;
        uint256 startAt;
        uint256 expriedAt;
        uint256 status; // mint = 1, transfer casino owner = 2, transfer lockup operator = 3
        uint256 stakingStatus; // status staking = 1, sttaus unstaking = 2
    }

    event EventToken(
        uint256 tokenId,
        address creator,
        string ipfsId,
        uint256 package,
        uint256 startAt,
        uint256 expriedAt,
        uint256 status,
        uint256 stakingStatus,
        uint256 eventTypeCode
    );

    constructor(
        address addressOperator,
        string memory baseURI,
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        _operator[addressOperator] = true;
        _operator[msg.sender] = true;
        _baseUri = baseURI;
        _isTransferContract = false;

        eventType["mint"] = 1;
        eventType["buy"] = 2;
        eventType["update"] = 3;
        eventType["transfer_operator"] = 4;
    }

    /**
     * @dev Modifier to restrict access to minting functionality
     * @param contractAddress - The contract address
     * @return bool - The status of the contract address
     */
    function onlyContractAddress(address contractAddress) internal view returns (bool) {
        if (_contractAddrerss[contractAddress] || address(this) == contractAddress){
            return true;
        }

        return false;
    }

    /**
     * @dev Modifier to restrict access to minting functionality
     */
    modifier onlyOperator() {
        require(_operator[msg.sender], "Not a minter");
        _;
    }

    /**
     * @dev Function to set a new minter, only accessible by the contract owner
     * @param operator - The operator address
     * @param status - The status of the operator
     */
    function setOperator(address operator, bool status) external onlyOperator {
        _operator[operator] = status;
    }

    /**
     * @dev Function to set a new contract address, only accessible by the contract owner
     * @param contractAddress - The contract address
     * @param status - The status of the contract address
     */
    function setContractAddress(address contractAddress, bool status) external onlyOperator {
        _contractAddrerss[contractAddress] = status;
    }

    /**
     * @dev Function to set a new transfer contract, only accessible by the contract owner
     * @param status - The status of the transfer contract
     */
    function setTransferContract(bool status) external onlyOperator {
        _isTransferContract = status;
    }

    /**
     * @dev Modifier to restrict access to minting functionality
     */
    modifier onlyStaking {
        require(_contractAddrerss[msg.sender], "Only the specified staking contract will be executed");
        _;
    }

    /**
     * @dev Mint tokens
     * @param ipfsIds - The IPFS hash of the token metadata
     * @param creator - The address of the creator
     * @return tokenIds - The token IDs of the minted tokens
     */
    function mintTokens(
        string[] memory ipfsIds,
        address creator
    ) public onlyOperator returns (uint256[] memory) {
        require(ipfsIds.length > 0, "Token URIs must not be empty");
        uint256[] memory tokenIds = new uint256[](ipfsIds.length);

        for (uint256 i = 0; i < ipfsIds.length; i++) {
            require(bytes(ipfsIds[i]).length != 0, "tokenURI must be nonzero");

            _tokenIds += 1;
            uint256 tokenId = _tokenIds;
            _safeMint(creator, tokenId);
            // Default packages
            uint256 package = 1;
            // Number of transfers
            uint256 numberTransfer = 0;
            // Time start lockup
            uint256 startAt = 0;
            // Time end lockup;
            uint256 expriedAt = 0;
            // New mint status
            uint256 status = 1;
            // Staking status => unstaking
            uint256 stakingStatus = 2;
            _dataTokens[tokenId] = DataToken(tokenId, creator, ipfsIds[i], package, numberTransfer, startAt, expriedAt, status, stakingStatus);
            tokenIds[i] = tokenId;
        }

        setApprovalForAll(address(this), true);

        // Shoot the mint token event for each tokenId
        for (uint256 j = 0; j < tokenIds.length; j++) {
            emitEventToken(tokenIds[j], eventType["mint"]);
        }

        return tokenIds;
    }

    /**
     * @dev Mint token to casino owner
     * @param buytor_address - The buytor address
     * @param package - The package of the token
     * @param ipfsId - The IPFS hash of the token metadata
     * @param startAt - The start at of the token
     * @param expriedAt - The expried at of the token
     */
    function mintToCasinoOwner(
        address buytor_address,
        uint256 package,
        string memory ipfsId,
        uint256 startAt,
        uint256 expriedAt
    ) public onlyOperator returns (uint256) {
        _tokenIds += 1;
        uint256 tokenId = _tokenIds;
        // Mint token to buytor
        _safeMint(buytor_address, tokenId);
        // Number of transfers
        uint256 numberTransfer = 0;
        // Status mint to casino owner
        uint256 status = 2;
        // Staking status => unstaking
        uint256 stakingStatus = 2;
        _dataTokens[tokenId] = DataToken(tokenId, buytor_address, ipfsId, package, numberTransfer, startAt, expriedAt, status, stakingStatus);

        setApprovalForAll(address(this), true);

        emitEventToken(tokenId, eventType["mint"]);

        return tokenId;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_dataTokens[tokenId].tokenId > 0, "ERC721Metadata: URI query for nonexistent token");
        return string(abi.encodePacked(_baseUri, _dataTokens[tokenId].ipfsId));
    }

    /**
     * @dev Set the base URI for all token IDs.
     */
    function setBaseURI(string memory baseUri) public onlyOperator {
        _baseUri = baseUri;
    }

    /** Get the current token id */
    function getTokenId() public view returns (uint256) {
        return _tokenIds;
    }

    /** Get tokens owned by me */
    function getTokensOwnedByMe() public view returns (uint256[] memory) {
        uint256 numberOfExistingTokens = _tokenIds;
        uint256 numberOfTokensOwned = balanceOf(msg.sender);
        uint256[] memory ownedTokenIds = new uint256[](numberOfTokensOwned);

        uint256 currentIndex = 0;
        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            if (ownerOf(tokenId) != msg.sender) continue;
            ownedTokenIds[currentIndex] = tokenId;
            currentIndex += 1;
        }

        return ownedTokenIds;
    }

    /**
    * @dev Get tokens owned by address
    * @param walletAddress - The wallet address
    */
    function getTokensOwnedByAddress(address walletAddress) public view returns (uint256[] memory) {
        uint256 numberOfExistingTokens = _tokenIds;
        uint256 numberOfTokensOwned = balanceOf(walletAddress);
        uint256[] memory ownedTokenIds = new uint256[](numberOfTokensOwned);

        uint256 currentIndex = 0;
        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            if (ownerOf(tokenId) != walletAddress) continue;
            ownedTokenIds[currentIndex] = tokenId;
            currentIndex += 1;
        }

        return ownedTokenIds;
    }

    /** Get token creator by id */
    function getTokenCreatorById(uint256 tokenId) public view returns (address) {
        return _dataTokens[tokenId].creator;
    }

    /*
    * @dev Is token
    * @param tokenId - The token ID
    */
    function isTokenId(uint256 tokenId) public view returns (bool) {
        if (_dataTokens[tokenId].tokenId > 0) {
            return true;
        }

        return false;
    }

    /** Get the token creator by my */
    function getTokensCreatedByMe() public view returns (uint256[] memory) {
        uint256 numberOfExistingTokens = _tokenIds;
        uint256 numberOfTokensCreated = 0;

        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            if (_dataTokens[tokenId].creator != msg.sender) continue;
            numberOfTokensCreated += 1;
        }

        uint256[] memory createdTokenIds = new uint256[](numberOfTokensCreated);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            if (_dataTokens[tokenId].creator != msg.sender) continue;
            createdTokenIds[currentIndex] = tokenId;
            currentIndex += 1;
        }

        return createdTokenIds;
    }

    /** Get all token nft */
    function getAllTokenNft() public view returns (uint256, uint256[] memory) {
        uint256 numberOfExistingTokens = _tokenIds;

        uint256[] memory createdTokenIds = new uint256[](numberOfExistingTokens);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            createdTokenIds[currentIndex] = tokenId;
            currentIndex += 1;
        }

        return (numberOfExistingTokens, createdTokenIds);
    }

    /** Take out all nft and get new mint */
    function getAllTokenNftMint() public view returns (uint256, uint256[] memory) {
        uint256 numberOfExistingTokens = _tokenIds;
        uint256 numberOfTokensMint = 0;

        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            if (_dataTokens[tokenId].status == 1){
                numberOfTokensMint += 1;
            }
        }

        uint256[] memory createdTokenIds = new uint256[](numberOfTokensMint);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            // Status 1 = new minted nft
            if (_dataTokens[tokenId].status == 1) {
                createdTokenIds[currentIndex] = tokenId;
                currentIndex += 1;
            }
        }

        return (numberOfTokensMint, createdTokenIds);
    }

    /** Retrieve all nft transferred to casino owner */
    function getAllTokenNftTransferCasinoOwner() public view returns (uint256, uint256[] memory) {
        uint256 numberOfExistingTokens = _tokenIds;
        uint256 numberOfTokensTCO = 0;

        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            if (_dataTokens[tokenId].status == 2){
                numberOfTokensTCO += 1;
            }
        }

        uint256[] memory createdTokenIds = new uint256[](numberOfTokensTCO);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            // Status 2 = nft has been transferred to casino owner
            if (_dataTokens[tokenId].status == 2) {
                createdTokenIds[currentIndex] = tokenId;
                currentIndex += 1;
            }
        }

        return (numberOfTokensTCO, createdTokenIds);
    }

    /** Retrieve all nft transferred back to the casino owner */
    function getAllTokenNftTransferOperator() public view returns (uint256, uint256[] memory) {
        uint256 numberOfExistingTokens = _tokenIds;
        uint256 numberOfTokensTO = 0;

        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            if (_dataTokens[tokenId].status == 3){
                numberOfTokensTO += 1;
            }
        }

        uint256[] memory createdTokenIds = new uint256[](numberOfTokensTO);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < numberOfExistingTokens; i++) {
            uint256 tokenId = i + 1;
            // status 3 = nft is transferred lockup by casino owner to operator
            if (_dataTokens[tokenId].status == 3) {
                createdTokenIds[currentIndex] = tokenId;
                currentIndex += 1;
            }
        }

        return (numberOfTokensTO, createdTokenIds);
    }

    /**
    * @dev Upgrade package
    * @param tokenId - The token ID
    * @param ipfsId - The IPFS hash of the token metadata
    * @param package - The package of the token
    * @param expriedAt - The expried at of the token
    */
    function upgradePackage(
        uint256 tokenId,
        string memory ipfsId,
        uint256 package,
        uint256 expriedAt
    ) public payable onlyOperator returns (uint256){
        _dataTokens[tokenId].ipfsId = ipfsId;
        _dataTokens[tokenId].package = package;
        _dataTokens[tokenId].expriedAt = expriedAt;

        emitEventToken(tokenId, eventType["update"]);

        return tokenId;
    }

    /**
    * @dev Emit event token
    * @param tokenId - The token ID
    * @param eventTypeCode - The event type code
    */
    function emitEventToken(uint256 tokenId, uint256 eventTypeCode) internal {
        DataToken storage marketItem = _dataTokens[tokenId];

        emit EventToken(
            marketItem.tokenId,
            marketItem.creator,
            marketItem.ipfsId,
            marketItem.package,
            marketItem.startAt,
            marketItem.expriedAt,
            marketItem.status,
            // Status staking
            marketItem.stakingStatus,
            eventTypeCode
        );
    }

    /**
    * @dev Get data token
    * @param tokenId - The token ID
    */
    function getDataToken(uint256 tokenId)
        public
        view
        returns (DataToken memory)
    {
        return _dataTokens[tokenId];
    }


    /**
    * @dev Buy NFT
    * @param tokenId - The token ID
    * @param buytor_address - The buytor address
    * @param owner_address - The owner address
    * @param package - The package of the token
    */
    function buyNft(
        uint256 tokenId,
        address buytor_address,
        address owner_address,
        uint256 package,
        string memory ipfsId,
        uint256 startAt,
        uint256 expriedAt
    ) public payable onlyOperator returns (uint256){
        require(_dataTokens[tokenId].tokenId > 0 , "Token not found");
        // Transfer token to buytor
        transferFrom(owner_address, buytor_address, tokenId);
        // Update data token
        _dataTokens[tokenId].package = package;
        _dataTokens[tokenId].ipfsId = ipfsId;
        _dataTokens[tokenId].creator = buytor_address;
        _dataTokens[tokenId].startAt = startAt;
        _dataTokens[tokenId].expriedAt = expriedAt;
        // Status transfer to the user
        _dataTokens[tokenId].status = 2;

        emitEventToken(tokenId, eventType["buy"]);

        return tokenId;
    }

    /**
    * @dev Transfer NFT to operator
    * @param tokenId - The token ID
    * @param operator - The operator address
    */
    function transferToOperator(
        uint256 tokenId,
        address operator
    ) public payable returns (uint256) {
        require(_dataTokens[tokenId].tokenId > 0, "NFT not found");
        // Transfer token to operator
        address owner = ownerOf(tokenId);
        transferFrom(owner, operator, tokenId);
        _dataTokens[tokenId].package = 1;
        _dataTokens[tokenId].creator = payable(operator);
        _dataTokens[tokenId].startAt = 0;
        _dataTokens[tokenId].expriedAt = 0;
        // Casino owner status transferred to operator
        _dataTokens[tokenId].status = 3;

        emitEventToken(tokenId, eventType["transfer_operator"]);

        return tokenId;
    }

    /**
    * @dev Update data token
    * @param tokenId - The token ID
    * @param ipfsId - The IPFS hash of the token metadata
    * @param package - The package of the token
    * @param expriedAt - The expried at of the token
    */
    function updataDataToken(
        uint256 tokenId,
        string memory ipfsId,
        uint256 package,
        uint256 startAt,
        uint256 expriedAt
    ) public onlyOperator {
        _dataTokens[tokenId].ipfsId = ipfsId;
        _dataTokens[tokenId].package = package;
        _dataTokens[tokenId].startAt = startAt;
        _dataTokens[tokenId].expriedAt = expriedAt;

        emitEventToken(tokenId, eventType["uprage"]);
    }

    /**
    * @dev Update status staking
    * @param tokenId - The token ID
    * @param status - status staking
    */
    function updataStakingStatus(
        uint256 tokenId,
        uint256 status
    ) external onlyStaking {
        _dataTokens[tokenId].stakingStatus = status;

        emitEventToken(tokenId, eventType["uprage"]);
    }

    /**
    * @dev Get NFT status
    * @param tokenId - The token ID
    */
    function getNFTStatus(
        uint256 tokenId
    ) public view returns (bool, uint256, string memory) {
        require(tokenId > 0, "tokenId is required.");

        // Default value if object not found
        bool status = false;

        if (_dataTokens[tokenId].numberTransfer == 0) {
            status = true;
        }

        // Returns the default value if the object is not found
        return (status,  _dataTokens[tokenId].package, tokenURI(tokenId));
    }

    /**
    * @dev Check lockup NFT
    * @param tokenId - The token ID
    */
    function checkLockupNFT(
        uint256 tokenId
    ) public view returns (bool, uint256, uint256) {
        require(tokenId > 0, "tokenId is required.");

        // Default value if object not found
        bool isExpred = false;

        if (_dataTokens[tokenId].expriedAt != 0 && block.timestamp < _dataTokens[tokenId].expriedAt) {
            isExpred = true;
        }
        
        return (isExpred, _dataTokens[tokenId].package, block.timestamp);
    }

    /**
    * @dev Transfer from
    * @param from - The from address
    * @param to - The to address
    * @param tokenId - The token ID
    */
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
        // The transfer condition to another exchange only works when configured to allow transfer to another contract or specified contracts
        if (!_isTransferContract && isContract(to) && !onlyContractAddress(to)) {
            revert("Not a contract address or token is pending during lockup");
        }

        // During the lockup period, transfers are not allowed. Status = 2 is transferred to the casino owner
        if (_dataTokens[tokenId].status == 2 && _dataTokens[tokenId].expriedAt > 0 && block.timestamp < _dataTokens[tokenId].expriedAt) {
            revert("Currently in lockup period");
        }

        // If nft is staking, it cannot be transferred. stakingStatus = 1 is staking
        if (_dataTokens[tokenId].stakingStatus == 1) {
            revert("NFT is staking so transfer is not allowed");
        }

        super.transferFrom(from, to, tokenId);

        _dataTokens[tokenId].numberTransfer = (_dataTokens[tokenId].numberTransfer + 1);
    }

    /**
    * @dev Check contract address
    * @param contractAddress - The address
    */
    function isContract(address contractAddress) public view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(contractAddress)
        }
        return (size > 0);
    }
}