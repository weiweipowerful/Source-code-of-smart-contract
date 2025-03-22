/**
 *Submitted for verification at Etherscan.io on 2025-03-17
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}


abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
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
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
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
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    bool internal locked;

    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }
}

contract RichPresale is ReentrancyGuard, Ownable {
    IUniswapV2Pair public uniswapPair;
    IERC20 public token;
    address public usdt = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address public tokenAddress = address(0xe84F1953DE8D9D28E3E53a14D5f9e32Ec9A179d7);
    address public uniswapETHUSDTPairAddress = address(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852);
    address public BankAddress = address(0xec2D05b7802C93309B1Ad8A399598739A554fDa4);

    uint256 public tokenPrice = 200000;

    uint256 public MIN_PURCHASE = 0.1 ether;
    uint256 public MAX_PURCHASE = 25 ether;

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }
    bool public paused = false;

    event Paused(address account);
    event Unpaused(address account);
    event Buy(address indexed  account, uint256 ethAmount, uint256 tokenAmount, uint256 dateTime);

    constructor() {
        token = IERC20(tokenAddress);
        uniswapPair = IUniswapV2Pair(uniswapETHUSDTPairAddress);
    }

    receive() external payable {
        buyTokens();
    }

    function getEthPrice() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = uniswapPair.getReserves();
        address token0 = uniswapPair.token0();
        uint256 price;
        if (token0 == usdt) {
            price = (uint256(reserve0) * (10 ** 20)) / uint256(reserve1);
        } else if (uniswapPair.token1() == usdt) {
            price = (uint256(reserve1) * (10 ** 20)) / uint256(reserve0);
        } else {
            revert("USDT not found in the pair");
        }
        return price;
    }

    function buyTokens() public payable noReentrant whenNotPaused {
        require(msg.value >= MIN_PURCHASE, "Under Minimum purchase");
        require(msg.value <= MAX_PURCHASE, "Above Maximum purchase");

        uint256 ethPrice = getEthPrice();
        uint256 usdAmount = (msg.value * ethPrice) / 1e18;
        uint256 tokensToTransfer = (usdAmount * 1e18) / tokenPrice;
        require(tokensToTransfer > 0, "Insufficient ETH for token purchase");

        require(token.transfer(msg.sender, tokensToTransfer), "Token transfer failed");

        (bool success, ) = BankAddress.call{value: msg.value}("");
        require(success, "ETH transfer failed");

        emit Buy(msg.sender, msg.value, tokensToTransfer, block.timestamp);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function setMinMax(uint256 min, uint256 max) external onlyOwner {
        MIN_PURCHASE = min;
        MAX_PURCHASE = max;
    }

    function withdrawCoin(address destination) public onlyOwner {
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "No ETH to withdraw");
        (bool success, ) = destination.call{value: ethBalance}("");
        require(success, "ETH withdrawal failed");
    }

    function withdrawNativeToken(address destination) public onlyOwner {
        IERC20 tokenContract = IERC20(tokenAddress);
        uint256 tokenBalance = tokenContract.balanceOf(address(this));
        require(tokenBalance > 0, "No token to withdraw");
        require(tokenContract.transfer(destination, tokenBalance), "Token withdrawal failed");
    }

    function withdrawERC20Token(address _token, address destination) public onlyOwner {
        IERC20 tokenContract = IERC20(_token);
        uint256 tokenBalance = tokenContract.balanceOf(address(this));
        require(tokenBalance > 0, "No token to withdraw");
        require(tokenContract.transfer(destination, tokenBalance), "Token withdrawal failed");
    }
}