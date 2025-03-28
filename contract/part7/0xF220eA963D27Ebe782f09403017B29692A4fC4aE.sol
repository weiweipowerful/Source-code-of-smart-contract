/**
 *Submitted for verification at Etherscan.io on 2022-05-09
*/

// SPDX-License-Identifier: BUSL-1.1


// This source code is licensed under the Business Source License
// The Licensed Work is (c) 2022 ElkLabs
// Full License Text available at https://github.com/elkfinance/elknet-core/blob/main/LICENSE
// File: contracts/interfaces/IElkERC20.sol



pragma solidity >=0.5.0;

interface IElkERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}

// File: @openzeppelin/[email protected]/utils/Address.sol


// OpenZeppelin Contracts (last updated v4.5.0) (utils/Address.sol)

pragma solidity ^0.8.1;

/**
 * @dev Collection of functions related to the address type
 */
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
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
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
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
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
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
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
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
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
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
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

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
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

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

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

// File: @openzeppelin/[email protected]/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
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
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

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
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

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

// File: @openzeppelin/[email protected]/token/ERC20/utils/SafeERC20.sol


// OpenZeppelin Contracts v4.4.1 (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;



/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
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
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
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

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// File: @openzeppelin/[email protected]/security/ReentrancyGuard.sol


// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

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
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// File: @openzeppelin/[email protected]/utils/math/Math.sol


// OpenZeppelin Contracts (last updated v4.5.0) (utils/math/Math.sol)

pragma solidity ^0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a / b + (a % b == 0 ? 0 : 1);
    }
}

// File: @openzeppelin/[email protected]/utils/Context.sol


// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// File: @openzeppelin/[email protected]/security/Pausable.sol


// OpenZeppelin Contracts v4.4.1 (security/Pausable.sol)

pragma solidity ^0.8.0;


/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// File: @openzeppelin/[email protected]/access/Ownable.sol


// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

pragma solidity ^0.8.0;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// File: contracts/FarmingRewardsNewNew.sol


pragma solidity >=0.8.0;








