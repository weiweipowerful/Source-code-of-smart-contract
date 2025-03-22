// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./StakingProxyBase.sol";
import "../interfaces/IFxnGauge.sol";
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

/*
Vault implementation for basic erc20 tokens
*/
contract StakingProxyERC20 is StakingProxyBase, ReentrancyGuard{
    using SafeERC20 for IERC20;

    constructor(address _poolRegistry, address _feeRegistry, address _fxnminter) 
        StakingProxyBase(_poolRegistry, _feeRegistry, _fxnminter){
    }

    //vault type
    function vaultType() external pure override returns(VaultType){
        return VaultType.Erc20Basic;
    }

    //vault version
    function vaultVersion() external pure override returns(uint256){
        return 1;
    }

    //initialize vault
    function initialize(address _owner, uint256 _pid) public override{
        super.initialize(_owner, _pid);

        //set infinite approval
        IERC20(stakingToken).approve(gaugeAddress, type(uint256).max);

        //set extra rewards to send directly back to owner
        //..could technically save gas on initialize() by using claim(address,address) but
        //since claim is unguarded would be better UX to set receiver in case called by some other address
        IFxnGauge(gaugeAddress).setRewardReceiver(_owner);
    }


    //deposit into gauge
    function deposit(uint256 _amount) external onlyOwner nonReentrant{
        if(_amount > 0){
            //pull tokens from user
            address _stakingToken = stakingToken;
            IERC20(_stakingToken).safeTransferFrom(msg.sender, address(this), _amount);

            //stake (use balanceof in case of change during transfer)
            IFxnGauge(gaugeAddress).deposit(IERC20(_stakingToken).balanceOf(address(this)));
        }
        
        //checkpoint rewards
        _checkpointRewards();
    }

    //deposit into gauge with manage flag
    function deposit(uint256 _amount, bool _manage) external onlyOwner nonReentrant{
        if(_amount > 0){
            //pull tokens from user
            address _stakingToken = stakingToken;
            IERC20(_stakingToken).safeTransferFrom(msg.sender, address(this), _amount);

            //stake (use balanceof in case of change during transfer)
            IFxnGauge(gaugeAddress).deposit(IERC20(_stakingToken).balanceOf(address(this)), address(this), _manage);
        }
        
        //checkpoint rewards
        _checkpointRewards();
    }


    //withdraw a staked position
    function withdraw(uint256 _amount) external onlyOwner nonReentrant{

        //withdraw to vault
        IFxnGauge(gaugeAddress).withdraw(_amount);

        //checkpoint rewards
        _checkpointRewards();

        //send back to owner any staking tokens on the vault (may differ from _amount)
        address _stakingToken = stakingToken;
        IERC20(_stakingToken).safeTransfer(msg.sender, IERC20(_stakingToken).balanceOf(address(this)));
    }


    //return earned tokens on staking contract and any tokens that are on this vault
    function earned() external override returns (address[] memory token_addresses, uint256[] memory total_earned) {
        //get list of reward tokens
        address[] memory rewardTokens = IFxnGauge(gaugeAddress).getActiveRewardTokens();

        //create array of rewards on gauge, rewards on extra reward contract, and fxn that is minted
        address _rewards = rewards;
        token_addresses = new address[](rewardTokens.length + IRewards(_rewards).rewardTokenLength() + 1);// +1 for fxn
        total_earned = new uint256[](rewardTokens.length + IRewards(_rewards).rewardTokenLength() + 1); // +1 for fxn

        //simulate claiming

        //mint fxn
        try IFxnTokenMinter(fxnMinter).mint(gaugeAddress){}catch{}
        
        //check fxn
        token_addresses[0] = fxn;
        //remove fee (assumes all fxn on vault came from minting)
        total_earned[0] = IERC20(fxn).balanceOf(address(this)) * (FEE_DENOMINATOR - IFeeRegistry(feeRegistry).totalFees()) / FEE_DENOMINATOR;

        //claim other rewards on gauge to this address to tally
        IFxnGauge(gaugeAddress).claim(address(this),address(this));

        //get balance of tokens
        for(uint256 i = 0; i < rewardTokens.length; i++){
            token_addresses[i+1] = rewardTokens[i];
            if(rewardTokens[i] == fxn){
                //if more fxn was distributed as an extra reward, add difference of current-minted
                total_earned[i+1] = IERC20(rewardTokens[i]).balanceOf(address(this)) - total_earned[0];
            }else{
                total_earned[i+1] = IERC20(rewardTokens[i]).balanceOf(address(this));
            }
        }

        //also add an extra rewards from convex's side
        IRewards.EarnedData[] memory extraRewards = IRewards(_rewards).claimableRewards(address(this));
        for(uint256 i = 0; i < extraRewards.length; i++){
            token_addresses[i+rewardTokens.length+1] = extraRewards[i].token;
            total_earned[i+rewardTokens.length+1] = extraRewards[i].amount;
        }
    }

    /*
    claim flow:
        mint fxn rewards directly to vault
        claim extra rewards directly to the owner
        calculate fees on fxn
        distribute fxn between owner and fee deposit
    */
    function getReward() external override{
        getReward(true);
    }

    //get reward with claim option.
    function getReward(bool _claim) public override{

        //claim
        if(_claim){
            //fxn rewards (claim here first then send to user after fees)
            try IFxnTokenMinter(fxnMinter).mint(gaugeAddress){}catch{}

            //extras (will get claimed directly to owner)
            IFxnGauge(gaugeAddress).claim();
        }

        //process fxn fees
        _processFxn();

        //extra rewards
        _processExtraRewards();
    }

    //get reward with claim option, as well as a specific token list to claim from convex extra rewards
    function getReward(bool _claim, address[] calldata _tokenList) external override{

        //claim
        if(_claim){
            //fxn rewards
            try IFxnTokenMinter(fxnMinter).mint(gaugeAddress){}catch{}

            //extras
            IFxnGauge(gaugeAddress).claim();
        }

        //process fxn fees
        _processFxn();

        //extra rewards
        _processExtraRewardsFilter(_tokenList);
    }

    //return any tokens in vault back to owner
    function transferTokens(address[] calldata _tokenList) external onlyOwner{
        //transfer tokens back to owner
        //fxn and gauge tokens are skipped
        _transferTokens(_tokenList);
    }

}