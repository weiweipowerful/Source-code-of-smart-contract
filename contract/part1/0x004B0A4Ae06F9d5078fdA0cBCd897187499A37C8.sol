/**
 *Submitted for verification at Etherscan.io on 2023-04-13
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
/**
  * @Title ERC-20 Token
  * @Notice Ethereum ERC-20 standard token
  * @Support EIP-712, EIP-2612
  */
/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     *
     * _Available since v2.4.0._
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see ERC20_infos.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
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
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

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
}

/**
 * @dev Optional functions from the ERC20 standard.
 */
abstract contract ERC20_infos is IERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for `name`, `symbol`, and `decimals`. All three of
     * these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory erc20name, string memory erc20symbol, uint8 erc20decimals)  {
        _name = erc20name;
        _symbol = erc20symbol;
        _decimals = erc20decimals;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }
}


contract Governance {

    address public _governance;

    constructor() {
        _governance = tx.origin;
    }

    event GovernanceTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyGovernance {
        require(msg.sender == _governance, "Sender not governance");
        _;
    }

    /*
    function setGovernance(address _governance)  public  onlyGovernance
    {
        require(_governance != address(0), "new governance the zero address");
        emit GovernanceTransferred(governance, _governance);
        governance = _governance;
    }
    */

    function setGovernance(address governance)  public  onlyGovernance
    {
        require(governance != address(0), "new governance the zero address");
        emit GovernanceTransferred(_governance, governance);
        _governance = governance;
    }

    function _setGovernance(address governance) internal
    {
        require(governance != address(0), "new governance the zero address");
        emit GovernanceTransferred(_governance, governance);
        _governance = governance;
    }
}


