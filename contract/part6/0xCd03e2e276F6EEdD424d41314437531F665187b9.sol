/**
 *Submitted for verification at Etherscan.io on 2024-08-15
*/

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0 ^0.8.0;

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

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
}

// src/interfaces/IUniswapV3Factory.sol

/// @title The interface for the Uniswap V3 Factory
/// @notice The Uniswap V3 Factory facilitates creation of Uniswap V3 pools and control over the protocol fees
interface IUniswapV3Factory {
    /// @notice Emitted when the owner of the factory is changed
    /// @param oldOwner The owner before the owner was changed
    /// @param newOwner The owner after the owner was changed
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    /// @notice Emitted when a pool is created
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks
    /// @param pool The address of the created pool
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );

    /// @notice Emitted when a new fee amount is enabled for pool creation via the factory
    /// @param fee The enabled fee, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks for pools created with the given fee
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);

    /// @notice Returns the current owner of the factory
    /// @dev Can be changed by the current owner via setOwner
    /// @return The address of the factory owner
    function owner() external view returns (address);

    /// @notice Returns the tick spacing for a given fee amount, if enabled, or 0 if not enabled
    /// @dev A fee amount can never be removed, so this value should be hard coded or cached in the calling context
    /// @param fee The enabled fee, denominated in hundredths of a bip. Returns 0 in case of unenabled fee
    /// @return The tick spacing
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @return pool The pool address
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    /// @notice Creates a pool for the given two tokens and fee
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param fee The desired fee for the pool
    /// @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0. tickSpacing is retrieved
    /// from the fee. The call will revert if the pool already exists, the fee is invalid, or the token arguments
    /// are invalid.
    /// @return pool The address of the newly created pool
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);

    /// @notice Updates the owner of the factory
    /// @dev Must be called by the current owner
    /// @param _owner The new owner of the factory
    function setOwner(address _owner) external;

    /// @notice Enables a fee amount with the given tickSpacing
    /// @dev Fee amounts may never be removed once enabled
    /// @param fee The fee amount to enable, denominated in hundredths of a bip (i.e. 1e-6)
    /// @param tickSpacing The spacing between ticks to be enforced for all pools created with the given fee amount
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
}

// src/interfaces/IUniswapV3Pool.sol

interface IUniswapV3Pool {
  // IUniswapV3PoolActions
  function initialize(uint160 sqrtPriceX96) external;

  function mint(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint128 amount,
    bytes calldata data
  ) external returns (uint256 amount0, uint256 amount1);

  function collect(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint128 amount0Requested,
    uint128 amount1Requested
  ) external returns (uint128 amount0, uint128 amount1);

  function burn(
    int24 tickLower,
    int24 tickUpper,
    uint128 amount
  ) external returns (uint256 amount0, uint256 amount1);

  function swap(
    address recipient,
    bool zeroForOne,
    int256 amountSpecified,
    uint160 sqrtPriceLimitX96,
    bytes calldata data
  ) external returns (int256 amount0, int256 amount1);

  function flash(
    address recipient,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external;

  function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;

  // IUniswapV3PoolDerivedState
  function observe(uint32[] calldata secondsAgos)
    external
    view
    returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

  function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
    external
    view
    returns (
      int56 tickCumulativeInside,
      uint160 secondsPerLiquidityInsideX128,
      uint32 secondsInside
    );
  
  // IUniswapV3PoolErrors
  error LOK();
  error TLU();
  error TLM();
  error TUM();
  error AI();
  error M0();
  error M1();
  error AS();
  error IIA();
  error L();
  error F0();
  error F1();

  // IUniswapV3PoolEvents
  event Initialize(uint160 sqrtPriceX96, int24 tick);
  event Mint(
    address sender,
    address indexed owner,
    int24 indexed tickLower,
    int24 indexed tickUpper,
    uint128 amount,
    uint256 amount0,
    uint256 amount1
  );

  event Collect(
    address indexed owner,
    address recipient,
    int24 indexed tickLower,
    int24 indexed tickUpper,
    uint128 amount0,
    uint128 amount1
  );

  event Burn(
    address indexed owner,
    int24 indexed tickLower,
    int24 indexed tickUpper,
    uint128 amount,
    uint256 amount0,
    uint256 amount1
  );

  event Swap(
    address indexed sender,
    address indexed recipient,
    int256 amount0,
    int256 amount1,
    uint160 sqrtPriceX96,
    uint128 liquidity,
    int24 tick
  );

  event Flash(
    address indexed sender,
    address indexed recipient,
    uint256 amount0,
    uint256 amount1,
    uint256 paid0,
    uint256 paid1
  );

  event IncreaseObservationCardinalityNext(
    uint16 observationCardinalityNextOld,
    uint16 observationCardinalityNextNew
  );

  event SetFeeProtocol(uint8 feeProtocol0Old, uint8 feeProtocol1Old, uint8 feeProtocol0New, uint8 feeProtocol1New);

  event CollectProtocol(address indexed sender, address indexed recipient, uint128 amount0, uint128 amount1);

  // IUniswapV3PoolImmutables
  function factory() external view returns (address);
  function token0() external view returns (address);
  function token1() external view returns (address);
  function fee() external view returns (uint24);
  function tickSpacing() external view returns (int24);
  function maxLiquidityPerTick() external view returns (uint128);

  // IUniswapV3PoolOwnerActions
  function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external;
  function collectProtocol(
    address recipient,
    uint128 amount0Requested,
    uint128 amount1Requested
  ) external returns (uint128 amount0, uint128 amount1);

  // IUniswapV3PoolState
  function slot0()
    external
    view
    returns (
      uint160 sqrtPriceX96,
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      uint16 observationCardinalityNext,
      uint8 feeProtocol,
      bool unlocked
    );

  function feeGrowthGlobal0X128() external view returns (uint256);
  function feeGrowthGlobal1X128() external view returns (uint256);
  function protocolFees() external view returns (uint128 token0, uint128 token1);
  function liquidity() external view returns (uint128);

  function ticks(int24 tick)
    external
    view
    returns (
      uint128 liquidityGross,
      int128 liquidityNet,
      uint256 feeGrowthOutside0X128,
      uint256 feeGrowthOutside1X128,
      int56 tickCumulativeOutside,
      uint160 secondsPerLiquidityOutsideX128,
      uint32 secondsOutside,
      bool initialized
    );

  function tickBitmap(int16 wordPosition) external view returns (uint256);

  function positions(bytes32 key)
    external
    view
    returns (
      uint128 liquidity,
      uint256 feeGrowthInside0LastX128,
      uint256 feeGrowthInside1LastX128,
      uint128 tokensOwed0,
      uint128 tokensOwed1
    );

  function observations(uint256 index)
    external
    view
    returns (
      uint32 blockTimestamp,
      int56 tickCumulative,
      uint160 secondsPerLiquidityCumulativeX128,
      bool initialized
    );
}

// lib/openzeppelin-contracts/contracts/access/Ownable.sol

// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
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
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
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

// lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol

// OpenZeppelin Contracts (last updated v4.8.0) (access/Ownable2Step.sol)

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership} and {acceptOwnership}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Ownable).
 */
