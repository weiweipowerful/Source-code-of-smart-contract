/**
 *Submitted for verification at Etherscan.io on 2025-02-14
*/

// SPDX-License-Identifier: MIT

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// File: @chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol


pragma solidity ^0.8.0;

// solhint-disable-next-line interface-starts-with-i
interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(
    uint80 _roundId
  ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// File: Mainnet/EDMPresaleNew.sol


pragma solidity ^0.8.23;



abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Owner cannot be the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

}

interface CustomIER20 is IERC20Metadata {
    function transferAndVest(address recipient, uint256 amount) external returns (bool);
}

contract EDMAPresale is ReentrancyGuard, Ownable {
    struct PresaleStage {
        uint256 pricePerToken;  // Price in USD (scaled to 18 decimals)
        uint256 tokensToSell;   // Total tokens allocated for this stage
        uint256 bonusPercentage;    // Bonus percentage for this stage
        uint256 tokensSold;     // Total tokens sold in this stage
        uint256 fundsRaised;    // Total funds raised in USD for this stage
        uint256 bonusGiven;     // Total bonus given
    }

    uint256 ETH_MULTIPLIER = 10**18;
    CustomIER20 public edm; // EDMA token
    CustomIER20 public usdt; // USDT token
    AggregatorV3Interface public priceFeed; // Chainlink price feed for ETH/USD

    uint256 public activeStage; // Active presale stage ID
    uint256 public nextStage;   // ID of the next presale stage
    uint256 public totalFundsRaised; // Total funds raised across all stages

    bool public isBuyEnabled = true;

    struct RewardTier {
        uint256 minAmount;
        uint256 percentage;
    }

    mapping(string => RewardTier) public rewardTiers;

    struct UserData {
        uint256 investedAmountUSD;
        uint256 receivedTokenAmount;
        uint256 referalRewardUSDAmount;
        bool didInvested;
    }
    mapping(address => UserData) public userData; // wallet address => user's detail

    mapping(uint256 => PresaleStage) public presaleStages; // Stage ID => Stage Data
    uint256 public stageCount; // Total number of stages created

    
    event StageCreated(uint256 indexed stageId, uint256 pricePerToken, uint256 tokensToSell, uint256 bonusPercentage);
    event StageUpdated(uint256 indexed stageId, uint256 pricePerToken, uint256 tokensToSell, uint256 bonusPercentage);
    event TokensPurchased(address indexed buyer, uint256 indexed stageId, uint256 usdAmount, uint256 tokens, string method);
    event RewardAdded(address indexed tokenBuyer, address referralAddress, uint256 indexed stageId, uint256 usdAmount, uint256 purchasedTokens, uint256 rewardAmount);
    event RewardClaimed(address indexed user, uint256 claimedRewardAmount, string method);
    event StageActivated(uint256 indexed stageId);
    event FundsWithdrawn(uint256 amount, string method);

    modifier validReferral(address referalAddress) {
        require(referalAddress != msg.sender, "Self-referral is not allowed");
        // require(referalAddress == address(0) || userData[referalAddress].didInvested == true, "Invalid referral");
        _;
    }

    constructor(
        address _edm,
        address _usdt,
        address _priceFeed
    ) {
        require(_edm != address(0), "Invalid EDM address");
        require(_usdt != address(0), "Invalid USDT token address");
        require(_priceFeed != address(0), "Invalid price feed address");

        edm = CustomIER20(_edm);
        usdt = CustomIER20(_usdt);
        priceFeed = AggregatorV3Interface(_priceFeed);

        // Initialize the first two stages
        _createStage(5e16, 20_000_000 , 10); // Stage 1: $0.05
        _createStage(8e16, 20_000_000 , 5); // Stage 2: $0.08


        // Set the first stage as active and the second as next
        activeStage = 0;
        nextStage = 1;

        // set rewardtiers
        rewardTiers["Platinum"] = RewardTier({minAmount: 10_000, percentage: 10});
        rewardTiers["Gold"] = RewardTier({minAmount: 1_000, percentage: 7});
        rewardTiers["Silver"] = RewardTier({minAmount: 500, percentage: 5});
        rewardTiers["Bronze"] = RewardTier({minAmount: 100, percentage: 3});
    }

    function _createStage(uint256 pricePerToken, uint256 tokensToSell, uint256 bonusPercentage) internal {
        presaleStages[stageCount] = PresaleStage(pricePerToken, tokensToSell, bonusPercentage, 0, 0, 0);
        emit StageCreated(stageCount, pricePerToken, tokensToSell, bonusPercentage);
        stageCount++;
    }

    function createNewStage(uint256 pricePerToken, uint256 tokensToSell, uint256 bonusPercentage) external onlyOwner {
        require(pricePerToken > 0, "Price must be greater than 0");
        require(tokensToSell > 0, "Tokens must be greater than 0");
        
        _createStage(pricePerToken, tokensToSell , bonusPercentage);
    }

    function activateStage(uint256 stageId) external  onlyOwner {
        require(stageId > activeStage, "Cannot activate previous stages");
        require(stageId < stageCount - 1, "Stage not available");
        activeStage = stageId;
        nextStage = stageId+1;
        emit StageActivated(activeStage);
    }

    function updateStage(uint256 stageId, uint256 pricePerToken, uint256 bonusPercentage, uint256 tokensToSell) external onlyOwner {
        presaleStages[stageId].bonusPercentage = bonusPercentage;
        // only udpdate tokens and price if its passed.
        if(tokensToSell > 0) {
            presaleStages[stageId].tokensToSell = tokensToSell;
        }

        if(pricePerToken > 0) {
            presaleStages[stageId].pricePerToken = pricePerToken;
        }

        emit StageUpdated(stageId, presaleStages[stageId].pricePerToken, presaleStages[stageId].tokensToSell, presaleStages[stageId].bonusPercentage);
    }

    function buyWithETH(address referalAddress) external payable nonReentrant validReferral(referalAddress) {
        require(isBuyEnabled, "Purchasing is currently unavailable.");
        require(msg.value > 0, "Cannot send 0 ETH");
        uint256 ethPriceUSD = getETHUSDPrice();
        uint256 usdAmount = (msg.value * ethPriceUSD) / (ETH_MULTIPLIER * ETH_MULTIPLIER);
        _handlePurchase(usdAmount, msg.value, "ETH", referalAddress);
        // (bool success, ) = payable(address(this)).call{value: msg.value}("");
        // require(success, "ETH transfer failed");
    }

    function buyWithUSDT(uint256 usdtAmount, address referalAddress) external nonReentrant validReferral(referalAddress) {
        require(isBuyEnabled, "Purchasing is currently unavailable.");
        require(usdtAmount > 0, "Cannot send 0 USDT");
        uint256 ourAllowance = usdt.allowance(msg.sender,address(this));
        require(usdtAmount <= ourAllowance, "Make sure to add enough allowance");
        (bool success, ) = address(usdt).call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender,
                address(this),
                usdtAmount * (10**usdt.decimals())
            )
        );
        require(success, "USDT transfer failed");
        _handlePurchase(usdtAmount, usdtAmount, "USDT", referalAddress);
    }

    function calculateTokenWithBnus(uint256 usdAmount) public view returns (uint256 tokensToBuy, uint256 tokenBonus) {
        PresaleStage storage stage = presaleStages[activeStage];
        tokensToBuy = (usdAmount * ETH_MULTIPLIER) / stage.pricePerToken;
        tokenBonus = 0;
        if(stage.bonusPercentage > 0) {
            tokenBonus = (tokensToBuy * stage.bonusPercentage) / 100;
        }
        return  (tokensToBuy, tokenBonus);
    }


    function calculateTokenWithEth(uint256 ethAmount) external view returns (uint256 tokensToBuy, uint256 tokenBonus) {
        uint256 ethPriceUSD = getETHUSDPrice();
        uint256 usdAmount = (ethAmount * ethPriceUSD) / (ETH_MULTIPLIER * ETH_MULTIPLIER);
        return calculateTokenWithBnus(usdAmount);
    }

    function _handlePurchase(uint256 usdAmount, uint256 /*paymentAmount*/, string memory method, address referalAddress) internal {
        (uint256 tokensToBuy, uint256 tokenBonus) = calculateTokenWithBnus(usdAmount);
        PresaleStage storage stage = presaleStages[activeStage];
        uint256 tokenWithBonus = tokensToBuy+tokenBonus;

        if (tokensToBuy > stage.tokensToSell) {
            uint256 tokensFromCurrentStage = stage.tokensToSell;
            tokenBonus = (tokensFromCurrentStage * stage.bonusPercentage) / 100; // update bonus;
            // uint256 remainingTokens = tokensToBuy - tokensFromCurrentStage;
            uint256 remainingUSD = usdAmount - ((tokensFromCurrentStage * stage.pricePerToken) / ETH_MULTIPLIER);
            stage.tokensToSell = 0;
            stage.tokensSold = stage.tokensSold + tokensFromCurrentStage;
            stage.fundsRaised = stage.fundsRaised + ((tokensFromCurrentStage * stage.pricePerToken) / ETH_MULTIPLIER);
            stage.bonusGiven = stage.bonusGiven + tokenBonus;

            _activateNextStage();
            PresaleStage storage next = presaleStages[activeStage];

            uint256 tokensFromNextStage = (remainingUSD * ETH_MULTIPLIER) / next.pricePerToken;
            require(next.tokensToSell >= tokensFromNextStage, "Not enough tokens in next stage");

            next.tokensToSell =  next.tokensToSell - tokensFromNextStage;
            uint nexttokenBonus = (tokensFromNextStage * next.bonusPercentage) / 100; // update bonus;
            next.tokensSold = next.tokensSold + tokensFromNextStage;
            next.bonusGiven = next.bonusGiven + nexttokenBonus;
            next.fundsRaised = next.fundsRaised + remainingUSD;

            // final tokens to be given
            tokenWithBonus = (tokensFromCurrentStage + tokensFromNextStage  + tokenBonus + nexttokenBonus);
            tokensToBuy = (tokensFromCurrentStage + tokensFromNextStage);
        } else {
            stage.tokensToSell = stage.tokensToSell - tokensToBuy;
            stage.tokensSold = stage.tokensSold + tokensToBuy;
            stage.fundsRaised = stage.fundsRaised + usdAmount;
            stage.bonusGiven = stage.bonusGiven + tokenBonus;
            if(stage.tokensToSell <= 0) {
                if(nextStage < stageCount) {
                    _activateNextStage();
                }
            }
        }

        totalFundsRaised = totalFundsRaised + usdAmount;

        // update Stats
        userData[msg.sender].investedAmountUSD = userData[msg.sender].investedAmountUSD + usdAmount;
        userData[msg.sender].receivedTokenAmount = userData[msg.sender].receivedTokenAmount + tokenWithBonus;
        userData[msg.sender].didInvested = true;
        emit TokensPurchased(msg.sender, activeStage, usdAmount, tokenWithBonus, method);

        // check and generate reward for refferal user.
        if(referalAddress != address(0)) {
            uint256 rewardAmount =  _calculateRewards(usdAmount);
            if(rewardAmount > 0) {
                userData[referalAddress].referalRewardUSDAmount = userData[referalAddress].referalRewardUSDAmount + rewardAmount;
                emit RewardAdded(msg.sender, referalAddress, activeStage, usdAmount, tokensToBuy, rewardAmount);
            }
        }

        require(edm.transferAndVest(msg.sender, tokenWithBonus*ETH_MULTIPLIER), "Token transfer failed");
    }

    function claimUsdtRewards() external  {
        uint256 usdAmount = userData[msg.sender].referalRewardUSDAmount;
        require(usdAmount > 0, "No rewards found.");
        userData[msg.sender].referalRewardUSDAmount = 0;
        emit RewardClaimed(msg.sender, usdAmount, "USDT");
        (bool success, ) = address(usdt).call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                msg.sender,
                usdAmount* (10**usdt.decimals())
            )
        );
        require(success, "Claim failed");
        // require(usdt.transfer(msg.sender, usdAmount* (10**usdt.decimals())), "Claim failed");
    }

    function claimTokenRewards() external {
        uint256 usdAmount = userData[msg.sender].referalRewardUSDAmount;
        require(usdAmount > 0, "No rewards found.");
        PresaleStage storage stage = presaleStages[activeStage];
        uint256 tokensToReward = (usdAmount * ETH_MULTIPLIER) / stage.pricePerToken;
        userData[msg.sender].referalRewardUSDAmount = 0;
        emit RewardClaimed(msg.sender, tokensToReward, "EDM");
        require(edm.transferAndVest(msg.sender, tokensToReward*ETH_MULTIPLIER), "Token transfer failed");
    }

    function claimRewards() external {
        uint256 usdAmount = userData[msg.sender].referalRewardUSDAmount;
        require(usdAmount > 0, "No rewards found.");
        uint256 ethPriceUSD = getETHUSDPrice();
        uint256 ethAmount = (usdAmount * (ETH_MULTIPLIER * ETH_MULTIPLIER) ) / ethPriceUSD; 
        userData[msg.sender].referalRewardUSDAmount = 0;
        emit RewardClaimed(msg.sender, ethAmount, "ETH");
        payable(msg.sender).transfer(ethAmount);
    }

    function _calculateRewards(uint256 usdAmount) public view returns(uint256) {
        if (usdAmount >= rewardTiers["Platinum"].minAmount) {
            return (usdAmount * rewardTiers["Platinum"].percentage) / 100; // 10% reward for Platinum
        } else if (usdAmount >= rewardTiers["Gold"].minAmount) {
            return (usdAmount * rewardTiers["Gold"].percentage) / 100; // 7% reward for Gold
        } else if (usdAmount >= rewardTiers["Silver"].minAmount) {
            return (usdAmount * rewardTiers["Silver"].percentage) / 100; // 5% reward for Silver
        } else if (usdAmount >= rewardTiers["Bronze"].minAmount) {
            return (usdAmount * rewardTiers["Bronze"].percentage) / 100; // 3% reward for Bronze
        } else {
            return 0; // No reward for amounts less than $100
        }
    }

    function updateRewardTier(string memory tierName, uint256 minAmount, uint256 percentage) public onlyOwner {
        require(percentage > 0, "Percent must greater than zero");
        rewardTiers[tierName] = RewardTier({minAmount: minAmount, percentage: percentage});
    }

    function _activateNextStage() internal {
        require(nextStage < stageCount, "No more stages available");
        activeStage = nextStage;
        nextStage++;
        emit StageActivated(activeStage);
    }

    function getPreSaleStage(uint256 stageId) public view returns (PresaleStage memory stageDetails) {
        stageDetails = presaleStages[stageId];
        return stageDetails;
    }

    function getRewardTier(string memory tier) public view returns (RewardTier memory rewardTierDetails) {
        rewardTierDetails = rewardTiers[tier];
        return rewardTierDetails;
    }

    function getETHUSDPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid ETH price");
        return uint256(price) * 10 ** 10; // Scale to 18 decimals
    }

    function withdrawUSDT(uint256 amount, address fundReceiver) external onlyOwner {
        require(fundReceiver != address(0), "Address must not be 0");
        require(amount > 0, "Amount must not be 0");
        emit FundsWithdrawn(amount, "USDT");
        (bool success, ) = address(usdt).call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                msg.sender,
                amount
            )
        );
        require(success, "USDT Transfer failed");
        // usdt.transfer(fundReceiver, amount);
    }

    function withdrawEDM(uint256 amount, address fundReceiver) external onlyOwner {
        require(fundReceiver != address(0), "Address must not be 0");
        require(amount > 0, "Amount must not be 0");
        emit FundsWithdrawn(amount, "EDM");
        edm.transfer(fundReceiver, amount);
    }

    function withdrawEth(uint256 amount, address fundReceiver) external onlyOwner {
        require(fundReceiver != address(0), "Address must not be 0");
        require(amount > 0, "Amount must not be 0");
        emit FundsWithdrawn(amount, "ETH");
        payable(fundReceiver).transfer(amount);
    }

    function toggleBuyEnabled() external onlyOwner {
        isBuyEnabled = !isBuyEnabled;
    }

    
}