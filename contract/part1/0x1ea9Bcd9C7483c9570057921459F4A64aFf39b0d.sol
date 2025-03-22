// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract FlaryTokenSale is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for ERC20;

    ERC20 public usdt;

    AggregatorV3Interface public nativeUsdPriceFeed;
    uint256 public tokensPriceInUsdt;

    uint256 public tokenSold;
    mapping(address => uint256) public investemetByAddress;
    address[] public buyers;

    constructor(
        address _usdt,
        address _priceFeed,
        uint256 _tokensPriceInUsdt
    ) Ownable(msg.sender) {
        usdt = ERC20(_usdt);
        nativeUsdPriceFeed = AggregatorV3Interface(_priceFeed);
        tokensPriceInUsdt = _tokensPriceInUsdt;
    }

    function buyTokensNative() external payable whenNotPaused {
        buyers.push(msg.sender);

        (, int256 nativePrice, , , ) = nativeUsdPriceFeed.latestRoundData();

        uint8 feed_Decimals = nativeUsdPriceFeed.decimals();
        uint8 usdtDecimals = usdt.decimals();

        // assuming token's decimals 18
        uint256 tokensAmount;
        if (feed_Decimals > usdtDecimals) {
            tokensAmount =
                (msg.value * uint256(nativePrice)) /
                (tokensPriceInUsdt * 10 ** (feed_Decimals - usdtDecimals));
        } else {
            tokensAmount =
                (msg.value *
                    uint256(nativePrice) *
                    10 ** (usdtDecimals - feed_Decimals)) /
                tokensPriceInUsdt;
        }

        investemetByAddress[msg.sender] += tokensAmount;
        tokenSold += tokensAmount;
    }

    function buyTokensUSDT(uint256 amount) external whenNotPaused {
        usdt.safeTransferFrom(msg.sender, address(this), amount);

        uint256 tokensAmount = (amount * 10 ** 18) / tokensPriceInUsdt;

        investemetByAddress[msg.sender] += tokensAmount;
        tokenSold += tokensAmount;
    }

    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    function unpause() external whenPaused onlyOwner {
        _unpause();
    }

    function withdrawUSDT(uint256 _amount) external onlyOwner {
        usdt.forceApprove(address(this), _amount);
        usdt.safeTransferFrom(address(this), owner(), _amount);
    }

    function withdrawNative(uint256 _amount) external onlyOwner {
        (bool hs, ) = payable(owner()).call{value: _amount}("");
        require(hs, "EnergiWanBridge:: Failed to withdraw native coins");
    }

    function changePrice(uint256 _tokensPriceInUsdt) external onlyOwner {
        tokensPriceInUsdt = _tokensPriceInUsdt;
    }
}