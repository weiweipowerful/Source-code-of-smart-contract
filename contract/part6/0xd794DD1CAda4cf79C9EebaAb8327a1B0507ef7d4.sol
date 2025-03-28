/**
 *Submitted for verification at Etherscan.io on 2020-10-12
*/

pragma solidity 0.7.3;


abstract contract Context {
    function _msgSender() 
        internal
        view 
        virtual
        returns (address payable) 
    {
        return msg.sender;
    }

    function _msgData() 
        internal
        view 
        virtual 
        returns (bytes memory) 
    {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}


interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


library SafeMath {
    function add(
        uint256 a, 
        uint256 b
    ) 
        internal 
        pure 
        returns (uint256) 
    {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(
        uint256 a, 
        uint256 b
    ) 
        internal 
        pure 
        returns (uint256) 
    {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a, 
        uint256 b, 
        string memory errorMessage
    ) 
        internal 
        pure 
        returns (uint256) 
    {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(
        uint256 a, 
        uint256 b
    ) 
        internal 
        pure 
        returns (uint256) 
    {
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

    function div(
        uint256 a, 
        uint256 b
    ) 
        internal 
        pure 
        returns (uint256) 
    {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(
        uint256 a, 
        uint256 b, 
        string memory errorMessage
    ) 
        internal 
        pure 
        returns (uint256) 
    {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(
        uint256 a, 
        uint256 b
    ) 
        internal 
        pure 
        returns (uint256) 
    {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(
        uint256 a, 
        uint256 b, 
        string memory errorMessage
    ) 
        internal 
        pure 
        returns (uint256) 
    {
        require(b != 0, errorMessage);
        return a % b;
    }
}


library Address {
    function isContract(
        address account
    ) 
        internal 
        view 
        returns (bool) 
    {
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    function sendValue(
        address payable recipient, 
        uint256 amount
    ) 
        internal 
    {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(
        address target, 
        bytes memory data
    ) 
        internal 
        returns (bytes memory) 
    {
      return functionCall(target, data, "Address: low-level call failed");
    }

   function functionCall(
       address target, 
       bytes memory data, 
       string memory errorMessage
    ) 
        internal 
        returns (bytes memory) 
    {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target, 
        bytes memory data, 
        uint256 value
    ) 
        internal 
        returns (bytes memory) 
    {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target, 
        bytes memory data, 
        uint256 value, 
        string memory errorMessage
    ) 
        internal 
        returns (bytes memory) 
    {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(
        address target, 
        bytes memory data, 
        uint256 weiValue, 
        string memory errorMessage
    ) 
        private 
        returns (bytes memory) 
    {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
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


abstract contract Ownable is Context {
    address public owner;
    address public pendingOwner;

    event OwnershipTransferred(
        address indexed previousOwner, 
        address indexed newOwner
    );

    constructor () {
        address msgSender = _msgSender();
        owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    modifier onlyOwner() {
        require(owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(
        address newOwner
    ) 
        onlyOwner 
        external 
    {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        pendingOwner = newOwner;
     }
    
     function claimOwnership() 
        external 
    {
        require(_msgSender() == pendingOwner);
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
     }
}


abstract contract Pausable is Ownable {
    event Pause();
    event Unpause();

    bool public paused = true;

    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    modifier whenPaused() {
        require(paused);
        _;
    }

    function pause() 
        onlyOwner 
        whenNotPaused 
        external 
    {
        paused = true;
        emit Pause();
    }

    function unpause()
        onlyOwner 
        whenPaused 
        external 
    {
        paused = false;
        emit Unpause();
    }
}


abstract contract Whitelist is Pausable {
    mapping(address => bool) public whitelist;
    mapping(address => bool) public blacklist;

    modifier isWhitelisted() {
        require(whitelist[_msgSender()]);
        _;
    }
  
    modifier isBlacklisted() {
        require(blacklist[_msgSender()]);
        _;
    }

    function addWhitelist(
        address account
    ) 
        public 
        onlyOwner 
    {
        whitelist[account] = true;
    }
    
    function removeWhitelist(
        address account
    ) 
        public 
        onlyOwner 
    {
        whitelist[account] = false;
    }

    function addBlacklist(
        address account
    ) 
        public 
        onlyOwner 
    {
        blacklist[account] = true;
    }

    function removeBlacklist(
        address account
    ) 
        public 
        onlyOwner 
    {
        blacklist[account] = false;
    }
}


abstract contract ERC20 is Whitelist, IERC20 {
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string internal _name;
    string internal _symbol;
    string internal _website;
    uint8 private _decimals;

    constructor (
        string memory name, 
        string memory symbol
    ) {
        _name = name;
        _symbol = symbol;
        _decimals = 18;
    }

    function name() 
        public 
        view 
        returns (string memory)
    {
        return _name;
    }

    function symbol() 
        public 
        view 
        returns (string memory) 
    {
        return _symbol;
    }
    
    function website() 
        public 
        view 
        returns (string memory) 
    {
        return _website;
    }

    function decimals() 
        public 
        view 
        returns (uint8) 
    {
        return _decimals;
    }

    function totalSupply() 
        public 
        view 
        override 
        returns (uint256) 
    {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) 
        public 
        view 
        override 
        returns (uint256) 
    {
        return _balances[account];
    }

    function transfer(
        address recipient, 
        uint256 amount
    ) 
        public 
        virtual 
        override 
        returns (bool) 
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    
    function allowance(
        address owner, 
        address spender
    ) 
        public 
        view 
        virtual 
        override 
        returns (uint256) 
    {
        return _allowances[owner][spender];
    }

    function approve(
        address spender, 
        uint256 amount
    ) 
        public 
        virtual 
        override 
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender, 
        address recipient, 
        uint256 amount
    ) 
        public 
        virtual 
        override 
        returns (bool) 
    {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(
        address spender, 
        uint256 addedValue
    ) 
        public 
        virtual 
        returns (bool) 
    {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(
        address spender, 
        uint256 subtractedValue
    ) 
        public 
        virtual 
        returns (bool) 
    {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function _transfer(
        address sender, 
        address recipient, 
        uint256 amount
    ) 
        canTransfer
        internal 
        virtual 
    {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(
        address account, 
        uint256 amount
    ) 
        internal 
        virtual 
    {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(
        address account, 
        uint256 amount
    ) 
        internal 
        virtual 
    {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner, 
        address spender, 
        uint256 amount
    ) 
        internal 
        virtual 
    {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    modifier canTransfer() 
    {
        address msgSender = _msgSender();
        require(whitelist[msgSender] || !paused);
        require(!blacklist[msgSender]);
        _;
    }

    function _setupDecimals(
        uint8 decimals_
    ) 
        internal 
    {
        _decimals = decimals_;
    }

    function _beforeTokenTransfer(
        address from, 
        address to, 
        uint256 amount
    ) 
        internal 
        virtual 
    { 
        
    }
}


contract HYVE is ERC20("HYVE", "HYVE") {
    function mint(
        address _to, 
        uint256 _amount
    ) 
        public 
        onlyOwner 
    {
        _mint(_to, _amount);
    }
    
    function burn(
        address _from, 
        uint256 _amount
    ) 
        public 
        onlyOwner 
    {
        _burn(_from, _amount);
    }
    
    function setName(
        string memory _newName
    ) 
        public 
        onlyOwner 
    {
       _name = _newName;
    } 
    
    function setSymbol(
        string memory _newSymbol
    ) 
        public 
        onlyOwner 
    {
       _symbol = _newSymbol;
    } 
    
    function setWebsite(
        string memory _newWebsite
    ) 
        public 
        onlyOwner 
    {
       _website = _newWebsite;
    }
    
    function tokenFallback(
        address _from, 
        uint256 _value, 
        bytes memory _data
    ) 
        public 
    {
        revert();
    }
    
    function takeOut(
        IERC20 _token, 
        uint256 _amount
    ) 
        external 
        onlyOwner 
    {
        _token.transfer(owner, _amount);
    }
}