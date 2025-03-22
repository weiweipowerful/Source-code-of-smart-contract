// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


contract TokenPresale is Context, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

   // The token being sold
    IERC20 private _token;
    IERC20 private _usdt;

    AggregatorV3Interface internal priceFeed;

    // Address where funds are collected
    address payable private _wallet;
    address private _tokenWallet;

    uint256 private _rate;
    uint256 private _weiRaised;
    uint256 private _usdtRaised;


    mapping(address => uint256) public contribution; 

    event TokensPurchased(address indexed purchaser, uint256 value, uint256 amount, string paymentType);


    constructor (
        uint256 __rate, 
        address payable __wallet, 
        IERC20 __token, 
        address __tokenWallet, 
        IERC20 __usdt
        ) Ownable(_msgSender()) {
        require(__rate > 0, "Presale: rate is 0");
        require(__wallet != address(0), "Presale: wallet is the zero address");
        require(address(__token) != address(0), "Presale: token is the zero address");
        require(__tokenWallet != address(0), "Presale: token wallet is the zero address");

        _rate = __rate;
        _wallet = __wallet;
        _token = __token;
        _tokenWallet = __tokenWallet;
        _usdt = __usdt;
        // sepolia 0x694AA1769357215DE4FAC081bf1f309aDC325306 mainnet 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        priceFeed= AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); 
    }

    fallback() external  {}

    receive () external payable {
        buyTokens(_msgSender());
    }

    function token() public view returns (IERC20) {
        return _token;
    }

    function wallet() public view returns (address payable) {
        return _wallet;
    }

    function rate() public view returns (uint256) {
        return _rate;
    }

    function tokenWallet() public view returns (address) {
        return _tokenWallet;
    }

    function setTokenWallet(address __tokenWallet) public onlyOwner {
        require(__tokenWallet != address(0), "Invalid Address");
        _tokenWallet = __tokenWallet;
    }

    function remainingTokens() public view returns (uint256) {
        return Math.min(token().balanceOf(_tokenWallet), token().allowance(_tokenWallet, address(this)));
    }

    function setRate(uint256 __rate) external onlyOwner {
        require(__rate > 0, "Presale: rate is 0");
        _rate = __rate;
    }

    function weiRaised() public view returns (uint256) {
        return _weiRaised;
    }

    function usdtRaised() public view returns (uint256) {
        return _usdtRaised;
    }

    function buyTokens(address beneficiary) public nonReentrant payable {
        uint256 weiAmount = msg.value;
        _preValidatePurchase(beneficiary, weiAmount);

        // calculate token amount to be created
        uint8 decimals = ERC20(address(_token)).decimals();
        uint256 tokenPrice = _getTokenPriceInEth(); // calculate token price in eth
        uint256 tokens = (weiAmount * (10**uint256(decimals))) / tokenPrice;

        // update state
        _weiRaised = _weiRaised + weiAmount;

        contribution[_msgSender()] = tokens;
        
        _deliverTokens(beneficiary, tokens);
        _forwardFunds();

        emit TokensPurchased(_msgSender(), weiAmount, tokens, 'ETH');
    }

    function buyTokens(address beneficiary, uint256 amount) public nonReentrant {
        uint256 weiAmount = amount;
        _preValidatePurchase(beneficiary, weiAmount);
        _usdt.safeTransferFrom(_msgSender(), _wallet, weiAmount);

        uint8 decimals = ERC20(address(_token)).decimals();
        uint256 tokenPrice = _rate; // calculate token price in eth
        uint256 tokens = (weiAmount * (10**uint256(decimals))) / tokenPrice;

        _usdtRaised = _usdtRaised + weiAmount;

        contribution[_msgSender()] = tokens;
        
        _deliverTokens(beneficiary, tokens);
        emit TokensPurchased(_msgSender(), weiAmount, tokens, 'USDT');

    }

    function _preValidatePurchase(address beneficiary, uint256 weiAmount) internal view {
        require(beneficiary != address(0), "Crowdsale: beneficiary is the zero address");
        require(weiAmount != 0, "Crowdsale: weiAmount is 0");
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
    }

    function _getTokenPriceInEth() internal view returns (uint256) {
        uint256 ethPriceInUsd = uint256(getLatestPriceEth());
        uint256 ethPriceinUSDT = ethPriceInUsd / 100;
        uint256 tokenPriceInEth = _rate * (10 ** 18) / ethPriceinUSDT;
        return tokenPriceInEth;
    }

    function _forwardFunds() internal {
        _wallet.transfer(msg.value);
    }

    function getLatestPriceEth() public view returns (int) {
        (
            /*uint80 roundID*/,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return answer;
    }

    function _deliverTokens(address beneficiary, uint256 tokenAmount) internal {
        _token.safeTransferFrom(_tokenWallet, beneficiary, tokenAmount);
    }




}