/**
 *Submitted for verification at Etherscan.io on 2024-05-13
*/

// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

// solhint-disable

/**
 * @dev Reverts if `condition` is false, with a revert reason containing `errorCode`. Only codes up to 999 are
 * supported.
 */
function _require(bool condition, uint256 errorCode) pure {
    if (!condition) _revert(errorCode);
}

/**
 * @dev Reverts with a revert reason containing `errorCode`. Only codes up to 999 are supported.
 */
function _revert(uint256 errorCode) pure {
    // We're going to dynamically create a revert string based on the error code, with the following format:
    // 'BAL#{errorCode}'
    // where the code is left-padded with zeroes to three digits (so they range from 000 to 999).
    //
    // We don't have revert strings embedded in the contract to save bytecode size: it takes much less space to store a
    // number (8 to 16 bits) than the individual string characters.
    //
    // The dynamic string creation algorithm that follows could be implemented in Solidity, but assembly allows for a
    // much denser implementation, again saving bytecode size. Given this function unconditionally reverts, this is a
    // safe place to rely on it without worrying about how its usage might affect e.g. memory contents.
    assembly {
        // First, we need to compute the ASCII representation of the error code. We assume that it is in the 0-999
        // range, so we only need to convert three digits. To convert the digits to ASCII, we add 0x30, the value for
        // the '0' character.

        let units := add(mod(errorCode, 10), 0x30)

        errorCode := div(errorCode, 10)
        let tenths := add(mod(errorCode, 10), 0x30)

        errorCode := div(errorCode, 10)
        let hundreds := add(mod(errorCode, 10), 0x30)

        // With the individual characters, we can now construct the full string. The "BAL#" part is a known constant
        // (0x42414c23): we simply shift this by 24 (to provide space for the 3 bytes of the error code), and add the
        // characters to it, each shifted by a multiple of 8.
        // The revert reason is then shifted left by 200 bits (256 minus the length of the string, 7 characters * 8 bits
        // per character = 56) to locate it in the most significant part of the 256 slot (the beginning of a byte
        // array).

        let revertReason := shl(200, add(0x42414c23000000, add(add(units, shl(8, tenths)), shl(16, hundreds))))

        // We can now encode the reason in memory, which can be safely overwritten as we're about to revert. The encoded
        // message will have the following layout:
        // [ revert reason identifier ] [ string location offset ] [ string length ] [ string contents ]

        // The Solidity revert reason identifier is 0x08c739a0, the function selector of the Error(string) function. We
        // also write zeroes to the next 28 bytes of memory, but those are about to be overwritten.
        mstore(0x0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
        // Next is the offset to the location of the string, which will be placed immediately after (20 bytes away).
        mstore(0x04, 0x0000000000000000000000000000000000000000000000000000000000000020)
        // The string length is fixed: 7 characters.
        mstore(0x24, 7)
        // Finally, the string itself is stored.
        mstore(0x44, revertReason)

        // Even if the string is only 7 bytes long, we need to return a full 32 byte slot containing it. The length of
        // the encoded message is therefore 4 + 32 + 32 + 32 = 100.
        revert(0, 100)
    }
}

library Errors {
    // Math
    uint256 internal constant ADD_OVERFLOW = 0;
    uint256 internal constant SUB_OVERFLOW = 1;
    uint256 internal constant SUB_UNDERFLOW = 2;
    uint256 internal constant MUL_OVERFLOW = 3;
    uint256 internal constant ZERO_DIVISION = 4;
    uint256 internal constant DIV_INTERNAL = 5;
    uint256 internal constant X_OUT_OF_BOUNDS = 6;
    uint256 internal constant Y_OUT_OF_BOUNDS = 7;
    uint256 internal constant PRODUCT_OUT_OF_BOUNDS = 8;
    uint256 internal constant INVALID_EXPONENT = 9;

    // Input
    uint256 internal constant OUT_OF_BOUNDS = 100;
    uint256 internal constant UNSORTED_ARRAY = 101;
    uint256 internal constant UNSORTED_TOKENS = 102;
    uint256 internal constant INPUT_LENGTH_MISMATCH = 103;
    uint256 internal constant ZERO_TOKEN = 104;

    // Shared pools
    uint256 internal constant MIN_TOKENS = 200;
    uint256 internal constant MAX_TOKENS = 201;
    uint256 internal constant MAX_SWAP_FEE_PERCENTAGE = 202;
    uint256 internal constant MIN_SWAP_FEE_PERCENTAGE = 203;
    uint256 internal constant MINIMUM_BPT = 204;
    uint256 internal constant CALLER_NOT_VAULT = 205;
    uint256 internal constant UNINITIALIZED = 206;
    uint256 internal constant BPT_IN_MAX_AMOUNT = 207;
    uint256 internal constant BPT_OUT_MIN_AMOUNT = 208;
    uint256 internal constant EXPIRED_PERMIT = 209;
    uint256 internal constant NOT_TWO_TOKENS = 210;

    // Pools
    uint256 internal constant MIN_AMP = 300;
    uint256 internal constant MAX_AMP = 301;
    uint256 internal constant MIN_WEIGHT = 302;
    uint256 internal constant MAX_STABLE_TOKENS = 303;
    uint256 internal constant MAX_IN_RATIO = 304;
    uint256 internal constant MAX_OUT_RATIO = 305;
    uint256 internal constant MIN_BPT_IN_FOR_TOKEN_OUT = 306;
    uint256 internal constant MAX_OUT_BPT_FOR_TOKEN_IN = 307;
    uint256 internal constant NORMALIZED_WEIGHT_INVARIANT = 308;
    uint256 internal constant INVALID_TOKEN = 309;
    uint256 internal constant UNHANDLED_JOIN_KIND = 310;
    uint256 internal constant ZERO_INVARIANT = 311;
    uint256 internal constant ORACLE_INVALID_SECONDS_QUERY = 312;
    uint256 internal constant ORACLE_NOT_INITIALIZED = 313;
    uint256 internal constant ORACLE_QUERY_TOO_OLD = 314;
    uint256 internal constant ORACLE_INVALID_INDEX = 315;
    uint256 internal constant ORACLE_BAD_SECS = 316;
    uint256 internal constant AMP_END_TIME_TOO_CLOSE = 317;
    uint256 internal constant AMP_ONGOING_UPDATE = 318;
    uint256 internal constant AMP_RATE_TOO_HIGH = 319;
    uint256 internal constant AMP_NO_ONGOING_UPDATE = 320;
    uint256 internal constant STABLE_INVARIANT_DIDNT_CONVERGE = 321;
    uint256 internal constant STABLE_GET_BALANCE_DIDNT_CONVERGE = 322;
    uint256 internal constant RELAYER_NOT_CONTRACT = 323;
    uint256 internal constant BASE_POOL_RELAYER_NOT_CALLED = 324;
    uint256 internal constant REBALANCING_RELAYER_REENTERED = 325;
    uint256 internal constant GRADUAL_UPDATE_TIME_TRAVEL = 326;
    uint256 internal constant SWAPS_DISABLED = 327;
    uint256 internal constant CALLER_IS_NOT_LBP_OWNER = 328;
    uint256 internal constant PRICE_RATE_OVERFLOW = 329;
    uint256 internal constant INVALID_JOIN_EXIT_KIND_WHILE_SWAPS_DISABLED = 330;
    uint256 internal constant WEIGHT_CHANGE_TOO_FAST = 331;
    uint256 internal constant LOWER_GREATER_THAN_UPPER_TARGET = 332;
    uint256 internal constant UPPER_TARGET_TOO_HIGH = 333;
    uint256 internal constant UNHANDLED_BY_LINEAR_POOL = 334;
    uint256 internal constant OUT_OF_TARGET_RANGE = 335;

    // Lib
    uint256 internal constant REENTRANCY = 400;
    uint256 internal constant SENDER_NOT_ALLOWED = 401;
    uint256 internal constant PAUSED = 402;
    uint256 internal constant PAUSE_WINDOW_EXPIRED = 403;
    uint256 internal constant MAX_PAUSE_WINDOW_DURATION = 404;
    uint256 internal constant MAX_BUFFER_PERIOD_DURATION = 405;
    uint256 internal constant INSUFFICIENT_BALANCE = 406;
    uint256 internal constant INSUFFICIENT_ALLOWANCE = 407;
    uint256 internal constant ERC20_TRANSFER_FROM_ZERO_ADDRESS = 408;
    uint256 internal constant ERC20_TRANSFER_TO_ZERO_ADDRESS = 409;
    uint256 internal constant ERC20_MINT_TO_ZERO_ADDRESS = 410;
    uint256 internal constant ERC20_BURN_FROM_ZERO_ADDRESS = 411;
    uint256 internal constant ERC20_APPROVE_FROM_ZERO_ADDRESS = 412;
    uint256 internal constant ERC20_APPROVE_TO_ZERO_ADDRESS = 413;
    uint256 internal constant ERC20_TRANSFER_EXCEEDS_ALLOWANCE = 414;
    uint256 internal constant ERC20_DECREASED_ALLOWANCE_BELOW_ZERO = 415;
    uint256 internal constant ERC20_TRANSFER_EXCEEDS_BALANCE = 416;
    uint256 internal constant ERC20_BURN_EXCEEDS_ALLOWANCE = 417;
    uint256 internal constant SAFE_ERC20_CALL_FAILED = 418;
    uint256 internal constant ADDRESS_INSUFFICIENT_BALANCE = 419;
    uint256 internal constant ADDRESS_CANNOT_SEND_VALUE = 420;
    uint256 internal constant SAFE_CAST_VALUE_CANT_FIT_INT256 = 421;
    uint256 internal constant GRANT_SENDER_NOT_ADMIN = 422;
    uint256 internal constant REVOKE_SENDER_NOT_ADMIN = 423;
    uint256 internal constant RENOUNCE_SENDER_NOT_ALLOWED = 424;
    uint256 internal constant BUFFER_PERIOD_EXPIRED = 425;
    uint256 internal constant CALLER_IS_NOT_OWNER = 426;
    uint256 internal constant NEW_OWNER_IS_ZERO = 427;
    uint256 internal constant CODE_DEPLOYMENT_FAILED = 428;
    uint256 internal constant CALL_TO_NON_CONTRACT = 429;
    uint256 internal constant LOW_LEVEL_CALL_FAILED = 430;

    // Vault
    uint256 internal constant INVALID_POOL_ID = 500;
    uint256 internal constant CALLER_NOT_POOL = 501;
    uint256 internal constant SENDER_NOT_ASSET_MANAGER = 502;
    uint256 internal constant USER_DOESNT_ALLOW_RELAYER = 503;
    uint256 internal constant INVALID_SIGNATURE = 504;
    uint256 internal constant EXIT_BELOW_MIN = 505;
    uint256 internal constant JOIN_ABOVE_MAX = 506;
    uint256 internal constant SWAP_LIMIT = 507;
    uint256 internal constant SWAP_DEADLINE = 508;
    uint256 internal constant CANNOT_SWAP_SAME_TOKEN = 509;
    uint256 internal constant UNKNOWN_AMOUNT_IN_FIRST_SWAP = 510;
    uint256 internal constant MALCONSTRUCTED_MULTIHOP_SWAP = 511;
    uint256 internal constant INTERNAL_BALANCE_OVERFLOW = 512;
    uint256 internal constant INSUFFICIENT_INTERNAL_BALANCE = 513;
    uint256 internal constant INVALID_ETH_INTERNAL_BALANCE = 514;
    uint256 internal constant INVALID_POST_LOAN_BALANCE = 515;
    uint256 internal constant INSUFFICIENT_ETH = 516;
    uint256 internal constant UNALLOCATED_ETH = 517;
    uint256 internal constant ETH_TRANSFER = 518;
    uint256 internal constant CANNOT_USE_ETH_SENTINEL = 519;
    uint256 internal constant TOKENS_MISMATCH = 520;
    uint256 internal constant TOKEN_NOT_REGISTERED = 521;
    uint256 internal constant TOKEN_ALREADY_REGISTERED = 522;
    uint256 internal constant TOKENS_ALREADY_SET = 523;
    uint256 internal constant TOKENS_LENGTH_MUST_BE_2 = 524;
    uint256 internal constant NONZERO_TOKEN_BALANCE = 525;
    uint256 internal constant BALANCE_TOTAL_OVERFLOW = 526;
    uint256 internal constant POOL_NO_TOKENS = 527;
    uint256 internal constant INSUFFICIENT_FLASH_LOAN_BALANCE = 528;

    // Fees
    uint256 internal constant SWAP_FEE_PERCENTAGE_TOO_HIGH = 600;
    uint256 internal constant FLASH_LOAN_FEE_PERCENTAGE_TOO_HIGH = 601;
    uint256 internal constant INSUFFICIENT_FLASH_LOAN_FEE_AMOUNT = 602;
}

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow checks.
 * Adapted from OpenZeppelin's SafeMath library
 */
library Math {
    /**
     * @dev Returns the addition of two unsigned integers of 256 bits, reverting on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        _require(c >= a, Errors.ADD_OVERFLOW);
        return c;
    }

    /**
     * @dev Returns the addition of two signed integers, reverting on overflow.
     */
    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        _require((b >= 0 && c >= a) || (b < 0 && c < a), Errors.ADD_OVERFLOW);
        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers of 256 bits, reverting on overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        _require(b <= a, Errors.SUB_OVERFLOW);
        uint256 c = a - b;
        return c;
    }

    /**
     * @dev Returns the subtraction of two signed integers, reverting on overflow.
     */
    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        _require((b >= 0 && c <= a) || (b < 0 && c > a), Errors.SUB_OVERFLOW);
        return c;
    }

    /**
     * @dev Returns the largest of two numbers of 256 bits.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers of 256 bits.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a * b;
        _require(a == 0 || c / a == b, Errors.MUL_OVERFLOW);
        return c;
    }

    function div(
        uint256 a,
        uint256 b,
        bool roundUp
    ) internal pure returns (uint256) {
        return roundUp ? divUp(a, b) : divDown(a, b);
    }

    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        _require(b != 0, Errors.ZERO_DIVISION);
        return a / b;
    }

    function divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        _require(b != 0, Errors.ZERO_DIVISION);

        if (a == 0) {
            return 0;
        } else {
            return 1 + (a - 1) / b;
        }
    }
}

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
        _require(address(this).balance >= amount, Errors.ADDRESS_INSUFFICIENT_BALANCE);

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        _require(success, Errors.ADDRESS_CANNOT_SEND_VALUE);
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
        _require(isContract(target), Errors.CALL_TO_NON_CONTRACT);

        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResult(success, returndata);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
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
                _revert(Errors.LOW_LEVEL_CALL_FAILED);
            }
        }
    }
}

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
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
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
        _require(owner() == msg.sender, Errors.CALLER_IS_NOT_OWNER);
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
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        _require(newOwner != address(0), Errors.NEW_OWNER_IS_ZERO);
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
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _enterNonReentrant();
        _;
        _exitNonReentrant();
    }

    function _enterNonReentrant() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        _require(_status != _ENTERED, Errors.REENTRANCY);

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _exitNonReentrant() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

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
    function transferFrom(
        address sender,
        address recipient,
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
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(address(token), abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(address(token), abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     *
     * WARNING: `token` is assumed to be a contract: calls to EOAs will *not* revert.
     */
    function _callOptionalReturn(address token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves.
        (bool success, bytes memory returndata) = token.call(data);

        // If the low-level call didn't succeed we return whatever was returned from it.
        assembly {
            if eq(success, 0) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }

        // Finally we check the returndata size is either zero or true - note that this check will always pass for EOAs
        _require(returndata.length == 0 || abi.decode(returndata, (bool)), Errors.SAFE_ERC20_CALL_FAILED);
    }
}

