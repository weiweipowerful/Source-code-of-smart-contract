// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title TokenSwapETH - A decentralized token marketplace using ETH
/// @notice This contract allows users to list and purchase tokens using ETH.
/// @dev Prices are converted using a TRX/ETH price oracle.
interface IPriceOracle {
    function getPrice() external view returns (uint256);
}

contract TokenSwapETH {
    IERC20 public token;
    IPriceOracle public priceOracle; // External price oracle contract
    address public owner;

    struct TokenListing {
        address seller;
        uint256 amount; // In token's smallest units (18 decimals)
        uint256 priceInTRX; // In TRX's smallest units (6 decimals)
    }

    TokenListing[] public tokenListings;
    mapping(address => uint256[]) public sellerListings;

    event TokensListed(
        address indexed seller,
        uint256 amount,
        uint256 priceInTRX
    );
    event TokensPurchased(
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        uint256 totalPriceETH
    );
    event TokensCancelSell(
        address indexed seller,
        uint256 indexed listingIndex
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    /// @notice Contract constructor to initialize token and price oracle
    /// @param _token Address of the ERC20 token
    /// @param _priceOracle Address of the TRX/ETH price oracle
    constructor(address _token, address _priceOracle) {
        token = IERC20(_token);
        priceOracle = IPriceOracle(_priceOracle);
        owner = msg.sender;
    }

    /// @notice Fetches the latest TRX/ETH price from the oracle
    /// @return The TRX/ETH conversion rate
    function getLatestPrice() public view returns (uint256) {
        return priceOracle.getPrice();
    }

    /// @notice Retrieves all token listings
    /// @return sellers Array of seller addresses
    /// @return amounts Array of token amounts
    /// @return prices Array of prices in TRX
    function getTokenListings()
        external
        view
        returns (
            address[] memory sellers,
            uint256[] memory amounts,
            uint256[] memory prices
        )
    {
        uint256 numListings = tokenListings.length;
        sellers = new address[](numListings);
        amounts = new uint256[](numListings);
        prices = new uint256[](numListings);

        for (uint256 i = 0; i < numListings; i++) {
            TokenListing storage listing = tokenListings[i];
            sellers[i] = listing.seller;
            amounts[i] = listing.amount;
            prices[i] = listing.priceInTRX;
        }
    }

    /// @notice Allows a user to list tokens for sale
    /// @param amount The number of tokens to sell (18 decimals)
    /// @param priceInTRX The price in TRX (6 decimals)
    function sellTokens(uint256 amount, uint256 priceInTRX) external {
        require(amount > 0, "Amount must be greater than zero");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");

        token.transferFrom(msg.sender, address(this), amount);

        tokenListings.push(TokenListing(msg.sender, amount, priceInTRX));
        sellerListings[msg.sender].push(tokenListings.length - 1);

        emit TokensListed(msg.sender, amount, priceInTRX);
    }

    /// @notice Purchases the entire listing for ETH
    /// @param listingIndex The index of the listing
    function buyWholeListing(uint256 listingIndex) external payable {
        require(listingIndex < tokenListings.length, "Invalid listing index");
        TokenListing storage listing = tokenListings[listingIndex];

        uint256 trxEthPrice = getLatestPrice();
        uint256 priceInETH = (listing.priceInTRX * 1e18) / trxEthPrice;
        require(msg.value >= priceInETH, "Insufficient ETH sent");

        token.transfer(msg.sender, listing.amount);
        payable(listing.seller).transfer(priceInETH);

        deleteTokenListing(listingIndex);

        if (msg.value > priceInETH) {
            payable(msg.sender).transfer(msg.value - priceInETH);
        }

        emit TokensPurchased(
            msg.sender,
            listing.seller,
            listing.amount,
            priceInETH
        );
    }

    /// @notice Purchases a portion of a token listing
    /// @param listingIndex The index of the listing
    /// @param amount The amount of tokens to buy
    function buyPartialListing(
        uint256 listingIndex,
        uint256 amount
    ) external payable {
        require(listingIndex < tokenListings.length, "Invalid listing index");
        TokenListing storage listing = tokenListings[listingIndex];

        require(amount > 0 && amount <= listing.amount, "Invalid amount");

        uint256 priceInTRX = (listing.priceInTRX * amount) / listing.amount;
        uint256 trxEthPrice = getLatestPrice();
        uint256 priceInETH = (priceInTRX * 1e18) / trxEthPrice;

        require(msg.value >= priceInETH, "Insufficient ETH sent");

        token.transfer(msg.sender, amount);
        payable(listing.seller).transfer(priceInETH);

        listing.amount -= amount;
        listing.priceInTRX -= priceInTRX;

        if (listing.amount == 0) {
            deleteTokenListing(listingIndex);
        }

        if (msg.value > priceInETH) {
            payable(msg.sender).transfer(msg.value - priceInETH);
        }

        emit TokensPurchased(msg.sender, listing.seller, amount, priceInETH);
    }

    /// @notice Cancels a token listing
    /// @param listingIndex The index of the listing
    function cancelSell(uint256 listingIndex) external {
        require(listingIndex < tokenListings.length, "Invalid listing index");
        require(
            tokenListings[listingIndex].seller == msg.sender,
            "Not your listing"
        );

        token.transfer(msg.sender, tokenListings[listingIndex].amount);
        deleteTokenListing(listingIndex);

        emit TokensCancelSell(msg.sender, listingIndex);
    }

    function deleteTokenListing(uint256 listingIndex) private {
        uint256 lastIndex = tokenListings.length - 1;
        tokenListings[listingIndex] = tokenListings[lastIndex];
        tokenListings.pop();
    }

    /// @notice Updates the price oracle address
    /// @param _priceOracle The new oracle address
    function setPriceOracle(address _priceOracle) external onlyOwner {
        require(_priceOracle != address(0), "Invalid oracle address");
        priceOracle = IPriceOracle(_priceOracle);
    }

    /// @notice Checks the ETH equivalent price for a given token amount
    /// @param amount The amount of tokens
    /// @return priceInETH The price in ETH
    function checkPriceInETH(uint256 amount) external view returns (uint256) {
        require(amount > 0, "Amount must be greater than zero");

        uint256 trxEthPrice = getLatestPrice();
        require(trxEthPrice > 0, "Invalid TRX/ETH price");

        uint256 priceInTRX = (amount * 1e6) / 1e18;
        uint256 priceInETH = (priceInTRX * 1e18) / trxEthPrice;

        return priceInETH;
    }
}