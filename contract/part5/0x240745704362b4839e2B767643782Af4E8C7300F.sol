// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

//
//░░██╗░░░░░░  ██╗░░██╗░█████╗░░█████╗░███╗░░██╗░█████╗░██╗░░██╗  ░░░░░░██╗░░
//░██╔╝░░░░░░  ██║░██╔╝██╔══██╗██╔══██╗████╗░██║██╔══██╗██║░░██║  ░░░░░░╚██╗░
//██╔╝░█████╗  █████═╝░███████║███████║██╔██╗██║██║░░╚═╝███████║  █████╗░╚██╗
//╚██╗░╚════╝  ██╔═██╗░██╔══██║██╔══██║██║╚████║██║░░██╗██╔══██║  ╚════╝░██╔╝
//░╚██╗░░░░░░  ██║░╚██╗██║░░██║██║░░██║██║░╚███║╚█████╔╝██║░░██║  ░░░░░░██╔╝░
//░░╚═╝░░░░░░  ╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝░╚════╝░╚═╝░░╚═╝  ░░░░░░╚═╝░░
//Kaanch.com
//New Layer1 Blockchain with 1.4M TPS, 3600 Node, 0.8 Sec Block Timing & Near Zero Gas Fees


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

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// File @openzeppelin/contracts/access/[email protected]

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;

abstract contract Ownable is Context {
    address private immutable _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev Initializes the contract setting the deployer as the owner.
     */
    constructor(address initialOwner) {
        require(initialOwner != address(0), "Ownable: Invalid owner address");
        _owner = initialOwner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        if (_owner != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }
}

// File @openzeppelin/contracts/token/ERC20/[email protected]

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

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
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

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
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

// File @openzeppelin/contracts/utils/[email protected]

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/Address.sol)

pragma solidity ^0.8.20;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedInnerCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(
            data
        );
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(
        address target,
        bytes memory data
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedInnerCall}) in case of an
     * unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata
    ) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

// File @openzeppelin/contracts/token/ERC20/utils/[email protected]

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.20;

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

    /**
     * @dev An operation with an ERC20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(
        address spender,
        uint256 currentAllowance,
        uint256 requestedDecrease
    );

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeCall(token.transferFrom, (from, to, value))
        );
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     */
    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 requestedDecrease
    ) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(
                    spender,
                    currentAllowance,
                    requestedDecrease
                );
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     */
    function forceApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        bytes memory approvalCall = abi.encodeCall(
            token.approve,
            (spender, value)
        );

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(
                token,
                abi.encodeCall(token.approve, (spender, 0))
            );
            _callOptionalReturn(token, approvalCall);
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
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silents catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(
        IERC20 token,
        bytes memory data
    ) private returns (bool) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We cannot use {Address-functionCall} here since this should return false
        // and not revert is the subcall reverts.

        (bool success, bytes memory returndata) = address(token).call(data);
        return
            success &&
            (returndata.length == 0 || abi.decode(returndata, (bool))) &&
            address(token).code.length > 0;
    }
}

pragma solidity ^0.8.0;

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

// Original license: SPDX_License_Identifier: MIT

pragma solidity ^0.8.20;