abstract contract AMPLRebaser {

    event Rebase(uint256 old_supply, uint256 new_supply);

    //
    // Check last AMPL total supply from AMPL contract.
    //
    uint256 public last_ampl_supply;

    uint256 public last_rebase_call;

    IERC20 immutable public ampl_token;

    constructor(IERC20 _ampl_token) {
        ampl_token = _ampl_token;
        last_ampl_supply = _ampl_token.totalSupply();
        last_rebase_call = block.timestamp;
    }

    function rebase() external {
        uint256 new_supply = ampl_token.totalSupply();
        // require timestamp to exceed 24 hours in order to execute function OR if ampl supply changed
        if(new_supply == last_ampl_supply)
            require(block.timestamp - 24 hours > last_rebase_call, "AMPLRebaser: rebase can only be called once every 24 hours");
        last_rebase_call = block.timestamp;
        
        _rebase(new_supply);
        emit Rebase(last_ampl_supply, new_supply);
        last_ampl_supply = new_supply;
    }

    function _rebase(uint256 new_supply) internal virtual;

    modifier _rebaseSynced() {
        require(last_ampl_supply == ampl_token.totalSupply(), "AMPLRebaser: Operation unavailable mid-rebase");
        _;
    }
}

library DepositsLinkedList {
    using Math for uint256;

    struct Deposit {
        uint208 amount;
        uint48 timestamp;
    }

    struct Node {
        Deposit deposit;
        uint next;
    }

    struct List {
        mapping(uint => Node) nodes;
        uint head;
        uint tail;
        uint length;
        uint nodeIdCounter;
    }

    uint private constant NULL = 0; // Represent the 'null' pointer

    function initialize(List storage list) internal {
        list.nodeIdCounter = 1; // Initialize node ID counter
    }

    function insertEnd(List storage list, Deposit memory _deposit) internal {
        uint newNodeId = list.nodeIdCounter++; // Use and increment the counter for unique IDs
        list.nodes[newNodeId] = Node({deposit: _deposit, next: NULL});
        if (list.head == NULL) {
            list.head = list.tail = newNodeId;
        } else {
            list.nodes[list.tail].next = newNodeId;
            list.tail = newNodeId;
        }
        list.length++;
    }

    function popHead(List storage list) internal {
        require(list.head != NULL, "List is empty, cannot pop head.");
        uint oldHead = list.head;
        list.head = list.nodes[oldHead].next;
        delete list.nodes[oldHead];
        list.length--;
        if (list.head == NULL) {
            list.tail = NULL; // Reset the tail if the list is empty
        }
    }

    function sumExpiredDeposits(List storage list, uint256 lock_duration) internal view returns (uint256 sum) {
        uint current = list.head;

        while (current != NULL) {
            Node memory currentNode = list.nodes[current];
            if (lock_duration == 0 || ((block.timestamp.sub(currentNode.deposit.timestamp)) > lock_duration)) {
                sum = sum.add(currentNode.deposit.amount);
            } else {
                break;
            }
            current = currentNode.next;
        }

        return sum;
    }

    function modifyDepositAmount(List storage list, uint nodeID, uint256 newAmount) internal {
        require(newAmount <= type(uint208).max, "Invalid amount: Amount exceeds maximum deposit amount.");
        Node storage node = list.nodes[nodeID];
        require(nodeID < list.nodeIdCounter, "Invalid ID: ID does not exist.");
        require(node.deposit.amount != 0, "Invalid amount: Deposit does not exist.");
        node.deposit.amount = uint208(newAmount);
    }

    function getDepositById(List storage list, uint id) internal view returns (Deposit memory) {
        require(id != NULL, "Invalid ID: ID cannot be zero.");
        Node memory node = list.nodes[id];
        require(node.next != NULL || id == list.head, "Node does not exist.");

        return node.deposit;
    }
}

