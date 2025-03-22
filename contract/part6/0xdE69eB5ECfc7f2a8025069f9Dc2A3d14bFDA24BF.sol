/**
 *Submitted for verification at Etherscan.io on 2025-02-22
*/

/**
 *Submitted for verification at BscScan.com on 2024-12-17
*/

// SPDX-License-Identifier: MIT
// File: @openzeppelin/contracts/utils/Context.sol


// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

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

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
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
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
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

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
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
    function allowance(address owner, address spender) external view returns (uint256);

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
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// File: @openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol


// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity ^0.8.20;


/**
 * @dev Interface for the optional metadata functions from the ERC-20 standard.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// File: @chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol


pragma solidity ^0.8.0;

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(
    uint80 _roundId
  ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// File: presale.sol


pragma solidity ^0.8.20;





contract VULPEPRESALE is Ownable {
    IERC20 public token;
    IERC20Metadata public tokenMetadata;
    AggregatorV3Interface public priceFeed;
    address public sellerAddress;
    address public paymentAddress;
    address public UsdtAddress;
    bool public presaleActive = true;
    uint256 public totalSold = 0;

    struct Stage {
        uint256 id;
        uint256 price;
        uint256 maxTokens;
        uint256 tokensSold;
        bool active;
    }

    struct SaleRecord {
        uint256 stageId;
        uint256 tokensSold;
        address buyer;
    }

    mapping(address => SaleRecord[]) public referallSalesRecords;

    mapping(uint256 => Stage) public stages;
    uint256 public maxStage = 10;
    uint256 currentStageId = 0;

    /***
     * constructor
     */
    constructor(
        address _seller,
        address _payment,
        address _token
    ) Ownable(msg.sender) {
        transferOwnership(0x8aB654A21D8AC187F94fac01CEbbFCcd575d6C55);
        token = IERC20(_token);
        tokenMetadata = IERC20Metadata(_token);
        sellerAddress = _seller;
        paymentAddress = _payment;
        if (block.chainid == 56) {
            UsdtAddress = 0x55d398326f99059fF775485246999027B3197955; // USDT na BSC
            priceFeed = AggregatorV3Interface(
                0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE
            ); // ETH/USD na BSC
        } else if (block.chainid == 1) {
            UsdtAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT na Ethereum
            priceFeed = AggregatorV3Interface(
                0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
            ); // ETH/USD na Ethereum
        } else {
            revert("Unsupported network!");
        }
    }

    /***
     * Get the latest ETH/USD price from the Aggregator
     */
    function getEthToUsdPrice() public view returns (int256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return price;
    }

    /***
     * Convert ETH to USD based on the latest price from the Aggregator
     */
    function convertEthToUsd(uint256 ethAmount) public view returns (uint256) {
        int256 ethToUsdPrice = getEthToUsdPrice();

        uint256 usdAmount = (ethAmount * uint256(ethToUsdPrice)) /
            (10**priceFeed.decimals());
        return usdAmount;
    }

    function calculateWeiRequired(uint256 tokenAmount)
        public
        view
        returns (uint256)
    {
        require(presaleActive, "Presale is not active!");
        uint256 _id = getCurrentStageIdActive();
        require(_id > 0, "No active stage available!");

        Stage memory currentStage = stages[_id];

        uint256 totalPayUsd = tokenAmount * currentStage.price; // Calculate total USD needed
        uint256 ethToUsd = convertEthToUsd(1e18); // Get current ETH to USD conversion rate for 1 ETH

        uint256 totalPayInWei = (totalPayUsd * 1e18) / ethToUsd;

        return totalPayInWei;
    }

    function buyTokenWithUsdt(uint256 _amount, address _referallAddress)
        public
    {
        require(presaleActive, "Presale is not active!");
        require(_amount > 0, "Please enter minimum token amount!");

        uint256 _id = getCurrentStageIdActive();
        require(_id > 0, "Stage info not available!");

        Stage storage currentStage = stages[_id];

        uint256 totalPayInUsd = _amount * currentStage.price; // Total payment in USD
        uint256 usdtDecimals = IERC20Metadata(UsdtAddress).decimals();
        uint256 totalPayInUsdt = (totalPayInUsd * (10**usdtDecimals)) / 1e18;

        require(
            IERC20(UsdtAddress).allowance(msg.sender, address(this)) >=
                totalPayInUsdt,
            "Insufficient USDT allowance!"
        );

        // Transfer USDT to seller
        bool paymentSuccess = IERC20(UsdtAddress).transferFrom(
            msg.sender,
            paymentAddress,
            totalPayInUsdt
        );

        require(paymentSuccess, "USDT payment failed!");

        uint256 totalTokenAmount = (_amount * 1e18) /
            (10**(18 - tokenMetadata.decimals()));

        require(
            currentStage.tokensSold + totalTokenAmount <=
                currentStage.maxTokens,
            "Stage token limit exceeded!"
        );

        // Transfer tokens to buyer
        bool tokenTransferSuccess = token.transferFrom(
            sellerAddress,
            msg.sender,
            totalTokenAmount
        );

        currentStage.tokensSold += totalTokenAmount;

        require(tokenTransferSuccess, "Token transfer failed!");

        if (_referallAddress != address(0)) {
            referallSalesRecords[_referallAddress].push(
                SaleRecord({
                    stageId: _id,
                    tokensSold: totalTokenAmount,
                    buyer: msg.sender
                })
            );
        }

        totalSold += totalTokenAmount;
    }

    function buyToken(uint256 _amount, address _referallAddress)
        public
        payable
    {
        require(presaleActive, "Presale is not active!");
        require(_amount >= 0, "Please enter minimum token!");
        uint256 _id = getCurrentStageIdActive();
        require(_id > 0, "Stage info not available!");
        Stage storage currentStage = stages[_id];

        uint256 _totalPayInEther = calculateWeiRequired(_amount);
        require(msg.value >= _totalPayInEther, "Not enough payment!");

        uint256 _totalAmount = _amount * 1e18;
        uint256 _tokenDecimals = tokenMetadata.decimals();
        uint256 _subDecimals = 18 - _tokenDecimals;
        uint256 _totalTokenAmount = _totalAmount / (10**_subDecimals);

        require(
            currentStage.tokensSold + _totalTokenAmount <=
                currentStage.maxTokens,
            "Stage token limit exceeded!"
        );

        // Payment price transfer to seller address
        require(
            payable(paymentAddress).send(msg.value),
            "Failed to transfer ETH payment!"
        );

        // Purchased tokens transfer from seller address to buyer address
        bool success = token.transferFrom(
            sellerAddress,
            msg.sender,
            _totalTokenAmount
        );

        currentStage.tokensSold += _totalTokenAmount;

        require(success, "Failed to transfer token!");

        if (_referallAddress != address(0)) {
            referallSalesRecords[_referallAddress].push(
                SaleRecord({
                    stageId: _id,
                    tokensSold: _totalTokenAmount,
                    buyer: msg.sender
                })
            );
        }

        totalSold += _totalTokenAmount;
    }

    /***
     * @dev update token address
     */
    function setToken(address _token) public onlyOwner {
        require(_token != address(0), "Token is zero address!");
        token = IERC20(_token);
        tokenMetadata = IERC20Metadata(_token);
    }

    /***
     * @dev update price feed address
     */
    function setPriceFeed(address _priceFeed) public onlyOwner {
        require(_priceFeed != address(0), "Token is zero address!");
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /***
     * @dev update sellerAddress
     */
    function setSellerAddress(address _seller) public onlyOwner {
        sellerAddress = _seller;
    }

    /***
     * @dev update paementAddress
     */
    function setPaymentAddress(address _payment) public onlyOwner {
        paymentAddress = _payment;
    }

    /***
     * @dev flip presaleActive as true/false
     */
    function flipPresaleActive() public onlyOwner {
        presaleActive = !presaleActive;
    }

    /**
     * @dev Emergency function to withdraw all presale tokens from the contract to the owner's address
     */
    function emergencyWithdraw() public onlyOwner {
        uint256 remainingTokens = token.balanceOf(address(this));
        require(remainingTokens > 0, "No tokens left to withdraw");

        bool success = token.transfer(msg.sender, remainingTokens);
        require(success, "Failed to withdraw tokens");
    }

    /***
     * @dev update maximum stage
     */
    function setMaxStage(uint256 _maxStage) public onlyOwner {
        maxStage = _maxStage;
    }

    /***
     * @dev ading stage info
     */

    function addStage(
        uint256 _price,
        uint256 _maxTokens,
        bool _active
    ) public onlyOwner {
        uint256 _id = currentStageId + 1;
        require(_id <= maxStage, "Maximum stage exceeds!");
        currentStageId += 1;

        stages[_id] = Stage({
            id: _id,
            price: _price,
            maxTokens: _maxTokens,
            tokensSold: 0,
            active: _active
        });
    }

    function setStage(
        uint256 _id,
        uint256 _price,
        uint256 _maxTokens,
        bool _active
    ) public onlyOwner {
        require(stages[_id].id == _id, "ID doesn't exist!");
        stages[_id].price = _price;
        stages[_id].maxTokens = _maxTokens;
        stages[_id].active = _active;
    }

    /***
     * @dev get current stage id active
     */

    function getCurrentStageIdActive() public view returns (uint256) {
        uint256 _id = 0;
        for (uint256 i = 1; i <= currentStageId; i++) {
            if (stages[i].active) {
                _id = i;
                break;
            }
        }
        return _id;
    }

    /***
     * @dev withdrawFunds functions to get remaining funds transfer to seller address
     */
    function withdrawFunds() public onlyOwner {
        require(
            payable(msg.sender).send(address(this).balance),
            "Failed withdraw!"
        );
    }
}