/**
 *Submitted for verification at Etherscan.io on 2023-07-13
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

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

// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

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
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
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

// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/draft-IERC20Permit.sol)

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// OpenZeppelin Contracts (last updated v4.8.0) (utils/Address.sol)

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
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
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
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
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
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
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
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
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
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}

// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/utils/SafeERC20.sol)

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

    function safePermit(
        IERC20Permit token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonceBefore = token.nonces(owner);
        token.permit(owner, spender, value, deadline, v, r, s);
        uint256 nonceAfter = token.nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
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
}

// https://github.com/Uniswap/permit2

/// @title SignatureTransfer
/// @notice Handles ERC20 token transfers through signature based actions
/// @dev Requires user's token approval on the Permit2 contract
interface ISignatureTransfer {

    /// @notice The token and amount details for a transfer signed in the permit transfer signature
    struct TokenPermissions {
        // ERC20 token address
        address token;
        // the maximum amount that can be spent
        uint256 amount;
    }

    /// @notice The signed permit message for a single token transfer
    struct PermitTransferFrom {
        TokenPermissions permitted;
        // a unique value for every token owner's signature to prevent signature replays
        uint256 nonce;
        // deadline on the permit signature
        uint256 deadline;
    }

    /// @notice Specifies the recipient address and amount for batched transfers.
    /// @dev Recipients and amounts correspond to the index of the signed token permissions array.
    /// @dev Reverts if the requested amount is greater than the permitted signed amount.
    struct SignatureTransferDetails {
        // recipient address
        address to;
        // spender requested amount
        uint256 requestedAmount;
    }

    /// @notice Used to reconstruct the signed permit message for multiple token transfers
    /// @dev Do not need to pass in spender address as it is required that it is msg.sender
    /// @dev Note that a user still signs over a spender address
    struct PermitBatchTransferFrom {
        // the tokens and corresponding amounts permitted for a transfer
        TokenPermissions[] permitted;
        // a unique value for every token owner's signature to prevent signature replays
        uint256 nonce;
        // deadline on the permit signature
        uint256 deadline;
    }
    /// @notice Transfers a token using a signed permit message
    /// @dev Reverts if the requested amount is greater than the permitted signed amount
    /// @param permit The permit data signed over by the owner
    /// @param owner The owner of the tokens to transfer
    /// @param transferDetails The spender's requested transfer details for the permitted token
    /// @param signature The signature to verify
    function permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;

    /// @notice Transfers multiple tokens using a signed permit message
    /// @param permit The permit data signed over by the owner
    /// @param owner The owner of the tokens to transfer
    /// @param transferDetails Specifies the recipient and requested amount for the token transfer
    /// @param signature The signature to verify
    function permitTransferFrom(
        PermitBatchTransferFrom memory permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}

// @dev interface for interacting with an Odos executor
interface IOdosExecutor {
  function executePath (
    bytes calldata bytecode,
    uint256[] memory inputAmount,
    address msgSender
  ) external payable;
}

/// @title Routing contract for Odos SOR
/// @author Semiotic AI
/// @notice Wrapper with security gaurentees around execution of arbitrary operations on user tokens
contract OdosRouterV2 is Ownable {
  using SafeERC20 for IERC20;

  /// @dev The zero address is uniquely used to represent eth since it is already
  /// recognized as an invalid ERC20, and due to its gas efficiency
  address constant _ETH = address(0);

  /// @dev Address list where addresses can be cached for use when reading from storage is cheaper
  // than reading from calldata. addressListStart is the storage slot of the first dynamic array element
  uint256 private constant addressListStart = 
    80084422859880547211683076133703299733277748156566366325829078699459944778998;
  address[] public addressList;

  // @dev constants for managing referrals and fees
  uint256 public constant REFERRAL_WITH_FEE_THRESHOLD = 1 << 31;
  uint256 public constant FEE_DENOM = 1e18;

  // @dev fee taken on multi-input and multi-output swaps instead of positive slippage
  uint256 public swapMultiFee;

  /// @dev Contains all information needed to describe the input and output for a swap
  struct permit2Info {
    address contractAddress;
    uint256 nonce;
    uint256 deadline;
    bytes signature;
  }
  /// @dev Contains all information needed to describe the input and output for a swap
  struct swapTokenInfo {
    address inputToken;
    uint256 inputAmount;
    address inputReceiver;
    address outputToken;
    uint256 outputQuote;
    uint256 outputMin;
    address outputReceiver;
  }
  /// @dev Contains all information needed to describe an intput token for swapMulti
  struct inputTokenInfo {
    address tokenAddress;
    uint256 amountIn;
    address receiver;
  }
  /// @dev Contains all information needed to describe an output token for swapMulti
  struct outputTokenInfo {
    address tokenAddress;
    uint256 relativeValue;
    address receiver;
  }
  // @dev event for swapping one token for another
  event Swap(
    address sender,
    uint256 inputAmount,
    address inputToken,
    uint256 amountOut,
    address outputToken,
    int256 slippage,
    uint32 referralCode
  );
  /// @dev event for swapping multiple input and/or output tokens
  event SwapMulti(
    address sender,
    uint256[] amountsIn,
    address[] tokensIn,
    uint256[] amountsOut,
    address[] tokensOut,
    uint32 referralCode
  );
  /// @dev Holds all information for a given referral
  struct referralInfo {
    uint64 referralFee;
    address beneficiary;
    bool registered;
  }
  /// @dev Register referral fee and information
  mapping(uint32 => referralInfo) public referralLookup;

  /// @dev Set the null referralCode as "Unregistered" with no additional fee
  constructor() {
    referralLookup[0].referralFee = 0;
    referralLookup[0].beneficiary = address(0);
    referralLookup[0].registered = true;

    swapMultiFee = 5e14;
  }
  /// @dev Must exist in order for contract to receive eth
  receive() external payable { }

  /// @notice Custom decoder to swap with compact calldata for efficient execution on L2s
  function swapCompact() 
    external
    payable
    returns (uint256)
  {
    swapTokenInfo memory tokenInfo;

    address executor;
    uint32 referralCode;
    bytes calldata pathDefinition;
    {
      address msgSender = msg.sender;

      assembly {
        // Define function to load in token address, either from calldata or from storage
        function getAddress(currPos) -> result, newPos {
          let inputPos := shr(240, calldataload(currPos))

          switch inputPos
          // Reserve the null address as a special case that can be specified with 2 null bytes
          case 0x0000 {
            newPos := add(currPos, 2)
          }
          // This case means that the address is encoded in the calldata directly following the code
          case 0x0001 {
            result := and(shr(80, calldataload(currPos)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            newPos := add(currPos, 22)
          }
          // Otherwise we use the case to load in from the cached address list
          default {
            result := sload(add(addressListStart, sub(inputPos, 2)))
            newPos := add(currPos, 2)
          }
        }
        let result := 0
        let pos := 4

        // Load in the input and output token addresses
        result, pos := getAddress(pos)
        mstore(tokenInfo, result)

        result, pos := getAddress(pos)
        mstore(add(tokenInfo, 0x60), result)

        // Load in the input amount - a 0 byte means the full balance is to be used
        let inputAmountLength := shr(248, calldataload(pos))
        pos := add(pos, 1)

        if inputAmountLength {
          mstore(add(tokenInfo, 0x20), shr(mul(sub(32, inputAmountLength), 8), calldataload(pos)))
          pos := add(pos, inputAmountLength)
        }

        // Load in the quoted output amount
        let quoteAmountLength := shr(248, calldataload(pos))
        pos := add(pos, 1)

        let outputQuote := shr(mul(sub(32, quoteAmountLength), 8), calldataload(pos))
        mstore(add(tokenInfo, 0x80), outputQuote)
        pos := add(pos, quoteAmountLength)

        // Load the slippage tolerance and use to get the minimum output amount
        {
          let slippageTolerance := shr(232, calldataload(pos))
          mstore(add(tokenInfo, 0xA0), div(mul(outputQuote, sub(0xFFFFFF, slippageTolerance)), 0xFFFFFF))
        }
        pos := add(pos, 3)

        // Load in the executor address
        executor, pos := getAddress(pos)

        // Load in the destination to send the input to - Zero denotes the executor
        result, pos := getAddress(pos)
        if eq(result, 0) { result := executor }
        mstore(add(tokenInfo, 0x40), result)

        // Load in the destination to send the output to - Zero denotes msg.sender
        result, pos := getAddress(pos)
        if eq(result, 0) { result := msgSender }
        mstore(add(tokenInfo, 0xC0), result)

        // Load in the referralCode
        referralCode := shr(224, calldataload(pos))
        pos := add(pos, 4)

        // Set the offset and size for the pathDefinition portion of the msg.data
        pathDefinition.length := mul(shr(248, calldataload(pos)), 32)
        pathDefinition.offset := add(pos, 1)
      }
    }
    return _swapApproval(
      tokenInfo,
      pathDefinition,
      executor,
      referralCode
    );
  }
  /// @notice Externally facing interface for swapping two tokens
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralCode referral code to specify the source of the swap
  function swap(
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    uint32 referralCode
  )
    external
    payable
    returns (uint256 amountOut)
  {
    return _swapApproval(
      tokenInfo,
      pathDefinition,
      executor,
      referralCode
    );
  }

  /// @notice Internal function for initiating approval transfers
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralCode referral code to specify the source of the swap
  function _swapApproval(
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    uint32 referralCode
  )
    internal
    returns (uint256 amountOut)
  {
    if (tokenInfo.inputToken == _ETH) {
      // Support rebasing tokens by allowing the user to trade the entire balance
      if (tokenInfo.inputAmount == 0) {
        tokenInfo.inputAmount = msg.value;
      } else {
        require(msg.value == tokenInfo.inputAmount, "Wrong msg.value");
      }
    }
    else {
      // Support rebasing tokens by allowing the user to trade the entire balance
      if (tokenInfo.inputAmount == 0) {
        tokenInfo.inputAmount = IERC20(tokenInfo.inputToken).balanceOf(msg.sender);
      }
      IERC20(tokenInfo.inputToken).safeTransferFrom(
        msg.sender,
        tokenInfo.inputReceiver,
        tokenInfo.inputAmount
      );
    }
    return _swap(
      tokenInfo,
      pathDefinition,
      executor,
      referralCode
    );
  }

  /// @notice Externally facing interface for swapping two tokens
  /// @param permit2 All additional info for Permit2 transfers
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralCode referral code to specify the source of the swap
  function swapPermit2(
    permit2Info memory permit2,
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    uint32 referralCode
  )
    external
    returns (uint256 amountOut)
  {
    ISignatureTransfer(permit2.contractAddress).permitTransferFrom(
      ISignatureTransfer.PermitTransferFrom(
        ISignatureTransfer.TokenPermissions(
          tokenInfo.inputToken,
          tokenInfo.inputAmount
        ),
        permit2.nonce,
        permit2.deadline
      ),
      ISignatureTransfer.SignatureTransferDetails(
        tokenInfo.inputReceiver,
        tokenInfo.inputAmount
      ),
      msg.sender,
      permit2.signature
    );
    return _swap(
      tokenInfo,
      pathDefinition,
      executor,
      referralCode
    );
  }

  /// @notice contains the main logic for swapping one token for another
  /// Assumes input tokens have already been sent to their destinations and
  /// that msg.value is set to expected ETH input value, or 0 for ERC20 input
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralCode referral code to specify the source of the swap
  function _swap(
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    uint32 referralCode
  )
    internal
    returns (uint256 amountOut)
  {
    // Check for valid output specifications
    require(tokenInfo.outputMin <= tokenInfo.outputQuote, "Minimum greater than quote");
    require(tokenInfo.outputMin > 0, "Slippage limit too low");
    require(tokenInfo.inputToken != tokenInfo.outputToken, "Arbitrage not supported");

    uint256 balanceBefore = _universalBalance(tokenInfo.outputToken);

    // Delegate the execution of the path to the specified Odos Executor
    uint256[] memory amountsIn = new uint256[](1);
    amountsIn[0] = tokenInfo.inputAmount;

    IOdosExecutor(executor).executePath{value: msg.value}(pathDefinition, amountsIn, msg.sender);

    amountOut = _universalBalance(tokenInfo.outputToken) - balanceBefore;

    if (referralCode > REFERRAL_WITH_FEE_THRESHOLD) {
      referralInfo memory thisReferralInfo = referralLookup[referralCode];

      _universalTransfer(
        tokenInfo.outputToken,
        thisReferralInfo.beneficiary,
        amountOut * thisReferralInfo.referralFee * 8 / (FEE_DENOM * 10)
      );
      amountOut = amountOut * (FEE_DENOM - thisReferralInfo.referralFee) / FEE_DENOM;
    }
    int256 slippage = int256(amountOut) - int256(tokenInfo.outputQuote);
    if (slippage > 0) {
      amountOut = tokenInfo.outputQuote;
    }
    require(amountOut >= tokenInfo.outputMin, "Slippage Limit Exceeded");

    // Transfer out the final output to the end user
    _universalTransfer(tokenInfo.outputToken, tokenInfo.outputReceiver, amountOut);

    emit Swap(
      msg.sender,
      tokenInfo.inputAmount,
      tokenInfo.inputToken,
      amountOut,
      tokenInfo.outputToken,
      slippage,
      referralCode
    );
  }

  /// @notice Custom decoder to swapMulti with compact calldata for efficient execution on L2s
  function swapMultiCompact() 
    external
    payable
    returns (uint256[] memory amountsOut)
  {
    address executor;
    uint256 valueOutMin;

    inputTokenInfo[] memory inputs;
    outputTokenInfo[] memory outputs;

    uint256 pos = 6;
    {
      address msgSender = msg.sender;

      uint256 numInputs;
      uint256 numOutputs;

      assembly {
        numInputs := shr(248, calldataload(4))
        numOutputs := shr(248, calldataload(5))
      }
      inputs = new inputTokenInfo[](numInputs);
      outputs = new outputTokenInfo[](numOutputs);

      assembly {
        // Define function to load in token address, either from calldata or from storage
        function getAddress(currPos) -> result, newPos {
          let inputPos := shr(240, calldataload(currPos))

          switch inputPos
          // Reserve the null address as a special case that can be specified with 2 null bytes
          case 0x0000 {
            newPos := add(currPos, 2)
          }
          // This case means that the address is encoded in the calldata directly following the code
          case 0x0001 {
            result := and(shr(80, calldataload(currPos)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            newPos := add(currPos, 22)
          }
          // Otherwise we use the case to load in from the cached address list
          default {
            result := sload(add(addressListStart, sub(inputPos, 2)))
            newPos := add(currPos, 2)
          }
        }
        executor, pos := getAddress(pos)

        // Load in the quoted output amount
        let outputMinAmountLength := shr(248, calldataload(pos))
        pos := add(pos, 1)

        valueOutMin := shr(mul(sub(32, outputMinAmountLength), 8), calldataload(pos))
        pos := add(pos, outputMinAmountLength)

        let result := 0
        let memPos := 0

        for { let element := 0 } lt(element, numInputs) { element := add(element, 1) }
        {
          memPos := mload(add(inputs, add(mul(element, 0x20), 0x20)))

          // Load in the token address
          result, pos := getAddress(pos)
          mstore(memPos, result)

          // Load in the input amount - a 0 byte means the full balance is to be used
          let inputAmountLength := shr(248, calldataload(pos))
          pos := add(pos, 1)

          if inputAmountLength {
             mstore(add(memPos, 0x20), shr(mul(sub(32, inputAmountLength), 8), calldataload(pos)))
            pos := add(pos, inputAmountLength)
          }
          result, pos := getAddress(pos)
          if eq(result, 0) { result := executor }

          mstore(add(memPos, 0x40), result)
        }
        for { let element := 0 } lt(element, numOutputs) { element := add(element, 1) }
        {
          memPos := mload(add(outputs, add(mul(element, 0x20), 0x20)))

          // Load in the token address
          result, pos := getAddress(pos)
          mstore(memPos, result)

          // Load in the quoted output amount
          let outputAmountLength := shr(248, calldataload(pos))
          pos := add(pos, 1)

          mstore(add(memPos, 0x20), shr(mul(sub(32, outputAmountLength), 8), calldataload(pos)))
          pos := add(pos, outputAmountLength)

          result, pos := getAddress(pos)
          if eq(result, 0) { result := msgSender }

          mstore(add(memPos, 0x40), result)
        }
      }
    }
    uint32 referralCode;
    bytes calldata pathDefinition;

    assembly {
      // Load in the referralCode
      referralCode := shr(224, calldataload(pos))
      pos := add(pos, 4)

      // Set the offset and size for the pathDefinition portion of the msg.data
      pathDefinition.length := mul(shr(248, calldataload(pos)), 32)
      pathDefinition.offset := add(pos, 1)
    }
    return _swapMultiApproval(
      inputs,
      outputs,
      valueOutMin,
      pathDefinition,
      executor,
      referralCode
    );
  }

  /// @notice Externally facing interface for swapping between two sets of tokens
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param valueOutMin minimum amount of value out the user will accept
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralCode referral code to specify the source of the swap
  function swapMulti(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    uint256 valueOutMin,
    bytes calldata pathDefinition,
    address executor,
    uint32 referralCode
  )
    external
    payable
    returns (uint256[] memory amountsOut)
  {
    return _swapMultiApproval(
      inputs,
      outputs,
      valueOutMin,
      pathDefinition,
      executor,
      referralCode
    );
  }

  /// @notice Internal logic for swapping between two sets of tokens with approvals
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param valueOutMin minimum amount of value out the user will accept
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralCode referral code to specify the source of the swap
  function _swapMultiApproval(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    uint256 valueOutMin,
    bytes calldata pathDefinition,
    address executor,
    uint32 referralCode
  )
    internal
    returns (uint256[] memory amountsOut)
  {
    // If input amount is still 0 then that means the maximum possible input is to be used
    uint256 expected_msg_value = 0;

    for (uint256 i = 0; i < inputs.length; i++) {
      if (inputs[i].tokenAddress == _ETH) {
        if (inputs[i].amountIn == 0) {
          inputs[i].amountIn = msg.value;
        }
        expected_msg_value = inputs[i].amountIn;
      } 
      else {
        if (inputs[i].amountIn == 0) {
          inputs[i].amountIn = IERC20(inputs[i].tokenAddress).balanceOf(msg.sender);
        }
        IERC20(inputs[i].tokenAddress).safeTransferFrom(
          msg.sender,
          inputs[i].receiver,
          inputs[i].amountIn
        );
      }
    }
    require(msg.value == expected_msg_value, "Wrong msg.value");

    return _swapMulti(
      inputs,
      outputs,
      valueOutMin,
      pathDefinition,
      executor,
      referralCode
    );
  }

  /// @notice Externally facing interface for swapping between two sets of tokens with Permit2
  /// @param permit2 All additional info for Permit2 transfers
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param valueOutMin minimum amount of value out the user will accept
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralCode referral code to specify the source of the swap
  function swapMultiPermit2(
    permit2Info memory permit2,
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    uint256 valueOutMin,
    bytes calldata pathDefinition,
    address executor,
    uint32 referralCode
  )
    external
    payable
    returns (uint256[] memory amountsOut)
  {
    ISignatureTransfer.PermitBatchTransferFrom memory permit;
    ISignatureTransfer.SignatureTransferDetails[] memory transferDetails;
    {
      uint256 permit_length = msg.value > 0 ? inputs.length - 1 : inputs.length;

      permit = ISignatureTransfer.PermitBatchTransferFrom(
        new ISignatureTransfer.TokenPermissions[](permit_length),
        permit2.nonce,
        permit2.deadline
      );
      transferDetails = 
        new ISignatureTransfer.SignatureTransferDetails[](permit_length);
    }
    {
      uint256 expected_msg_value = 0;
      for (uint256 i = 0; i < inputs.length; i++) {

        if (inputs[i].tokenAddress == _ETH) {
          if (inputs[i].amountIn == 0) {
            inputs[i].amountIn = msg.value;
          }
          expected_msg_value = inputs[i].amountIn;
        }
        else {
          if (inputs[i].amountIn == 0) {
            inputs[i].amountIn = IERC20(inputs[i].tokenAddress).balanceOf(msg.sender);
          }
          uint256 permit_index = expected_msg_value == 0 ? i : i - 1;

          permit.permitted[permit_index].token = inputs[i].tokenAddress;
          permit.permitted[permit_index].amount = inputs[i].amountIn;

          transferDetails[permit_index].to = inputs[i].receiver;
          transferDetails[permit_index].requestedAmount = inputs[i].amountIn;
        }
      }
      require(msg.value == expected_msg_value, "Wrong msg.value");
    }
    ISignatureTransfer(permit2.contractAddress).permitTransferFrom(
      permit,
      transferDetails,
      msg.sender,
      permit2.signature
    );
    return _swapMulti(
      inputs,
      outputs,
      valueOutMin,
      pathDefinition,
      executor,
      referralCode
    );
  }

  /// @notice contains the main logic for swapping between two sets of tokens
  /// assumes that inputs have already been sent to the right location and msg.value
  /// is set correctly to be 0 for no native input and match native inpuit otherwise
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param valueOutMin minimum amount of value out the user will accept
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralCode referral code to specify the source of the swap
  function _swapMulti(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    uint256 valueOutMin,
    bytes calldata pathDefinition,
    address executor,
    uint32 referralCode
  )
    internal
    returns (uint256[] memory amountsOut)
  {
    // Check for valid output specifications
    require(valueOutMin > 0, "Slippage limit too low");

    // Extract arrays of input amount values and tokens from the inputs struct list
    uint256[] memory amountsIn = new uint256[](inputs.length);
    address[] memory tokensIn = new address[](inputs.length);

    // Check input specification validity and transfer input tokens to executor
    {
      for (uint256 i = 0; i < inputs.length; i++) {

        amountsIn[i] = inputs[i].amountIn;
        tokensIn[i] = inputs[i].tokenAddress;

        for (uint256 j = 0; j < i; j++) {
          require(
            inputs[i].tokenAddress != inputs[j].tokenAddress,
            "Duplicate source tokens"
          );
        }
        for (uint256 j = 0; j < outputs.length; j++) {
          require(
            inputs[i].tokenAddress != outputs[j].tokenAddress,
            "Arbitrage not supported"
          );
        }
      }
    }
    // Check outputs for duplicates and record balances before swap
    uint256[] memory balancesBefore = new uint256[](outputs.length);
    for (uint256 i = 0; i < outputs.length; i++) {
      for (uint256 j = 0; j < i; j++) {
        require(
          outputs[i].tokenAddress != outputs[j].tokenAddress,
          "Duplicate destination tokens"
        );
      }
      balancesBefore[i] = _universalBalance(outputs[i].tokenAddress);
    }
    // Delegate the execution of the path to the specified Odos Executor
    IOdosExecutor(executor).executePath{value: msg.value}(pathDefinition, amountsIn, msg.sender);

    referralInfo memory thisReferralInfo;
    if (referralCode > REFERRAL_WITH_FEE_THRESHOLD) {
      thisReferralInfo = referralLookup[referralCode];
    }

    {
      uint256 valueOut;
      uint256 _swapMultiFee = swapMultiFee;
      amountsOut = new uint256[](outputs.length);

      for (uint256 i = 0; i < outputs.length; i++) {
        // Record the destination token balance before the path is executed
        amountsOut[i] = _universalBalance(outputs[i].tokenAddress) - balancesBefore[i];

        // Remove the swapMulti Fee (taken instead of positive slippage)
        amountsOut[i] = amountsOut[i] * (FEE_DENOM - _swapMultiFee) / FEE_DENOM;

        if (referralCode > REFERRAL_WITH_FEE_THRESHOLD) {
          _universalTransfer(
            outputs[i].tokenAddress,
            thisReferralInfo.beneficiary,
            amountsOut[i] * thisReferralInfo.referralFee * 8 / (FEE_DENOM * 10)
          );
          amountsOut[i] = amountsOut[i] * (FEE_DENOM - thisReferralInfo.referralFee) / FEE_DENOM;
        }
        _universalTransfer(
          outputs[i].tokenAddress,
          outputs[i].receiver,
          amountsOut[i]
        );
        // Add the amount out sent to the user to the total value of output
        valueOut += amountsOut[i] * outputs[i].relativeValue;
      }
      require(valueOut >= valueOutMin, "Slippage Limit Exceeded");
    }
    address[] memory tokensOut = new address[](outputs.length);
    for (uint256 i = 0; i < outputs.length; i++) {
        tokensOut[i] = outputs[i].tokenAddress;
    }
    emit SwapMulti(
      msg.sender,
      amountsIn,
      tokensIn,
      amountsOut,
      tokensOut,
      referralCode
    );
  }

  /// @notice Register a new referrer, optionally with an additional swap fee
  /// @param _referralCode the referral code to use for the new referral
  /// @param _referralFee the additional fee to add to each swap using this code
  /// @param _beneficiary the address to send the referral's share of fees to
  function registerReferralCode(
    uint32 _referralCode,
    uint64 _referralFee,
    address _beneficiary
  )
    external
  {
    // Do not allow for any overwriting of referral codes
    require(!referralLookup[_referralCode].registered, "Code in use");

    // Maximum additional fee a referral can set is 2%
    require(_referralFee <= FEE_DENOM / 50, "Fee too high");

    // Reserve the lower half of referral codes to be informative only
    if (_referralCode <= REFERRAL_WITH_FEE_THRESHOLD) {
      require(_referralFee == 0, "Invalid fee for code");
    } else {
      require(_referralFee > 0, "Invalid fee for code");

      // Make sure the beneficiary is not the null address if there is a fee
      require(_beneficiary != address(0), "Null beneficiary");
    }
    referralLookup[_referralCode].referralFee = _referralFee;
    referralLookup[_referralCode].beneficiary = _beneficiary;
    referralLookup[_referralCode].registered = true;
  }

  /// @notice Set the fee used for swapMulti
  /// @param _swapMultiFee the new fee for swapMulti
  function setSwapMultiFee(
    uint256 _swapMultiFee
  ) 
    external
    onlyOwner
  {
    // Maximum swapMultiFee that can be set is 0.5%
    require(_swapMultiFee <= FEE_DENOM / 200, "Fee too high");
    swapMultiFee = _swapMultiFee;
  }

  /// @notice Push new addresses to the cached address list for when storage is cheaper than calldata
  /// @param addresses list of addresses to be added to the cached address list
  function writeAddressList(
    address[] calldata addresses
  ) 
    external
    onlyOwner
  {
    for (uint256 i = 0; i < addresses.length; i++) {
      addressList.push(addresses[i]);
    }
  }

  /// @notice Allows the owner to transfer funds held by the router contract
  /// @param tokens List of token address to be transferred
  /// @param amounts List of amounts of each token to be transferred
  /// @param dest Address to which the funds should be sent
  function transferRouterFunds(
    address[] calldata tokens,
    uint256[] calldata amounts,
    address dest
  )
    external
    onlyOwner
  {
    require(tokens.length == amounts.length, "Invalid funds transfer");
    for (uint256 i = 0; i < tokens.length; i++) {
      _universalTransfer(
        tokens[i], 
        dest, 
        amounts[i] == 0 ? _universalBalance(tokens[i]) : amounts[i]
      );
    }
  }
  /// @notice Directly swap funds held in router 
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param valueOutMin minimum amount of value out the user will accept
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  function swapRouterFunds(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    uint256 valueOutMin,
    bytes calldata pathDefinition,
    address executor
  )
    external
    onlyOwner
    returns (uint256[] memory amountsOut)
  {
    uint256[] memory amountsIn = new uint256[](inputs.length);
    address[] memory tokensIn = new address[](inputs.length);

    for (uint256 i = 0; i < inputs.length; i++) {
      tokensIn[i] = inputs[i].tokenAddress;

      amountsIn[i] = inputs[i].amountIn == 0 ? 
        _universalBalance(tokensIn[i]) : inputs[i].amountIn;

      _universalTransfer(
        tokensIn[i],
        inputs[i].receiver,
        amountsIn[i]
      );
    }
    // Check outputs for duplicates and record balances before swap
    uint256[] memory balancesBefore = new uint256[](outputs.length);
    address[] memory tokensOut = new address[](outputs.length);
    for (uint256 i = 0; i < outputs.length; i++) {
      tokensOut[i] = outputs[i].tokenAddress;
      balancesBefore[i] = _universalBalance(tokensOut[i]);
    }
    // Delegate the execution of the path to the specified Odos Executor
    IOdosExecutor(executor).executePath{value: 0}(pathDefinition, amountsIn, msg.sender);

    uint256 valueOut;
    amountsOut = new uint256[](outputs.length);
    for (uint256 i = 0; i < outputs.length; i++) {

      // Record the destination token balance before the path is executed
      amountsOut[i] = _universalBalance(tokensOut[i]) - balancesBefore[i];

      _universalTransfer(
        outputs[i].tokenAddress,
        outputs[i].receiver,
        amountsOut[i]
      );
      // Add the amount out sent to the user to the total value of output
      valueOut += amountsOut[i] * outputs[i].relativeValue;
    }
    require(valueOut >= valueOutMin, "Slippage Limit Exceeded");

    emit SwapMulti(
      msg.sender,
      amountsIn,
      tokensIn,
      amountsOut,
      tokensOut,
      0
    );
  }
  /// @notice helper function to get balance of ERC20 or native coin for this contract
  /// @param token address of the token to check, null for native coin
  /// @return balance of specified coin or token
  function _universalBalance(address token) private view returns(uint256) {
    if (token == _ETH) {
      return address(this).balance;
    } else {
      return IERC20(token).balanceOf(address(this));
    }
  }
  /// @notice helper function to transfer ERC20 or native coin
  /// @param token address of the token being transferred, null for native coin
  /// @param to address to transfer to
  /// @param amount to transfer
  function _universalTransfer(address token, address to, uint256 amount) private {
    if (token == _ETH) {
      (bool success,) = payable(to).call{value: amount}("");
      require(success, "ETH transfer failed");
    } else {
      IERC20(token).safeTransfer(to, amount);
    }
  }
}