/**
 * staking contract for ERC20 tokens or ETH
 */
contract Distribute is Ownable, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /**
     @dev This value is used so when reward token distribution is computed
     the difference in precision between staking and reward token doesnt interfere
     with bond increase computation
     This will be computed based on the difference between decimals
     of the staking token and the reward token
     If both tokens have the same amount of decimals then this value is 1
     If reward token has less decimals then amounts will be multiplied by this value
     to match the staking token precision
     If staking token has less decimals then this value will also be 1
    */
    uint256 public DECIMALS_ADJUSTMENT;

    uint256 public constant INITIAL_BOND_VALUE = 1_000_000;

    uint256 public bond_value = INITIAL_BOND_VALUE;
    //just for info
    uint256 public staker_count;

    uint256 private _total_staked;
    uint256 private _temp_pool;
    // the amount of dust left to distribute after the bond value has been updated
    uint256 public to_distribute;
    mapping(address => uint256) private _bond_value_addr;
    mapping(address => uint256) private _stakes;
    mapping(address => uint256) private pending_rewards;
    uint256 immutable staking_decimals;

    /// @dev token to distribute
    IERC20 immutable public reward_token;

    /**
        @dev Initialize the contract
        @param _staking_decimals Number of decimals of the staking token
        @param _reward_decimals Number of decimals of the reward token
        @param _reward_token The token used for rewards. Set to 0 for ETH
    */
    constructor(uint256 _staking_decimals, uint256 _reward_decimals, IERC20 _reward_token) {
        require(address(_reward_token) != address(0), "Distribute: Invalid reward token");
        reward_token = _reward_token;
        // sanitize reward token decimals
        (bool success, uint256 checked_decimals) = tryGetDecimals(address(_reward_token));
        if(success) {
            require(checked_decimals == _reward_decimals, "Distribute: Invalid reward decimals");
        }
        staking_decimals = _staking_decimals;
        if(_staking_decimals > _reward_decimals) {
            DECIMALS_ADJUSTMENT = 10**(_staking_decimals - _reward_decimals);
        } else {
            DECIMALS_ADJUSTMENT = 1;
        }
    }

    /**
     * @dev Attempts to call the `decimals()` function on an ERC-20 token contract.
     * @param tokenAddress The address of the ERC-20 token contract.
     * @return success Indicates if the call was successful.
     * @return decimals The number of decimals the token uses, or 0 if the call failed.
     */
    function tryGetDecimals(address tokenAddress) public view returns (bool success, uint8 decimals) {
        bytes memory payload = abi.encodeWithSignature("decimals()");
        // Low-level call to the token contract
        bytes memory returnData;
        (success, returnData) = tokenAddress.staticcall(payload);
        
        // If call was successful and returned data is the expected length for uint8
        if (success && returnData.length == 32) {
            // Decode the return data
            decimals = abi.decode(returnData, (uint8));
        } else {
            // Default to 0 decimals if call failed or returned unexpected data
            return (false, 0);
        }
    }

    /**
        @dev Stakes a certain amount, this MUST transfer the given amount from the caller
        @param account Address who will own the stake afterwards
        @param amount Amount to stake
    */
    function stakeFor(address account, uint256 amount) public onlyOwner nonReentrant {
        require(account != address(0), "Distribute: Invalid account");
        require(amount > 0, "Distribute: Amount must be greater than zero");
        _total_staked = _total_staked.add(amount);
        uint256 stake = _stakes[account];
        if(stake == 0) {
            staker_count++;
        }
        uint256 accumulated_reward = getReward(account);
        if(accumulated_reward > 0) {
            // set pending rewards to the current reward
            pending_rewards[account] = accumulated_reward;
        }
        _stakes[account] = stake.add(amount);
        // reset bond value for this account
        _bond_value_addr[account] = bond_value;
    }

    /**
        @dev unstakes a certain amount, if unstaking is currently not possible the function MUST revert
        @param account From whom
        @param amount Amount to remove from the stake
    */
    function unstakeFrom(address payable account, uint256 amount) public onlyOwner nonReentrant {
        require(account != address(0), "Distribute: Invalid account");
        require(amount > 0, "Distribute: Amount must be greater than zero");
        uint256 stake = _stakes[account];
        require(amount <= stake, "Distribute: Dont have enough staked");
        uint256 to_reward = _getReward(account, amount);
        _total_staked -= amount;
        stake -= amount;
        _stakes[account] = stake;
        if(stake == 0) {
            staker_count--;
        }

        if(to_reward == 0) return;

        // void pending rewards
        pending_rewards[account] = 0;

        //take into account dust error during payment too
        if(address(reward_token) != address(0)) {
            reward_token.safeTransfer(account, to_reward);
        }
        else {
            Address.sendValue(account, to_reward);
        }
    }

     /**
        @dev Withdraws rewards (basically unstake then restake)
        @param account From whom
        @param amount Amount to remove from the stake
    */
    function withdrawFrom(address payable account, uint256 amount) external onlyOwner {
        unstakeFrom(account, amount);
        stakeFor(account, amount);
    }

    /**
        @dev Called contracts to distribute dividends
        Updates the bond value
        @param amount Amount of token to distribute
        @param from Address from which to take the token
    */
    function distribute(uint256 amount, address from) external payable onlyOwner nonReentrant {
        if(address(reward_token) != address(0)) {
            if(amount == 0) return;
            reward_token.safeTransferFrom(from, address(this), amount);
            require(msg.value == 0, "Distribute: Illegal distribution");
        } else {
            amount = msg.value;
        }
        // bond precision is always based on 1 unit of staked token
        uint256 total_bonds = _total_staked / 10**staking_decimals;

        if(total_bonds == 0) {
            // not enough staked to compute bonds account, put into temp pool
            _temp_pool = _temp_pool.add(amount);
            return;
        }

        // if a temp pool existed, add it to the current distribution
        if(_temp_pool > 0) {
            amount = amount.add(_temp_pool);
            _temp_pool = 0;
        }

        uint256 temp_to_distribute = to_distribute + amount;
        // bond value is always computed on decimals adjusted rewards
        uint256 bond_increase = temp_to_distribute * DECIMALS_ADJUSTMENT / total_bonds;
        // adjust back for distributed total
        uint256 distributed_total = total_bonds.mul(bond_increase) / DECIMALS_ADJUSTMENT;
        bond_value = bond_value.add(bond_increase);
        //collect the dust because of the PRECISION used for bonds
        //it will be reinjected into the next distribution
        to_distribute = temp_to_distribute - distributed_total;
    }

    /**
        @dev Returns the current total staked for an address
        @param account address owning the stake
        @return the total staked for this account
    */
    function totalStakedFor(address account) external view returns (uint256) {
        return _stakes[account];
    }
    
    /**
        @return current staked token
    */
    function totalStaked() external view returns (uint256) {
        return _total_staked;
    }

    /**
        @dev Returns how much the user can withdraw currently
        @param account Address of the user to check reward for
        @return the amount account will perceive if he unstakes now
    */
    function getReward(address account) public view returns (uint256) {
        return _getReward(account,_stakes[account]);
    }

    /**
        @dev returns the total amount of stored rewards
    */
    function getTotalReward() external view returns (uint256) {
        if(address(reward_token) != address(0)) {
            return reward_token.balanceOf(address(this));
        } else {
            return address(this).balance;
        }
    }

    /**
        @dev Returns how much the user can withdraw currently
        @param account Address of the user to check reward for
        @param amount Number of stakes
        @return reward the amount account will perceive if he unstakes now
    */
    function _getReward(address account, uint256 amount) internal view returns (uint256 reward) {
        // we apply decimals adjustement as bond value is computed on decimals adjusted rewards
        uint256 accountBonds = amount.divDown(10**staking_decimals);
        reward = accountBonds.mul(bond_value.sub(_bond_value_addr[account])).divDown(DECIMALS_ADJUSTMENT);
        // adding pending rewards
        reward = reward.add(pending_rewards[account]);
    }
}

