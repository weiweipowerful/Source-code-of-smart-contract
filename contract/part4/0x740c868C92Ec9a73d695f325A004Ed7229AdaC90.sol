// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import './IERC5192.sol';

contract TukuruERC721 is ERC721, AccessControl, Ownable, Pausable, IERC5192, ERC2981 {
    using Strings for uint256;

    // Role
    bytes32 public constant ADMIN = "ADMIN";
    bytes32 public constant MINTER = "MINTER";

    // Metadata
    string private _name;
    string private _symbol;
    string public baseURI;
    string public baseExtension;

    // Mint
    uint256 public mintCost;
    uint256 public maxSupply;
    uint256 public totalSupply;
    bool public isLocked;

    // Withdraw
    uint256 public usageFee = 0.1 ether;
    address public withdrawAddress;
    uint256 public systemRoyalty;
    address public royaltyReceiver;

    // Modifier
    modifier withinMaxSupply(uint256 _amount) {
        require(totalSupply + _amount <= maxSupply, 'Over Max Supply');
        _;
    }
    modifier enoughEth(uint256 _amount) {
        require(msg.value >= _amount * mintCost, 'Not Enough Eth');
        _;
    }

    // Constructor
    constructor() ERC721("", "") Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
    }

    function initialize (
        address _owner,
        string memory _erc721Name,
        string memory _src721Symbol,
        bool _isLocked,
        uint96 _royaltyFee,
        address _withdrawAddress,
        uint256 _systemRoyalty,
        address _royaltyReceiver,
        string memory _prefBaseURI
    ) external {
        // Role
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ADMIN, _owner);

        // Feature
        _name = _erc721Name;
        _symbol = _src721Symbol;
        isLocked = _isLocked;

        // Payment
        _setDefaultRoyalty(_withdrawAddress, _royaltyFee);
        withdrawAddress = _withdrawAddress;
        systemRoyalty = _systemRoyalty;
        royaltyReceiver = _royaltyReceiver;

        // Metadata
        baseURI = string(abi.encodePacked(
            _prefBaseURI,
            "/",
            Strings.toHexString(address(this)),
            "/"
        ));
        baseExtension = ".json";
    }
    function updateToNoSystemRoyalty() external payable {
        require(systemRoyalty > 0, "No System Royalty");
        require(msg.value >= usageFee, "Not Enough Eth");
        systemRoyalty = 0;
    }

    // Mint
    function airdrop(address[] calldata _addresses, uint256[] calldata _tokenIds) external onlyRole(ADMIN) {
        require(_addresses.length == _tokenIds.length, "Invalid Length");
        for (uint256 i = 0; i < _addresses.length; i++) {
            mintCommon(_addresses[i], _tokenIds[i]);
        }
    }
    function mint(address _address, uint256[] calldata _tokenIds) external payable
        whenNotPaused
        withinMaxSupply(_tokenIds.length)
        enoughEth(_tokenIds.length)
    {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            mintCommon(_address, _tokenIds[i]);
        }
    }
    function externalMint(address _address, uint256[] calldata _tokenIds) external onlyRole(MINTER) {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            mintCommon(_address, _tokenIds[i]);
        }
    }
    function mintCommon(address _address, uint256 _tokenId) private {
        _mint(_address, _tokenId);
        totalSupply++;
        if (isLocked) {
            emit Locked(_tokenId);
        }
    }
    function withdraw() public onlyRole(ADMIN) {
        bool success;
        if (systemRoyalty > 0) {
            (success, ) = payable(royaltyReceiver).call{value: address(this).balance * systemRoyalty / 100}("");
            require(success);
        }
        (success, ) = payable(withdrawAddress).call{value: address(this).balance}("");
        require(success);
    }

    // Getter
    function name() public view virtual override returns (string memory) {
        return _name;
    }
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }
    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        return string(abi.encodePacked(baseURI, Strings.toString(_tokenId), baseExtension));
    }
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    // Setter
    function setWithdrawAddress(address _value) public onlyRole(ADMIN) {
        withdrawAddress = _value;
    }
    function setMetadataBase(string memory _baseURI, string memory _baseExtension) external onlyRole(ADMIN) {
        baseURI = _baseURI;
        baseExtension = _baseExtension;
    }
    function setIsLocked(bool _isLocked) external onlyRole(ADMIN) {
        isLocked = _isLocked;
    }
    function setSalesInfo(uint256 _mintCost, uint256 _maxSupply) external onlyRole(ADMIN) {
        mintCost = _mintCost;
        maxSupply = _maxSupply;
    }

    // Pause
    function setPause(bool _value) external onlyRole(ADMIN) {
        if (_value) {
            _pause();
        } else {
            _unpause();
        }
    }

    // interface
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl, ERC2981) returns (bool) {
        return
            ERC721.supportsInterface(interfaceId) ||
            AccessControl.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId) ||
            interfaceId == type(IERC5192).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // Transfer
    function locked(uint256) override public view returns (bool){
        return isLocked;
    }
    function emitLockState(uint256 _tokenId, bool _locked) external onlyRole(ADMIN) {
        if (_locked) {
            emit Locked(_tokenId);
        } else {
            emit Unlocked(_tokenId);
        }
    }
    function setApprovalForAll(address _operator, bool _approved) public virtual override {
        require (!_approved || !isLocked, "Locked");
        super.setApprovalForAll(_operator, _approved);
    }
    function approve(address _to, uint256 _tokenId) public virtual override {
        require (!isLocked || _ownerOf(_tokenId) == address(0) || _to == address(0), "Locked");
        super.approve(_to, _tokenId);
    }
    function _update(address _to, uint256 _tokenId, address _auth) internal virtual override returns (address) {
        require(!isLocked || _ownerOf(_tokenId) == address(0) || _to == address(0), "Locked");
        return super._update(_to, _tokenId, _auth);
    }
}