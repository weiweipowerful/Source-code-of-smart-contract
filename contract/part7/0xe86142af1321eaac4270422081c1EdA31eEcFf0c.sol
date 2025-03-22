// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../extensions/EmergencyWithdrawable.sol";

interface IStoneVault {
    function deposit() external payable returns (uint256 mintAmount);
    function requestWithdraw(uint256 _shares) external;
    function cancelWithdraw(uint256 _shares) external;
    function instantWithdraw(uint256 _amount, uint256 _shares) external returns (uint256 actualWithdrawn);
    function currentSharePrice() external returns (uint256 price);
    function roundPricePerShare(uint256 _round) external view returns (uint256 price);
    function withdrawFeeRate() external view returns (uint256 price);
    function latestRoundID() external view returns (uint256);
}

contract YayStoneToken is ERC20, AccessManaged, EmergencyWithdrawable {
    using Address for address payable;

    IStoneVault public stoneVault;
    IERC20 public stoneToken;
    uint256 public maxStakeLimit;

    struct UnstakeRequest {
        uint256 stoneAmount;
        uint256 round;
    }

    // Mapping to track each user's ETH balance that has been already request withdrawn on previous rounds
    mapping(address => uint256) public ethBalances;

    // Mapping to track each user's requested unstake amount with round
    mapping(address => UnstakeRequest) public requestedUnstakes;

    // Mapping to track each user's total staked ETH
    mapping(address => uint256) public totalStakedETH;

    // Mapping to track each user's total unstaked ETH
    mapping(address => uint256) public totalUnstakedETH;

    // Events
    event Staked(address indexed user, uint256 ethAmount, uint256 stoneAmount, uint256 round, string referralCode);
    event UnstakeRequested(address indexed user, uint256 stoneAmount, uint256 round);
    event Unstaked(address indexed user, uint256 withdrawnETHAmount, uint256 ethAmount, uint256 stoneAmount, uint256 round);
    event CancelUnstake(address indexed user, uint256 stoneAmount, uint256 round);
    event StoneTokensRedeemed(address indexed user, uint256 amount);
    event MaxStakeLimitUpdated(uint256 newLimit);

    /**
     * @dev Initializes the contract by setting the initial authority, token name, token symbol, StoneVault address, StoneToken address, and max stake limit.
     * @param initialAuthority The address of the AccessManager contract.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param stoneVaultAddress The address of the StoneVault contract.
     * @param stoneTokenAddress The address of the StoneToken contract.
     * @param _maxStakeLimit The maximum stake limit in ETH.
     */
    constructor(address initialAuthority, string memory _name, string memory _symbol, address stoneVaultAddress, address stoneTokenAddress, uint256 _maxStakeLimit) AccessManaged(initialAuthority) ERC20(_name, _symbol) {
        stoneVault = IStoneVault(stoneVaultAddress);
        stoneToken = IERC20(stoneTokenAddress);
        maxStakeLimit = _maxStakeLimit;
        approveStoneTokenSpending();
    }

    /**
     * @dev Approves the StoneVault to spend the maximum possible amount of StoneToken owned by this contract.
     */
    function approveStoneTokenSpending() public {
        uint256 amount = type(uint256).max;
        stoneToken.approve(address(stoneVault), amount);
    }

    /**
     * @dev Stake ETH directly and deposit equivalent ETH to StoneVault.
     * @param referralCode Referral code for tracking.
     */
    function stake(string memory referralCode) public payable {
        require(msg.value > 0, "YayStoneToken: Amount must be greater than 0");
        
        uint256 newTotalValue = estimatedTotalValueLockedInETH() + msg.value;
        require(newTotalValue <= maxStakeLimit, "YayStoneToken: Exceeds max stake limit");

        uint256 stoneAmount = stoneVault.deposit{value: msg.value}();
        _mint(_msgSender(), stoneAmount);
        totalStakedETH[_msgSender()] += msg.value;

        emit Staked(_msgSender(), msg.value, stoneAmount, getCurrentRound(), referralCode);
    }

    /**
     * @dev Request to unstake specified amount of Stone.
     * @param stoneAmount Amount of Stone to unstake.
     */
    function requestUnstake(uint256 stoneAmount) external restricted {
        require(balanceOf(_msgSender()) >= stoneAmount, "YayStoneToken: Insufficient YST balance");

        settleRequestedUnstakeIfNeeded(_msgSender());
        _burn(_msgSender(), stoneAmount);

        stoneVault.requestWithdraw(stoneAmount);
        
        uint256 newRequestedStoneAmount = requestedUnstakes[_msgSender()].stoneAmount + stoneAmount;
        requestedUnstakes[_msgSender()] = UnstakeRequest(newRequestedStoneAmount, getCurrentRound());

        emit UnstakeRequested(_msgSender(), stoneAmount, getCurrentRound());
    }

    /**
     * @dev Unstake specified amount of ETH instantly and receive ETH.
     * @param ethAmount Amount of ETH to unstake instantly.
     * @param stoneAmount Amount of Stone corresponding to the ETH amount.
     */
    function instantUnstake(uint256 ethAmount, uint256 stoneAmount) external {
        require(balanceOf(_msgSender()) >= stoneAmount, string.concat("YayStoneToken: Insufficient ", symbol(), " balance"));
        settleRequestedUnstakeIfNeeded(_msgSender());
        require(ethBalances[_msgSender()] >= ethAmount, "YayStoneToken: Insufficient ETH balance");

        _burn(_msgSender(), stoneAmount);
        ethBalances[_msgSender()] -= ethAmount;

        uint256 withdrawnETHAmount = stoneVault.instantWithdraw(ethAmount, stoneAmount);
        Address.sendValue(payable(_msgSender()), withdrawnETHAmount);
        totalUnstakedETH[_msgSender()] += withdrawnETHAmount;

        emit Unstaked(_msgSender(), withdrawnETHAmount, ethAmount, stoneAmount, getCurrentRound());
    }

    /**
     * @dev Cancel the unstake request for the specified amount of Stone.
     * @param stoneAmount Amount of Stone to cancel unstake.
     */
    function cancelUnstake(uint256 stoneAmount) external {
        settleRequestedUnstakeIfNeeded(_msgSender());
        require(requestedUnstakes[_msgSender()].stoneAmount >= stoneAmount, "YayStoneToken: Insufficient requested unstake amount");

        requestedUnstakes[_msgSender()].stoneAmount -= stoneAmount;
        stoneVault.cancelWithdraw(stoneAmount);
        _mint(_msgSender(), stoneAmount);

        emit CancelUnstake(_msgSender(), stoneAmount, getCurrentRound());
    }

    /**
     * @dev Settles requested unstakes into ETH balances if the round is completed.
     */
    function settleRequestedUnstakeIfNeeded(address user) public {
        UnstakeRequest storage request = requestedUnstakes[user];
        if (request.stoneAmount > 0 && isRoundCompleted(request.round)) {
            uint256 stonePrice = stoneVault.roundPricePerShare(request.round);
            uint256 ethAmount = (request.stoneAmount * stonePrice) / 1e18;
            ethBalances[user] += ethAmount;

            delete requestedUnstakes[user];
        }
    }

    /**
     * @dev Get the fee rate for unstaking from the StoneVault.
     * @return The fee rate for unstaking.
     */
    function unstakeFeeRate() external view returns (uint256) {
        return stoneVault.withdrawFeeRate();
    }

    /**
     * @dev Get the current round. Placeholder function, needs actual implementation.
     * @return Current round number.
     */
    function getCurrentRound() public view returns (uint256) {
        return stoneVault.latestRoundID();
    }

    /**
     * @dev Check if the round is completed.
     * @param round Round number to check.
     * @return True if the round is completed, false otherwise.
     */
    function isRoundCompleted(uint256 round) public view returns (bool) {
        return stoneVault.latestRoundID() > round;
    }

    /**
     * @dev Get the current price per stone from the StoneVault.
     * @return The current price per stone.
     */
    function getCurrentPricePerStone() external returns (uint256) {
        return stoneVault.currentSharePrice();
    }

    /**
     * @dev Get the historical price per stone for a given round from the StoneVault.
     * @param round The round number to fetch the price for.
     * @return The price per stone for the given round.
     */
    function getHistoricalPricePerStone(uint256 round) public view returns (uint256) {
        return stoneVault.roundPricePerShare(round);
    }

    /**
     * @dev Get the value in ETH of a user's Stone tokens.
     * @param user The address of the user.
     * @return The value in ETH of the user's Stone tokens.
     */
    function estimatedUserStoneValueInETH(address user) public returns (uint256) {
        uint256 userStoneBalance = balanceOf(user);
        uint256 stonePrice = stoneVault.currentSharePrice();
        return (userStoneBalance * stonePrice) / 1e18;
    }

    /**
     * @dev Get the total value locked in the contract.
     * @return Total value locked in the contract in ETH.
     */
    function estimatedTotalValueLockedInETH() public returns (uint256) {
        uint256 totalStoneBalance = stoneToken.balanceOf(address(this));
        uint256 stonePrice = stoneVault.currentSharePrice();
        return (totalStoneBalance * stonePrice) / 1e18;
    }

    /**
     * @dev Enables the redemption of Stone tokens using YayStone.
     * @param amount The amount of Stone tokens to redeem.
     */
    function redeemStoneTokens(uint256 amount) external restricted {
        require(amount > 0, "YayStoneToken: Amount must be greater than zero");
        uint256 yayStoneBalance = balanceOf(_msgSender());
        require(yayStoneBalance >= amount, "YayStoneToken: Insufficient YayStone balance");

        _burn(_msgSender(), amount);
        stoneToken.transfer(_msgSender(), amount);

        emit StoneTokensRedeemed(_msgSender(), amount);
    }

    /**
     * @dev Sets the maximum total value that can be staked in ETH.
     * @param newLimit The new maximum stake limit in ETH.
     */
    function setMaxStakeLimit(uint256 newLimit) external restricted {
        maxStakeLimit = newLimit;
        emit MaxStakeLimitUpdated(newLimit);
    }

    /**
     * @dev Emergency withdraw token function that excludes StoneToken and requires access control.
     * @param beneficiary The address to send the tokens to.
     * @param token The address of the token to withdraw.
     */
    function emergencyWithdrawToken(address beneficiary, address token) external restricted {
        require(token != address(stoneToken), "YayStoneToken: Cannot withdraw StoneToken");
        _emergencyWithdrawToken(beneficiary, token);
    }

    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {
    }
}