abstract contract Ownable2Step is Ownable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() external {
        address sender = _msgSender();
        require(pendingOwner() == sender, "Ownable2Step: caller is not the new owner");
        _transferOwnership(sender);
    }
}

// src/Auth.sol

abstract contract Auth is Ownable2Step {

    event SetTrusted(address indexed user, bool isTrusted);

    mapping(address => bool) public trusted;

    error OnlyTrusted();

    modifier onlyTrusted() {
        if (!trusted[msg.sender]) revert OnlyTrusted();
        _;
    }

    constructor(address trustedUser) {
        trusted[trustedUser] = true;
        emit SetTrusted(trustedUser, true);
    }

    function setTrusted(address user, bool isTrusted) external onlyOwner {
        trusted[user] = isTrusted;
        emit SetTrusted(user, isTrusted);
    }

}

// src/V3Manager.sol

/// @title V3Manager for UniswapV3Factory
/// @notice This contract is used to create fee tiers, set protocol fee on pools, and collect fees from pools
/// @dev Uses Auth contract for owner and trusted operators to guard functions
contract V3Manager is Auth {
  IUniswapV3Factory public factory;
  address public maker;
  uint8 public protocolFee;

  constructor(
    address _operator,
    address _factory,
    address _maker,
    uint8 _protocolFee
  ) Auth(_operator) {
    // initial owner is msg.sender
    factory = IUniswapV3Factory(_factory);
    maker = _maker;
    protocolFee = _protocolFee;
  }

  /// @notice Creates a new fee tier with passed tickSpacing
  /// @dev will revert on factory contract if inputs invalid
  /// @param fee The fee amount to enable, denominated in hundreths of a bip
  /// @param tickSpacing The spacing between ticks to be enforced for all pools created with the given fee amount
  function createFeeTier(uint24 fee, int24 tickSpacing) external onlyOwner {
    IUniswapV3Factory(factory).enableFeeAmount(fee, tickSpacing);
  }

  /// @notice transfer ownership of the factory contract
  /// @param newOwner The newOwner address to set on the factory contract
  function setFactoryOwner(address newOwner) external onlyOwner {
    IUniswapV3Factory(factory).setOwner(newOwner);
  }

  /// @notice Sets the protocol fee to be used for all pools
  /// @dev must be between 4 and 10, or 0 to disable - must apply to each pool everytime it's changed
  /// @param _protocolFee The protocol fee to be used for all pools
  function setProtocolFee(uint8 _protocolFee) external onlyOwner {
    require(
      _protocolFee == 0 || (_protocolFee >= 4 && _protocolFee <= 10)
    );
    protocolFee = _protocolFee;
  }

  /// @notice Sets the maker contract to be used for collecting fees
  /// @dev Where all fees will be sent to when collected
  /// @param _maker The address of the maker contract
  function setMaker(address _maker) external onlyOwner {
    maker = _maker;
  }

  /// @notice Applies the protocol fee to all pools passed
  /// @dev must be called for each pool, after protocolFee is updated
  /// @param pools The addresses of the pools to apply the protocol fee to
  function applyProtocolFee(address[] calldata pools) external onlyTrusted {
    for (uint256 i = 0; i < pools.length; i++) {
      IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);
      pool.setFeeProtocol(protocolFee, protocolFee);
    }
  } 

  /// @notice Collects fees from pools passed
  /// @dev Will call collectProtocol on each pool address, sending fees to maker contract that is set
  /// @param pools The addresses of the pools to collect fees from
  function collectFees(address[] calldata pools) external onlyTrusted {
    for (uint256 i = 0; i < pools.length; i++) {
      IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);
      (uint128 amount0, uint128 amount1) = pool.protocolFees();
      pool.collectProtocol(maker, amount0, amount1);
    }
  }

  /// @notice Available function in case we need to do any calls that aren't supported by the contract (unwinding lp positions, etc.)
  /// @dev can only be called by owner
  /// @param to The address to send the call to
  /// @param _value The amount of eth to send with the call
  /// @param data The data to be sent with the call
  function doAction(address to, uint256 _value, bytes memory data) onlyOwner external {
    (bool success, ) = to.call{value: _value}(data);
    require(success);
  }
}