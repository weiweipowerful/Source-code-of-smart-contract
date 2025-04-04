/**
 *Submitted for verification at Etherscan.io on 2024-03-27
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IVShare {
    function stake(address _account, uint256 _amount) external;
    function unstake(address _account, uint256 _amount) external;
}
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

contract XCHNGStaking is Ownable {
    IERC20 public xchngToken;

    address public vShare;
    struct Stake {
        uint256 amount;
        uint256 lockedTime;
        uint256 unlockTime;
        uint256 vXCHNGAmount;
    }

    mapping( address => mapping (uint256 => Stake) ) public stakes;
    mapping (address => uint256 ) public stakeIndex;

    mapping(address => uint256) public vXCHNGBalance;
    uint256 public totalXCHNGStaked;
    uint256 public totalVXCHNGSupply;
    
    event Staked(address indexed user, uint256 amount, uint256 duration, uint256 vXCHNGAmount);
    event Unstaked(address indexed user, uint256 amount);

    constructor(address _xchngTokenAddress) Ownable(msg.sender) {
        xchngToken = IERC20(_xchngTokenAddress);
    }

    function setVShare(address _vShare) public onlyOwner {
        vShare = _vShare;
    }

    function stake(uint256 _amount, uint256 _duration) public {
        require(_amount > 0, "Amount must be greater than 0");
        uint256 _durationSeconds = _getDurationSeconds(_duration);
        require(_durationSeconds > 0, "Invalid duration");

        uint256 _vXCHNGAmount = _calculateVXCHNGAmount(_amount, _duration);
        uint256 _stakeIndex = stakeIndex[msg.sender];
        stakes[msg.sender][_stakeIndex] = Stake(_amount, block.timestamp,  block.timestamp + _durationSeconds, _vXCHNGAmount);
        stakeIndex[msg.sender] =  _stakeIndex + 1;

        vXCHNGBalance[msg.sender] += _vXCHNGAmount;
        totalXCHNGStaked += _amount;
       
        if(vShare != address(0)) IVShare(vShare).stake(msg.sender, _vXCHNGAmount);

        totalVXCHNGSupply += _vXCHNGAmount;
        require(xchngToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        emit Staked(msg.sender, _amount, _duration, _vXCHNGAmount);
    }

    function unstake(uint256 _stakeIndex) public {
        Stake memory _userStake = stakes[msg.sender][_stakeIndex];
        require(block.timestamp >= _userStake.unlockTime, "Stake is still locked");
        require(_userStake.amount > 0, "Empty stakeIndex");
        require(xchngToken.transfer(msg.sender, _userStake.amount), "Transfer failed");
        totalXCHNGStaked -= _userStake.amount;
        totalVXCHNGSupply -= _userStake.vXCHNGAmount;
        delete stakes[msg.sender][_stakeIndex];
        vXCHNGBalance[msg.sender] -= _userStake.vXCHNGAmount;
        if(vShare != address(0))  IVShare(vShare).unstake(msg.sender, _userStake.vXCHNGAmount);
        emit Unstaked(msg.sender, _userStake.amount);
    }

    function _getDurationSeconds(uint256 _duration) private pure returns (uint256) {
        if (_duration == 6) return 180 days;
        if (_duration == 12) return 365 days;
        if (_duration == 24) return 730 days;
        if (_duration == 48) return 1460 days;
        return 0;
    }

    function _calculateVXCHNGAmount(uint256 _amount, uint256 _duration) private pure returns (uint256) {
        if (_duration == 6) return _amount;
        if (_duration == 12) return _amount * 3 / 2;
        if (_duration == 24) return _amount * 3;
        if (_duration == 48) return _amount * 8;
        return 0;
    }
}