// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AurealOnePresale is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public s_usdt;
    IERC20 public s_usdc;

    address public i_eth_usd_priceFeed;
    address public i_usdt_usd_priceFeed;

    constructor(address _owner) Ownable(_owner) {
        if (block.chainid == 1) {
            // Ethereum
            i_eth_usd_priceFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            i_usdt_usd_priceFeed = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
            s_usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
            s_usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        } else if (block.chainid == 56) {
            // Binance
            i_eth_usd_priceFeed = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;
            i_usdt_usd_priceFeed = 0xB97Ad0E74fa7d920791E90258A6E2085088b4320;
            s_usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
            s_usdc = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
        } else if (block.chainid == 137) {
            // Polygon
            i_eth_usd_priceFeed = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
            i_usdt_usd_priceFeed = 0x0A6513e40db6EB1b165753AD52E80663aeA50545;
            s_usdt = IERC20(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);
            s_usdc = IERC20(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
        } else if (block.chainid == 42161) {
            // Arbitrum
            i_eth_usd_priceFeed = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
            i_usdt_usd_priceFeed = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
            s_usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
            s_usdc = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        }
    }

    function _multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function _div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    function _getDerivedPrice(
        address _base,
        address _quote,
        uint8 _decimals
    ) internal view returns (int256) {
        require(
            _decimals > uint8(0) && _decimals <= uint8(18),
            "Invalid decimals"
        );
        int256 decimals = int256(10**uint256(_decimals));
        (, int256 basePrice, , , ) = AggregatorV3Interface(_base)
            .latestRoundData();
        uint8 baseDecimals = AggregatorV3Interface(_base).decimals();
        basePrice = _scalePrice(basePrice, baseDecimals, _decimals);

        (, int256 quotePrice, , , ) = AggregatorV3Interface(_quote)
            .latestRoundData();
        uint8 quoteDecimals = AggregatorV3Interface(_quote).decimals();
        quotePrice = _scalePrice(quotePrice, quoteDecimals, _decimals);

        return (basePrice * decimals) / quotePrice;
    }

    function _scalePrice(
        int256 _price,
        uint8 _priceDecimals,
        uint8 _decimals
    ) internal pure returns (int256) {
        if (_priceDecimals < _decimals) {
            return _price * int256(10**uint256(_decimals - _priceDecimals));
        } else if (_priceDecimals > _decimals) {
            return _price / int256(10**uint256(_priceDecimals - _decimals));
        }
        return _price;
    }

    event BoughtWithNativeToken(address user, uint256 amount, uint256 time, string clickid, uint256 token_quantity);
    event BoughtWithUSDT(address user, uint256 amount, uint256 time, string clickid, uint256 token_quantity);
    event BoughtWithUSDC(address user, uint256 amount, uint256 time, string clickid, uint256 token_quantity);

    function buyTokensNative(uint256 token_quantity, string memory clickid) external payable whenNotPaused {
        (bool sent, ) = payable(owner()).call{value: msg.value}("");
        require(sent, "Funds transfer unsuccesfull");
        emit BoughtWithNativeToken(msg.sender, msg.value, block.timestamp, clickid, token_quantity);
    }

    function buyTokensUSDT(uint256 amount, uint256 token_quantity, string memory clickid) external whenNotPaused {
        s_usdt.safeTransferFrom(msg.sender, owner(), amount);
        emit BoughtWithUSDT(msg.sender, amount, block.timestamp, clickid, token_quantity);
    }
    
    function buyTokensUSDC(uint256 amount, uint256 token_quantity, string memory clickid) external whenNotPaused {
        s_usdc.safeTransferFrom(msg.sender, owner(), amount);
        emit BoughtWithUSDC(msg.sender, amount, block.timestamp, clickid, token_quantity);
    }
    
    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    function unpause() external whenPaused onlyOwner {
        _unpause();
    }

    function withdrawERC20(address _tokenAddress, uint256 _amount)
        external
        onlyOwner
    {
        IERC20 currentToken = IERC20(_tokenAddress);
        currentToken.approve(address(this), _amount);
        currentToken.safeTransferFrom(address(this), owner(), _amount);
    }

    function withdrawNative(uint256 _amount) external onlyOwner {
        (bool hs, ) = payable(owner()).call{value: _amount}("");
        require(hs, "EnergiWanBridge:: Failed to withdraw native coins");
    }
}