contract FarmingRewards is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable rewardsToken;
    IERC20 public immutable stakingToken;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    IERC20 public boosterToken;
    uint256 public boosterRewardRate;
    uint256 public boosterRewardPerTokenStored;

    mapping(address => uint256) public userBoosterRewardPerTokenPaid;
    mapping(address => uint256) public boosterRewards;

    mapping(address => uint256) public coverages;
    uint256 public totalCoverage;

    uint256[] public feeSchedule;
    uint256[] public withdrawalFeesPct;
    uint256 public withdrawalFeesUnit = 10000; // unit for fees
    uint256 public maxWithdrawalFee = 1000;    // max withdrawal fee (here, 10%)
    mapping(address => uint256) public lastStakedTime;
    uint256 public totalFees;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _rewardsToken,
        address _stakingToken,
        address _boosterToken,
        uint256 _rewardsDuration,
        uint256[] memory _feeSchedule,       // assumes a sorted array
        uint256[] memory _withdrawalFeesPct  // aligned to fee schedule
    ) {
        require(_boosterToken != _rewardsToken, "The booster token must be different from the reward token");
        require(_boosterToken != _stakingToken, "The booster token must be different from the staking token");
        require(_rewardsDuration > 0, "Rewards duration cannot be zero");
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        boosterToken = IERC20(_boosterToken);
        rewardsDuration = _rewardsDuration;
        _setWithdrawalFees(_feeSchedule, _withdrawalFeesPct);
        _pause();
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / _totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + rewards[account];
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    function boosterRewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return boosterRewardPerTokenStored;
        }
        return boosterRewardPerTokenStored + (lastTimeRewardApplicable() - lastUpdateTime) * boosterRewardRate * 1e18 / _totalSupply;
    }

    function boosterEarned(address account) public view returns (uint256) {
        return _balances[account] * (boosterRewardPerToken() - userBoosterRewardPerTokenPaid[account]) / 1e18 + boosterRewards[account];
    }

    function getBoosterRewardForDuration() external view returns (uint256) {
        return boosterRewardRate * rewardsDuration;
    }

    function exitFee(address account) external view returns (uint256) {
        return fee(account, _balances[account]);
    }

    function fee(address account, uint256 withdrawalAmount) public view returns (uint256) {
        for (uint i=0; i < feeSchedule.length; ++i) {
            if (block.timestamp - lastStakedTime[account] < feeSchedule[i]) {
                return withdrawalAmount * withdrawalFeesPct[i] / withdrawalFeesUnit;
            }
        }
        return 0;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply + amount;
        _balances[msg.sender] = _balances[msg.sender] + amount;
        lastStakedTime[msg.sender] = block.timestamp;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function stakeWithPermit(uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply + amount;
        _balances[msg.sender] = _balances[msg.sender] + amount;

        // permit
        IElkERC20(address(stakingToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);

        lastStakedTime[msg.sender] = block.timestamp;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        _withdraw(amount);
    }

    function emergencyWithdraw(uint256 amount) external nonReentrant {
        _withdraw(amount);
    }

    function _withdraw(uint256 amount) private {
        require(amount > 0, "Cannot withdraw 0");
        uint256 balance = _balances[msg.sender];
        require(amount <= balance, "Cannot withdraw more than account balance");
        _totalSupply = _totalSupply - amount;
        uint256 collectedFee = fee(msg.sender, amount);
        _balances[msg.sender] = balance - amount;
        uint256 withdrawableBalance = amount - collectedFee;
        stakingToken.safeTransfer(msg.sender, withdrawableBalance);
        emit Withdrawn(msg.sender, withdrawableBalance);
        if (collectedFee > 0) {
            emit FeesCollected(msg.sender, collectedFee);
            totalFees = totalFees + collectedFee;
        }
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function getBoosterReward() public nonReentrant updateReward(msg.sender) {
        if (address(boosterToken) != address(0)) {
            uint256 reward = boosterRewards[msg.sender];
            if (reward > 0) {
                boosterRewards[msg.sender] = 0;
                boosterToken.safeTransfer(msg.sender, reward);
                emit BoosterRewardPaid(msg.sender, reward);
            }
        }
    }

    function getCoverage() public nonReentrant {
        uint256 coverageAmount = coverages[msg.sender];
        if (coverageAmount > 0) {
            totalCoverage = totalCoverage - coverages[msg.sender];
            coverages[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, coverageAmount);
            emit CoveragePaid(msg.sender, coverageAmount);
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
        getBoosterReward();
        getCoverage();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function sendRewardsAndStartEmission(uint256 reward, uint256 boosterReward, uint256 duration) external onlyOwner {
        rewardsToken.safeTransferFrom(msg.sender, address(this), reward);
        if (address(boosterToken) != address(0) && boosterReward > 0) {
            boosterToken.safeTransferFrom(owner(), address(this), boosterReward);
        }
        _startEmission(reward, boosterReward, duration);
    }

    function startEmission(uint256 reward, uint256 boosterReward, uint256 duration) external onlyOwner {
        _startEmission(reward, boosterReward, duration);
    }

    function stopEmission() external onlyOwner {
        require(block.timestamp < periodFinish, "Cannot stop rewards emissions if not started or already finished");

        uint256 tokensToBurn;
        uint256 boosterTokensToBurn;

        if (_totalSupply == 0) {
            tokensToBurn = rewardsToken.balanceOf(address(this));
            if (address(boosterToken) != address(0)) {
                boosterTokensToBurn = boosterToken.balanceOf(address(this));
            } else {
                boosterTokensToBurn = 0;
            }
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            tokensToBurn = rewardRate * remaining;
            boosterTokensToBurn = boosterRewardRate * remaining;
        }

        periodFinish = block.timestamp;
        if (tokensToBurn > 0) {
            rewardsToken.safeTransfer(owner(), tokensToBurn);
        }
        if (address(boosterToken) != address(0) && boosterTokensToBurn > 0) {
            boosterToken.safeTransfer(owner(), boosterTokensToBurn);
        }

        emit RewardsEmissionEnded(tokensToBurn);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function recoverLeftoverReward() external onlyOwner {
        require(_totalSupply == 0 && rewardsToken == stakingToken, "Cannot recover leftover reward if it is not the staking token or there are still staked tokens");
        uint256 tokensToBurn = rewardsToken.balanceOf(address(this));
        if (tokensToBurn > 0) {
            rewardsToken.safeTransfer(msg.sender, tokensToBurn);
        }
        emit LeftoverRewardRecovered(tokensToBurn);
    }

    function recoverLeftoverBooster() external onlyOwner {
        require(address(boosterToken) != address(0), "Cannot recover leftover booster if there was no booster token set");
        require(_totalSupply == 0, "Cannot recover leftover booster if there are still staked tokens");
        uint256 tokensToBurn = boosterToken.balanceOf(address(this));
        if (tokensToBurn > 0) {
            boosterToken.safeTransfer(msg.sender, tokensToBurn);
        }
        emit LeftoverBoosterRecovered(tokensToBurn);
    }

    function recoverFees() external onlyOwner {
        uint256 previousFees = totalFees;
        totalFees = 0;
        stakingToken.safeTransfer(owner(), previousFees);
        emit FeesRecovered(previousFees);
    }

    function setRewardsDuration(uint256 duration) external onlyOwner {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        _setRewardsDuration(duration);
    }

    // Booster Rewards

    function setBoosterToken(address _boosterToken) external onlyOwner {
        require(_boosterToken != address(rewardsToken), "The booster token must be different from the reward token");
        require(_boosterToken != address(stakingToken), "The booster token must be different from the staking token");
        boosterToken = IERC20(_boosterToken);
        emit BoosterRewardSet(_boosterToken);
    }

    // ILP

    function setCoverageAmount(address addr, uint256 amount) public onlyOwner {
        totalCoverage = totalCoverage - coverages[addr];
        coverages[addr] = amount;
        totalCoverage = totalCoverage + coverages[addr];
    }

    function setCoverageAmounts(address[] memory addresses, uint256[] memory amounts) external onlyOwner {
        require(addresses.length == amounts.length, "The same number of addresses and amounts must be provided");
        for (uint i=0; i < addresses.length; ++i) {
            setCoverageAmount(addresses[i], amounts[i]);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Withdrawal Fees

    function setWithdrawalFees(uint256[] memory _feeSchedule, uint256[] memory _withdrawalFees) external onlyOwner {
        _setWithdrawalFees(_feeSchedule, _withdrawalFees);
    }

    // Private functions

    function _setRewardsDuration(uint256 duration) private {
        rewardsDuration = duration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function _setWithdrawalFees(uint256[] memory _feeSchedule, uint256[] memory _withdrawalFeesPct) private {
        require(_feeSchedule.length == _withdrawalFeesPct.length, "Fee schedule and withdrawal fees arrays must be the same length!");
        require(_feeSchedule.length <= 10, "Fee schedule and withdrawal fees arrays lengths cannot be larger than 10!");
        uint256 lastFeeSchedule = 0;
        uint256 lastWithdrawalFee = maxWithdrawalFee + 1;
        for(uint256 i = 0; i < _feeSchedule.length; ++i) {
           require(_feeSchedule[i] > lastFeeSchedule, "Fee schedule must be ascending!");
           require(_withdrawalFeesPct[i] < lastWithdrawalFee, "Withdrawal fees must be descending and lower than maximum!");
           lastFeeSchedule = _feeSchedule[i];
           lastWithdrawalFee = _withdrawalFeesPct[i];
        }
        feeSchedule = _feeSchedule;
        withdrawalFeesPct = _withdrawalFeesPct;
        emit WithdrawalFeesSet(_feeSchedule, _withdrawalFeesPct);
    }

    // Must send reward before calling this!
    function _startEmission(uint256 reward, uint256 boosterReward, uint256 duration) private updateReward(address(0)) {
        if (duration > 0) {
            _setRewardsDuration(duration);
        }

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
            boosterRewardRate = boosterReward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
            uint256 boosterLeftover = remaining * boosterRewardRate;
            boosterRewardRate = (boosterReward + boosterLeftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardsToken.balanceOf(address(this));
        if (rewardsToken != stakingToken) {
            require(rewardRate <= balance / rewardsDuration, "Provided reward too high");
        } else { // Handle care where rewardsToken is the same as stakingToken (need to subtract total supply)
            require(rewardRate <= (balance - _totalSupply) / rewardsDuration, "Provided reward too high");
        }

        if (address(boosterToken) != address(0)) {
            uint boosterBalance = boosterToken.balanceOf(address(this));
            require(boosterRewardRate <= boosterBalance / rewardsDuration, "Provided booster reward too high");
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        emit RewardsEmissionStarted(reward, boosterReward, duration);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        boosterRewardPerTokenStored = boosterRewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
            boosterRewards[account] = boosterEarned(account);
            userBoosterRewardPerTokenPaid[account] = boosterRewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event CoveragePaid(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event BoosterRewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event LeftoverRewardRecovered(uint256 amount);
    event LeftoverBoosterRecovered(uint256 amount);
    event RewardsEmissionStarted(uint256 reward, uint256 boosterReward, uint256 duration);
    event RewardsEmissionEnded(uint256 amount);
    event BoosterRewardSet(address token);
    event WithdrawalFeesSet(uint256[] _feeSchedule, uint256[] _withdrawalFees);
    event FeesCollected(address indexed user, uint256 amount);
    event FeesRecovered(uint256 amount);
}