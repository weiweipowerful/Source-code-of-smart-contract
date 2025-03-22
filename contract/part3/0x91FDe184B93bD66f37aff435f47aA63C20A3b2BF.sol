// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {IUniswapV2Locker} from "./interfaces/IUniswapV2Locker.sol";

import {Math} from "./libraries/Math.sol";

contract DFDX is ERC20, Ownable {
    using SafeERC20 for IERC20;

    bool public initialized;

    error DFDX__InvalidEthValue();
    error DFDX__AlreadyInitialized();
    error DFDX__ZeroAddress();
    error DFDX__WETHTransfer();

    uint256 public constant TOTAL_SUPPLY = 888_888_888e18;
    uint256 public constant INITIAL_LP_DFDX = 10_000_000e18;
    uint256 public constant INITIAL_LP_WETH = 0.37e18;
    uint256 public constant INITIAL_LP_DX = 420_000_000e18;
    uint256 public constant LOCK_DURATION = 365 days;

    uint256 public constant PRECISION = 1e48;
    uint256 public constant PRECISION_SQRT = 1e24;
    uint256 public constant SLIPPAGE = 100;
    uint256 public constant BPS = 1e4;

    uint24 public constant V3_POOL_FEE = 10_000;

    int24 public constant MIN_TICK = -887272;
    int24 public constant MAX_TICK = -MIN_TICK;

    IUniswapV2Locker public immutable uniswapV2Locker;
    IUniswapV2Router02 public immutable uniswapV2Router;
    INonfungiblePositionManager public immutable uniswapV3PositionManager;

    address public immutable DX;
    address public immutable WETH;

    address public immutable DFDX_WETH_V2_PAIR;
    address public immutable DFDX_WETH_V3_PAIR;
    address public immutable DFDX_DX_V2_PAIR;
    address public immutable DFDX_DX_V3_PAIR;

    constructor(
        string memory name,
        string memory symbol,
        address _DX,
        address _v2Locker,
        address _v2Router,
        address _v3PositionManager,
        address _owner
    ) ERC20(name, symbol) Ownable(_owner) {
        if (
            _DX == address(0) ||
            _v2Locker == address(0) ||
            _v2Router == address(0) ||
            _v3PositionManager == address(0)
        ) revert DFDX__ZeroAddress();

        _mint(address(this), TOTAL_SUPPLY);

        DX = _DX;
        uniswapV2Locker = IUniswapV2Locker(_v2Locker);
        uniswapV2Router = IUniswapV2Router02(_v2Router);
        uniswapV3PositionManager = INonfungiblePositionManager(
            _v3PositionManager
        );

        WETH = IUniswapV2Router02(_v2Router).WETH();

        IUniswapV2Factory v2Factory = IUniswapV2Factory(
            uniswapV2Router.factory()
        );

        IUniswapV3Factory v3Factory = IUniswapV3Factory(
            uniswapV3PositionManager.factory()
        );

        DFDX_DX_V2_PAIR = v2Factory.createPair(address(this), _DX);
        DFDX_WETH_V2_PAIR = v2Factory.createPair(address(this), WETH);

        DFDX_DX_V3_PAIR = v3Factory.createPool(address(this), _DX, V3_POOL_FEE);
        DFDX_WETH_V3_PAIR = v3Factory.createPool(
            address(this),
            WETH,
            V3_POOL_FEE
        );

        address _token0;
        address _token1;

        _token0 = IUniswapV3Pool(DFDX_DX_V3_PAIR).token0();
        _token1 = IUniswapV3Pool(DFDX_DX_V3_PAIR).token1();

        uint160 sqrtPriceX96DX = _token0 == address(this)
            ? _encodeSqrtRatioX96(INITIAL_LP_DFDX, INITIAL_LP_DX)
            : _encodeSqrtRatioX96(INITIAL_LP_DX, INITIAL_LP_DFDX);

        IUniswapV3Pool(DFDX_DX_V3_PAIR).initialize(sqrtPriceX96DX);

        _token0 = IUniswapV3Pool(DFDX_WETH_V3_PAIR).token0();
        _token1 = IUniswapV3Pool(DFDX_WETH_V3_PAIR).token1();

        uint160 sqrtPriceX96WETH = _token0 == address(this)
            ? _encodeSqrtRatioX96(INITIAL_LP_DFDX, INITIAL_LP_WETH)
            : _encodeSqrtRatioX96(INITIAL_LP_WETH, INITIAL_LP_DFDX);

        IUniswapV3Pool(DFDX_WETH_V3_PAIR).initialize(sqrtPriceX96WETH);
    }

    function initialize(uint256 deadline) external payable onlyOwner {
        if (initialized) revert DFDX__AlreadyInitialized();

        initialized = true;

        uint256 lockerFee = uniswapV2Locker.gFees().ethFee;

        if (msg.value != 2 * (lockerFee + INITIAL_LP_WETH))
            revert DFDX__InvalidEthValue();

        (bool success, ) = address(WETH).call{value: 2 * INITIAL_LP_WETH}("");
        if (!success) revert DFDX__WETHTransfer();

        IERC20(DX).safeTransferFrom(
            msg.sender,
            address(this),
            2 * INITIAL_LP_DX
        );

        IERC20(DX).approve(address(uniswapV2Router), INITIAL_LP_DX);
        IERC20(WETH).approve(address(uniswapV2Router), INITIAL_LP_WETH);
        _approve(address(this), address(uniswapV2Router), 2 * INITIAL_LP_DFDX);

        uint256 dfdxSent;
        uint256 tokenBalance;

        tokenBalance = IERC20(DX).balanceOf(DFDX_DX_V2_PAIR);
        if (tokenBalance > 0)
            dfdxSent = _fixV2Pair(DFDX_DX_V2_PAIR, INITIAL_LP_DX);

        uniswapV2Router.addLiquidity(
            address(this),
            DX,
            INITIAL_LP_DFDX - dfdxSent,
            INITIAL_LP_DX - tokenBalance,
            ((INITIAL_LP_DFDX - dfdxSent) * (BPS - SLIPPAGE)) / BPS,
            ((INITIAL_LP_DX - tokenBalance) * (BPS - SLIPPAGE)) / BPS,
            address(this),
            deadline
        );

        dfdxSent = 0;

        tokenBalance = IERC20(WETH).balanceOf(DFDX_WETH_V2_PAIR);
        if (tokenBalance > 0)
            dfdxSent = _fixV2Pair(DFDX_WETH_V2_PAIR, INITIAL_LP_WETH);

        uniswapV2Router.addLiquidity(
            address(this),
            WETH,
            INITIAL_LP_DFDX - dfdxSent,
            INITIAL_LP_WETH - tokenBalance,
            ((INITIAL_LP_DFDX - dfdxSent) * (BPS - SLIPPAGE)) / BPS,
            ((INITIAL_LP_WETH - tokenBalance) * (BPS - SLIPPAGE)) / BPS,
            address(this),
            deadline
        );

        IERC20(DFDX_DX_V2_PAIR).approve(
            address(uniswapV2Locker),
            IERC20(DFDX_DX_V2_PAIR).balanceOf(address(this))
        );

        uniswapV2Locker.lockLPToken{value: lockerFee}(
            DFDX_DX_V2_PAIR,
            IERC20(DFDX_DX_V2_PAIR).balanceOf(address(this)),
            block.timestamp + LOCK_DURATION,
            payable(address(0)),
            true,
            payable(msg.sender)
        );

        IERC20(DFDX_WETH_V2_PAIR).approve(
            address(uniswapV2Locker),
            IERC20(DFDX_WETH_V2_PAIR).balanceOf(address(this))
        );

        uniswapV2Locker.lockLPToken{value: lockerFee}(
            DFDX_WETH_V2_PAIR,
            IERC20(DFDX_WETH_V2_PAIR).balanceOf(address(this)),
            block.timestamp + LOCK_DURATION,
            payable(address(0)),
            true,
            payable(msg.sender)
        );

        IERC20(DX).approve(address(uniswapV3PositionManager), INITIAL_LP_DX);
        IERC20(WETH).approve(
            address(uniswapV3PositionManager),
            INITIAL_LP_WETH
        );
        _approve(
            address(this),
            address(uniswapV3PositionManager),
            2 * INITIAL_LP_DFDX
        );

        address _token0;
        address _token1;

        uint256 _amount0Desired;
        uint256 _amount1Desired;

        int24 tickSpacing;

        _token0 = IUniswapV3Pool(DFDX_DX_V3_PAIR).token0();
        _token1 = IUniswapV3Pool(DFDX_DX_V3_PAIR).token1();

        _amount0Desired = _token0 == address(this)
            ? INITIAL_LP_DFDX
            : INITIAL_LP_DX;
        _amount1Desired = _token0 == address(this)
            ? INITIAL_LP_DX
            : INITIAL_LP_DFDX;

        tickSpacing = IUniswapV3Pool(DFDX_DX_V3_PAIR).tickSpacing();

        uniswapV3PositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: _token0,
                token1: _token1,
                fee: V3_POOL_FEE,
                tickLower: (MIN_TICK / tickSpacing) * tickSpacing,
                tickUpper: (MAX_TICK / tickSpacing) * tickSpacing,
                amount0Desired: _amount0Desired,
                amount1Desired: _amount1Desired,
                amount0Min: (_amount0Desired * (BPS - SLIPPAGE)) / BPS,
                amount1Min: (_amount1Desired * (BPS - SLIPPAGE)) / BPS,
                recipient: msg.sender,
                deadline: deadline
            })
        );

        _token0 = IUniswapV3Pool(DFDX_WETH_V3_PAIR).token0();
        _token1 = IUniswapV3Pool(DFDX_WETH_V3_PAIR).token1();

        _amount0Desired = _token0 == address(this)
            ? INITIAL_LP_DFDX
            : INITIAL_LP_WETH;

        _amount1Desired = _token0 == address(this)
            ? INITIAL_LP_WETH
            : INITIAL_LP_DFDX;

        tickSpacing = IUniswapV3Pool(DFDX_WETH_V3_PAIR).tickSpacing();

        uniswapV3PositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: _token0,
                token1: _token1,
                fee: V3_POOL_FEE,
                tickLower: (MIN_TICK / tickSpacing) * tickSpacing,
                tickUpper: (MAX_TICK / tickSpacing) * tickSpacing,
                amount0Desired: _amount0Desired,
                amount1Desired: _amount1Desired,
                amount0Min: (_amount0Desired * (BPS - SLIPPAGE)) / BPS,
                amount1Min: (_amount1Desired * (BPS - SLIPPAGE)) / BPS,
                recipient: msg.sender,
                deadline: deadline
            })
        );

        _transfer(address(this), msg.sender, balanceOf(address(this)));
    }

    function _encodeSqrtRatioX96(
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint160) {
        // 1e48 is used for high precision
        uint160 sqrtPX96 = uint160(
            (Math.sqrt((amount1 * PRECISION) / amount0) << 96) / PRECISION_SQRT
        );
        return sqrtPX96;
    }

    function _fixV2Pair(
        address _pair,
        uint256 _initialLP
    ) internal returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(_pair);
        address token = pair.token0() == address(this)
            ? pair.token1()
            : pair.token0();

        uint256 tokenAmount = IERC20(token).balanceOf(_pair);

        uint256 dfdxToSend = (tokenAmount * INITIAL_LP_DFDX) / _initialLP;
        _transfer(address(this), _pair, dfdxToSend);

        pair.sync();

        return dfdxToSend;
    }
}