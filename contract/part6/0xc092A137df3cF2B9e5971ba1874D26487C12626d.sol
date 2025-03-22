// SPDX-License-Identifier: MIT
// Telegram: https://t.me/ringcommunity
// Website: http://tryring.ai/

pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/dex/IUniswapRouter02.sol";
import "./interfaces/dex/IUniswapFactory.sol";
import "./interfaces/dex/IWETH.sol";

contract RingAIToken is ERC20, Ownable {
  uint private constant _RATE_NOMINATOR = 100e2;

  // Access config
  mapping(address => bool) public isInBlacklist;
  mapping(address => bool) public isInWhitelist;
  // Anti bot
  uint public tradeStartTime;
  uint public tradeMaxAmount;
  // Dex
  address public dexLP;
  address public dexRouter;
  // Tax
  uint public buyTax;
  uint public buyTaxCollected;
  uint public sellTax;
  uint public sellTaxCollected;
  uint public transferTax;
  uint public transferTaxCollected;
  uint public taxThreshold;
  uint public taxEndTime;
  address public taxHolder;

  event ProcessTaxSuccess(uint _taxProcess, uint _swappedETHAmount_);

  modifier onlyGranted(address _account) {
    require(_msgSender() == _account, "The caller has no rights");
    _;
  }

  /**
   * @dev Allow contract to receive ethers
   */
  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}

  constructor(string memory _pName, string memory _pSymbol, uint256 _pInitialSupply) ERC20(_pName, _pSymbol) {
    address sender_ = _msgSender();

    // Decimal and supply
    _mint(sender_, _pInitialSupply * 1e18);

    // Exclude addresses
    isInWhitelist[sender_] = true;

    // Tax config. Default 4% buy sell, 0% transfer
    taxHolder = sender_;
    buyTax = 4e2;
    sellTax = 4e2;
    transferTax = 0;
    taxThreshold = 1_000 * 1e18;
    taxEndTime = type(uint).max;
  }

  /**
   * @dev Get total tax collected
   */
  function totalTaxCollected() public view returns (uint) {
    return buyTaxCollected + sellTaxCollected + transferTaxCollected;
  }

  /**
   * @dev Override ERC20 transfer the tokens
   */
  function _transfer(address _pFrom, address _pTo, uint256 _pAmount) internal override {
    require(!isInBlacklist[_pFrom] && !isInBlacklist[_pTo], "ERC20Token: Blacklist");

    // No tax types
    bool isZeroFee_ = isInWhitelist[_pFrom] ||
      isInWhitelist[_pTo] ||
      _pFrom == address(this) ||
      block.timestamp >= taxEndTime;
    // Transfer types
    bool isRemoveLP_ = (_pFrom == dexLP && _pTo == dexRouter) ||
      (_pFrom == dexRouter && _pTo != dexLP && _pTo != dexRouter);
    bool isSellOrAddLP_ = _pFrom != dexLP && _pFrom != dexRouter && _pTo == dexLP;
    bool isBuy_ = _pFrom == dexLP && _pTo != dexLP && _pTo != dexRouter;

    // Logic
    if (isZeroFee_ || isRemoveLP_) {
      super._transfer(_pFrom, _pTo, _pAmount);
    } else {
      // Cannot transfer before trade start time
      require(tradeStartTime > 0 && tradeStartTime <= block.timestamp, "Invalid time");
      // Cannot transfer exceed trade max amount
      require(_pAmount <= tradeMaxAmount, "Invalid amount");

      // Tax swapping first
      if (!isBuy_) {
        _processAllTax();
      }

      // Tax calculating
      uint taxAmount_;
      if (isBuy_ && buyTax > 0) {
        taxAmount_ = (_pAmount * buyTax) / _RATE_NOMINATOR;
        buyTaxCollected += taxAmount_;
      } else if (isSellOrAddLP_ && sellTax > 0) {
        taxAmount_ = (_pAmount * sellTax) / _RATE_NOMINATOR;
        sellTaxCollected += taxAmount_;
      } else if (transferTax > 0) {
        taxAmount_ = (_pAmount * transferTax) / _RATE_NOMINATOR;
        transferTaxCollected += taxAmount_;
      }
      if (taxAmount_ > 0) {
        super._transfer(_pFrom, address(this), taxAmount_);
      }
      super._transfer(_pFrom, _pTo, _pAmount - taxAmount_);
    }
  }

  /**
   * @dev Set dex info
   * @param _pDexRouter address of router
   */
  function fSetDexInfo(address _pDexRouter, address _pToken2) external onlyOwner {
    dexRouter = _pDexRouter;
    IUniswapRouter02 router_ = IUniswapRouter02(dexRouter);
    IUniswapFactory factory_ = IUniswapFactory(router_.factory());
    address lpAddress_ = factory_.getPair(address(this), _pToken2);
    if (lpAddress_ == address(0)) {
      lpAddress_ = factory_.createPair(address(this), _pToken2);
    }
    dexLP = lpAddress_;
  }

  /**
   * @dev Function to add a account to blacklist
   */
  function fSetBlacklist(address _pAccount, bool _pStatus) external onlyOwner {
    require(isInBlacklist[_pAccount] != _pStatus, "0x1");
    isInBlacklist[_pAccount] = _pStatus;
  }

  /**
   * @dev Function to add a account to whitelist
   */
  function fSetWhitelist(address _pAccount, bool _pStatus) external onlyOwner {
    require(isInWhitelist[_pAccount] != _pStatus, "0x1");
    isInWhitelist[_pAccount] = _pStatus;
  }

  /**
   * @dev Config trade
   * @param _pStartTime start trade time. 0 will disable trade, should be > 0
   * @param _pMaxAmount max trade amount
   */
  function fConfigTrade(uint _pStartTime, uint _pMaxAmount) external onlyOwner {
    tradeStartTime = _pStartTime;
    tradeMaxAmount = _pMaxAmount;
  }

  /**
   * @dev Config tax for token
   * @param _pBuyTax buy tax value
   * @param _pSellTax sell tax value
   */
  function fConfigTax(uint _pBuyTax, uint _pSellTax, uint _pTransferTax) external onlyOwner {
    buyTax = _pBuyTax;
    sellTax = _pSellTax;
    transferTax = _pTransferTax;
  }

  /**
   * @dev Config tax threshold
   */
  function fConfigTaxThreshold(uint _pTaxThreshold) external onlyOwner {
    taxThreshold = _pTaxThreshold;
  }

  /**
   * @dev Config tax end time
   */
  function fConfigTaxEndTime(uint _pTaxEndTime) external onlyOwner {
    taxEndTime = _pTaxEndTime;
  }

  /**
   * @dev Config tax holder
   * @param _pTaxHolder buy tax value
   */
  function fConfigTaxHolder(address _pTaxHolder) external onlyOwner {
    taxHolder = _pTaxHolder;
  }

  /**
   * @dev Emergency withdraw eth balance
   */
  function fEmergencyEth(address _pTo, uint256 _pAmount) external onlyOwner {
    require(_pTo != address(0), "fEmergencyEth:0x1");
    payable(_pTo).transfer(_pAmount);
  }

  /**
   * @dev Emergency withdraw token balance
   */
  function fEmergencyToken(address _pToken, address _pTo, uint256 _pAmount) external onlyOwner {
    require(_pTo != address(0), "fEmergencyToken:0x1");
    IERC20 token_ = IERC20(_pToken);
    if (_pToken == address(this)) {
      uint balance_ = token_.balanceOf(_pToken);
      require(balance_ >= _pAmount + totalTaxCollected(), "fEmergencyToken:0x2");
    }
    token_.transfer(_pTo, _pAmount);
  }

  /**
   * @dev Burn all tax collected
   */
  function fBurnAllTax() external onlyGranted(taxHolder) {
    uint totalTax_ = totalTaxCollected();
    require(totalTax_ > 0, "0x1");
    _resetAllTax();
    _burn(address(this), totalTax_);
  }

  /**
   * @dev Claim all tax collected
   */
  function fClaimAllTax() external onlyGranted(taxHolder) {
    uint totalTax_ = totalTaxCollected();
    require(totalTax_ > 0, "0x1");
    _resetAllTax();
    _transfer(address(this), taxHolder, totalTax_);
  }

  /**
   * @dev Reset tax collected to zero
   */
  function _resetAllTax() private {
    buyTaxCollected = 0;
    sellTaxCollected = 0;
    transferTaxCollected = 0;
  }

  /**
   * @dev Process tax
   */
  function _processAllTax() private {
    uint taxProcess = totalTaxCollected();
    if (taxProcess >= taxThreshold) {
      // Reset tax collected
      _resetAllTax();

      // Swap to ETH
      _approve(address(this), dexRouter, taxProcess);

      address weth_ = IUniswapRouter02(dexRouter).WETH();
      address[] memory path_ = new address[](2);
      path_[0] = address(this);
      path_[1] = weth_;
      uint initialBalance_ = address(taxHolder).balance;
      IUniswapRouter02(dexRouter).swapExactTokensForETHSupportingFeeOnTransferTokens(
        taxProcess,
        0,
        path_,
        taxHolder,
        block.timestamp
      );
      uint swappedETHAmount_ = address(taxHolder).balance - initialBalance_;
      emit ProcessTaxSuccess(taxProcess, swappedETHAmount_);
    }
  }
}