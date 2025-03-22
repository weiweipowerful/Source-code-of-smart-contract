// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";

contract GodCoin is OFT {
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111; // Replace with Sepolia chain ID
    uint256 public constant ETH_CHAIN_ID = 1; // Mainnet chain ID
    uint256 public constant MAX_SUPPLY = 777777777 * 10 ** 18; // 777777777 tokens with 18 decimals

    bool public hasMinted;

    event InitialMintCompleted(address indexed to, uint256 amount);

    constructor(string memory _name, string memory _symbol, address _lzEndpoint, address _delegate)
        OFT(_name, _symbol, _lzEndpoint, _delegate)
        Ownable(_delegate)
    {}

    function mint(address to, uint256 amount) external onlyOwner {
        require(
            block.chainid == SEPOLIA_CHAIN_ID || block.chainid == ETH_CHAIN_ID,
            "Minting allowed only on Sepolia or Ethereum mainnet"
        );
        require(!hasMinted, "Initial minting already completed");
        require(amount == MAX_SUPPLY, "Must mint exact max supply");

        hasMinted = true;
        _mint(to, amount);

        emit InitialMintCompleted(to, amount);
    }
}