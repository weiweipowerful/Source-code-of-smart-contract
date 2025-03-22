// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract XUSDPDeposit {
    address public owner;
    IERC20 public token;

    // Mapping to store total deposits per wallet
    mapping(address => uint256) public totalDeposits;

    // Total overall deposits from all wallets
    uint256 public overallDeposits;

    // Reentrancy guard per wallet
    mapping(address => bool) private walletLock;

    event Deposit(
        address indexed depositor,
        uint256 amount,
        uint256 totalAmount,
        uint256 overallDeposits,
        uint256 timestamp
    );

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    modifier noReentrancy() {
        require(!walletLock[msg.sender], "Reentrant call detected");
        walletLock[msg.sender] = true;
        _;
        walletLock[msg.sender] = false;
    }

    constructor(address _token) {
        require(_token != address(0), "Token address cannot be zero");
        owner = msg.sender;
        token = IERC20(_token);
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @dev Allows a user to deposit ERC20 tokens.
     * Records total deposited amount per wallet and overall.
     */
    function depositToken(uint256 _amount) external noReentrancy {
        require(_amount > 0, "Amount must be greater than zero");

        bool success = token.transferFrom(msg.sender, address(this), _amount);
        require(success, "Token transfer failed");

        // Update user's total deposits
        totalDeposits[msg.sender] += _amount;

        // Update overall deposits
        overallDeposits += _amount;

        emit Deposit(
            msg.sender, 
            _amount, 
            totalDeposits[msg.sender], 
            overallDeposits, 
            block.timestamp
        );
    }

    /**
     * @dev Allows the owner to transfer ownership.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Returns the balance of the token in this contract.
     */
    function contractBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @dev Allows the owner to withdraw ERC20 tokens from the contract.
     */
    function withdrawTokens(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Amount must be greater than zero");

        bool success = token.transfer(owner, _amount);
        require(success, "Token withdrawal failed");
    }

    /**
     * @dev Returns the total deposits made by a user.
     */
    function getTotalDeposits(address user) external view returns (uint256) {
        return totalDeposits[user];
    }
}