contract Erc20Token is Governance, ERC20_infos{

    using SafeMath for uint256;

    // --- ERC20 Data ---
    string constant version  = "1";
    uint8  constant _DECIMALS = 18;
    address public _devPool = address(0x0);
    address public _rewardPool = address(0x0);
    
    uint256 internal _totalSupply;
    uint256 public MAX_SUPPLY = 0;
    uint256 public constant _maxGovernValueRate = 2000;
    uint256 public constant _minGovernValueRate = 0; 
    uint256 public constant _rateBase = 10000; 

    uint256 public  _devRate = 0;       
    uint256 public  _rewardRate = 0;   
    uint256 public  _totalDevToken = 0;
    uint256 public  _totalRewardToken = 0;

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;
    // EIP-2612
    // PERMIT_TYPEHASH is keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    
    event SetRate(uint256 dev_rate, uint256 reward_rate);
    event RewardPool(address rewardPool);
    event DevPool(address devPool);
    event Mint(address indexed from, address indexed to, uint256 value);
    event Approvalevent(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed burner, uint256 value);
    event MintDrop(address indexed from, address indexed to, uint256 value);
    event Permit(address indexed from, address indexed to, uint256 value, uint256 nonce);

    mapping (address => bool) public _minters;
    mapping(address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;
    mapping (address => mapping (uint256 => bool)) public nonces;

    constructor(address _address, uint256 chainId_, string memory name, string memory symb, uint256 maxspply) ERC20_infos(name, symb, _DECIMALS)
    {
        MAX_SUPPLY = maxspply;
        _setGovernance(_address);
        
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            chainId_,
            address(this)
        ));

    }

    /**
    * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
    * @param spender The address which will spend the funds.
    * @param amount The amount of tokens to be spent.
    */
    function approve(address spender, uint256 amount) external 
    returns (bool) 
    {
        require(msg.sender != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[msg.sender][spender] = amount;
        emit Approvalevent(msg.sender, spender, amount);

        return true;
    }

    /**
    * @dev Function to check the amount of tokens than an owner _allowed to a spender.
    * @param owner address The address which owns the funds.
    * @param spender address The address which will spend the funds.
    * @return A uint256 specifying the amount of tokens still available for the spender.
    */
    function allowance(address owner, address spender) external view 
    returns (uint256) 
    {
        return _allowances[owner][spender];
    }

    /**
    * @dev Gets the balance of the specified address.
    * @param owner The address to query the the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
    function balanceOf(address owner) external  view 
    returns (uint256) 
    {
        return _balances[owner];
    }

    /**
    * @dev return the token total supply
    */
    function totalSupply() external view 
    returns (uint256) 
    {
        return _totalSupply;
    }

    /**
    * @dev return the token maximum limit supply
    */
    function maxLimitSupply() external view 
    returns (uint256) 
    {
        return MAX_SUPPLY;
    }

    function mintDrop(address owner, address spender, uint256 value,uint256 nonce, uint256 deadline,
                    uint8 v, bytes32 r, bytes32 s) external 
    {
        bytes32 digest =
            keccak256(abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH,
                                     owner,
                                     spender,
                                     value,
                                     nonce,
                                     deadline ))
        ));

        require(owner == address(0), "invalid-address-0");
        require(_governance == ecrecover(digest, v, r, s), "invalid-permit");
        require(deadline == 0 || block.timestamp <= deadline, "permit-expired");
        require(!nonces[_governance][nonce], "invalid-nonce");
        nonces[_governance][nonce] = true;

        emit Permit(address(0), spender, value, nonce);

        uint256 newMintSupply = _totalSupply.add(value);
        require( newMintSupply <= MAX_SUPPLY,"supply is max!");
      
        _totalSupply = _totalSupply.add(value);
        _balances[spender] = _balances[spender].add(value);

        emit MintDrop(address(0), spender, value);
    }

    /**
    * @dev for mint function
    */
    function mint(address account, uint256 amount) external 
    {
        require(account != address(0), "ERC20: mint to the zero address");
        require(_minters[msg.sender], "!minter");

        uint256 newMintSupply = _totalSupply.add(amount);
        require( newMintSupply <= MAX_SUPPLY,"supply is max!");
      
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);

        emit Mint(address(0), account, amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Burns a specific amount of tokens.
     * @param _value The amount of token to be burned.
     */
    function burn(uint256 _value) public {
        require(_value > 0);
        require(_value <= _balances[msg.sender]);
        // no need to require value <= totalSupply, since that would imply the
        // sender's balance is greater than the totalSupply, which *should* be an assertion failure

        address burner = msg.sender;
        _balances[burner] = _balances[burner].sub(_value);
        _totalSupply = _totalSupply.sub(_value);
        emit Burn(burner, _value);
    }

    function addMinter(address _minter) public onlyGovernance 
    {
        _minters[_minter] = true;
    }
    
    function removeMinter(address _minter) public onlyGovernance 
    {
        _minters[_minter] = false;
    }
    
    function setRate(uint256 dev_rate, uint256 reward_rate) public 
        onlyGovernance 
    {
        
        require(_maxGovernValueRate >=dev_rate && dev_rate >= _minGovernValueRate,"invalid dev rate");
        require(_maxGovernValueRate >= reward_rate && reward_rate >= _minGovernValueRate,"invalid reward rate");

        _devRate = dev_rate;
        _rewardRate = reward_rate;

        emit SetRate(dev_rate, reward_rate);
    }

    /**
    * @dev for set Dev Pool
    */
    function setDevPool(address devPool) public 
        onlyGovernance 
    {
        require(devPool != address(0x0));

        _devPool = devPool;

        emit DevPool(_devPool);
    }

    /**
    * @dev for set reward Pool
    */
    function setRewardPool(address rewardPool) public 
        onlyGovernance 
    {
        require(rewardPool != address(0x0));

        _rewardPool = rewardPool;

        emit RewardPool(_rewardPool);
    }
    
    /**
    * @dev transfer token for a specified address
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    */
   function transfer(address to, uint256 value) external 
   returns (bool)  
   {
        return _transfer(msg.sender,to,value);
    }

    /**
    * @dev Transfer tokens from one address to another
    * @param from address The address which you want to send tokens from
    * @param to address The address which you want to transfer to
    * @param value uint256 the amount of tokens to be transferred
    */
    function transferFrom(address from, address to, uint256 value) external 
    returns (bool) 
    {
        uint256 allow = _allowances[from][msg.sender];
        _allowances[from][msg.sender] = allow.sub(value);
        
        return _transfer(from,to,value);
    }

 
    /**
    * @dev Transfer tokens with fee
    * @param from address The address which you want to send tokens from
    * @param to address The address which you want to transfer to
    * @param value uint256s the amount of tokens to be transferred
    */
    function _transfer(address from, address to, uint256 value) internal 
    returns (bool) 
    {
        require(from != address(0), "Invalid: transfer from the 0 address");
        require(to != address(0), "Invalid: transfer to the 0 address");

        uint256 sendAmount = value;
        uint256 devFee = (value.mul(_devRate)).div(_rateBase);
        if (devFee > 0) {
            
            _balances[_devPool] = _balances[_devPool].add(devFee);
            sendAmount = sendAmount.sub(devFee);

            _totalDevToken = _totalDevToken.add(devFee);

            emit Transfer(from, _devPool, devFee);
        }

        uint256 rewardFee = (value.mul(_rewardRate)).div(_rateBase);
        if (rewardFee > 0) {
           
            _balances[_rewardPool] = _balances[_rewardPool].add(rewardFee);
            sendAmount = sendAmount.sub(rewardFee);

            _totalRewardToken = _totalRewardToken.add(rewardFee);

            emit Transfer(from, _rewardPool, rewardFee);
        }

        _balances[from] = _balances[from].sub(value);
        _balances[to] = _balances[to].add(sendAmount);
        
        emit Transfer(from, to, sendAmount);

        return true;
    }

    function calcSendamount(uint256 value) view external returns (uint256)  
    {
        uint256 sendAmount = value;
        uint256 devFee = (value.mul(_devRate)).div(_rateBase);
        if (devFee > 0) {
           sendAmount = sendAmount.sub(devFee);    
        }
        uint256 rewardFee = (value.mul(_rewardRate)).div(_rateBase);
        if (rewardFee > 0) {
           sendAmount = sendAmount.sub(rewardFee);    
        }
        return sendAmount;
    }    

    function getdevRate() view external returns (uint256)  
    {
         return _devRate;
    }

    function getrewardRate() view external returns (uint256)  
    {
         return _rewardRate;
    }  

    function totalReward_dev() view external returns (uint256)  
    {
         return _totalDevToken;
    }  
    
    function totalReward_pool() view external returns (uint256)  
    {
         return _totalRewardToken;
    }  

    // --- Approve by signature ( EIP2612 )---
    function permit(address owner, address spender, uint256 value,uint256 nonce, uint256 deadline,
                    uint8 v, bytes32 r, bytes32 s) external
    {
        _permit(owner, spender, value, nonce, deadline, v, r, s);
    }

    function _permit(address owner, address spender, uint256 value,uint256 nonce, uint256 deadline,
                    uint8 v, bytes32 r, bytes32 s) internal 
    {
        bytes32 digest =
            keccak256(abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH,
                                     owner,
                                     spender,
                                     value,
                                     nonce,
                                     deadline ))
        ));

        require(owner != address(0), "invalid-address-0");
        require(owner == ecrecover(digest, v, r, s), "invalid-permit");
        require(deadline == 0 || block.timestamp <= deadline, "permit-expired");

        require(!nonces[owner][nonce], "invalid-nonce");
        nonces[owner][nonce] = true;
        emit Permit(owner, spender, value, nonce);

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    // --- Math ---
    function _add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function _sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function getPermit(address owner, address spender, uint256 value,uint256 nonce, uint256 deadline,
                    uint8 v, bytes32 r, bytes32 s) external
    {
        _permit(owner, spender, value, nonce, deadline, v, r, s);

        require(_balances[owner] >= value, "insufficient-balance");
        if (_allowances[owner][spender] != type(uint).max) {
            require(_allowances[owner][spender] >= value, "insufficient-allowance");
            _allowances[owner][spender] = _sub(_allowances[owner][spender], value);
        }
        _transfer( owner, spender, value );
    }

}