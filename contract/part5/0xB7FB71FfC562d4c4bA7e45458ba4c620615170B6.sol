// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "./DEXIndex.sol";

contract DEX {
    // -------  State ------- //
    address[] public portfolios;
    address public owner;
    mapping(string => address) private portfolioByName;
    mapping(address => string) private portfolioByAddress;

    // -------  Events ------- //
    event CreatePortfolio(
        address indexed portfolioAddress,
        string indexed name,
        string indexed symbol,
        address[] tokenAddresses,
        uint256[] percentageHoldings,
        address owner,
        uint256 ownerFee
    );

    // -------  Constructor ------- //
    constructor(address newOner) {
        owner = newOner;
    }

     //change owner
    function changeOwner(address newOner) public onlyOwner{
        owner = newOner;
    }

    // -------  Modifiers ------- //
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the contract owner can call this function");
        _;
    }

    // -------  Functions ------- //
    function create(
        string memory name_,
        string memory symbol_,
        address[] memory tokenAddresses_,
        uint256[] memory percentageHoldings_,
        uint256 ownerFee_
    ) public onlyOwner {
        DEXIndex portfolio = new DEXIndex(
            name_,
            symbol_,
            tokenAddresses_,
            percentageHoldings_,
            msg.sender,
            ownerFee_
        );
        emit CreatePortfolio(
            address(portfolio),
            name_,
            symbol_,
            tokenAddresses_,
            percentageHoldings_,
            msg.sender,
            ownerFee_
        );
        portfolios.push(address(portfolio));
        portfolioByName[name_] = address(portfolio);
        portfolioByAddress[address(portfolio)] = name_;
    }

    function getPortfolioByName(string memory name_) public view returns (address) {
        return portfolioByName[name_];
    }

    function getPortfolioByAddress(address  porAddress) public view returns (string memory) {
        return portfolioByAddress[porAddress];
    }

    function getPortfolioDetailsByName(string memory name_) public view returns (address[] memory, uint256[] memory) {
        address portfolioAddress = portfolioByName[name_];
        require(portfolioAddress != address(0), "Portfolio does not exist");

        DEXIndex portfolio = DEXIndex(portfolioAddress);
        return (portfolio.getTokenAddresses(), portfolio.getPercentageHoldings());
    }
}