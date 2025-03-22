// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

import {BitmapBT404} from "../bt404/BitmapBT404.sol";

contract BitmapPunks is BitmapBT404, OwnableRoles {
    /// @dev The role that can update the fee configurations of the contract.
    uint256 private constant _FEE_MANAGER_ROLE = _ROLE_101;

    uint32 public constant MAX_SUPPLY = 2_100_000;
    uint32 public constant MAX_PER_WALLET = 100;
    uint32 public constant MAX_PER_WALLET_SEND_TO = 5;

    error Locked();
    error InvalidMint();
    error TotalSupplyReached();

    string private _name;
    string private _symbol;
    uint32 public totalMinted;
    bool public nameAndSymbolLocked;
    bool public mintable;
    mapping(address sender => mapping(address receiver => uint256 nftAmount)) private _sendAmount;
    mapping(address sender => uint256 walletAmount) private _sendWallets;

    constructor(address mirror) {
        _initializeOwner(tx.origin);
        _name = "BitmapPunks";
        _symbol = "BMP";

        _initializeBT404(0, address(0), mirror, tx.origin);
    }

    modifier checkAndUpdateTotalMinted(uint256 nftAmount) {
        uint256 newTotalMinted = uint256(totalMinted) + nftAmount;
        require(newTotalMinted <= MAX_SUPPLY, TotalSupplyReached());

        totalMinted = uint32(newTotalMinted);
        _;
    }

    modifier checkAndUpdateBuyerMintCount(uint256 nftAmount) {
        uint256 currentMintCount = _getAux(msg.sender);
        uint256 newMintCount = currentMintCount + nftAmount;

        require(newMintCount <= MAX_PER_WALLET, InvalidMint());
        _setAux(msg.sender, uint56(newMintCount));
        _;
    }

    modifier checkMintable() {
        require(mintable, InvalidMint());
        _;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function mint(uint256 nftAmount)
        public
        payable
        checkMintable
        checkAndUpdateBuyerMintCount(nftAmount)
        checkAndUpdateTotalMinted(nftAmount)
    {
        _mint(msg.sender, nftAmount * _unit());
    }

    function mint(address to, uint256 nftAmount)
        public
        payable
        checkMintable
        checkAndUpdateTotalMinted(nftAmount)
    {
        uint256 minted = _sendAmount[msg.sender][to];
        require(minted + nftAmount <= MAX_PER_WALLET / MAX_PER_WALLET_SEND_TO, InvalidMint());

        if (minted == 0) {
            require(_sendWallets[msg.sender] < MAX_PER_WALLET_SEND_TO, InvalidMint());
            _sendWallets[msg.sender] += 1;
        }
        _sendAmount[msg.sender][to] += nftAmount;

        _mint(to, nftAmount * _unit());
    }

    function setExchangeNFTFeeRate(uint256 feeBips) public onlyOwnerOrRoles(_FEE_MANAGER_ROLE) {
        _setExchangeNFTFeeRate(feeBips);
    }

    function setNameAndSymbol(string memory name_, string memory symbol_) public onlyOwner {
        require(!nameAndSymbolLocked, Locked());

        _name = name_;
        _symbol = symbol_;
    }

    function lockNameAndSymbol() public onlyOwner {
        nameAndSymbolLocked = true;
    }

    function setMintable(bool mintable_) public onlyOwner {
        mintable = mintable_;
    }
}