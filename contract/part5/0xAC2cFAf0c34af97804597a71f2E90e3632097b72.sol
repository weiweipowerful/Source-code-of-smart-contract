//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "erc721a/contracts/extensions/ERC721AQueryable.sol";
import "./IERC721C.sol";

contract WADESIDE is IERC721C, ERC721AQueryable, ERC2981, Ownable, ReentrancyGuard {

    // Whether base URI is permanent. Once set, base URI is immutable.
    bool private _baseURIPermanent;

    // The total mintable supply.
    uint256 internal _maxMintableSupply;

    // Current base URI.
    string private _currentBaseURI;

    // The suffix for the token URL, e.g. ".json".
    string private _tokenURISuffix;

    uint256 constant secondsPerWeek = 604800;
    uint256 internal _minTimeBeforeClaim;
    uint256 internal immutable _privateAuctionSupply;
    uint256 internal immutable _publicAuctionSupply;
    uint256 internal immutable _teamSupply;
    uint256 internal immutable _fnfSupply;
    uint256 internal immutable _maxSupplyPerWeek;
    uint256 internal immutable _numberOfWeeks;

    address public withdrawAccount;
    bool public transferLocked;
    bool public publicAuctionStarted;
    bool public publicAuctionEnded;
    bool public privateAuctionStarted;
    bool public privateAuctionEnded;

    mapping(address => uint256) private _weekClaimed;
    mapping(address => uint256) private _totalClaimedBy;
    mapping(address => uint256) private _privateBid;
    mapping(address => uint256) private _privateClaimedBy;
    mapping(address => bool) private _privateAirdropped;

    mapping(address => mapping(uint256 => uint256)) private _bid;
    mapping(address => mapping(uint256 => uint256)) private _numClaimedBy;

    mapping(uint256 => uint256) private _totalClaimedAtWeek;
    mapping(uint256 => uint256) private _totalBid;
    mapping(uint256 => uint256) private _price;
    mapping(uint256 => uint256) private _supply;
    mapping(uint256 => bool) private _withdrawn;
    mapping(uint256 => bool) private _priceComputed;

    mapping(uint256 => address[]) private _allParticipants;

    uint256 private _totalPrivateBid;
    uint256 private _privatePrice;
    uint256 private _privateSupply;
    bool private _privateWithdrawn;

    address[] private _allPrivateParticipants;
    bytes32 private _merkleRoot;

    uint256 private _publicAuctionStartTime;
    uint256 private _privateAuctionStartTime;
    uint256 private _privateAuctionEndTime;

    constructor(
        string memory collectionName,
        string memory collectionSymbol
    ) ERC721A(collectionName, collectionSymbol) Ownable(0x26C4aB089D174929238c0FE42e5c7A241c8AC208) {

        _maxMintableSupply = 13333;
        _minTimeBeforeClaim = 3600;
        _privateAuctionSupply = 1916;
        _publicAuctionSupply = 8084;
        _teamSupply = 1233;
        _fnfSupply = 2100;
        _maxSupplyPerWeek = 188;
        _numberOfWeeks = 43;

        withdrawAccount = msg.sender;

        _tokenURISuffix = ".json";
        _currentBaseURI = "http://metadata.wade.club/wadeside/";
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function bulkTransfer(address[] calldata _to, uint256[] calldata _id) public {
        require(_to.length == _id.length, "Receivers and IDs are different length");
        for (uint256 i = 0; i < _to.length; i++) {
            transferFrom(msg.sender, _to[i], _id[i]);
        }
    }

    function getMinTimeBeforeClaim() external view returns (uint256) {
        return _minTimeBeforeClaim;
    }

    function getWeekClaimed(address addr) external view returns (uint256) {
        return _weekClaimed[addr];
    }

    function getTotalClaimedBy(address addr) external view returns (uint256) {
        return _totalClaimedBy[addr];
    }

    function getPrivateBidBy(address addr) external view returns (uint256) {
        return _privateBid[addr];
    }

    function getPrivateClaimedBy(address addr) external view returns (uint256) {
        return _privateClaimedBy[addr];
    }

    function getPrivateAirdropped(address addr) external view returns (bool) {
        return _privateAirdropped[addr];
    }

    function getBidBy(address addr, uint256 week) external view returns (uint256) {
        return _bid[addr][week];
    }

    function getNumClaimedBy(address addr, uint256 week) external view returns (uint256) {
        return _numClaimedBy[addr][week];
    }

    function getTotalClaimedAtWeek(uint256 week) external view returns (uint256) {
        return _totalClaimedAtWeek[week];
    }

    function getTotalBid(uint256 week) external view returns (uint256) {
        return _totalBid[week];
    }

    function getPrice(uint256 week) external view returns (uint256) {
        return _price[week];
    }

    function getSupply(uint256 week) external view returns (uint256) {
        return _supply[week];
    }

    function getWithrawn(uint256 week) external view returns (bool) {
        return _withdrawn[week];
    }

    function getPriceComputed(uint256 week) external view returns (bool) {
        return _priceComputed[week];
    }

    function getAllParticipants(uint256 week) external view returns (address[] memory) {
        return _allParticipants[week];
    }

    function getTotalPrivateBid() external view returns (uint256) {
        return _totalPrivateBid;
    }

    function getPrivatePrice() external view returns (uint256) {
        return _privatePrice;
    }

    function getPrivateSupply() external view returns (uint256) {
        return _privateSupply;
    }

    function getPrivateWithdrawn() external view returns (bool) {
        return _privateWithdrawn;
    }

    function getAllPrivateParticipants() external view returns (address[] memory) {
        return _allPrivateParticipants;
    }

    function getPublicAuctionStartTime() external view returns (uint256) {
        return _publicAuctionStartTime;
    }

    function getPrivateAuctionStartTime() external view returns (uint256) {
        return _privateAuctionStartTime;
    }

    function getPrivateAuctionEndTime() external view returns (uint256) {
        return _privateAuctionEndTime;
    }

    function currWeek(uint256 time) public view returns (uint256 week) {
        require(publicAuctionStarted && time >= _publicAuctionStartTime, "Public auction has not started");
        
        week = (time - _publicAuctionStartTime) / secondsPerWeek;
        if (week > _numberOfWeeks) {
            week = _numberOfWeeks;
        }
    }

    function currWeek() public view returns (uint256) {
        return currWeek(block.timestamp);
    }

    function numClaimable(address addr, uint256 week) public view returns (uint256) {
        if (_price[week] == 0) {
            return 0;
        }

        return _bid[addr][week] / _price[week];
    }

    function weeklyRefund(address addr, uint256 week) public view returns (uint256) {
        if (_price[week] == 0) {
            return 0;
        }

        return _bid[addr][week] % _price[week];
    }

    function totalClaimableAndRefund(address addr) public view returns (uint256 claimable, uint256 refund) {
        for (uint256 i = _weekClaimed[addr]; i < currWeek(block.timestamp - _minTimeBeforeClaim); i++) {
            claimable += numClaimable(addr, i);
            refund += weeklyRefund(addr, i);
        }
    }

    function _increaseNumClaimed(address addr) internal {
        for (uint256 i = _weekClaimed[addr]; i < currWeek(block.timestamp - _minTimeBeforeClaim); i++) {
            _totalClaimedAtWeek[i] += numClaimable(addr, i);
            require(_totalClaimedAtWeek[i] <= _supply[i], "Total claimed per week cannot exceed limit");
            _numClaimedBy[addr][i] += numClaimable(addr, i);
        }
    }

    function computeSum(uint256 week, uint256 price) internal view returns (uint256 sum) {
        uint256 length = _allParticipants[week].length;
        for (uint256 i; i < length;) {
            sum += _bid[_allParticipants[week][i]][week] / price;
            unchecked {
                ++i;
            }
        }
    }

    function computePrice(uint256 week) public view returns (uint256, uint256) {
        require(currWeek() > week, "Auction has not ended yet");

        if (_allParticipants[week].length == 0) {
            return (0, 1);
        }

        uint256 startingExponent = 55;
        uint256 foundExponent;

        if (computeSum(week, (1 << startingExponent)) < _maxSupplyPerWeek) {
            for (uint256 i = startingExponent - 1; i > 0; i--) {
                if (computeSum(week, (1 << i)) >= _maxSupplyPerWeek) {
                    foundExponent = i;
                    break;
                }
            }
        } else {
            for (uint256 i = startingExponent + 1; i < 90; i++) {
                if (computeSum(week, (1 << i)) < _maxSupplyPerWeek) {
                    foundExponent = i - 1;
                    break;
                }
            }
        }

        uint256 low = (1 << foundExponent);
        uint256 high = (1 << (foundExponent + 1));
        uint256 mid;
        while (low < high) {
            mid = (low + high) / 2;
            if (computeSum(week, mid) < _maxSupplyPerWeek) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        if (computeSum(week, low - 1) == _maxSupplyPerWeek) {
            return (low - 1, _maxSupplyPerWeek);
        } else {
            uint256 supply = computeSum(week, low);
            if (supply == 0) {
                return (_totalBid[week], 1);
            } else {
                startingExponent = foundExponent;

                if (computeSum(week, (1 << startingExponent)) < supply) {
                    for (uint256 i = startingExponent - 1; i > 0; i--) {
                        if (computeSum(week, (1 << i)) >= supply) {
                            foundExponent = i;
                            break;
                        }
                    }
                } else {
                    for (uint256 i = startingExponent + 1; i < 90; i++) {
                        if (computeSum(week, (1 << i)) < supply) {
                            foundExponent = i - 1;
                            break;
                        }
                    }
                }

                low = (1 << foundExponent);
                high = (1 << (foundExponent + 1));
                while (low < high) {
                    mid = (low + high) / 2;
                    if (computeSum(week, mid) < supply) {
                        high = mid;
                    } else {
                        low = mid + 1;
                    }
                }
                return (low - 1, supply);
            }
        }
    }

    function placePrivateBid(bytes32[] calldata proof) external payable nonReentrant {
        require(privateAuctionStarted && !privateAuctionEnded, "Private auction not in progress");
        require(_privateAuctionStartTime <= block.timestamp && block.timestamp <= _privateAuctionEndTime, "Invalid timestamp");
        require(MerkleProof.processProof(proof, keccak256(abi.encodePacked(msg.sender))) == _merkleRoot, "Not in whitelist");
        require(msg.value > 0, "Bid amount must be greater than zero");

        if (_privateBid[msg.sender] == 0) {
            _allPrivateParticipants.push(msg.sender);
        }

        _privateBid[msg.sender] += msg.value;
        _totalPrivateBid += msg.value;
    }

    function placeBid() external payable nonReentrant {
        require(publicAuctionStarted && !publicAuctionEnded && _publicAuctionStartTime <= block.timestamp, "Public auction not in progress");
        require(currWeek() < _numberOfWeeks, "Auction has ended");
        require(msg.value > _maxSupplyPerWeek ** 2, "Bid amount must be greater than minimum");

        if (_bid[msg.sender][currWeek()] == 0) {
            _allParticipants[currWeek()].push(msg.sender);
        }

        _bid[msg.sender][currWeek()] += msg.value;
        _totalBid[currWeek()] += msg.value;
    }

    function claimAndRefund() external nonReentrant {
        require(publicAuctionStarted && !publicAuctionEnded && _publicAuctionStartTime <= block.timestamp, "Public auction not in progress");
        require(currWeek(block.timestamp - _minTimeBeforeClaim) > _weekClaimed[msg.sender], "Already claimed");

        (uint256 claimable, uint256 refund) = totalClaimableAndRefund(msg.sender);
        require(claimable > 0 || refund > 0, "Nothing to claim or refund");

        (bool success, ) = msg.sender.call{value: refund}("");
        if (!success) revert WithdrawFailed();

        if (claimable > 0) {
            require(totalSupply() + claimable <= _teamSupply + _fnfSupply + _privateAuctionSupply + _maxSupplyPerWeek * (currWeek() + 1), "Exceeds current max supply");
            _safeMint(msg.sender, claimable);
            _totalClaimedBy[msg.sender] += claimable;

            _increaseNumClaimed(msg.sender);
        }

        for (uint256 week = currWeek(block.timestamp - _minTimeBeforeClaim); week > _weekClaimed[msg.sender]; week--) {
            if (_supply[week - 1] != 0) {
                _weekClaimed[msg.sender] = week;
                break;
            }
        }
    }

    function claimAndRelay() external payable nonReentrant {
        require(publicAuctionStarted && !publicAuctionEnded && _publicAuctionStartTime <= block.timestamp, "Public auction not in progress");
        require(currWeek(block.timestamp - _minTimeBeforeClaim) > _weekClaimed[msg.sender], "Already claimed");
        require(currWeek() < _numberOfWeeks, "Auction has ended");

        (uint256 claimable, uint256 refund) = totalClaimableAndRefund(msg.sender);
        require(claimable > 0 || refund > 0, "Nothing to claim or relay");
        require(msg.value + refund > _maxSupplyPerWeek ** 2, "Bid amount must be greater than minimum");

        if (_bid[msg.sender][currWeek()] == 0) {
            _allParticipants[currWeek()].push(msg.sender);
        }

        _bid[msg.sender][currWeek()] += msg.value + refund;
        _totalBid[currWeek()] += msg.value + refund;

        if (claimable > 0) {
            require(totalSupply() + claimable <= _teamSupply + _fnfSupply + _privateAuctionSupply + _maxSupplyPerWeek * (currWeek() + 1), "Exceeds current max supply");
            _safeMint(msg.sender, claimable);
            _totalClaimedBy[msg.sender] += claimable;

            _increaseNumClaimed(msg.sender);
        }

        for (uint256 week = currWeek(block.timestamp - _minTimeBeforeClaim); week > _weekClaimed[msg.sender]; week--) {
            if (_supply[week - 1] != 0) {
                _weekClaimed[msg.sender] = week;
                break;
            }
        }
    }

    function setComputedPrice(uint256 week) public {
        require(currWeek() > week, "Auction has not ended yet");
        require(!_priceComputed[week], "Price already computed");
        if (week != 0) require(_supply[week - 1] != 0, "Must have set price for previous week");

        _priceComputed[week] = true;
        (_price[week], _supply[week]) = computePrice(week);
    }

    function setPrice(uint256 week, uint256 price, uint256 supply) external onlyOwner {
        require(currWeek() > week, "Auction has not ended yet");
        require(!_priceComputed[week], "Price already computed");
        require(supply <= _maxSupplyPerWeek, "Supply cannot exceed limit");
        require(!_withdrawn[week], "Already withdrawn");
        require(supply > 0, "Invalid input");
        require(price * supply <= _totalBid[week], "Withdraw amount cannot exceed total bid");
        if (week != 0) require(_supply[week - 1] != 0, "Must have set price for previous week");

        _price[week] = price;
        _supply[week] = supply;
    }

    function withdraw(uint256 week) external nonReentrant onlyOwner {
        require(currWeek() > week, "Auction has not ended yet");
        require(_price[week] > 0 && _supply[week] > 0, "Price and supply not initialized");
        require(!_withdrawn[week], "Already withdrawn");
        require(_price[week] != _totalBid[week], "Special case: no winner");

        uint256 value = _price[week] * _supply[week];
        require(value <= _totalBid[week], "Withdraw amount cannot exceed total bid");
        (bool success, ) = withdrawAccount.call{value: value}("");
        if (!success) revert WithdrawFailed();
        _withdrawn[week] = true;
        emit Withdraw(value);
    }

    function withdrawFinal() external nonReentrant onlyOwner {
		require(publicAuctionEnded, "Public auction has not ended");

        uint256 value = address(this).balance;
        (bool success, ) = withdrawAccount.call{value: value}("");
        if (!success) revert WithdrawFailed();
        emit Withdraw(value);
	}

    function setPublicAuctionStartTime(uint256 time) external onlyOwner {
        require(!publicAuctionStarted, "Public auction already started");
        require(time > block.timestamp && time - block.timestamp < secondsPerWeek, "Time not in appropriate window");

        _publicAuctionStartTime = time;
    }

    function setPrivateAuctionStartTime(uint256 time) external onlyOwner {
        require(!privateAuctionStarted, "Private auction already started");

        _privateAuctionStartTime = time;
    }

    function setPrivateAuctionEndTime(uint256 time) external onlyOwner {
        require(!privateAuctionEnded, "Private auction already ended");

        _privateAuctionEndTime = time;
    }

    function startPublicAuction() external onlyOwner {
        require(_publicAuctionStartTime > block.timestamp, "Start time must come after current time");
        require(!publicAuctionEnded, "Public auction has already ended");
        require(privateAuctionEnded, "Private auction has not ended yet");
        require(totalSupply() == _teamSupply + _fnfSupply + _privateAuctionSupply, "Other sales must have terminated");

        publicAuctionStarted = true;
    }

    function startPrivateAuction() external onlyOwner {
        require(_privateAuctionStartTime != 0, "Private auction start time not initialized");
        require(_privateAuctionEndTime != 0, "Private auction end time not initialized");
        require(!privateAuctionEnded, "Private auction has already ended");

        privateAuctionStarted = true;
    }

    function endPublicAuction() external onlyOwner {
        require(publicAuctionStarted, "Public auction has not started");
        // require(_withdrawn[_numberOfWeeks - 1], "Public auction has not ended");

        publicAuctionEnded = true;
    }

    function endPrivateAuction() external onlyOwner {
        require(_privateAuctionEndTime != 0, "Private auction end time not initialized");
        require(privateAuctionStarted, "Private auction has not started");
        require(block.timestamp >= _privateAuctionEndTime, "Private auction end time has not passed yet");

        privateAuctionEnded = true;
    }

    function setPrivatePrice(uint256 price, uint256 supply) external onlyOwner {
        require(privateAuctionEnded, "Private auction has not ended yet");
        require(supply <= _privateAuctionSupply, "Supply cannot exceed limit");
        require(!_privateWithdrawn, "Already withdrawn");
        require(price * supply <= _totalPrivateBid, "Withdraw amount cannot exceed total bid");

        _privatePrice = price;
        _privateSupply = supply;
    }

    function withdrawPrivateFund() external nonReentrant onlyOwner {
        require(privateAuctionEnded, "Private auction has not ended yet");
        require(_privatePrice > 0 && _privateSupply > 0, "Price and supply not initialized");
        require(!_privateWithdrawn, "Already withdrawn");

        uint256 value = _privatePrice * _privateSupply;
        require(value <= _totalPrivateBid, "Withdraw amount cannot exceed total bid");
        (bool success, ) = withdrawAccount.call{value: value}("");
        if (!success) revert WithdrawFailed();
        _privateWithdrawn = true;
        emit Withdraw(value);
    }

    function airdropAllPrivate(address[] calldata addrs) external nonReentrant onlyOwner {
        require(privateAuctionEnded, "Private auction has not ended yet");
        require(_privatePrice > 0 && _privateSupply > 0, "Price and supply not initialized");

        for (uint256 i = 0; i < addrs.length; i++) {
            if (!_privateAirdropped[addrs[i]]) {
                (bool success, ) = addrs[i].call{value: _privateBid[addrs[i]] % _privatePrice}("");
                if (!success) revert WithdrawFailed();
                
                if (_privateBid[addrs[i]] / _privatePrice > 0) {
                    _safeMint(addrs[i], _privateBid[addrs[i]] / _privatePrice);
                    _privateClaimedBy[addrs[i]] += _privateBid[addrs[i]] / _privatePrice;
                }

                _privateAirdropped[addrs[i]] = true;
            }
        }

        require(totalSupply() <= _teamSupply + _fnfSupply + _privateAuctionSupply, "Exceeds mint limit");
    }

    function airdropAllPublic(address[] calldata addrs) external nonReentrant onlyOwner {
        require(publicAuctionEnded, "Public auction has not ended");

        for (uint256 i = 0; i < addrs.length; i++) {
            if (_weekClaimed[addrs[i]] < _numberOfWeeks) {
                (uint256 claimable, uint256 refund) = totalClaimableAndRefund(addrs[i]);

                (bool success, ) = addrs[i].call{value: refund}("");
                if (!success) revert WithdrawFailed();

                if (claimable > 0) {
                    _safeMint(addrs[i], claimable);
                    _totalClaimedBy[addrs[i]] += claimable;
                    _increaseNumClaimed(addrs[i]);
                }

                _weekClaimed[addrs[i]] = _numberOfWeeks;
            }
        }

        require(totalSupply() <= _maxMintableSupply, "Exceeds mint limit");
    }

    function setMinTimeBeforeClaim(uint256 time) external onlyOwner {
        _minTimeBeforeClaim = time;
    }

    function setMerkleRoot(bytes32 root) external onlyOwner {
        _merkleRoot = root;
    }

    function setWithdrawAccount(address addr) external onlyOwner {
        withdrawAccount = addr;
    }

    function setTransferLocked(bool locked) external onlyOwner {
        transferLocked = locked;
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable virtual override(ERC721A, IERC721A) {
        require(!transferLocked, "Cannot transfer - currently locked");
        super.transferFrom(from, to, tokenId);
    }
    
    /**
     * @dev Returns whether it has enough supply for the given qty.
     */
    modifier hasSupply(uint256 qty) {
        if (totalSupply() + qty > _maxMintableSupply) revert NoSupplyLeft();
        _;
    }

    /**
     * @dev Returns maximum mintable supply.
     */
    function getMaxMintableSupply() external view override returns (uint256) {
        return _maxMintableSupply;
    }

    /**
     * @dev Sets maximum mintable supply.
     *
     * New supply cannot be larger than the old.
     */
    function setMaxMintableSupply(uint256 maxMintableSupply)
        external
        virtual
        onlyOwner
    {
        if (maxMintableSupply > _maxMintableSupply) {
            revert CannotIncreaseMaxMintableSupply();
        }
        _maxMintableSupply = maxMintableSupply;
        emit SetMaxMintableSupply(maxMintableSupply);
    }

    /**
     * @dev Returns number of minted token for a given address.
     */
    function totalMintedByAddress(address a)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _numberMinted(a);
    }

    /**
     * @dev Mints token(s) by owner.
     *
     * NOTE: This function bypasses validations thus only available for owner.
     * This is typically used for owner to  pre-mint or mint the remaining of the supply.
     */
    function ownerMint(uint32 qty, address to)
        public
        onlyOwner
        hasSupply(qty)
    {
        if (publicAuctionStarted) {
            require(publicAuctionEnded, "Owner cannot mint during public auction");
        } else {
            if (!privateAuctionEnded) { 
                require(totalSupply() + qty <= _teamSupply + _fnfSupply, "Exceeds mint limit");
            } else {
                require(totalSupply() + qty <= _teamSupply + _fnfSupply + _privateAuctionSupply, "Exceeds mint limit");
            }
        }

        _safeMint(to, qty);
    }

    function ownerMintBulk(address[] calldata _to, uint32[] calldata _qty) external onlyOwner {
        require(_to.length == _qty.length, "Receivers and quantities are different length");
        for (uint256 i = 0; i < _to.length; i++) {
            ownerMint(_qty[i], _to[i]);
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override (IERC721A, ERC721A, ERC2981)
        returns (bool)
    {
        // Supports the following `interfaceId`s:
        // - IERC165: 0x01ffc9a7
        // - IERC721: 0x80ac58cd
        // - IERC721Metadata: 0x5b5e139f
        // - IERC2981: 0x2a55205a
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator)
        public
        onlyOwner
    {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @dev Sets token base URI.
     */
    function setBaseURI(string calldata baseURI) external onlyOwner {
        if (_baseURIPermanent) revert CannotUpdatePermanentBaseURI();
        _currentBaseURI = baseURI;
        emit SetBaseURI(baseURI);
    }

    /**
     * @dev Sets token base URI permanent. Cannot revert.
     */
    function setBaseURIPermanent() external onlyOwner {
        _baseURIPermanent = true;
        emit PermanentBaseURI(_currentBaseURI);
    }

    /**
     * @dev Returns token URI suffix.
     */
    function getTokenURISuffix()
        external
        view
        override
        returns (string memory)
    {
        return _tokenURISuffix;
    }

    /**
     * @dev Sets token URI suffix. e.g. ".json".
     */
    function setTokenURISuffix(string calldata suffix) external onlyOwner {
        _tokenURISuffix = suffix;
    }

    /**
     * @dev Returns token URI for a given token id.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721A, IERC721A)
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI = _currentBaseURI;
        return
            bytes(baseURI).length != 0
                ? string(
                    abi.encodePacked(
                        baseURI,
                        _toString(tokenId),
                        _tokenURISuffix
                    )
                )
                : "";
    }

    /**
     * @dev Returns chain id.
     */
    function _chainID() private view returns (uint256) {
        uint256 chainID;
        assembly {
            chainID := chainid()
        }
        return chainID;
    }
}