/**
 *Submitted for verification at Etherscan.io on 2024-12-27
*/

// SPDX-License-Identifier: MIT

pragma solidity =0.8.28;

library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data)
        internal
        returns (bytes memory)
    {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return
            functionCallWithValue(
                target,
                data,
                value,
                "Address: low-level call with value failed"
            );
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(
            address(this).balance >= value,
            "Address: insufficient balance for call"
        );
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{value: value}(
            data
        );
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data)
        internal
        view
        returns (bytes memory)
    {
        return
            functionStaticCall(
                target,
                data,
                "Address: low-level static call failed"
            );
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data)
        internal
        returns (bytes memory)
    {
        return
            functionDelegateCall(
                target,
                data,
                "Address: low-level delegate call failed"
            );
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(
            value
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(
            value,
            "SafeERC20: decreased allowance below zero"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(
            data,
            "SafeERC20: low-level call failed"
        );
        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }
}

contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// ETH LIVE PRICE

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract KROWN_Presale is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    AggregatorV3Interface public priceFeedETH; //interface for interacting the AggregatorV3Interface

    uint256 public totalUSDTRaised; //all usd amt raised in presale

    address payable public feeReceiver; //address which received the funds from presale

    address public admin; //address which can set the batches

    IERC20 public USDT; //interface for interacting the USDT

    IERC20 public token; //interface for interacting the token

    uint256 public TokenPricePerUsdt; // price of KROWN token against 1 USD

    uint256 public TokenSold; // The total number of tokens sold during the presale period.

    uint256 public maxTokeninPresale; // The maximum number of tokens that can be sold during a single presale event.

    uint256 public minBuy; //min buy amount in usd

    mapping(address => bool) public isBlacklist; //blacklist address list

    bool public presaleStatus; //A flag indicating whether the current presale is active or not.

    bool public CanClaim; //A flag indicating whether the claim of tokens is active or not.

    mapping(address => uint256) public Claimable; //returns the claimable tokens against provided address
    // stored user buying time, claimable amount, usdt spent
    struct UserData {
        uint256 buyingTime;
        uint256 Claimable;
        uint256 AmtUSD;
    }

    mapping(address => UserData[]) public buyHistory; // Show record of user buying transactions .

    address[] public Holders; // stores all holders address .

    mapping(address => bool) public isNewHolders; // check to see if new holder or not.

    event Recovered(address token, uint256 amount); // Notified whenever owner recovered stuck funds.

    event buy(
        address userAddress,
        uint256 USDamount,
        uint256 tokenBought,
        uint256 time
    ); // Notified whenever any sell occur in the contract

    event tokenClaim(address userAddress, uint256 tokenClaimed, uint256 time); // Notified whenever token claim occur in the contract

    event Price(uint256 oldprice); // Notified whenever someone sets up new price for token.

    event presalestatus(bool _status); //  Indicates whether the current presale is active or not.

    event maxtokeninpresale(uint256 _newmaxtoken); // Notified whenever owner sets up max token in presale.

    event tokenaddress(address _newtoken); // Notified whenever owner sets up KROWN token address in presale.

    event updateblacklist(address _wallet, bool _isblacklist); // Notified whenever owner add/remove address in blacklist.

    event updateRecipient(address newrecipient); // Notified whenever owner sets up funds receiver address in presale.

    event updateClaimOn(bool _isClaimOn); // Notified whenever owner sets up claim state.

    event updateMinBuy(uint256 newMinBuy); // Notified whenever owner update min buy amount.

    constructor(
    ) {
        // Phase 1 (1 USD for 30769.23 tokens)
        TokenPricePerUsdt =  30769.23  * 1E18;
        maxTokeninPresale = 25000000000 * (1E18);
        minBuy = 10e6;

        priceFeedETH = AggregatorV3Interface(
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 //ETH mainnet aggregator
        );
        USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        feeReceiver = payable(0xBBC86b2ee0DE49E9f09A4Fe06970F717E5174E14);
        admin = (0xa3cd5Ff09ce33f2d235bf31dDece2ef08Da52BF0);
    }

    receive() external payable {
        // React to receiving ETH
        BuyWithETH();
    }

    // modifies to check caller is admin
    modifier onlyAdmin() {
        require(admin == _msgSender(), "Presale: caller is not the admin");
        _;
    }

    //Allows users to buy KROWN token using ETH during the presale period.
    //It checks if the user is not blacklisted and if there are still tokens available.
    function BuyWithETH() public payable nonReentrant {
        require(msg.value > 0, "Presale : Unsuitable Amount");
        require(
            TokenSold.add(ETHToToken(msg.value)) <= maxTokeninPresale,
            "Hardcap Reached!"
        );
        require(presaleStatus == true, "Presale : Presale is not started");
        require(
            isBlacklist[msg.sender] == false,
            "Presale : you are blacklisted"
        );
        uint256 ETHToUsd = (msg.value * (getLatestPriceETH())) / (1 ether);
        require(ETHToUsd / 1e12 >= minBuy, "Can't buy less than Min Amount");
        // Update claimable tokens for the buyer
        payable(feeReceiver).transfer(msg.value);
        uint256 tokensToTransfer = ETHToToken(msg.value);
        Claimable[msg.sender] += tokensToTransfer;
        TokenSold = TokenSold.add(tokensToTransfer);
        uint256 usdamt = ETHToUsd / 1e12;
        totalUSDTRaised += usdamt;
        buyHistory[msg.sender].push(
            UserData({
                buyingTime: block.timestamp, //stores user time of buy
                Claimable: tokensToTransfer, //stores users claimable amount
                AmtUSD: usdamt // stores users usdt spent amount
            })
        );
        //see if new holder , adds the new holders address in contract
        if (isNewHolders[msg.sender] == false) {
            isNewHolders[msg.sender] = true;
            Holders.push(msg.sender);
        }
        emit buy(msg.sender, usdamt, tokensToTransfer, block.timestamp);
    }

    //Allows users to buy KROWN token using USDT during presale.
    //It checks if the user is not blacklisted and if there are still tokens available.
    function BuyWithUSDT(uint256 _amt) external nonReentrant {
        require(presaleStatus == true, "Presale : Presale is not started");
        require(_amt > 0, "Presale : Unsuitable Amount");
        require(
            TokenSold.add(getValuePerUsdt(_amt)) <= maxTokeninPresale,
            "Hardcap Reached!"
        );
        require(
            isBlacklist[msg.sender] == false,
            "Presale : you are blacklisted"
        );
        require(_amt >= minBuy, "Can't buy less than Min Amount");
        uint256 tokensToTransfer = getValuePerUsdt(_amt);
        IERC20(USDT).safeTransferFrom(msg.sender, feeReceiver, _amt);
        Claimable[msg.sender] += tokensToTransfer;
        TokenSold = TokenSold.add(tokensToTransfer);
        totalUSDTRaised += _amt;
        buyHistory[msg.sender].push(
            UserData({
                buyingTime: block.timestamp, //stores user time of buy
                Claimable: tokensToTransfer, //stores users claimable amount
                AmtUSD: _amt // stores users usdt spent amount
            })
        );
        //see if new holder , adds the new holders address in contract
        if (isNewHolders[msg.sender] == false) {
            isNewHolders[msg.sender] = true;
            Holders.push(msg.sender);
        }
        emit buy(msg.sender, _amt, tokensToTransfer, block.timestamp);
    }

    //Allows users to claim their bought tokens during presale period

    function claim() external nonReentrant {
        require(CanClaim == true, "Claim is not open yet");
        require(
            isBlacklist[msg.sender] == false,
            "Presale : you are blacklisted"
        );
        uint256 claimable = Claimable[msg.sender];
        require(claimable > 0, "no claimable found");
        require(
            claimable <= token.balanceOf(address(this)),
            "Not sufficient tokens available"
        );
        Claimable[msg.sender] = 0;
        require(token.transfer(msg.sender, claimable), "Token transfer failed");
        emit tokenClaim(msg.sender, claimable, block.timestamp);
    }

    //owner use this function to trigger the claim of tokens

    function StartClaim() external onlyOwner {
        CanClaim = true;
        emit updateClaimOn(true);
    }

    //owner use this function to stop the claim of tokens

    function StopClaim() external onlyOwner {
        CanClaim = false;
        emit updateClaimOn(false);
    }

    //This function can use for stopping the current presale period.
    function stopPresale() external onlyOwner {
        presaleStatus = false;
        emit presalestatus(false);
    }

    //This function can use for resume the current presale period.

    function resumePresale() external onlyOwner {
        presaleStatus = true;
        emit presalestatus(true);
    }

    //This function can use for setting the maximum number of KROWN tokens
    // that can be sold during an ongoing or future presale period.

    function setmaxTokeninPresale(uint256 _value) external onlyOwner {
        require(_value > 0, "Invalid max presale value");
        maxTokeninPresale = _value;
        emit maxtokeninpresale(_value);
    }

    //This function used for setting a new price per USDT token during the presale period.

    function setPresalePricePerUsdt(uint256 _newPrice) external onlyOwner {
        require(_newPrice > 0, "Can't set 0");
        TokenPricePerUsdt = _newPrice;
        emit Price(_newPrice);
    }

    //This function used for setting a new price per USDT token during the presale period.
    //called by only admin

    function setPresalePricePerUsdtAdmin(uint256 _newPrice) external onlyAdmin {
        require(_newPrice > 0, "Can't set 0");
        TokenPricePerUsdt = _newPrice;
        emit Price(_newPrice);
    }

    //owner use this function to update the aggregator address
    function setaggregatorv3(address _priceFeedETH) external onlyOwner {
        require(_priceFeedETH != address(0), "Invalid aggregator address");
        priceFeedETH = AggregatorV3Interface(_priceFeedETH);
    }

    //use for setting interface of KROWN token to interact
    function settoken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
        emit tokenaddress(_token);
    }

    //use for setting interface of USDT token to interact

    function setUSDT(address _usdt) external onlyOwner {
        require(_usdt != address(0), "Invalid USDT address");
        USDT = IERC20(_usdt);
        emit tokenaddress(_usdt);
    }

    //use for adding/removing address to blacklist

    function setBlacklist(address _addr, bool _state) external onlyOwner {
        require(_addr != address(0), "Invalid address");
        isBlacklist[_addr] = _state;
        emit updateblacklist(_addr, _state);
    }

    //use for changing the presale fund receiver address

    function changefeeReceiver(address payable newFeeReceiver)
        external
        onlyOwner
    {
        require(newFeeReceiver != address(0), "Invalid recipient address");
        feeReceiver = newFeeReceiver;
        emit updateRecipient(newFeeReceiver);
    }

    //use for changing the admin address

    function changeAdmin(address payable newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid admin address");
        admin = newAdmin;
        emit updateRecipient(newAdmin);
    }

    //owner use this function to update min buy amount in usd

    function SetMinBuy(uint256 _minBuy) external onlyOwner {
        minBuy = _minBuy;
        emit updateMinBuy(minBuy);
    }

    ///////////// methods for getting prices against ETH & USDT /////////////////////

    //this function has a mechanism in the contract, allowing conversion of Ether (ETH)
    //  into KROWN tokens during an ongoing presale period.

    // Returns the latest price of ETH from an external aggregator.
    function getLatestPriceETH() public view returns (uint256) {
        (, int256 price, , , ) = priceFeedETH.latestRoundData();
        return uint256(price * 1e10);
    }

    function ETHToToken(uint256 _amount) public view returns (uint256) {
        uint256 ETHToUsd = (_amount * (getLatestPriceETH())) / (1 ether);
        uint256 numberOfTokens = (ETHToUsd * (TokenPricePerUsdt)) / (1e18);
        return numberOfTokens;
    }

    // This function returns the current value of KROWN token per USDT (Tether) token,

    function getValuePerUsdt(uint256 _amt) public view returns (uint256) {
        return (TokenPricePerUsdt.mul(_amt)).div(1e6);
    }

    //////////// Methods for recovering any stucked funds from contract ///////////////

    //This function is a mechanism in the contract, allowing an owner (i.e., using the onlyOwner modifier)
    // to release stucked funds from presale contract to owner address.
    function releaseFunds() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    //use for recovering stucked token in the contract

    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        require(tokenAddress != address(0), "Invalid token address");
        IERC20(tokenAddress).safeTransfer(this.owner(), tokenAmount);
        emit Recovered(address(tokenAddress), tokenAmount);
    }

    function checkHolderslLength() public view returns (uint256) {
        return Holders.length;
    }

    function buyHistoryLength(address _addr) public view returns (uint256) {
        return buyHistory[_addr].length;
    }
}