interface IStakingDoubleERC20  {
    function forward() external;
}

interface ITrader {
    event Sale_EEFI(uint256 ampl_amount, uint256 eefi_amount);
    event Sale_OHM(uint256 ampl_amount, uint256 ohm_amount);

    function sellAMPLForOHM(uint256 amount, uint256 minimalExpectedAmount) external returns (uint256);
    function sellAMPLForEEFI(uint256 amount, uint256 minimalExpectedAmount) external returns (uint256);
}

/**
 * Helper inspired by waampl https://github.com/ampleforth/ampleforth-contracts/blob/master/contracts/waampl.sol
 * The goal is to wrap AMPL into non rebasing user shares
*/
abstract contract Wrapper {
    using Math for uint256;

    /// @dev The maximum waampl supply.
    uint256 public constant MAX_WAAMPL_SUPPLY = 10_000_000e12; // 10 M at 12 decimals
    IERC20 immutable public ampl;

    constructor(IERC20 _ampl) {
        require(address(_ampl) != address(0), "Wrapper: Invalid ampl token address");
        ampl = _ampl;
    }

    /// @dev Converts AMPLs to waampl amount.
    function _ampleTowaample(uint256 amples)
        internal
        view
        returns (uint208)
    {
        uint256 waamples = amples.mul(MAX_WAAMPL_SUPPLY).divDown(ampl.totalSupply());
        // maximum value is 10_000_000e12 and always fits into uint208
        require(waamples <= type(uint208).max, "Wrapper: waampl supply overflow");
        return uint208(waamples); 
    }
}

