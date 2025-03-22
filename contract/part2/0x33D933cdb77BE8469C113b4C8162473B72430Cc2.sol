pragma solidity >=0.5.16;
pragma experimental ABIEncoderV2;

import "./EIP20Interface.sol";
import "./SafeMath.sol";

contract EsgSHIPV4Pro {
    using SafeMath for uint256;

    /// @notice ESG token
    EIP20Interface public esg;

    /// @notice Emitted when set invitee
    event SetInvitee(address referrerAddress, address inviteeAddress);

    /// @notice Emitted when ESG is staked  
    event EsgStaked(address account, uint amount);

    /// @notice Emitted when ESG is withdrawn 
    event EsgWithdrawn(address account, uint amount);

    /// @notice Emitted when ESG is claimed 
    event EsgClaimed(address account, uint amount);

    // @notice The rate every day. 
    uint256 public dayEsgRate1 = 18;
    uint256 public dayEsgRate2 = 20;
    uint256 public dayEsgRate3 = 28;

    uint256 public feeRate_claim = 15;
    uint256 public feeRate_withdraw = 30;
    uint256 public feeRate_invest = 30;

    address public feeWallet = 0x767477fD6fC874f9FcFc8cF5A4aA00ec24467a22;

    uint256 public referralThreshold = 500 * 1e18;

    // @notice A checkpoint for staking
    struct Checkpoint {
        uint256 deposit_time;
        uint256 total_staked;
        uint256 bonus_unclaimed;
    }

    // @notice staking struct of every account
    mapping (address => Checkpoint) public stakings;

    struct Referrer {
        address[] invitees;
    }
    mapping (address => Referrer) internal inviteeslist;

    struct User {
        address referrer_addr;
    }
    mapping (address => User) public referreraddr;

    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    // @notice total stake amount
    uint256 public total_deposited;
    uint256 public total_user;

    constructor(address esgAddress) public {
        owner = msg.sender;
        esg = EIP20Interface(esgAddress);
    }

    function setInvitee(address inviteeAddress) public returns (bool) {
        require(inviteeAddress != address(0), "inviteeAddress cannot be 0x0.");

        User storage user = referreraddr[inviteeAddress];
        require(user.referrer_addr == address(0), "This account had been invited!");
        
        Checkpoint storage cp = stakings[msg.sender];
        require(cp.total_staked >= referralThreshold, "Referrer has no referral qualification.");
        
        Checkpoint storage inviteeLocks = stakings[inviteeAddress];
        require(inviteeLocks.total_staked == 0, "This account had staked!");
        
        Referrer storage referrer = inviteeslist[msg.sender];
        require(referrer.invitees.length < 2, "You can only recommend a maximum of two people!");
        referrer.invitees.push(inviteeAddress);

        User storage _user = referreraddr[inviteeAddress];
        _user.referrer_addr = msg.sender;

        emit SetInvitee(msg.sender, inviteeAddress);
        return true;   
    }

    /**
     * @notice Stake ESG token to contract 
     * @param amount The amount of address to be staked 
     * @return Success indicator for whether staked 
     */
    function stake(uint256 amount) public returns (bool) {
        require(amount > 0, "No zero.");
        require(amount <= esg.balanceOf(msg.sender), "Insufficient ESG token.");

        Checkpoint storage cp = stakings[msg.sender];
        uint256 fee_amount = amount.mul(feeRate_invest).div(100);
        esg.transferFrom(msg.sender, feeWallet, fee_amount);
        esg.transferFrom(msg.sender, address(this), amount.sub(fee_amount));

        if(cp.deposit_time > 0)
        {
            uint256 dayEsgRate = getDayEsgRate(cp.total_staked);
            uint256 bonus = block.timestamp.sub(cp.deposit_time).mul(cp.total_staked).mul(dayEsgRate).div(10000).div(86400);
            cp.bonus_unclaimed = cp.bonus_unclaimed.add(bonus);
            cp.total_staked = cp.total_staked.add(amount);
            cp.deposit_time = block.timestamp;
        }else
        {
            cp.total_staked = amount;
            cp.deposit_time = block.timestamp;
            total_user = total_user + 1;
        }
        total_deposited = total_deposited.add(amount);
        emit EsgStaked(msg.sender, amount);

        return true;
    }

    /**
     * @notice withdraw ESG token staked in contract 
     * @return Success indicator for success 
     */
    function withdraw(uint256 amount) public returns (bool) {
        require(amount > 0, "Amount must be greater than 0");
        Checkpoint storage cp = stakings[msg.sender];
        require(cp.total_staked >= amount, "Amount can not greater than total_staked");
        uint256 dayEsgRate = getDayEsgRate(cp.total_staked);
        uint256 bonus = block.timestamp.sub(cp.deposit_time).mul(cp.total_staked).mul(dayEsgRate).div(10000).div(86400);
        cp.bonus_unclaimed = cp.bonus_unclaimed.add(bonus);
        if(cp.total_staked == amount){
            cp.total_staked = 0;
            cp.deposit_time = 0;
        }else{
            cp.total_staked = cp.total_staked.sub(amount);
            cp.deposit_time = block.timestamp;
        }
        
        total_deposited = total_deposited.sub(amount);
        uint256 fee_amount = amount.mul(feeRate_withdraw).div(100);
        esg.transfer(feeWallet, fee_amount);
        esg.transfer(msg.sender, amount.sub(fee_amount));

        emit EsgWithdrawn(msg.sender, amount); 

        return true;
    }

    /**
     * @notice claim all ESG token bonus in contract 
     * @return Success indicator for success 
     */
    function claim() public returns (bool) {
        Checkpoint storage cp = stakings[msg.sender];
        require(cp.total_staked > 0, "No staked!");
        uint256 amount = cp.bonus_unclaimed;
        uint256 dayEsgRate = getDayEsgRate(cp.total_staked);
        if(cp.deposit_time > 0)
        {
            uint256 bonus = block.timestamp.sub(cp.deposit_time).mul(cp.total_staked).mul(dayEsgRate).div(10000).div(86400);
            amount = amount.add(bonus);
            cp.bonus_unclaimed = 0; 
            cp.deposit_time = block.timestamp;  
        }else{
            //has beed withdrawn
            cp.bonus_unclaimed = 0;
        }
        uint256 fee_amount = amount.mul(feeRate_claim).div(100);
        esg.transfer(feeWallet, fee_amount);
        esg.transfer(msg.sender, amount.sub(fee_amount));
        emit EsgClaimed (msg.sender, amount); 

        return true;
    }

    function getDayEsgRate(uint256 stakeAmount) internal view returns(uint256) {
        uint256 dayEsgRate = 0;
        if(stakeAmount < 10000 * 1e18){
            dayEsgRate = dayEsgRate1;
        }else if(stakeAmount >= 10000 * 1e18 && stakeAmount < 50000 * 1e18){
            dayEsgRate = dayEsgRate2;
        }else{
            dayEsgRate = dayEsgRate3;
        }
        return dayEsgRate;
    }

    function getInviteelist(address referrerAddress) public view returns (address[] memory) {
        require(referrerAddress != address(0), "referrerAddress cannot be 0x0.");
        Referrer storage referrer = inviteeslist[referrerAddress];
        return referrer.invitees;
    }

    function getReferrer(address inviteeAddress) public view returns (address) {
        require(inviteeAddress != address(0), "inviteeAddress cannot be 0x0.");
        User storage user = referreraddr[inviteeAddress];
        return user.referrer_addr;
    }

    // set the dayrate
    function setDayEsgRate(uint256 dayRate1, uint256 dayRate2, uint256 dayRate3) onlyOwner public  {
        dayEsgRate1 = dayRate1;
        dayEsgRate2 = dayRate2;
        dayEsgRate3 = dayRate3;
    }

    // set the feerate
    function setFeeRate(uint256 claimRate, uint256 withdrawRate, uint256 investRate) onlyOwner public  {
        feeRate_claim = claimRate;
        feeRate_withdraw = withdrawRate;
        feeRate_invest = investRate;
    }

    // set the feewallet
    function setFeeWallet(address fee_wallet) onlyOwner public  {
        require(fee_wallet != address(0), "fee_wallet cannot be 0x0.");
        feeWallet = fee_wallet;
    }

    // set the referralThreshold
    function setReferralThreshold(uint256 _referralThreshold) onlyOwner public  {
        referralThreshold = _referralThreshold;
    }

    function changeUserStaked(address account, uint256 depositTime, uint256 totalStaked, uint256 bonusUnclaimed) onlyOwner public returns (bool) {
        require(account != address(0), "account cannot be 0x0.");
        Checkpoint storage cp = stakings[account];
        cp.deposit_time = depositTime;
        cp.total_staked = totalStaked;
        cp.bonus_unclaimed = bonusUnclaimed;
        return true;
    }

    function changeTotalNum(uint256 totalDeposited, uint256 totalUser) onlyOwner public returns (bool) {
        total_deposited = totalDeposited;
        total_user = totalUser;
        return true;
    }

    /**
     * @notice Returns the balance of ESG an account has staked
     * @param account The address of the account 
     * @return balance of ESG 
     */
    function getStakingBalance(address account) public view returns (uint256) {
        Checkpoint memory cp = stakings[account];
        return cp.total_staked;
    }

    /**
     * @notice Return the unclaimed bonus ESG of staking 
     * @param account The address of the account 
     * @return The amount of unclaimed ESG 
     */
    function getUnclaimedEsg(address account) public view returns (uint256) {
        Checkpoint memory cp = stakings[account];
        uint256 amount = cp.bonus_unclaimed;
        uint256 dayEsgRate = getDayEsgRate(cp.total_staked);
        if(cp.deposit_time > 0)
        {
            uint256 bonus = block.timestamp.sub(cp.deposit_time).mul(cp.total_staked).mul(dayEsgRate).div(10000).div(86400);
            amount = amount.add(bonus);
        }
        return amount;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner cannot be 0x0.");
        owner = newOwner;
    }
}