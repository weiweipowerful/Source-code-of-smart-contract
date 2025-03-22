// SPDX-License-Identifier: VPL - VIRAL PUBLIC LICENSE
pragma solidity 0.8.28;

/*

     _                              _             _    ___ ___
    | |                            | |           | |  |  _|_  |
  __| |_ __ ___  __ _ _ __ ___  ___| |_ __ _  ___| | _| |   | |_  ___   _ ____
 / _` | '__/ _ \/ _` | '_ ` _ \/ __| __/ _` |/ __| |/ / |   | \ \/ / | | |_  /
| (_| | | |  __/ (_| | | | | | \__ \ || (_| | (__|   <| | _ | |>  <| |_| |/ /
 \__,_|_|  \___|\__,_|_| |_| |_|___/\__\__,_|\___|_|\_\ |(_)| /_/\_\\__, /___|
                                                      |___|___|      __/ |
                                                                    |___/

**/

import "lib/solady/src/utils/LibClone.sol";
import "lib/solady/src/utils/LibBitmap.sol";

import "./modded/creator-token-standards/ERC721C.sol";
import "./modded/creator-token-standards/BasicRoyalties.sol";
import "./modded/openzeppelin/ReentrancyGuard.sol"; // this version uses tstore

import "./Refunds.sol";

import "./Interfaces.sol";
import "./Structs.sol";
import "./Withdrawable.sol"; // for stray tokens
import "./LibPack.sol";
import "./Errors.sol";
import "./Common.sol";

