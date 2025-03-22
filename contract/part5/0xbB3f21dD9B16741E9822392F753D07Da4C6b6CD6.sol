// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PFP is
    ERC721Enumerable,
    ReentrancyGuard,
    Ownable
{
    using Strings for uint256;
    uint256 public constant MAX_SUPPLY = 6000;

    mapping(address => uint256) private _whitelist;
    string private _baseTokenURI;
    uint256 private _transferStartTime;
    address private _timeAdmin;

    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {
        _timeAdmin = msg.sender;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function getTimeAdmin() external view returns (address) {
        return _timeAdmin;
    }

    function renounceTimeAdmin() external  {
        require(msg.sender == _timeAdmin, "Caller is not the time admin");
        _timeAdmin = address(0);
    }

    function setTransferStartTime(uint256 transferStartTime) external {
        require(msg.sender == _timeAdmin, "Caller is not the time admin");
        _transferStartTime = transferStartTime;
    }

    function getTransferStartTime() external view returns (uint256) {
        return _transferStartTime;
    }

    function setBaseURI(string memory baseTokenURI) public virtual onlyOwner {
        _baseTokenURI = baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(abi.encodePacked(baseURI, tokenId.toString()), ".json")) : "";
    }

    function addWhitelist(address account, uint256 mintAllowance) external virtual onlyOwner {
        _whitelist[account] = mintAllowance;
    }

    function removeWhitelist(address account) external virtual onlyOwner {
        _whitelist[account] = 0;
    }

    function getWhitelistMintAllowance(address account) external view returns (uint256) {
        return _whitelist[account];
    }

    function mint(address to, uint256 tokenId) external virtual nonReentrant {
        require(tokenId > 0, "Token ID must be greater than 0");
        require(tokenId <= MAX_SUPPLY, "Exceeds max token supply");
        require(_whitelist[msg.sender] >= 1, "Insufficient mint allowance");
        _whitelist[msg.sender] -= 1;
        _mint(to, tokenId);
    }

    function mintTokens(address[] calldata recipients, uint[] calldata tokenIds) external virtual nonReentrant {
        uint256 numberOfTokens = tokenIds.length;
        require(numberOfTokens > 0, "Number of tokens must be greater than 0");
        require(recipients.length == numberOfTokens, "Array lengths must match");
        require(_whitelist[msg.sender] >= numberOfTokens, "Insufficient mint allowance");
        _whitelist[msg.sender] -= numberOfTokens;
        for (uint i = 0; i < numberOfTokens; i++) {
            address to = recipients[i];
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "Token ID must be greater than 0");
            require(tokenId <= MAX_SUPPLY, "Exceeds max token supply");
            _mint(to, tokenId);
        }
    }

    function batchTransferFrom(address from, address to, uint256[] calldata tokenIds) external virtual {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            transferFrom(from, to, tokenIds[i]);
        }
    }

    function withdrawTokens(IERC20 token, uint256 amount, address to) external onlyOwner {
        token.transfer(to, amount);
    }

    function withdrawEther(address to) external onlyOwner {
        payable(to).transfer(address(this).balance);
    }

    function withdrawNFT(IERC721 nft, uint256 tokenId, address to) external onlyOwner {
        nft.transferFrom(address(this), to, tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override(ERC721Enumerable) {
        require(block.timestamp >= _transferStartTime || from == address(0) , "Transfer not started");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721Enumerable) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}