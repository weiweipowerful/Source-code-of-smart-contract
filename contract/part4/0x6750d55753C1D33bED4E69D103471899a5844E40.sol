// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "src/interfaces/IOracle.sol";
import "src/utils/AddressUtils.sol";

contract XOracle is AccessControl, IOracle {
    bytes32 public constant FEEDER_ROLE = keccak256("FEEDER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    /// @inheritdoc IOracle
    uint32 public constant STALENESS_DEFAULT_THRESHOLD = 86400;

    /// @inheritdoc IOracle
    address public immutable baseToken;

    mapping (address => IOracle.Price) public prices;
    /**
     * @notice Maps the token address to to the staleness threshold in seconds.
     *          When the value equals to the max value of uint32, it indicates unrestricted.
     */
    mapping(address quoteToken => uint32) internal _stalenessThreshold;
    mapping(address quoteToken => uint256) internal _maxPriceTolerance;
    mapping(address quoteToken => uint256) internal _minPriceTolerance;

    constructor(address baseToken_) {
        // Grant the contract deployer the default admin role: it will be able
        // to grant and revoke any roles
        _setRoleAdmin(GUARDIAN_ROLE, GUARDIAN_ROLE);
        _setRoleAdmin(FEEDER_ROLE, GUARDIAN_ROLE);

        _grantRole(GUARDIAN_ROLE, msg.sender);
        _grantRole(FEEDER_ROLE, msg.sender);

        AddressUtils.checkContract(baseToken_);
        baseToken = baseToken_;
    }

    // ========================= FEEDER FUNCTIONS ====================================

    /// @inheritdoc IOracle
    function putPrice(address asset, uint64 timestamp, uint256 price) public onlyRole(FEEDER_ROLE) {
        uint64 prev_timestamp = prices[asset].timestamp;
        if (timestamp <= prev_timestamp || timestamp > block.timestamp) revert TimestampInvalid();
        _checkPriceInTolerance(asset, price);
        uint256 prev_price = prices[asset].price;
        prices[asset] = IOracle.Price(asset, timestamp, prev_timestamp, price, prev_price);
        emit newPrice(asset, timestamp, price);
    }

    /// @inheritdoc IOracle
    function updatePrices(IOracle.NewPrice[] calldata _array) external onlyRole(FEEDER_ROLE) {
        uint256 arrLength = _array.length;
        for(uint256 i=0; i<arrLength; ){
            address asset = _array[i].asset;
            uint64 timestamp = _array[i].timestamp;
            uint256 price = _array[i].price;
            putPrice(asset, timestamp, price);
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IOracle
    function setStalenessThresholds(address[] calldata quoteTokens, uint32[] calldata thresholds) external onlyRole(GUARDIAN_ROLE) {
        uint256 tokenCount = quoteTokens.length;
        if (tokenCount != thresholds.length) revert LengthMismatched();

        for (uint256 i; i < tokenCount; i++) {
            _stalenessThreshold[quoteTokens[i]] = thresholds[i];
            emit StalenessThresholdUpdated(quoteTokens[i], thresholds[i]);
        }
    }

    /// @inheritdoc IOracle
    function setPriceTolerance(address quoteToken, uint256 minPrice, uint256 maxPrice) external onlyRole(GUARDIAN_ROLE) {
        _setPriceTolerance(quoteToken, minPrice, maxPrice);
    }

    // ========================= VIEW FUNCTIONS ====================================

    /// @inheritdoc IOracle
    function getPrice(address asset) public view returns (uint64, uint64, uint256, uint256) {
        return (
            prices[asset].timestamp,
            prices[asset].prev_timestamp,
            prices[asset].price,
            prices[asset].prev_price
        );
    }

    /// @inheritdoc IOracle
    function getLatestPrice(address quoteToken) public view returns (uint256 price) {
        _checkPriceNotStale(quoteToken);

        price = prices[quoteToken].price;

        if (price == 0) revert PriceZero();
    }

    /// @inheritdoc IOracle
    function getPrices(address[] calldata assets) public view returns (IOracle.Price[] memory) {
        uint256 assetCount = assets.length;
        IOracle.Price[] memory _prices = new IOracle.Price[](assetCount);

        for (uint256 i; i < assetCount; i++) {
            _prices[i] = prices[assets[i]];
        }

        return _prices;
    }

    /// @inheritdoc IOracle
    function getStalenessThreshold(address quoteToken) public view returns (uint32) {
        uint32 threshold = _stalenessThreshold[quoteToken];

        return threshold == 0 ? STALENESS_DEFAULT_THRESHOLD : threshold;
    }

    /// @inheritdoc IOracle
    function getPriceTolerance(address quoteToken) public view returns (uint256 minPrice, uint256 maxPrice) {
        minPrice = _minPriceTolerance[quoteToken];
        maxPrice = _maxPriceTolerance[quoteToken];
    }

    /// @inheritdoc IOracle
    function getQuoteToken(address tokenX, address tokenY) public view returns (address quoteToken) {
        if (tokenX == tokenY) revert TokensInvalid();

        bool isXBase = tokenX == baseToken;
        if (!isXBase && tokenY != baseToken) revert TokensInvalid();

        quoteToken = isXBase ? tokenY : tokenX;
    }

    /// @inheritdoc IOracle
    function getQuoteTokenAndPrice(address tokenX, address tokenY) public view returns (address quoteToken, uint256 price) {
        quoteToken = getQuoteToken(tokenX, tokenY);
        price = getLatestPrice(quoteToken);
    }

    // ========================= PURE FUNCTIONS ====================================

    function decimals() public pure returns (uint8) {
        return 18;
    }

    // ========================= INTERNAL FUNCTIONS ================================

    function _setPriceTolerance(address quoteToken, uint256 minPrice, uint256 maxPrice) internal {
        if (maxPrice == 0 || minPrice == 0 || minPrice > maxPrice) revert PriceToleranceInvalid();
        _maxPriceTolerance[quoteToken] = maxPrice;
        _minPriceTolerance[quoteToken] = minPrice;
        emit PriceToleranceUpdated(quoteToken, minPrice, maxPrice);
    }

    /**
     * @notice Reverts if the price tolerance is invalid or if the price is outside the acceptable tolerance range
     * @param quoteToken Address of quote token
     * @param price The price of `baseToken`/`quoteToken`
     */
    function _checkPriceInTolerance(address quoteToken, uint256 price) internal view {
        (uint256 minPrice, uint256 maxPrice) = getPriceTolerance(quoteToken);

        if (minPrice == 0 || maxPrice == 0) revert PriceToleranceInvalid();
        if (price < minPrice || price > maxPrice) revert PriceNotInTolerance();
    }

    /**
     * @notice Reverts if the price is stale
     * @param quoteToken Address of the quote token
     */
    function _checkPriceNotStale(address quoteToken) internal view {
        uint32 threshold = getStalenessThreshold(quoteToken);

        if (threshold < type(uint32).max) {
            uint64 priceTimestamp = prices[quoteToken].timestamp;
            if (priceTimestamp <= block.timestamp && block.timestamp - priceTimestamp > threshold) {
                revert PriceStale();
            }
        }
    }
}