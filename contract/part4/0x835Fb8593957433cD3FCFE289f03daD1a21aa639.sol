// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '../lib/openzeppelin-contracts/contracts/access/Ownable.sol';
import '../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import '../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol';
import '../lib/openzeppelin-contracts/contracts/utils/Pausable.sol';
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import './interfaces/IAggregator.sol';
import './interfaces/IStaking.sol';

contract Presale is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    address public tokenAddress;
    address public usdtAddress;
    address public usdcAddress;
    IAggregator public aggregatorContract;
    address public stakingContract;
    address public paymentWallet;
    uint256 public maxTotalSellingAmount;
    uint256 public totalTokensSold;
    uint256 usdLimitPhase0;
    uint256 usdLimitPhase1;
    bool public claimStarted;

    uint256 public currentPhase;
    uint256[][3] public phases;
    uint256 public usdRaised;
    uint256 public totalUsers;

    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public hasClaimed;
    mapping(address => uint256) public userTokenBalance;
    mapping(address => bool) public hasBought;

    struct PhaseData {
    uint256 currentPhase;
    uint256 phaseMaxTokens;
    uint256 phasePrice;
    uint256 phaseEndTime;
    }

    event TokensBought(address indexed user, uint256 indexed tokensBought, uint256 usdRaised, uint256 timestamp);
    event TokensBoughtAndStaked(address indexed user, uint256 indexed tokensBought, uint256 usdRaised, uint256 timestamp);
    event TokensClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event TokensClaimedAndStaked(address indexed user, uint256 amount, uint256 timestamp);
    event NewPhase(uint256 indexed phase, uint256 phaseMaxTokens, uint256 phasePrice, uint256 phaseEndTime);

    constructor(
        address tokenAddress_,
        address usdtAddress_,
        address usdcAddress_,
        address aggregatorContract_,
        address stakingContract_,
        address paymentWallet_,
        address ownerWallet_,
        uint256[][3] memory phases_,
        uint256 maxTotalSellingAmount_,
        uint256 usdLimitPhase0_,
        uint256 usdLimitPhase1_
    ) Ownable(ownerWallet_) {
        tokenAddress = tokenAddress_;
        usdtAddress = usdtAddress_;
        usdcAddress = usdcAddress_;
        aggregatorContract = IAggregator(aggregatorContract_);
        stakingContract = stakingContract_;
        paymentWallet = paymentWallet_;
        phases = phases_;
        maxTotalSellingAmount = maxTotalSellingAmount_;
        usdLimitPhase0 = usdLimitPhase0_;
        usdLimitPhase1 = usdLimitPhase1_;

        _pause();
    }

    /**
    * @dev To set the token address
    * @param tokenAddress_ Token address
    */
    function setToken(address tokenAddress_) external onlyOwner {
        tokenAddress = tokenAddress_;
    }

    /**
    * @dev usdLimitPhase records cumulative prices
    */
    function checkIfEnoughTokens(uint256 usdAmount) internal view {
        if (currentPhase == 0) if (usdRaised + usdAmount > usdLimitPhase0) revert("Phase 0 completed");
        else if (currentPhase == 1) if (usdRaised + usdAmount > usdLimitPhase1) revert("Phase 1 completed");
    }

    /**
    * @dev To calculate the current phase.
    * @param amount_ Number of tokens
    */
    function _checkCurrentPhase(uint256 amount_) private view returns (uint256 phase) {
        if ((totalTokensSold + amount_ >= phases[currentPhase][0] || (block.timestamp >= phases[currentPhase][2])) && currentPhase < 2) {
            phase = currentPhase + 1;
        } else {
            phase = currentPhase;
        }
    }

    /**
    * @dev To calculate and update the current phase.
    * @param amount_ Number of tokens
    */
    function _checkAndUpdateCurrentPhase(uint256 amount_) private returns (uint256 phase) {
        if ((totalTokensSold + amount_ >= phases[currentPhase][0] || (block.timestamp >= phases[currentPhase][2])) && currentPhase < 2) {
            currentPhase++;
            phase = currentPhase;
            emit NewPhase(phase, phases[phase][0], phases[phase][1], phases[phase][2]);
        } else {
            phase = currentPhase;
        }
    }

    /**
    * @dev To get latest ETH price in 10**18 format
    */
    function getLatestPrice() public view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = aggregatorContract.latestRoundData();
        if (updatedAt < block.timestamp - 2 hours) revert("Chainlink data is too old");
        price = (price * (10 ** 10));
        return uint256(price);
    }

    /**
    * @dev To buy into a presale using USDT
    * @param amount_ Number of tokens to pay
    */
    function buyWithStable(address paymentToken_, uint256 amount_, bool stake_) external whenNotPaused nonReentrant {
        require(!isBlacklisted[msg.sender], 'This Address is Blacklisted');
        require(amount_ > 0, 'Amount can not be zero');
        require(paymentToken_ == usdtAddress || paymentToken_ == usdcAddress, "Token not supported");

        if (!hasBought[msg.sender]) {
            totalUsers++;
            hasBought[msg.sender] = true;
        }
        
        uint256 scalatedAmount;
        if (ERC20(paymentToken_).decimals() == 18) scalatedAmount = amount_;
        else scalatedAmount = amount_ * 10**(18 - ERC20(paymentToken_).decimals());
        checkIfEnoughTokens(scalatedAmount);
        uint256 tokenAmountToReceive;

        if (ERC20(paymentToken_).decimals() == 18) tokenAmountToReceive = amount_ * 1e6 / phases[currentPhase][1];
        else tokenAmountToReceive = amount_ * 10**(18 - ERC20(paymentToken_).decimals()) * 1e6 / phases[currentPhase][1];

        _checkAndUpdateCurrentPhase(tokenAmountToReceive); 
        if (ERC20(paymentToken_).decimals() == 18) usdRaised += amount_;
        else usdRaised += amount_ * 10**(18 -ERC20(paymentToken_).decimals());
        totalTokensSold += tokenAmountToReceive;
       
        require(totalTokensSold <= maxTotalSellingAmount, "Sold out");

        IERC20(paymentToken_).safeTransferFrom(msg.sender, paymentWallet, amount_);

        if (stake_) { 
            IERC20(tokenAddress).approve(address(stakingContract), tokenAmountToReceive);
            IStaking(stakingContract).depositByPresale(msg.sender, tokenAmountToReceive);
            emit TokensBoughtAndStaked(msg.sender, tokenAmountToReceive, usdRaised, block.timestamp);
        } else {
            userTokenBalance[msg.sender] += tokenAmountToReceive;
            emit TokensBought(msg.sender, tokenAmountToReceive, usdRaised, block.timestamp);
        }
    }

    /**
    * @dev To buy into a presale using ETH
    */
    function buyWithETH(bool stake_) external payable whenNotPaused nonReentrant {
        require(!isBlacklisted[msg.sender], 'This Address is Blacklisted');
        require(msg.value > 0, 'Amount can not be zero');

        if (!hasBought[msg.sender]) {
            totalUsers++;
            hasBought[msg.sender] = true;
        }

        uint256 usdAmount = msg.value * getLatestPrice() / 1e18; 
        checkIfEnoughTokens(usdAmount);
        uint256 tokenAmountToReceive = usdAmount * 1e6 / phases[currentPhase][1]; 
        _checkAndUpdateCurrentPhase(tokenAmountToReceive);  

        usdRaised += usdAmount;
        totalTokensSold += tokenAmountToReceive;

        require(totalTokensSold <= maxTotalSellingAmount, "Sold out");

        (bool success, ) = paymentWallet.call{value: msg.value}('');
        require(success, 'Transfer fail.');

        if (stake_) { 
            IERC20(tokenAddress).approve(address(stakingContract), tokenAmountToReceive);
            IStaking(stakingContract).depositByPresale(msg.sender, tokenAmountToReceive);
            emit TokensBoughtAndStaked(msg.sender, tokenAmountToReceive, usdRaised, block.timestamp);
        } else {
            userTokenBalance[msg.sender] += tokenAmountToReceive;
            emit TokensBought(msg.sender, tokenAmountToReceive, usdRaised, block.timestamp);
        }

        emit TokensBought(msg.sender, tokenAmountToReceive, usdAmount, block.timestamp);
    }

    /**
    * @dev To buy into a presale using ETH
    */
    function buyWithFiat(address userAddress_) external payable whenNotPaused nonReentrant {
        require(!isBlacklisted[userAddress_], 'This Address is Blacklisted');
        require(msg.value > 0, 'Amount can not be zero');

        if (!hasBought[userAddress_]) {
        totalUsers++;
        hasBought[userAddress_] = true;
        }
        
        uint256 usdAmount = msg.value * getLatestPrice() / 1e18; 
        checkIfEnoughTokens(usdAmount);
        uint256 tokenAmountToReceive = usdAmount * 1e6 / phases[currentPhase][1]; 
        _checkAndUpdateCurrentPhase(tokenAmountToReceive);  

        usdRaised += usdAmount;
        totalTokensSold += tokenAmountToReceive;

        require(totalTokensSold <= maxTotalSellingAmount, "Sold out");

        userTokenBalance[userAddress_] += tokenAmountToReceive;

        (bool success, ) = paymentWallet.call{value: msg.value}('');
        require(success, 'Transfer fail.');

        emit TokensBought(userAddress_, tokenAmountToReceive, usdAmount, block.timestamp);
    }

    /**
    * @dev To blacklist a user
    * @param user_ User address
    * @param amount_ amount of assigned tokens
    */
    function increaseUserBalance(address user_, uint256 amount_) external onlyOwner {
        if (!hasBought[user_]) {
            totalUsers++;
            hasBought[user_] = true;
        }

        uint256 usdAmount = amount_ * phases[currentPhase][1] / 1e6;
        checkIfEnoughTokens(usdAmount);
        _checkAndUpdateCurrentPhase(amount_);
        usdRaised += usdAmount;
        totalTokensSold += amount_;
        userTokenBalance[user_] += amount_;

        require(totalTokensSold <= maxTotalSellingAmount, "Sold out");

        emit TokensBought(user_, amount_, usdAmount, block.timestamp);
    }

    /**
    * @dev To stake tokens after buy
    */
    function stakePostBuy() external whenNotPaused() nonReentrant() {
        require(!isBlacklisted[msg.sender], 'This Address is Blacklisted');
        require(userTokenBalance[msg.sender] > 0, 'Nothing to stake');

        uint256 amount_ = userTokenBalance[msg.sender];

        delete userTokenBalance[msg.sender];

        IERC20(tokenAddress).approve(address(stakingContract), amount_);
        IStaking(stakingContract).depositByPresale(msg.sender, amount_);
        emit TokensClaimedAndStaked(msg.sender, amount_, block.timestamp);
    }

    /**
    * @dev To claim tokens after claiming starts
    */
    function claim(bool stake_) external nonReentrant {
        require(!isBlacklisted[msg.sender], 'This Address is Blacklisted');
        require(claimStarted, 'Claim has not started yet');
        require(!hasClaimed[msg.sender], 'Already claimed');

        hasClaimed[msg.sender] = true;
        uint256 amount_ = userTokenBalance[msg.sender];
        require(amount_ > 0, 'Nothing to claim');

        delete userTokenBalance[msg.sender];
        if (stake_) {
            IERC20(tokenAddress).approve(address(stakingContract), amount_);
            IStaking(stakingContract).depositByPresale(msg.sender, amount_);
            emit TokensClaimedAndStaked(msg.sender, amount_, block.timestamp);
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, amount_);
            emit TokensClaimed(msg.sender, amount_, block.timestamp);
        }
    }

    /**
    * @dev To start claiming
    */
    function startClaim(bool claimStarted_) external onlyOwner {
        claimStarted = claimStarted_;
    }
  
    /**
    * @dev To blacklist a user
    * @param user_ User address
    */
    function blacklistUser(address user_) external onlyOwner {
        require(user_ != address(0), 'Invalid address');

        isBlacklisted[user_] = true;
    }

    /**
    * @dev To remove a user from the blacklist
    * @param user_ User address
    */
    function removeFromBlacklist(address user_) external onlyOwner {
        require(user_ != address(0), 'Invalid address');

        isBlacklisted[user_] = false;
    }

    /**
    * @dev Each phase amount contains the cumulative amount from older phases
    */
    function checkPhaseLeftTokens(uint256 phase) public view returns(uint256 tokensLeft) {
        if (phase == 0) {
            if (totalTokensSold >= phases[0][0]) tokensLeft = 0;
            else tokensLeft = phases[0][0] - totalTokensSold;
        } else if (phase == 1) {
            if (totalTokensSold >= phases[1][0]) tokensLeft = 0;
            else tokensLeft = phases[1][0] - totalTokensSold;
        } else {
            if (totalTokensSold >= phases[2][0]) tokensLeft = 0;
            else tokensLeft = phases[2][0] - totalTokensSold;
        }
    }

    /**
    * @dev To get the number of tokens for a given amount in USDT.
    * @param usdtAmount_ Amount in USDT
    */
    function getTokensFromUSDT(uint256 usdtAmount_) public view returns (uint256 tokensAmount) {
        if (ERC20(usdtAddress).decimals() == 18) tokensAmount = usdtAmount_ * 1e6 / phases[currentPhase][1];
        else tokensAmount = usdtAmount_ * 10**(18 -ERC20(usdtAddress).decimals()) * 1e6 / phases[currentPhase][1];
    }

    /**
    * @dev To get the number of tokens for a given amount in USDT.
    * @param usdcAmount_ Amount in USDC
    */
    function getTokensFromUSDC(uint256 usdcAmount_) public view returns (uint256 tokensAmount) {
        if (ERC20(usdcAddress).decimals() == 18) tokensAmount = usdcAmount_ * 1e6 / phases[currentPhase][1];
        else tokensAmount = usdcAmount_ * 10**(18 -ERC20(usdcAddress).decimals()) * 1e6 / phases[currentPhase][1];
    }

    /**
    * @dev To get the number of tokens for a given amount in ETH.
    * @param ethAmount_ Amount in ETH
    */
    function getTokensFromETH(uint256 ethAmount_) public view returns (uint256 tokensAmount) {
        uint256 usdAmount = ethAmount_ * getLatestPrice() / 1e18;
        tokensAmount = usdAmount * 1e6 / phases[currentPhase][1]; 
    }

    /**
    * @dev To get the current phase data.
    */
    function getCurrentPhaseData() public view returns (PhaseData memory) {
        PhaseData memory currentPhaseData;
        uint256 currentPhase_ = _checkCurrentPhase(0);
        currentPhaseData.currentPhase = currentPhase_;
        currentPhaseData.phaseMaxTokens = phases[currentPhase_][0];
        currentPhaseData.phasePrice = phases[currentPhase_][1];
        currentPhaseData.phaseEndTime = phases[currentPhase_][2];

        return currentPhaseData;
    }

    /**
    * @dev To update the phases
    */
    function changePhases(uint256[][3] memory phases_) external onlyOwner {
        phases = phases_;
    }

    /**
    * @dev To update a single phase
    */
    function updatePhase(uint256 phaseIndex_, uint256 phaseMaxTokens_, uint256 phasePrice_, uint256 phaseEndTime_) external onlyOwner {
        phases[phaseIndex_][0] = phaseMaxTokens_;
        phases[phaseIndex_][1] = phasePrice_;
        phases[phaseIndex_][2] = phaseEndTime_;
    }

    /**
    * @dev To update the maxTotalSellingAmount
    */
    function updatemaxTotalSellingAmount(uint256 maxTotalSellingAmount_) external onlyOwner {
        maxTotalSellingAmount = maxTotalSellingAmount_;
    }

    /**
    * @dev To update the paymentWallet
    * @param paymentWallet_ New paymentWallet address
    */
    function updatePaymentWallet(address paymentWallet_) external onlyOwner {
        paymentWallet = paymentWallet_;
    }


    /**
    * @dev To withdraw the contract balance in emergency case of any token
    * @param tokenToWithdraw_ address of the token to withdraw
    * @param receiverAddress_ address to receive tokens
    */
    function emergencyWithdraw(address tokenToWithdraw_, address receiverAddress_) external onlyOwner {
        uint256 contractBalance = IERC20(tokenToWithdraw_).balanceOf(address(this));

        IERC20(tokenToWithdraw_).safeTransfer(receiverAddress_, contractBalance);
    }

    /**
    * @dev To withdraw the contract balance in emergency case of any token
    * @param tokenToWithdraw_ address of the token to withdraw
    * @param receiverAddress_ address to receive tokens
    */
  function customWithdraw(address tokenToWithdraw_, address receiverAddress_, uint256 amount_) external onlyOwner {
    IERC20(tokenToWithdraw_).safeTransfer(receiverAddress_, amount_);
  }

    /**
    * @dev To withdraw the contract balance in emergency case of ether
    * @param receiverAddress_ address to receive tokens
    */
    function emergencyEthWithdraw(address receiverAddress_) external onlyOwner {
        uint256 contractBalance = address(this).balance;

        (bool success, ) = receiverAddress_.call{value: contractBalance}("");
        require(success, "Transfer failed");
    }

    /**
    * @dev To update the current phase
    * @param newCurrentPhase_ new phase
    */
    function setCurrentPhase(uint256 newCurrentPhase_) external onlyOwner {
        currentPhase = newCurrentPhase_;
    }

    function setUsdLimitPhase0(uint256 newLimit_) external onlyOwner {
        usdLimitPhase0 = newLimit_;
    }

    function setUsdLimitPhase1(uint256 newLimit_) external onlyOwner {
        usdLimitPhase1 = newLimit_;
    }

    function setHasClaimed(bool hasClaimed_, address user_) external onlyOwner {
        hasClaimed[user_] = hasClaimed_;
    }

    function setStaking(address stakingAddress_) external onlyOwner {
        stakingContract = stakingAddress_;
    }

    /**
    * @dev To pause the presale
    */
    function pausePresale() public onlyOwner {
        _pause();
    }

    /**
    * @dev To unpause the presale
    */
    function unpausePresale() public onlyOwner {
        _unpause();
    }

    receive() external payable {
        (bool success, ) = paymentWallet.call{value: msg.value}('');
        require(success, 'Transfer fail.');
    }
}