contract KaanchPresale is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    uint256 public rate;

    address public saleToken;
    uint public saleTokenDec;

    uint256 public totalTokensforSale;

    mapping(address => bool) public payableTokens;

    mapping(address => uint256) public tokenPrices;

    bool public saleStatus;

    address[] public buyers;

    mapping(address => bool) public buyersExists;
    mapping(address => uint256) public buyersAmount;

    uint256 public totalBuyers;
    uint256 public totalTokensSold;

    address public ICO;
    address public DEV;

    struct BuyerDetails {
        address buyer;
        uint amount;
    }

    event BuyToken(
        address indexed buyer,
        address indexed token,
        uint256 paidAmount,
        uint256 purchasedAmount
    );

    constructor(
        address _ICO,
        address _DEV
    ) Ownable(msg.sender) {
        saleStatus = false;
        ICO = _ICO;
        DEV = _DEV;
    }

    modifier saleEnabled() {
        require(saleStatus == true, "Kaanch: is not enabled");
        _;
    }

    modifier saleStoped() {
        require(saleStatus == false, "Kaanch: is not stopped");
        _;
    }

    function setSaleToken(
        address _saleToken,
        uint256 _totalTokensforSale,
        uint256 _rate,
        bool _saleStatus
    ) external onlyOwner {
        require(_rate != 0);
        rate = _rate;
        saleToken = _saleToken;
        saleStatus = _saleStatus;
        saleTokenDec = IERC20Metadata(_saleToken).decimals();
        totalTokensforSale = _totalTokensforSale;

        IERC20(_saleToken).safeTransferFrom(
            msg.sender,
            address(this),
            _totalTokensforSale
        );
    }

    function stopSale() external onlyOwner saleEnabled {
        saleStatus = false;
    }

    function resumeSale() external onlyOwner saleStoped {
        saleStatus = true;
    }

    function addPayableTokens(
        address[] memory _tokens,
        uint256[] memory _prices
    ) external onlyOwner {
        require(
            _tokens.length == _prices.length,
            "Kaanch: tokens & prices arrays length mismatch"
        );

        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_prices[i] != 0);
            payableTokens[_tokens[i]] = true;
            tokenPrices[_tokens[i]] = _prices[i];
        }
    }

    function payableTokenStatus(
        address _token,
        bool _status
    ) external onlyOwner {
        require(payableTokens[_token] != _status);

        payableTokens[_token] = _status;
    }

    function updateTokenRate(
        address[] memory _tokens,
        uint256[] memory _prices,
        uint256 _rate
    ) external onlyOwner {
        require(
            _tokens.length == _prices.length,
            "Kaanch: tokens & prices arrays length mismatch"
        );

        if (_rate != 0) {
            rate = _rate;
        }

        for (uint256 i = 0; i < _tokens.length; i += 1) {
            require(payableTokens[_tokens[i]] == true);
            require(_prices[i] != 0);
            tokenPrices[_tokens[i]] = _prices[i];
        }
    }

    function getTokenAmount(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        uint256 amtOut;
        if (token != address(0)) {
            require(
                payableTokens[token] == true,
                "Kaanch: Token not allowed"
            );
            uint256 price = tokenPrices[token];
            amtOut = (amount * (10 ** saleTokenDec)) / (price);
        } else {
            amtOut = (amount * (10 ** saleTokenDec)) / (rate);
        }
        return amtOut;
    }

    function getPayAmount(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        uint256 amtOut;
        if (token != address(0)) {
            require(
                payableTokens[token] == true,
                "Kaanch: Token not allowed"
            );
            uint256 price = tokenPrices[token];
            amtOut = (amount * (price)) / (10 ** saleTokenDec);
        } else {
            amtOut = (amount * (rate)) / (10 ** saleTokenDec);
        }
        return amtOut;
    }

    function transferETH(uint256 _amount) internal {
        uint256 DEVAmt = (_amount * 5) / 100;
        payable(DEV).transfer(DEVAmt);
        payable(ICO).transfer(_amount - DEVAmt);
    }

    function transferToken(address _token, uint256 _amount) internal {
        uint256 DEVAmt = (_amount * 5) / 100;
        IERC20(_token).safeTransferFrom(
            msg.sender,
            DEV,
            DEVAmt
        );
        IERC20(_token).safeTransferFrom(
            msg.sender,
            ICO,
            _amount - DEVAmt
        );
    }

    function buyToken(
        address _token,
        uint256 _amount
    ) external payable saleEnabled {
        uint256 amount = _token != address(0) ? _amount : msg.value;
        uint256 saleTokenAmt = getTokenAmount(_token, amount);

        require(saleTokenAmt != 0, "Kaanch: Amount is 0");
        require(
            (totalTokensSold + saleTokenAmt) < totalTokensforSale,
            "Kaanch: Not enough tokens to be sold"
        );

        if (_token != address(0)) {
            transferToken(_token, _amount);
        } else {
            transferETH(msg.value);
        }

        IERC20(saleToken).safeTransfer(msg.sender, saleTokenAmt);

        totalTokensSold += saleTokenAmt;

        if (!buyersExists[msg.sender]) {
            buyers.push(msg.sender);
            buyersExists[msg.sender] = true;
            totalBuyers += 1;
        }

        buyersAmount[msg.sender] += saleTokenAmt;

        emit BuyToken(msg.sender, _token, amount, saleTokenAmt);
    }

    function buyersDetailsList(
        uint _from,
        uint _to
    ) external view returns (BuyerDetails[] memory) {
        require(_from < _to, "Kaanch: _from should be less than _to");

        uint to = _to > totalBuyers ? totalBuyers : _to;
        uint from = _from > totalBuyers ? totalBuyers : _from;

        BuyerDetails[] memory buyersAmt = new BuyerDetails[](to - from);

        for (uint i = from; i < to; i += 1) {
            buyersAmt[i] = BuyerDetails(buyers[i], buyersAmount[buyers[i]]);
        }

        return buyersAmt;
    }

    function withdrawFunds(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            // Withdraw Ether
            uint256 balance = address(this).balance;
            require(
                balance >= amount,
                "KaanchPresale: Insufficient Ether balance"
            );
            payable(owner()).transfer(amount);
        } else {
            // Withdraw ERC20 tokens
            uint256 balance = IERC20(token).balanceOf(address(this));
            require(
                balance >= amount,
                "KaanchPresale: Insufficient token balance"
            );
            IERC20(token).safeTransfer(owner(), amount);
        }
    }
}