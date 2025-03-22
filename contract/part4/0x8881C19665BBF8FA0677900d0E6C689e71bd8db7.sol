// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "erc721a/contracts/extensions/ERC721AQueryable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


// ██████╗░███████╗██████╗░░█████╗░░█████╗░██╗░░██╗  ███╗░░░███╗░█████╗░░██████╗░██╗░█████╗░██╗░░██╗███████╗██╗░░░██╗
// ██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔══██╗██║░██╔╝  ████╗░████║██╔══██╗██╔════╝░██║██╔══██╗██║░██╔╝██╔════╝╚██╗░██╔╝
// ██║░░██║█████╗░░██████╦╝██║░░██║██║░░██║█████═╝░  ██╔████╔██║███████║██║░░██╗░██║██║░░╚═╝█████═╝░█████╗░░░╚████╔╝░
// ██║░░██║██╔══╝░░██╔══██╗██║░░██║██║░░██║██╔═██╗░  ██║╚██╔╝██║██╔══██║██║░░╚██╗██║██║░░██╗██╔═██╗░██╔══╝░░░░╚██╔╝░░
// ██████╔╝███████╗██████╦╝╚█████╔╝╚█████╔╝██║░╚██╗  ██║░╚═╝░██║██║░░██║╚██████╔╝██║╚█████╔╝██║░╚██╗███████╗░░░██║░░░
// ╚═════╝░╚══════╝╚═════╝░░╚════╝░░╚════╝░╚═╝░░╚═╝  ╚═╝░░░░░╚═╝╚═╝░░╚═╝░╚═════╝░╚═╝░╚════╝░╚═╝░░╚═╝╚══════╝░░░╚═╝░░░


