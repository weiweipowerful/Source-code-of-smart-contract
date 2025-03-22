// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface AggregatorV3Interface {
    function latestRoundData() external view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

contract StableCoinGold is ReentrancyGuard, Ownable, ERC20 {
    AggregatorV3Interface public priceOracle;

    uint256 private constant GRAMS_PER_OUNCE = 311035;
    uint256 private constant INITIAL_FIXED_PRICE = 35; // $0.000035

    bool public isPeggedToGold = false;
    bool public isConsiderReserve = false;

    uint256 public goldReserve;
    uint256 public targetPrice = 80; // actual by price from oracle
    uint256 public rebaseInterval = 1 seconds; // for rebase
    uint256 public lastRebaseTime; // last timestamp of rebase
    uint256 public maxRebasePercentage = 10; // percentage 10%

    event Mint(address indexed to, uint256 amount, uint256 timestamp);
    event Burn(address indexed from, uint256 amount, uint256 timestamp);
    event GoldReserveUpdated(uint256 newReserve, uint256 timestamp);
    event Rebase(uint256 newTotalSupply, uint256 timestamp);
    event Transaction(address indexed from, address indexed to, uint256 amount, string action, uint256 timestamp);
    event PegSwitched(bool peggedSwitch, uint256 timestamp);
    event ConsiderReserveSwitched(bool isConsiderReserveSwitched, uint256 timestamp);
    event TargetPriceUpdated(uint256 newTargetPrice, uint256 timestamp);

    constructor(address _priceOracle, address _initialOwner)
        ERC20("GLD Coin", "GLDC")
        Ownable(_initialOwner)
    {
        priceOracle = AggregatorV3Interface(_priceOracle);
        _mint(address(this), 1000000000);
        lastRebaseTime = block.timestamp;
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function setRebaseInterval(uint256 _newTime) external onlyOwner {
        require(_newTime > 0, "Rebase interval must be > 0");
        rebaseInterval = _newTime;
    }

    function setMaxRebasePercentage(uint256 newValue) external onlyOwner {
        maxRebasePercentage = newValue;
    }

    function updateOracleFeedAddress(address _oracleAddress) external onlyOwner {
        require(_oracleAddress != address(0), "New oracle is zero address");
        priceOracle = AggregatorV3Interface(_oracleAddress);
    }

    function mint(address to, uint256 amount) external onlyOwner nonReentrant {
        if(isConsiderReserve) {
            require(amount <= goldReserve, "Not enough gold reserve");
            goldReserve -= amount;
        }
        _mint(to, amount);
        emit Mint(to, amount, block.timestamp);
        emit Transaction(address(0), to, amount, "transfer_mint", block.timestamp);
    }

    function burn(uint256 amount) external nonReentrant {
        _burn(msg.sender, amount);
        goldReserve += amount;
        emit Burn(msg.sender, amount, block.timestamp);
        emit Transaction(msg.sender, address(0), amount, "transfer_burn", block.timestamp);
    }

    function burnFrom(address account, uint256 amount) external nonReentrant {
        require(allowance(account, msg.sender) >= amount, "Not allowed");
        _approve(account, msg.sender, allowance(account, msg.sender) - amount);
        _burn(account, amount);
        goldReserve += amount;
        emit Burn(account, amount, block.timestamp);
        emit Transaction(account, address(0), amount, "transfer_burn", block.timestamp);
    }

    function burnFromAddress(uint256 amount, address to) external nonReentrant {
        address burnAddress = (to == address(0)) ? address(this) : to;
        _burn(burnAddress, amount);
        goldReserve += amount;
        emit Burn(burnAddress, amount, block.timestamp);
        emit Transaction(burnAddress, address(0), amount, "transfer_burn", block.timestamp);
    }

    function switchToGoldPeg() external onlyOwner  {
        isPeggedToGold = !isPeggedToGold;
        emit PegSwitched(isPeggedToGold, block.timestamp);
    }

    function switchToConsiderReserveGold() external onlyOwner  {
        isConsiderReserve = !isConsiderReserve;
        emit ConsiderReserveSwitched(isConsiderReserve, block.timestamp);
    }

    function updateTargetPrice(uint256 newTargetPrice) external onlyOwner {
        targetPrice = newTargetPrice;
        emit TargetPriceUpdated(newTargetPrice, block.timestamp);
    }

    function rebase() external onlyOwner nonReentrant {
        require(isPeggedToGold, "Need peg actual gold price");
        require(block.timestamp >= lastRebaseTime + rebaseInterval, "Rebase interval not reached");
        lastRebaseTime = block.timestamp;

        uint256 marketPrice = getGoldPricePerGram();
        uint256 currentSupply = totalSupply();
        uint256 supplyChange;

        if (marketPrice > targetPrice) {
            supplyChange = (marketPrice - targetPrice) * currentSupply / targetPrice;
            uint256 maxChange = currentSupply * maxRebasePercentage / 100;
            if(supplyChange > maxChange) {
                supplyChange = maxChange;
            }
            _mint(address(this), supplyChange);
        } else if (marketPrice < targetPrice) {
            supplyChange = (targetPrice - marketPrice) * currentSupply / targetPrice;
            uint256 maxChange = currentSupply * maxRebasePercentage / 100;
            if(supplyChange > maxChange) {
                supplyChange = maxChange;
            }
            require(balanceOf(address(this)) >= supplyChange, "Insufficient balance for rebase burn");
            _burn(address(this), supplyChange);
        }
        emit Rebase(totalSupply(), block.timestamp);
    }

    function transfer(address to, uint256 amount) public override nonReentrant returns (bool) {
        bool success = super.transfer(to, amount);
        if (success) {
            emit Transaction(_msgSender(), to, amount, "transfer", block.timestamp);
        }
        return success;
    }

    function sendTokens(address recipient, uint256 amount) external onlyOwner nonReentrant {
        require(balanceOf(address(this)) >= amount, "Not enough tokens in contract");
        _transfer(address(this), recipient, amount);
        emit Transaction(address(this), recipient, amount, "transfer", block.timestamp);
    }

    function transferFrom(address from, address to, uint256 amount) public override nonReentrant returns (bool) {
        bool success = super.transferFrom(from, to, amount);
        if (success) {
            emit Transaction(from, to, amount, "transfer_from", block.timestamp);
        }
        return success;
    }

    function updateGoldReserve(uint256 newReserve) external onlyOwner nonReentrant {
        goldReserve = newReserve;
        emit GoldReserveUpdated(newReserve, block.timestamp);
    }

    function calculateUSDValue(uint256 tokenAmount) public view returns (uint256) {
        uint256 goldPricePerGram = getGoldPricePerGram();
        return tokenAmount * goldPricePerGram;
    }

    function getGoldPricePerOunce() public view returns (uint256) {
        if (!isPeggedToGold) {
            return INITIAL_FIXED_PRICE * 1000;
        } else {
            (, int256 price, , uint256 updatedAt, ) = priceOracle.latestRoundData();
            require(price > 0, "Invalid price");
            return uint256(price);
        }
    }

    function getGoldPricePerGram() public view returns (uint256) {
        if (!isPeggedToGold) {
            return INITIAL_FIXED_PRICE;
        } else {
            uint256 goldPricePerOunce = getGoldPricePerOunce();
            return ((goldPricePerOunce * 10**4) / GRAMS_PER_OUNCE) + 10;
        }
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        _transferOwnership(newOwner);
    }

    function getIsPeggedToGold() public view returns (bool) {
        return isPeggedToGold;
    }

    function getIsConsiderReserve() public view returns (bool) {
        return isConsiderReserve;
    }

    function getTargetPrice() public view returns (uint256) {
        return targetPrice;
    }

    function getGoldReserve() public view returns (uint256) {
        return goldReserve;
    }

    function getTotalSupply() public view returns (uint256) {
        return totalSupply();
    }

    function getLastRebaseTime() public view returns (uint256) {
        return lastRebaseTime;
    }
}