contract Hub is IHub, ERC721C, BasicRoyalties, Withdrawable, Refunds, ReentrancyGuard {
    Supply private _supply;
    string private _name;
    string private _symbol;

    uint256 public constant OWNER_TOKENID = 0;

    uint256 private constant ONE = 1 ether;
    uint256 public constant SHARE_SCALAR = ONE;
    uint256 public constant HUB_DIVISOR = 100_00;
    uint256 public hubRoyalty = 2_50;
    uint256 public hubPercentage = 2_50;
    uint256 public immortalizeFee; // = type(uint256).max; // setImmortalizeFee will unlock!

    address public paymentFiltererTemplate;
    address[] public nftTemplates; // allow for versioning of nftTemplates since we may find from users that they desire nft templates with added/reduced functionality or improved implementations
    IPremierAccessERC1155 public premierAccess;
    IRobustRenderer public robustRenderer;
    IValidityLens public validityLens;
    IURI public uriRenderer;
    IBridging public bridging;
    IProver public prover;

    uint256 public freelancerPercentage;
    uint96 public minFeeNumerator; // to ensure downstream elements get recognized
    uint256 public maxBurnWindow;

    mapping(uint256 => uint256) private _collectionIdxs;
    INFT[] public allCollections;

    mapping(address => bool) public accountOptedOut;
    mapping(uint256 => IPaymentFilterer) private _beneficiaries;
    mapping(bytes32 => uint256) public pledgedRevealTimestamps;
    mapping(address => bool) public platformApprovedWrapper;
    mapping(uint256 => mapping(address => bool)) public ownerApprovedTokenWrapper;
    mapping(uint256 => bool) public ownerApprovedTokenOpen;
    // didn't do bitmap in above maps since they are all staticcall render related so would
    // not benefit greatly from gas vs bytecode size
    LibBitmap.Bitmap private _burned;

    event NewCollection(string collectionName, string collectionSymbol, uint256 curationTokenId, address nft);
    event FreelancerPercentageSet(uint256 newFreelancerPercentage);
    event MinFeeNumeratorSet(uint96 newFeeNumerator);
    event MaxBurnWindowSet(uint256 newMax);
    event NewNFTTemplate(uint256 idx, address newNFTTemplate);
    event AccountOptedOut(address account, bool tf);
    event ArtImmortalized(uint256 tokenId, Type t);
    event NewEncryptedReference(bytes32 encrypted, uint256 pledgedRevealTimestamp);
    event BridgingSet(bool active);
    event ContractURIUpdated();
    event MetadataUpdate(uint256 curationTokenId);

    constructor(address initialOwner) payable BasicRoyalties(initialOwner, uint96(hubRoyalty)) {
        _name = "DreamStack";
        _symbol = "DRS";
        _incrementSupply(1);
        _mint(initialOwner, OWNER_TOKENID);
        // means tabs cannot have tokenId < 1 lol
        allCollections.push(INFT(address(0))); // so that getCollection will consider 0 idx as pathological
    }

    receive() external payable {}
    fallback() external payable {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721C, ERC2981) returns (bool) {
        return ERC721C.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId)
            || super.supportsInterface(interfaceId);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function setComponents(
        INFT nft_,
        IPremierAccessERC1155 premierAccess_,
        IPaymentFilterer paymentFiltererTemplate_,
        IRobustRenderer robustRenderer_,
        IValidityLens validityLens_,
        IURI uri_,
        IRefunder refunder_
    ) external {
        _onlyOwner();

        if (address(premierAccess) != address(0)) revert AlreadySet_error();

        nftTemplates.push(address(nft_));
        premierAccess = premierAccess_;
        paymentFiltererTemplate = address(paymentFiltererTemplate_);
        robustRenderer = robustRenderer_;
        validityLens = validityLens_;
        platformApprovedWrapper[address(validityLens_)] = true;
        uriRenderer = uri_;
        platformApprovedWrapper[address(uri_)] = true;
        refunder = refunder_;
        refunder_.setCustomer(address(this));
        refunder_.setCustomer(address(premierAccess_));

        emit ContractURIUpdated();
    }

    function totalSupply() external view returns (uint256) {
        return uint256(_supply.totalSupply);
    }

    function totalMinted() external view returns (uint256) {
        return uint256(_supply.totalMinted);
    }

    function owner() public view override(IHub) returns (address) {
        if (!_exists(OWNER_TOKENID)) return address(0);
        return ownerOf(OWNER_TOKENID);
    }

    function contractURI() external view returns (string memory) {
        // wrapping is ok
        return uriRenderer.hubContractURI();
    }

    function tokenURI(uint256 curationTokenId) public view override(ERC721, IHub) returns (string memory ret) {
        bool ok;
        ownerOf(curationTokenId); // will throw if dne!
        (ok, ret) = _tokenURI(curationTokenId, msg.sender);
        if (!ok) revert NoWrapping_error();
    }

    function _tokenURI(uint256 curationTokenId, address caller) private view returns (bool ok, string memory ret) {
        if (
            !(
                caller == tx.origin || platformApprovedWrapper[caller] || ownerApprovedTokenOpen[curationTokenId]
                    || ownerApprovedTokenWrapper[curationTokenId][caller]
            )
        ) return (false, ret);
        return (true, uriRenderer.hubTokenURI(curationTokenId));
    }

    function multiTokenURI(uint256[] calldata curationTokenIds) public view returns (string[] memory ret) {
        ret = _allocateStringArr(curationTokenIds.length);
        bool ok;
        uint256 id;
        for (uint256 i; i < curationTokenIds.length; ++i) {
            string memory uri;
            id = curationTokenIds[i];
            if (!_exists(id)) continue; // gracefully ignores
            (ok, uri) = _tokenURI(id, msg.sender);
            if (ok) ret[i] = uri; // otherwise gracefully ignores
        }
    }

    // since the hub itself can be sold lol!
    // can be called by anyone
    function setDefaultRoyalty() external {
        _setDefaultRoyalty(ownerOf(OWNER_TOKENID), uint96(hubRoyalty));

        emit MetadataUpdate(OWNER_TOKENID);
        emit ContractURIUpdated();
    }

    function setHubValues(uint256 hubPercentage_, uint256 hubRoyalty_) external {
        _onlyOwner();
        hubPercentage = hubPercentage_;
        hubRoyalty = hubRoyalty_;
    }

    function addNewNFTTemplate(address newNFTTemplate) external {
        _onlyOwner();
        uint256 idx = nftTemplates.length;
        nftTemplates.push(newNFTTemplate);
        emit NewNFTTemplate(idx, newNFTTemplate);
    }

    function nftTemplatesLength() external view returns (uint256) {
        return nftTemplates.length;
    }

    // VERY convenient in the case of V2 etc
    function setApprovedWrapper(address wrapper) external {
        _onlyOwner();
        platformApprovedWrapper[wrapper] = true;
    }

    function setApprovedTokenOpen(uint256 curationTokenId) external {
        if (msg.sender != ownerOf(curationTokenId)) revert NotOwner_error();
        ownerApprovedTokenOpen[curationTokenId] = true;
    }

    function setApprovedTokenWrapper(uint256 curationTokenId, address wrapper) external {
        if (msg.sender != ownerOf(curationTokenId)) revert NotOwner_error();
        ownerApprovedTokenWrapper[curationTokenId][wrapper] = true;
    }

    function setBridging(IBridging bridging_, IProver prover_) external {
        _onlyOwner();
        bridging = bridging_;
        prover = prover_;
        emit BridgingSet(address(bridging_) != address(0) && address(prover_) != address(0));
        // we have bridging for the INFT's but not for these DreamStack curated components,
        // since payment streams of curated components would not map properly when bridged.
        // specifically if we had the PaymentFilterer check some "isBridged", then a bridged
        // frame could not receive a release which would stall transfers to featuredIds.
        // perhaps this feature will be in V2!!
    }

    function ownerOf(uint256 tokenId) public view override(IHub, ERC721) returns (address) {
        return super.ownerOf(tokenId);
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function beneficiariesOf(uint256 tokenId) public view returns (IPaymentFilterer beneficiary, address holder) {
        beneficiary = _beneficiaries[tokenId]; // if non-null, then is payment filterer associated with frame
        holder = _exists(tokenId) ? ownerOf(tokenId) : address(this);
    }

    function optOutIncentivizedRelease(bool optOut) external {
        accountOptedOut[msg.sender] = optOut;

        emit AccountOptedOut(msg.sender, optOut);
    }

    function getCollection(uint256 curationTokenId) public view returns (INFT) {
        return allCollections[_collectionIdxs[curationTokenId]];
    }

    function allCollectionsLength() public view returns (uint256) {
        return allCollections.length;
    }

    // note: feeDenominator is 100_00

    function setMinFeeNumerator(uint96 newFeeNumerator) external {
        _onlyOwner();
        if (newFeeNumerator > 100_00) revert InvalidInput_error();
        minFeeNumerator = newFeeNumerator;
        emit MinFeeNumeratorSet(newFeeNumerator);
    }

    function setMaxBurnWindow(uint256 newMax) external {
        _onlyOwner();
        maxBurnWindow = newMax;
        emit MaxBurnWindowSet(newMax);
    }

    function setFreelancerPercentage(uint256 newPercentage) external {
        _onlyOwner();
        if (newPercentage > IPaymentFilterer(paymentFiltererTemplate).BASIS()) revert InvalidInput_error();
        freelancerPercentage = newPercentage;
        emit FreelancerPercentageSet(newPercentage);
    }

    function setImmortalizeFee(uint256 newFee) external {
        _onlyOwner();
        immortalizeFee = newFee;
    }

    function immortalizeTab(
        bytes32 encrypted,
        FileBundle calldata compressedTab,
        ExclusivityData calldata exclusivityData,
        address to
    ) external payable returns (uint256 tokenId) {
        _processImmortalizeFee({qty: 1});
        tokenId = _incrementSupply({qty: 1});

        _immortalizeTab(encrypted, compressedTab, exclusivityData, to, tokenId);
    }

    function immortalizeTabBulk(
        bytes32[] calldata encrypteds,
        FileBundle[] calldata compressedTabs,
        ExclusivityData[] calldata exclusivityDatas,
        address[] calldata tos
    ) external payable nonReentrant returns (uint256[] memory tokenIds) {
        // nonReentrant since is _safeMint in a loop
        uint256 qty = compressedTabs.length;
        _processImmortalizeFee(qty);
        uint256 tokenId = _incrementSupply(qty);
        tokenIds = _allocateUintArr(qty);
        unchecked {
            for (uint256 i; i < qty; ++i) {
                tokenIds[i] = tokenId;
                _immortalizeTab(encrypteds[i], compressedTabs[i], exclusivityDatas[i], tos[i], tokenId++);
            }
        } // uc
    }

    function getDeclaredFingerprint(FileBundle calldata compressed) public pure returns (bytes32) {
        if (compressed.chunks.length == 0) revert InvalidFileBundle_error();
        return toBytes32(LibPack.bytesAt(compressed.chunks[0], 0));
    }

    function _immortalizeTab(
        bytes32 encrypted,
        FileBundle calldata compressedTab,
        ExclusivityData calldata exclusivityData,
        address to,
        uint256 tokenId
    ) private {
        bytes32 declaredFingerprint = getDeclaredFingerprint(compressedTab);

        if (robustRenderer.immortalized(declaredFingerprint) > 0) revert AlreadyImmortalized_error();
        // recall that the id > 0 .. since 0 tokenId is claimed by deployoor

        if (encrypted != bytes32(0) && pledgedRevealTimestamps[encrypted] < 1) revert RevealTimeNotSet_error();

        premierAccess.setExclusivityData(tokenId, exclusivityData); // this validates data

        robustRenderer.immortalize(tokenId, encrypted, declaredFingerprint, Type.TAB, compressedTab);

        _safeMint(to, tokenId);
        emit ArtImmortalized(tokenId, Type.TAB);
    }

    function immortalizeFrame(
        uint256[] calldata featuredIds, // tabIds and frameIds<Forks, unique array by client
        bytes32 encrypted,
        FileBundle calldata compressedFrame,
        ExclusivityData calldata exclusivityData,
        address to
    ) external payable returns (uint256 tokenId) {
        _processImmortalizeFee(1);
        uint256 pledgedRevealTimestamp_ = pledgedRevealTimestamps[encrypted];
        if (encrypted != bytes32(0) && pledgedRevealTimestamp_ < 1) revert RevealTimeNotSet_error();
        unchecked {
            tokenId = _incrementSupply(1);
            {
                //s2d
                uint256 length = featuredIds.length;
                if (length < 1) revert ZeroInput_error();
                uint256 id;
                Type t;
                for (uint256 i; i < length; ++i) {
                    id = featuredIds[i];
                    t = robustRenderer.immortalizedType(id);
                    // must be at or after reveal of children
                    if (pledgedRevealTimestamp_ < pledgedRevealTimestamps[robustRenderer.encryptionReference(id)]) {
                        revert RevealOrdering_error();
                    }
                    if (t < Type.TAB || t > Type.FRAME_ENCRYPTED) revert InvalidInput_error();

                    if (i < length - 1 && !(id < featuredIds[i + 1])) revert IDOrdering_error();

                    _processPremierAccess(id, msg.sender);
                }
                if (!(id < tokenId)) revert InvalidInput_error();

                premierAccess.setExclusivityData(tokenId, exclusivityData); // this validates data
            } //s2d

            bytes32 declaredFingerprint = getDeclaredFingerprint(compressedFrame);

            if (robustRenderer.immortalized(declaredFingerprint) > 0) revert AlreadyImmortalized_error();
            IPaymentFilterer paymentFiltererClone = IPaymentFilterer(
                LibClone.cloneDeterministic({implementation: paymentFiltererTemplate, salt: declaredFingerprint})
            );
            {
                (uint256[] memory payeeTokenIds, uint256[] memory shares,) = _getPaymentArrs(featuredIds, 1);
                payeeTokenIds[0] = tokenId;
                shares[0] = SHARE_SCALAR;
                // dev gets share of collection mint/royalties, so no use putting dev share here
                paymentFiltererClone.initialize(payeeTokenIds, shares);
            } // s2d

            _beneficiaries[tokenId] = paymentFiltererClone; // note: _beneficiaries is only set for frame, not for tab or collectionTokenId

            robustRenderer.immortalize(tokenId, encrypted, declaredFingerprint, Type.FRAME, compressedFrame);

            _safeMint(to, tokenId);
            emit ArtImmortalized(tokenId, (encrypted != bytes32(0)) ? Type.FRAME_ENCRYPTED : Type.FRAME);
        } //uc
    }

    function immortalizeCollection(ImmortalizeCollectionData calldata icd)
        public
        nonReentrant
        returns (uint256 tokenId)
    {
        // nonreentrant since future nftTemplate versions are in control of future hub owners
        unchecked {
            //s2d
            uint256 pledgedRevealTimestamp_ = pledgedRevealTimestamps[icd.encrypted];
            if (icd.encrypted != bytes32(0) && pledgedRevealTimestamp_ < 1) revert RevealTimeNotSet_error();
            tokenId = _incrementSupply(1);
            uint256 length = icd.featuredFrameIds.length;
            if (length < 1) revert ZeroInput_error();
            uint256 id;
            Type t;
            for (uint256 i; i < length; ++i) {
                id = icd.featuredFrameIds[i];
                t = robustRenderer.immortalizedType(id);
                // must be at or after reveal of children
                if (pledgedRevealTimestamp_ < pledgedRevealTimestamps[robustRenderer.encryptionReference(id)]) {
                    revert RevealOrdering_error();
                }
                // can be tab posing as frame
                if (t < Type.TAB || t > Type.FRAME_ENCRYPTED) revert InvalidInput_error();
                if (i < length - 1 && !(id < icd.featuredFrameIds[i + 1])) revert IDOrdering_error();
                _processPremierAccess(id, msg.sender);
            }
            if (!(id < tokenId)) revert InvalidInput_error();
        } //s2d

        INFT nftClone;
        IPaymentFilterer paymentFiltererClone;
        {
            // s2d

            bytes32 salt = _computeSalt(icd.featuredFrameIds, Type.COLLECTION);

            if (robustRenderer.immortalized(salt) > 0) revert AlreadyImmortalized_error();

            paymentFiltererClone = IPaymentFilterer(LibClone.cloneDeterministic(paymentFiltererTemplate, salt));
            (uint256[] memory payeeTokenIds, uint256[] memory shares, uint256 totalShares) =
                _getPaymentArrs(icd.featuredFrameIds, 2);

            payeeTokenIds[0] = tokenId; // as first index for availability target
            // notice this math IS checked since input can be hostile
            shares[0] = icd.mintEconomics.curatorShare * SHARE_SCALAR;
            totalShares += shares[0];

            payeeTokenIds[1] = OWNER_TOKENID;
            uint256 hp = hubPercentage;
            shares[1] = hp * totalShares / (HUB_DIVISOR - hp); // so that hub fee is hubRoyalty% of shares
            /* 
                algebra:
                  want share s such that s = (a/b) * t' where t' is the resulting total
                  since t' = s + t
                  it follows that s = a*t / (b - a)
            **/
            // so payeeTokenIds and shares will never be empty

            paymentFiltererClone.initialize(payeeTokenIds, shares);

            // will be initialized in nftClone.initialize(...)
            if (!(icd.nftVersionId < nftTemplates.length)) revert InvalidNFTTemplateVersion_error();
            nftClone = INFT(LibClone.cloneDeterministic(nftTemplates[icd.nftVersionId], salt));
        } // s2d

        // safeMint not needed since this is recipient
        _mint(address(this), tokenId); // 'this' necessary for ownership in initialization

        robustRenderer.setCollection(tokenId, icd.encrypted, icd.names.walker, icd.compressedCollectionData);

        nftClone.initialize(tokenId, paymentFiltererClone, refunder, icd.names, icd.mintEconomics, icd.dd, icd.auxData);
        refunder.setCustomer(address(nftClone));
        uriRenderer.setCollection(address(nftClone), tokenId);

        _collectionIdxs[tokenId] = allCollections.length;
        allCollections.push(nftClone);

        _transfer(address(this), icd.to, tokenId);

        emit NewCollection(icd.names.name, icd.names.symbol, tokenId, address(nftClone));
    }

    function immortalizeCollectionCombined(
        bytes32 encryptionPre,
        uint256 pledgedRevealTimestamp_,
        ImmortalizeCollectionData calldata icd
    ) external returns (bytes32 encryptionReference, uint256 tokenId) {
        encryptionReference = setEncryptedRevealTime(encryptionPre, pledgedRevealTimestamp_);
        tokenId = immortalizeCollection(icd);
    }

    function computeEncryptionReference(bytes32 encryptionPre, address account)
        public
        pure
        returns (bytes32 encryptionReference)
    {
        assembly {
            // efficient hashing lol
            mstore(0x00, encryptionPre)
            mstore(0x20, account)
            encryptionReference := keccak256(0x00, 0x40)
        }
    }

    function setEncryptedRevealTime(bytes32 encryptionPre, uint256 pledgedRevealTimestamp_)
        public
        returns (bytes32 encryptionReference)
    {
        // bound to msg.sender to prevent frontrunning griefoors
        encryptionReference = computeEncryptionReference(encryptionPre, msg.sender);
        if (encryptionReference == bytes32(0)) revert ZeroInput_error(); // overzealous assert

        if (pledgedRevealTimestamps[encryptionReference] != 0) revert RepeatedEncryptionReference_error();
        pledgedRevealTimestamps[encryptionReference] = pledgedRevealTimestamp_;
        emit NewEncryptedReference(encryptionReference, pledgedRevealTimestamp_);
    }

    // optionalCurationTokenId is for the sake of emitting logs to trigger updates on exchanges
    function reveal(bytes32 key, uint256 optionalCurationTokenId) external {
        bytes32 encryptedPre;
        assembly {
            // efficient hashing lol, equivalent to // = keccak256(abi.encodePacked(key));
            mstore(0x0, key)
            encryptedPre := keccak256(0x0, 0x20)
        }
        // bound to msg.sender to prevent frontrunning griefoors
        bytes32 encryptionReference = computeEncryptionReference(encryptedPre, msg.sender);
        if (pledgedRevealTimestamps[encryptionReference] == 0) revert InvalidKey_error();
        robustRenderer.reveal(encryptionReference, key); // only allows ONE reveal per encryptedReference
        if (optionalCurationTokenId < 1) return;
        emitUpdated(optionalCurationTokenId);
    }

    function emitUpdated(uint256 curationTokenId) public {
        emit MetadataUpdate(curationTokenId);

        Type t = robustRenderer.immortalizedType(curationTokenId);
        if (t > Type.FRAME_ENCRYPTED) {
            getCollection(curationTokenId).emitContractURIUpdated();
            getCollection(curationTokenId).emitBatchMetadataUpdate(0, type(uint256).max);
            return;
        }
        premierAccess.emitMetadataUpdate(curationTokenId);
    }

    function pledgedRevealTimestamp(uint256 id) external view returns (uint256) {
        return pledgedRevealTimestamps[robustRenderer.encryptionReference(id)];
    }

    function updateContractURIImage(uint256 curationTokenId, FileBundle calldata imageData, address customRenderer)
        external
    {
        if (msg.sender != ownerOf(curationTokenId)) revert NotOwner_error(); // throws if dne!
        robustRenderer.updateContractURIImage(curationTokenId, imageData, customRenderer);
        if (curationTokenId < 1) {
            emit ContractURIUpdated();
        } else {
            INFT nft = allCollections[_collectionIdxs[curationTokenId]];
            nft.emitContractURIUpdated();
        }
    }

    function burn(uint256 tokenId) external {
        if (msg.sender != ownerOf(tokenId)) revert NotOwner_error();
        unchecked {
            --_supply.totalSupply;
        }
        LibBitmap.set(_burned, tokenId);
        _burn(tokenId);
    }

    function burned(uint256 tokenId) external view returns (bool) {
        return LibBitmap.get(_burned, tokenId);
    }

    function _onlyOwner() internal view override {
        if (msg.sender != ownerOf(OWNER_TOKENID)) revert NotOwner_error();
    }

    function _processImmortalizeFee(uint256 qty) private {
        uint256 immortalizeFee_ = immortalizeFee * qty;
        if (msg.value < immortalizeFee_) revert InsufficientImmortalizeFee_error();
        if (msg.value > immortalizeFee_) {
            unchecked {
                _setRefund(msg.sender, msg.value - immortalizeFee_);
            } // uc
        }
    }

    function _processPremierAccess(uint256 id, address account) private {
        if (!_exists(id) || account != ownerOf(id)) {
            // check exists since can be burned

            if (!premierAccess.processAccess(account, id)) revert MustRespectExclusivity_error();
        }
    }

    function _incrementSupply(uint256 qty) private returns (uint256 tokenId) {
        Supply memory s = _supply;
        assembly {
            tokenId := mload(add(s, 0x20)) // = s.totalMinted

            mstore(s, add(mload(s), qty)) //s.totalSupply += uint128(qty);
            mstore(add(s, 0x20), add(tokenId, qty)) //s.totalMinted += uint128(qty);
        }
        _supply = s;
    }

    function _getPaymentArrs(uint256[] memory ids, uint256 offset)
        private
        pure
        returns (uint256[] memory payeeTokenIds, uint256[] memory shares, uint256 totalShares)
    {
        unchecked {
            uint256 length = ids.length + offset;
            payeeTokenIds = _allocateUintArr(length);
            shares = _allocateUintArr(length);
            uint256 idx;
            for (uint256 i; i < ids.length; ++i) {
                idx = i + offset;
                payeeTokenIds[idx] = ids[i];
                shares[idx] = SHARE_SCALAR;
                totalShares += SHARE_SCALAR;
            }
        } // uc
    }

    function _computeSalt(uint256[] calldata featuredIds, Type t) private pure returns (bytes32 salt) {
        salt = hashArr(featuredIds); // two frames cannot have same exact featuredIds lol
        assembly {
            mstore(0x0, salt)
            mstore(0x20, t)
            salt := keccak256(0x0, 0x40)
        }
    }

    function _requireCallerIsContractOwner() internal view override {
        if (msg.sender != ownerOf(OWNER_TOKENID)) revert NotOwner_error();
    }
}