interface IEEFIToken {
    function mint(address account, uint256 amount) external;
    function burn(uint256 amount) external;
}

contract TokenStorage is Ownable {
    using SafeERC20 for IERC20;

    function claim(address token) external onlyOwner() {
        IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }
}

contract ElasticVault is AMPLRebaser, Wrapper, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using DepositsLinkedList for DepositsLinkedList.List;

    TokenStorage public token_storage;
    IStakingDoubleERC20 public staking_pool;
    ITrader public trader;
    ITrader pending_trader;
    address public authorized_trader;
    address public pending_authorized_trader;
    IERC20 public eefi_token;
    Distribute immutable public rewards_eefi;
    Distribute immutable public rewards_ohm;
    address payable public treasury;
    uint256 public last_positive = block.timestamp;
    uint256 public rebase_caller_reward = 0; // The amount of EEFI to be minted to the rebase caller as a reward
    IERC20 public constant ohm_token = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
    uint256 public trader_change_request_time;
    uint256 public authorized_trader_change_request_time;
    bool emergencyWithdrawalEnabled;
    
    /* 

    Parameter Definitions: //Parameters updated from v1 vault

    - EEFI Deposit Rate: Depositors receive reward of .0001 EEFI * Amount of AMPL user deposited into vault 
    - EEFI Negative Rebase Rate: When AMPL supply declines mint EEFI at rate of .000001 EEFI * total AMPL deposited into vault 
    - EEFI Equilibrium Rebase Rate: When AMPL supply is does not change (is at equilibrium) mint EEFI at a rate of .00001 EEFI * total AMPL deposited into vault 
    - Deposit FEE_10000: .65% of EEFI minted to user upon initial deposit is delivered to Treasury 
    - Lock Time: AMPL deposited into vault is locked for 90 days; lock time applies to each new AMPL deposit
    - Trade Posiitve EEFI_100: Upon positive rebase 45% of new AMPL supply (based on total AMPL in vault) is sold and used to buy EEFI 
    - Trade Positive OHM_100: Upon positive rebase 22% of the new AMPL supply (based on total AMPL in vault) is sold for OHM 
    - Trade Positive Treasury_100: Upon positive rebase 3% of new AMPL supply (based on total AMPL in vault) is sent to Treasury 
    - Trade Positive Rewards_100: Upon positive rebase, send 55% of OHM rewards to users staking AMPL in vault 
    - Trade Positive LP Staking_100: Upon positive rebase, send 35% of OHM rewards to users staking LP tokens (EEFI/OHM)
    - Trade Neutral/Negative Rewards: Upon neutral/negative rebase, send 55% of EEFI rewards to users staking AMPL in vault
    - Trade Neutral/Negative LP Staking: Upon neutral/negative rebase, send 35% of EEFI rewards to users staking LP tokens (EEFI/OHM)
    - Minting Decay: If AMPL does not experience a positive rebase (increase in AMPL supply) for 20 days, do not mint EEFI, distribute rewards to stakers
    - Treasury EEFI_100: Amount of EEFI distributed to DAO Treasury after EEFI buy and burn; 10% of purchased EEFI distributed to Treasury
    - Max Rebase Reward: Immutable maximum amount of EEFI that can be minted to rebase caller
    - Trader Change Cooldown: Cooldown period for updates to authorized trader address
    */

    uint256 constant public EEFI_DEPOSIT_RATE = 0.0001e8;
    uint256 constant public EEFI_NEGATIVE_REBASE_RATE = 0.000001e12;
    uint256 constant public EEFI_EQULIBRIUM_REBASE_RATE = 0.00001e10;
    uint256 constant public DEPOSIT_FEE_10000 = 0.0065e4;
    uint256 constant public LOCK_TIME = 90 days;
    uint256 constant public TRADE_POSITIVE_EEFI_100 = 45;
    uint256 constant public TRADE_POSITIVE_OHM_100 = 22;
    uint256 constant public TRADE_POSITIVE_TREASURY_100 = 3;
    uint256 constant public TRADE_POSITIVE_OHM_REWARDS_100 = 55;
    uint256 constant public TRADE_NEUTRAL_NEG_EEFI_REWARDS_100 = 55;
    uint256 constant public TRADE_POSITIVE_LPSTAKING_100 = 35; 
    uint256 constant public TRADE_NEUTRAL_NEG_LPSTAKING_100 = 35;
    uint256 constant public TREASURY_EEFI_100 = 10;
    uint256 constant public MINTING_DECAY = 20 days;
    uint256 constant public MAX_REBASE_REWARD = 2 ether; // 2 EEFI is the maximum reward for a rebase caller
    uint256 constant public CHANGE_COOLDOWN = 1 days;

    /* 
    Event Definitions:

    - Burn: EEFI burned (EEFI purchased using AMPL is burned)
    - Claimed: Rewards claimed by address 
    - Deposit: AMPL deposited by address 
    - Withdrawal: AMPL withdrawn by address 
    - StakeChanged: AMPL staked in contract; calculated as shares of total AMPL deposited 
    - RebaseRewardChanged: Amount of reward distributed to rebase caller changed; Reward amount cannot exceed MAX_REBASE_REWARD
    - TraderChangeRequest: Initates 1-day cooldown period to change authorized trader 
    - TraderChanged: Authorized trader contract changed
    - AuthorizedTraderChanged: EOA authorized to conduct trading operations changed 
    - EmergencyWithdrawal: Emergency withdrawal mode enabled (allows depositors to withdraw deposits before timelock expires)
    */

    event Burn(uint256 amount);
    event Claimed(address indexed account, uint256 ohm, uint256 eefi);
    event Deposit(address indexed account, uint256 amount, uint256 length);
    event Withdrawal(address indexed account, uint256 amount, uint256 length);
    event StakeChanged(uint256 total, uint256 timestamp);
    event RebaseRewardChanged(uint256 rebaseCallerReward);
    event TraderChangeRequest(address oldTrader, address newTrader);
    event AuthorizedTraderChangeRequest(address oldTrader, address newTrader);
    event TraderChanged(address trader);
    event AuthorizedTraderChanged(address trader);
    event EmergencyWithdrawal(bool enabled);

    mapping(address => DepositsLinkedList.List) private _deposits;
    