contract DebookMagickey is ERC721AQueryable, Ownable {
    using SafeERC20 for IERC20;

    uint256[3] public priceUSDC = [333 * 10**6, 666 * 10**6, 999 * 10**6]; // 333, 666, 999 USDC
    uint256[3] public supplyPhases = [1111, 2222, 3333]; //

    // USDC token Adddress
    address public tokenAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Mainnet
    // address public tokenAddress = 0x14196F08a4Fa0B66B7331bC40dd6bCd8A1dEeA9F; // Sepolia

    using Strings for uint256;

    uint256 public maxSupply = 3333;
    uint256 public currentPublicSupply = 1111;
    uint256 public currentAllowlistSupply = 1111;

    uint256 public phaseLevel = 0;

    uint256[10] public allowlistLevelAllowances;
    bytes32[10] public merkleRoots;
    // "phase id": {"sale id": {"wallet address": "nft balance"}}
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public allowlistMintedBalance;

    uint256 public totalPublicMints = 0;
    uint256 public totalAllowlistMints = 0;

    string public baseURI = "https://debook-aws-s3.s3.amazonaws.com/public/jsons/";
    string public uriSuffix = ".json";

    bool public paused = false;
    bool public publicMintEnabled = true;
    bool public allowlistMintEnabled = true;

    address public recipient;

    constructor() Ownable(msg.sender) ERC721A("Debook Magickey", "DBK") {
        recipient = msg.sender;
    }

    //******************************* MODIFIERS

    modifier notPaused() {
        require(!paused, "The contract is paused!");
        _;
    }

    modifier mintCompliance(uint256 quantity) {
        require(_totalMinted() + quantity <= maxSupply, "Max Supply Exceeded.");
        _;
    }

    //******************************* OVERRIDES

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    //******************************* MINT

    function mintAllowlist(uint256 allowlistLevel, uint256 quantity, bytes32[] calldata proof) external notPaused
        mintCompliance(quantity) {

            require(allowlistMintEnabled, "Allowlist: Mint is disabled!");
            require(allowlistLevel < 10, "Invalid allowlist level");
            require(totalAllowlistMints + quantity <= currentAllowlistSupply, "Current Allowlist Supply Exceeded.");

            require(
                    allowlistMintedBalance[phaseLevel][allowlistLevel][_msgSender()] + quantity <= allowlistLevelAllowances[allowlistLevel],
                    "Allowlist: Exceeds allowance!"
                );

            bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
            require(MerkleProof.verify(proof, merkleRoots[allowlistLevel], leaf), "Not a valid proof!");

            allowlistMintedBalance[phaseLevel][allowlistLevel][_msgSender()] += quantity;
            totalAllowlistMints += quantity;
            _safeMint(_msgSender(), quantity);
    }

    function mintPublic(address to, uint256 quantity) external notPaused
        mintCompliance(quantity) {

            require(publicMintEnabled, "Public: Mint is disabled!");
            // require(msg.value >= price * quantity, "Insufficient funds.");
//            require(totalPublicMints + quantity <= currentPublicSupply, "Current Public Supply Exceeded.");

            uint price = priceUSDC[phaseLevel] * quantity;
            if (totalPublicMints + quantity >= currentPublicSupply && phaseLevel < 2) {
                uint quantityAtCurrentPrice = currentPublicSupply - totalPublicMints;
                price = priceUSDC[phaseLevel] * quantityAtCurrentPrice + priceUSDC[phaseLevel + 1] * (quantity - quantityAtCurrentPrice);

                phaseLevel++;
                currentPublicSupply = supplyPhases[phaseLevel];
            }

            IERC20 tokenInstance = IERC20(tokenAddress);
            tokenInstance.safeTransferFrom(msg.sender, address(this), price);
            tokenInstance.safeTransfer(recipient, price);

            totalPublicMints += quantity;
            _safeMint(to, quantity);


    }

    function mintPublicAdmin(address to, uint256 quantity) external onlyOwner mintCompliance(quantity) {
        totalPublicMints += quantity;
        currentPublicSupply += quantity;
        _safeMint(to, quantity);
    }

    function mintAllowlistAdmin(address to, uint256 quantity) external onlyOwner mintCompliance(quantity) {
        totalAllowlistMints += quantity;
        _safeMint(to, quantity);
    }

    //******************************* ADMIN


    function setMintPriceUSDC(uint256 _priceUSDC, uint phase) external onlyOwner {
        priceUSDC[phase] = _priceUSDC;
    }

    function setMaxSupply(uint256 _supply) external onlyOwner {
        require(_supply >= _totalMinted() && _supply <= maxSupply, "Invalid Max Supply.");
        maxSupply = _supply;
    }

    function setCurrentPublicSupply(uint256 _supply) external onlyOwner {
        currentPublicSupply = _supply;
    }

    function setCurrentAllowlistSupply(uint256 _supply) external onlyOwner {
        currentAllowlistSupply = _supply;
    }

    // function setPrice(uint256 _price) public onlyOwner {
    //     price = _price;
    // }

    function setPhaseLevel(uint256 _phaseLevel) public onlyOwner {
        phaseLevel = _phaseLevel;
    }

    function setAllowlistLevelAllowances(uint256[10] calldata newAllowlistLevelAllowances) external onlyOwner {
        for (uint i = 0; i < 10; i++) {
            allowlistLevelAllowances[i] = newAllowlistLevelAllowances[i];
        }
    }

    function setMerkleRoot(uint256 allowlistLevel, bytes32 newMerkleRoot) external onlyOwner {
        require(allowlistLevel < 10, "Invalid allowlist level");
        merkleRoots[allowlistLevel] = newMerkleRoot;
    }

    function setMerkleRoots(bytes32[10] calldata newMerkleRoots) external onlyOwner {
        for (uint256 i = 0; i < 10; i++) {
            merkleRoots[i] = newMerkleRoots[i];
        }
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function setUriSuffix(string memory _uriSuffix) external onlyOwner {
        uriSuffix = _uriSuffix;
    }

    function setRecipient(address newRecipient) public onlyOwner {
        require(newRecipient != address(0), "Cannot be the 0 address!");
        recipient = newRecipient;
    }

    function setAllowlistMintEnabled(bool _state) public onlyOwner {
        allowlistMintEnabled = _state;
    }

    function setPublicMintEnabled(bool _state) public onlyOwner {
        publicMintEnabled = _state;
    }

    function setPaused(bool _state) public onlyOwner {
        paused = _state;
    }

    function setTokenAddress(address _tokenAddress) public onlyOwner {
        require(_tokenAddress != address(0), "Cannot be the 0 address!");
        tokenAddress = _tokenAddress;
    }

    //******************************* WITHDRAW

    function withdraw() public onlyOwner {

        require(recipient != address(0), "Cannot be the 0 address!");

        IERC20 tokenInstance = IERC20(tokenAddress);
        tokenInstance.transfer(recipient, tokenInstance.balanceOf(address(this)));

        uint256 balance = address(this).balance;
        bool success;
        (success, ) = payable(recipient).call{value: balance}("");
        require(success, "Transaction Unsuccessful");

    }

    //******************************* VIEWS

    function tokenURI(uint256 _tokenId) public view virtual override (ERC721A, IERC721A) returns (string memory) {
        require(_exists(_tokenId), "URI query for nonexistent token");

        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, _tokenId.toString(), uriSuffix)) : "";
    }

    function getAllowlistInfo(address user, uint256 phase) external view returns (uint256[10] memory totalAllowances, uint256[10] memory remainingBalances) {
        for (uint256 i = 0; i < 10; i++) {
            // Set totalAllowance
            totalAllowances[i] = allowlistLevelAllowances[i];

            // Set remainingBalance
            remainingBalances[i] = allowlistLevelAllowances[i] > allowlistMintedBalance[phase][i][user] ? allowlistLevelAllowances[i] - allowlistMintedBalance[phase][i][user] : 0;
        }
        return (totalAllowances, remainingBalances);
    }

}