// Contract can mint new EEFI, and distribute OHM and EEFI rewards     
    constructor(IERC20 _eefi_token, IERC20 ampl_token)
    AMPLRebaser(ampl_token)
    Wrapper(ampl_token)
    Ownable() {
        require(address(_eefi_token) != address(0), "ElasticVault: Invalid eefi token");
        require(address(ampl_token) != address(0), "ElasticVault: Invalid ampl token");
        eefi_token = _eefi_token;
        // we're staking wampl which is 12 digits, reward eefi is 18 digits
        rewards_eefi = new Distribute(12, 18, IERC20(eefi_token));
        rewards_ohm = new Distribute(12, 9, IERC20(ohm_token));
        token_storage = new TokenStorage();
    }

    /**
     * @param account User address
     * @return total amount of shares owned by account
     */

    function totalStakedFor(address account) public view returns (uint256 total) {
        // if deposits are not initialized for this account then we have no deposits to sum
        if(_deposits[account].nodeIdCounter == 0) return 0;
        // use 0 as lock duration to sum all deposit amounts
        return _deposits[account].sumExpiredDeposits(0);
    }

    /**
        @return total The total amount of AMPL claimable by a user
    */
    function totalClaimableBy(address account) public view returns (uint256 total) {
        if(rewards_eefi.totalStaked() == 0) return 0;
        // only count expired deposits
        uint256 expired_amount = _deposits[account].sumExpiredDeposits(LOCK_TIME);
        total = _convertToAMPL(expired_amount);
    }

    /**
        @dev Current amount of AMPL owned by the user
        @param account Account to check the balance of
    */
    function balanceOf(address account) public view returns(uint256 ampl) {
        if(rewards_eefi.totalStaked() == 0) return 0;
        ampl = _convertToAMPL(rewards_eefi.totalStakedFor(account));
    }

    /**
        @dev Returns the first deposit of the user (frontend utility function)
        @param account Account to check the first deposit of
    */
    function firstDeposit(address account) public view returns (uint256 ampl, uint256 timestamp) {
        if(_deposits[account].nodeIdCounter == 0) return (0, 0);
        DepositsLinkedList.Deposit memory deposit = _deposits[account].getDepositById(_deposits[account].head);
        ampl = _convertToAMPL(deposit.amount);
        timestamp = deposit.timestamp;
    }

    /**
        @dev Called only once by the owner; this function sets up the vaults
        @param _staking_pool Address of the LP staking pool (EEFI/OHM Uniswap V2 LP token staking pool)
        @param _treasury Address of the treasury (Address of Elastic Finance DAO Treasury)
        @param _trader Address of the initial trader contract
    */
    function initialize(IStakingDoubleERC20 _staking_pool, address payable _treasury, address _trader) external
    onlyOwner() 
    {
        require(address(_staking_pool) != address(0), "ElasticVault: invalid staking pool");
        require(_treasury != address(0), "ElasticVault: invalid treasury");
        require(_trader != address(0), "ElasticVault: invalid trader");
        require(address(treasury) == address(0), "ElasticVault: contract already initialized");
        staking_pool = _staking_pool;
        treasury = _treasury;
        trader = ITrader(_trader);
    }

    /**
        @dev Request for contract owner to set and replace the contract used
        for trading AMPL, OHM and EEFI - Note: Trader update functionality intended to account for 
        future changes in AMPL liqudity distribution on DEXs.
        Additionally, the trader change request is subject to a 1 day cooldown
        @param _trader Address of the trader contract
    */
    function setTraderRequest(ITrader _trader) external onlyOwner() {
        require(address(_trader) != address(0), "ElasticVault: invalid trader");
        pending_trader = _trader;
        trader_change_request_time = block.timestamp;
        emit TraderChangeRequest(address(trader), address(pending_trader));
    }

    /**
        @dev Contract owner can set the trader contract after the cooldown period
    */
    function setTrader() external onlyOwner() {
        require(address(pending_trader) != address(0), "ElasticVault: invalid trader");
        require(block.timestamp > trader_change_request_time + CHANGE_COOLDOWN, "ElasticVault: Trader change cooldown");
        trader = pending_trader;
        pending_trader = ITrader(address(0));
        emit TraderChanged(address(trader));
    }

    /**
        Contract owner can enable or disable emergency withdrawal allowing users to withdraw their deposits before the end of lock time
        @param _emergencyWithdrawalEnabled Boolean to enable or disable emergency withdrawal
    */
    function setEmergencyWithdrawal(bool _emergencyWithdrawalEnabled) external onlyOwner() {
        emergencyWithdrawalEnabled = _emergencyWithdrawalEnabled;
        emit EmergencyWithdrawal(emergencyWithdrawalEnabled);
    }

    /**
        @dev Request for contract owner to set and replace the address authorized to call the sell function
        The change request is subject to a 1 day cooldown
        @param _authorized_trader Address of the authorized trader
    */
    function setAuthorizedTraderRequest(address _authorized_trader) external onlyOwner() {
        require(address(_authorized_trader) != address(0), "ElasticVault: invalid authorized trader");
        pending_authorized_trader = _authorized_trader;
        authorized_trader_change_request_time = block.timestamp;
        emit AuthorizedTraderChangeRequest(authorized_trader, pending_authorized_trader);
    }

    /**
        @dev Contract owner can set the authorized trader after the cooldown period
    */
    function setAuthorizedTrader() external onlyOwner() {
        require(address(pending_authorized_trader) != address(0), "ElasticVault: invalid trader");
        require(block.timestamp > authorized_trader_change_request_time + CHANGE_COOLDOWN, "ElasticVault: Trader change cooldown");
        authorized_trader = pending_authorized_trader;
        pending_authorized_trader = address(0);
        emit AuthorizedTraderChanged(authorized_trader);
    }

    /**
        @dev Deposits AMPL into the contract
        @param amount Amount of AMPL to take from the user
    */
    function makeDeposit(uint256 amount) _rebaseSynced() nonReentrant() external {
        ampl_token.safeTransferFrom(msg.sender, address(this), amount);
        uint208 waampl = _ampleTowaample(amount);
        // first deposit needs to initialize the linked list
        if(_deposits[msg.sender].nodeIdCounter == 0) {
            _deposits[msg.sender].initialize();
        }
        _deposits[msg.sender].insertEnd(DepositsLinkedList.Deposit({amount: waampl, timestamp:uint48(block.timestamp)}));

        uint256 to_mint = amount.mul(10**9).divDown(EEFI_DEPOSIT_RATE);
        uint256 deposit_fee = to_mint.mul(DEPOSIT_FEE_10000).divDown(10000);
        // Mint deposit reward to sender; send deposit fee to Treasury 
        if(last_positive + MINTING_DECAY > block.timestamp) { // if 20 days without positive rebase do not mint EEFI
            IEEFIToken(address(eefi_token)).mint(treasury, deposit_fee);
            IEEFIToken(address(eefi_token)).mint(msg.sender, to_mint.sub(deposit_fee));
        }
        
        // stake the shares also in the rewards pool
        rewards_eefi.stakeFor(msg.sender, waampl);
        rewards_ohm.stakeFor(msg.sender, waampl);
        emit Deposit(msg.sender, amount, _deposits[msg.sender].length);
        emit StakeChanged(rewards_ohm.totalStaked(), block.timestamp);
    }

    /**
        @dev Withdraw an amount of shares
        @param amount Amount of shares to withdraw
        !!! This isn't the amount of AMPL the user will get as we are using wrapped ampl to represent shares
    */
    function withdraw(uint256 amount) _rebaseSynced() nonReentrant() public returns (uint256 ampl_to_withdraw) {
        uint256 total_staked_user = rewards_eefi.totalStakedFor(msg.sender);
        require(amount <= total_staked_user, "ElasticVault: Not enough balance");
        uint256 to_withdraw = amount;
        // make sure the assets aren't time locked - all AMPL deposits into are locked for 90 days and withdrawal request will fail if timestamp of deposit < 90 days
        while(to_withdraw > 0) {
            // either liquidate the deposit, or reduce it
            if(_deposits[msg.sender].length > 0) {
                DepositsLinkedList.Deposit memory deposit = _deposits[msg.sender].getDepositById(_deposits[msg.sender].head);
                // if emergency withdrawal is enabled, allow the user to withdraw all of their deposits
                if(!emergencyWithdrawalEnabled) {
                    // if the first deposit is not unlocked return an error
                    require(deposit.timestamp < block.timestamp.sub(LOCK_TIME), "ElasticVault: No unlocked deposits found");
                }
                if(deposit.amount > to_withdraw) {
                    _deposits[msg.sender].modifyDepositAmount(_deposits[msg.sender].head, uint256(deposit.amount).sub(to_withdraw));
                    to_withdraw = 0;
                } else {
                    to_withdraw = to_withdraw.sub(deposit.amount);
                    _deposits[msg.sender].popHead();
                }
            }
            
        }
        // compute the current ampl count representing user shares
        ampl_to_withdraw = _convertToAMPL(amount);
        ampl_token.safeTransfer(msg.sender, ampl_to_withdraw);
        
        // unstake the shares also from the rewards pool
        rewards_eefi.unstakeFrom(msg.sender, amount);
        rewards_ohm.unstakeFrom(msg.sender, amount);
        emit Withdrawal(msg.sender, ampl_to_withdraw,_deposits[msg.sender].length);
        emit StakeChanged(totalStaked(), block.timestamp);
    }

    /**
    * AMPL share of the user based on the current stake
    * @param stake Amount of shares to convert to AMPL
    * @return Amount of AMPL the stake is worth
    */
    function _convertToAMPL(uint256 stake) internal view returns(uint256) {
        return ampl_token.balanceOf(address(this)).mul(stake).divDown(totalStaked());
    }

    /**
    * Change the rebase reward
    * @param new_rebase_reward New rebase reward
    !!!!!!!! This function is only callable by the owner
    */
    function setRebaseReward(uint256 new_rebase_reward) external onlyOwner() {
        require(new_rebase_reward <= MAX_REBASE_REWARD, "ElasticVault: invalid rebase reward"); //Max Rebase reward can't go above maximum 
        rebase_caller_reward = new_rebase_reward;
        emit RebaseRewardChanged(new_rebase_reward);
    }

    //Functions called depending on AMPL rebase status
    function _rebase(uint256 new_supply) internal override nonReentrant() {
        uint256 new_balance = ampl_token.balanceOf(address(this));

        if(new_supply > last_ampl_supply) {
            // This is a positive AMPL rebase and initates trading and distribuition of AMPL according to parameters (see parameters definitions)
            last_positive = block.timestamp;
            require(address(trader) != address(0), "ElasticVault: trader not set");

            uint256 changeRatio18Digits = last_ampl_supply.mul(10**18).divDown(new_supply);
            uint256 surplus = new_balance.sub(new_balance.mul(changeRatio18Digits).divDown(10**18));

            // transfer surplus to sell pool
            ampl_token.safeTransfer(address(token_storage), surplus);
        } else {
            // If AMPL supply is negative (lower) or equal (at eqilibrium/neutral), distribute EEFI rewards as follows; only if the minting_decay condition is not triggered
            if(last_positive + MINTING_DECAY > block.timestamp) { //if 45 days without positive rebase do not mint
                uint256 to_mint = new_balance.mul(10**9).divDown(new_supply < last_ampl_supply ? EEFI_NEGATIVE_REBASE_RATE : EEFI_EQULIBRIUM_REBASE_RATE); /*multiplying by 10^9 because EEFI is 18 digits and not 9*/
                IEEFIToken(address(eefi_token)).mint(address(this), to_mint);
                /* 
                EEFI Reward Distribution Overview: 

                - TRADE_Neutral_Neg_Rewards_100: Upon neutral/negative rebase, send 55% of EEFI rewards to users staking AMPL in vault 
                - Trade_Neutral_Neg_LPStaking_100: Upon neutral/negative rebase, send 35% of EEFI rewards to uses staking LP tokens (EEFI/OHM)  
                */


                uint256 to_rewards = to_mint.mul(TRADE_NEUTRAL_NEG_EEFI_REWARDS_100).divDown(100);
                uint256 to_lp_staking = to_mint.mul(TRADE_NEUTRAL_NEG_LPSTAKING_100).divDown(100);

                eefi_token.approve(address(rewards_eefi), to_rewards);
                eefi_token.safeTransfer(address(staking_pool), to_lp_staking); 

                rewards_eefi.distribute(to_rewards, address(this));
                staking_pool.forward(); 

                // distribute the remainder of EEFI to the treasury
                eefi_token.safeTransfer(treasury, eefi_token.balanceOf(address(this)));
            }
        }
        IEEFIToken(address(eefi_token)).mint(msg.sender, rebase_caller_reward);
    }

    /**
     * @param minimalExpectedEEFI Minimal amount of EEFI to be received from the trade
     * @param minimalExpectedOHM Minimal amount of OHM to be received from the trade
     !!!!!!!! This function is only callable by the authorized trader
    */
    function sell(uint256 minimalExpectedEEFI, uint256 minimalExpectedOHM) external nonReentrant() _onlyTrader() returns (uint256 eefi_purchased, uint256 ohm_purchased) {
        uint256 balance = ampl_token.balanceOf(address(token_storage));
        uint256 for_eefi = balance.mul(TRADE_POSITIVE_EEFI_100).divDown(100);
        uint256 for_ohm = balance.mul(TRADE_POSITIVE_OHM_100).divDown(100);
        uint256 for_treasury = balance.mul(TRADE_POSITIVE_TREASURY_100).divDown(100);

        token_storage.claim(address(ampl_token));

        ampl_token.approve(address(trader), for_eefi.add(for_ohm));
        // buy EEFI
        eefi_purchased = trader.sellAMPLForEEFI(for_eefi, minimalExpectedEEFI);
        // buy OHM
        ohm_purchased = trader.sellAMPLForOHM(for_ohm, minimalExpectedOHM);

        // 10% of purchased EEFI is sent to the DAO Treasury.
        IERC20(address(eefi_token)).safeTransfer(treasury, eefi_purchased.mul(TREASURY_EEFI_100).divDown(100));
        // burn the rest
        uint256 to_burn = eefi_token.balanceOf(address(this));
        emit Burn(to_burn);
        IEEFIToken(address(eefi_token)).burn(to_burn);
        
        // distribute ohm to vaults
        uint256 to_rewards = ohm_purchased.mul(TRADE_POSITIVE_OHM_REWARDS_100).divDown(100);
        uint256 to_lp_staking = ohm_purchased.mul(TRADE_POSITIVE_LPSTAKING_100).divDown(100);
        ohm_token.approve(address(rewards_ohm), to_rewards);
        rewards_ohm.distribute(to_rewards, address(this));
        ohm_token.safeTransfer(address(staking_pool), to_lp_staking);
        staking_pool.forward();

        // distribute the remainder of OHM to the DAO treasury
        ohm_token.safeTransfer(treasury, ohm_token.balanceOf(address(this)));
        // distribute the remainder of AMPL to the DAO treasury
        ampl_token.safeTransfer(treasury, for_treasury);
    }

    /**
     * Claims OHM and EEFI rewards for the user
    */
    function claim() external nonReentrant() { 
        (uint256 ohm, uint256 eefi) = getReward(msg.sender);
        rewards_ohm.withdrawFrom(msg.sender, rewards_ohm.totalStakedFor(msg.sender));
        rewards_eefi.withdrawFrom(msg.sender, rewards_eefi.totalStakedFor(msg.sender));
        emit Claimed(msg.sender, ohm, eefi);
    }

    /**
        @dev Returns how much OHM and EEFI the user can withdraw currently
        @param account Address of the user to check reward for
        @return ohm the amount of OHM the account will perceive if he unstakes now
        @return eefi the amount of tokens the account will perceive if he unstakes now
    */
    function getReward(address account) public view returns (uint256 ohm, uint256 eefi) { 
        ohm = rewards_ohm.getReward(account); 
        eefi = rewards_eefi.getReward(account);
    }

    /**
        @return current total amount of stakes
    */
    function totalStaked() public view returns (uint256) {
        return rewards_eefi.totalStaked();
    }

    /**
        @dev returns the total rewards stored for eefi and ohm
    */
    function totalReward() external view returns (uint256 ohm, uint256 eefi) {
        ohm = rewards_ohm.getTotalReward(); 
        eefi = rewards_eefi.getTotalReward();
    }

    /**
        @dev only authorized trader can call
    */
    modifier _onlyTrader() {
        require(msg.sender == authorized_trader, "ElasticVault: unauthorized");
        _;
    }

}