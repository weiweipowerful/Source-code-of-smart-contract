// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.7;

import "./interfaces/IWETH.sol";
import "./interfaces/IWowmaxRouter.sol";

import "./libraries/UniswapV2.sol";
import "./libraries/UniswapV3.sol";
import "./libraries/Curve.sol";
import "./libraries/CurveTricrypto.sol";
import "./libraries/PancakeSwapStable.sol";
import "./libraries/DODOV2.sol";
import "./libraries/DODOV1.sol";
import "./libraries/DODOV3.sol";
import "./libraries/Hashflow.sol";
import "./libraries/Saddle.sol";
import "./libraries/Wombat.sol";
import "./libraries/Level.sol";
import "./libraries/Fulcrom.sol";
import "./libraries/WooFi.sol";
import "./libraries/Elastic.sol";
import "./libraries/AlgebraV1.sol";
import "./libraries/SyncSwap.sol";
import "./libraries/Vooi.sol";
import "./libraries/VelocoreV2.sol";
import "./libraries/Iziswap.sol";
import "./libraries/Velodrome.sol";
import "./libraries/BalancerV2.sol";
import "./libraries/MaverickV1.sol";
import "./libraries/MaverickV2.sol";
import "./libraries/WrappedNative.sol";
import "./libraries/LiquiditybookV2_1.sol";
import "./libraries/SwaapV2.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./WowmaxSwapReentrancyGuard.sol";

/**
 * @title WOWMAX Router
 * @notice Router for stateless execution of swaps against multiple DEX protocols.
 *
 * The WowmaxRouter contract encompasses three primary responsibilities:
 * 1. Facilitating the exchange of user tokens based on a provided exchange route.
 * 2. Ensuring validation of the received output amounts for users, guaranteeing their alignment
 * within the designated slippage range.
 * 3. Transferring any surplus amounts to the treasury, thereby functioning as a service fee.
 *
 * The WowmaxRouter contract does not hold any tokens between swap operations. Tokens should not be transferred directly
 * to the contract. If, by any chance, tokens are transferred directly to the contract, they are most likely to be lost.
 */
contract WowmaxRouter is IWowmaxRouter, Ownable, WowmaxSwapReentrancyGuard {
    /**
     * @dev WETH contract
     */
    IWETH public WETH;

    /**
     * @dev Treasury address
     */
    address public treasury;

    /**
     * @dev Max fee percentage. All contract percentage values have two extra digits for precision. Default value is 1%
     */
    uint256 public maxFeePercentage = 100;

    /**
     * @dev Max allowed slippage percentage, default value is 20%
     */
    uint256 public maxSlippage = 2000;

    // Mapping of protocol names
    bytes32 internal constant UNISWAP_V2 = "UNISWAP_V2";
    bytes32 internal constant UNISWAP_V3 = "UNISWAP_V3";
    bytes32 internal constant UNISWAP_V2_ROUTER = "UNISWAP_V2_ROUTER";
    bytes32 internal constant CURVE = "CURVE";
    bytes32 internal constant CURVE_TRICRYPTO = "CURVE_TRICRYPTO";
    bytes32 internal constant DODO_V1 = "DODO_V1";
    bytes32 internal constant DODO_V2 = "DODO_V2";
    bytes32 internal constant DODO_V3 = "DODO_V3";
    bytes32 internal constant HASHFLOW = "HASHFLOW";
    bytes32 internal constant PANCAKESWAP_STABLE = "PANCAKESWAP_STABLE";
    bytes32 internal constant SADDLE = "SADDLE";
    bytes32 internal constant WOMBAT = "WOMBAT";
    bytes32 internal constant LEVEL = "LEVEL";
    bytes32 internal constant FULCROM = "FULCROM";
    bytes32 internal constant WOOFI = "WOOFI";
    bytes32 internal constant ELASTIC = "ELASTIC";
    bytes32 internal constant ALGEBRA_V1 = "ALGEBRA_V1";
    bytes32 internal constant ALGEBRA_V1_9 = "ALGEBRA_V1_9";
    bytes32 internal constant SYNCSWAP = "SYNCSWAP";
    bytes32 internal constant VOOI = "VOOI";
    bytes32 internal constant VELOCORE_V2 = "VELOCORE_V2";
    bytes32 internal constant IZISWAP = "IZISWAP";
    bytes32 internal constant VELODROME = "VELODROME";
    bytes32 internal constant BALANCER_V2 = "BALANCER_V2";
    bytes32 internal constant MAVERICK_V1 = "MAVERICK_V1";
    bytes32 internal constant WRAPPED_NATIVE = "WRAPPED_NATIVE";
    bytes32 internal constant LIQUIDITY_BOOK_V2_1 = "LIQUIDITY_BOOK_V2_1";
    bytes32 internal constant MAVERICK_V2 = "MAVERICK_V2";
    bytes32 internal constant SWAAP_V2 = "SWAAP_V2";

    using SafeERC20 for IERC20;

    /**
     * @dev sets the WETH and treasury addresses
     */
    constructor(address _weth, address _treasury) {
        require(_weth != address(0), "WOWMAX: Wrong WETH address");
        require(_treasury != address(0), "WOWMAX: Wrong treasury address");

        WETH = IWETH(_weth);
        treasury = _treasury;
    }

    /**
     * @dev fallback function to receive native tokens
     */
    receive() external payable {}

    /**
     * @dev fallback function to process various protocols callback functions
     */
    fallback() external onlyDuringSwap {
        (bool success, int256 amount0Delta, int256 amount1Delta, bytes calldata data) = UniswapV3.decodeCallback({
            dataWithSelector: msg.data
        });
        require(success, "WOWMAX: unsupported callback");
        UniswapV3.invokeCallback(amount0Delta, amount1Delta, data);
    }

    // Admin functions

    /**
     * @dev withdraws tokens from a contract, in case of leftovers after a swap, invalid swap requests,
     * or direct transfers. Only callable by the owner.
     * @param token Token to be withdrawn
     * @param amount Amount to be withdrawn
     */
    function withdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(treasury, amount);
    }

    /**
     * @dev withdraws native tokens from a contract, in case of leftovers after a swap or invalid swap requests.
     * Only callable by the owner.
     * @param amount Amount to be withdrawn
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        (bool sent, ) = payable(treasury).call{ value: amount }("");
        require(sent, "Wowmax: Failed to send native tokens");
    }

    /**
     * @dev sets the max fee percentage. Only callable by the owner.
     * @param _maxFeePercentage Max fee percentage
     */
    function setMaxFeePercentage(uint256 _maxFeePercentage) external onlyOwner {
        maxFeePercentage = _maxFeePercentage;
    }

    /**
     * @dev sets the max allowed slippage. Only callable by the owner.
     * @param _maxSlippage Max allowed slippage percentage
     */
    function setMaxSlippage(uint256 _maxSlippage) external onlyOwner {
        maxSlippage = _maxSlippage;
    }

    // Callbacks

    /**
     * @dev callback for Maverick V1 pools. Not allowed to be executed outside of a swap operation
     * @param amountToPay Amount to be paid
     * @param amountOut Amount to be received
     * @param data Additional data to be passed to the callback function
     */
    function swapCallback(uint256 amountToPay, uint256 amountOut, bytes calldata data) external onlyDuringSwap {
        MaverickV1.invokeCallback(amountToPay, amountOut, data);
    }

    /**
     * @dev callback for Maverick V2 pools. Not allowed to be executed outside of a swap operation
     * @param tokenIn Token to be transferred to the caller
     * @param amountIn Amount of tokens to be transferred to the caller
     */
    function maverickV2SwapCallback(
        address tokenIn,
        uint256 amountIn,
        uint256 /*amountOut*/,
        bytes calldata /*data*/
    ) external onlyDuringSwap {
        MaverickV2.invokeCallback(tokenIn, amountIn);
    }

    /**
     * @dev callback for Algebra V1 pairs. Not allowed to be executed outside of a swap operation
     * @param amount0Delta Amount of token0 to be transferred to the caller
     * @param amount1Delta Amount of token1 to be transferred to the caller
     * @param data Additional data to be passed to the callback function
     */
    function algebraSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external onlyDuringSwap {
        AlgebraV1.invokeCallback(amount0Delta, amount1Delta, data);
    }

    /**
     * @notice Called to msg.sender in iZiSwapPool#swapX2Y(DesireY) call
     * @param x Amount of tokenX trader will pay
     * @param data Any dadta passed though by the msg.sender via the iZiSwapPool#swapX2Y(DesireY) call
     */
    function swapX2YCallback(uint256 x, uint256 /*y*/, bytes calldata data) external onlyDuringSwap {
        Iziswap.transferTokens(x, data);
    }

    /**
     * @notice Called to msg.sender in iZiSwapPool#swapY2X(DesireX) call
     * @param y Amount of tokenY trader will pay
     * @param data Any dadta passed though by the msg.sender via the iZiSwapPool#swapY2X(DesireX) call
     */
    function swapY2XCallback(uint256 /*x*/, uint256 y, bytes calldata data) external onlyDuringSwap {
        Iziswap.transferTokens(y, data);
    }

    /**
     * @notice Callback for DODO v3 Pools
     * @param token Token to be transferred to the caller
     * @param value Amount of tokens to be transferred to the caller
     * @param data Additional data to be passed to the callback function
     */
    function d3MMSwapCallBack(address token, uint256 value, bytes calldata data) external {
        DODOV3.invokeCallback(token, value, data);
    }

    // Swap functions

    /**
     * @inheritdoc IWowmaxRouter
     */
    function swap(
        ExchangeRequest calldata request
    ) external payable virtual override reentrancyProtectedSwap returns (uint256[] memory amountsOut) {
        amountsOut = _swap(request);
    }

    /**
     * @dev swap inner logic
     */
    function _swap(ExchangeRequest calldata request) internal returns (uint256[] memory amountsOut) {
        checkRequest(request);
        uint256 amountIn = receiveTokens(request);
        for (uint256 i = 0; i < request.exchangeRoutes.length; i++) {
            exchange(request.exchangeRoutes[i]);
        }
        amountsOut = sendTokens(request);

        emit SwapExecuted(
            msg.sender,
            request.from == address(0) ? address(WETH) : request.from,
            amountIn,
            request.to,
            amountsOut
        );
    }

    /**
     * @dev receives tokens from the caller
     * @param request Exchange request that contains the token to be received parameters.
     */
    function receiveTokens(ExchangeRequest calldata request) private returns (uint256) {
        uint256 amountIn;
        if (msg.value > 0 && request.from == address(0) && request.amountIn == 0) {
            amountIn = msg.value;
            WETH.deposit{ value: amountIn }();
        } else {
            if (request.amountIn > 0) {
                amountIn = request.amountIn;
                IERC20(request.from).safeTransferFrom(msg.sender, address(this), amountIn);
            }
        }
        return amountIn;
    }

    /**
     * @dev sends swapped received tokens to the caller and treasury
     * @param request Exchange request that contains output tokens parameters
     */
    function sendTokens(ExchangeRequest calldata request) private returns (uint256[] memory amountsOut) {
        amountsOut = new uint256[](request.to.length);
        uint256 amountOut;
        IERC20 token;
        for (uint256 i = 0; i < request.to.length; i++) {
            token = IERC20(request.to[i]);
            amountOut = address(token) == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
                ? WETH.balanceOf(address(this))
                : token.balanceOf(address(this));

            uint256 feeAmount;
            if (amountOut > request.amountOutExpected[i]) {
                feeAmount = amountOut - request.amountOutExpected[i];
                uint256 maxFeeAmount = (amountOut * maxFeePercentage) / 10000;
                if (feeAmount > maxFeeAmount) {
                    feeAmount = maxFeeAmount;
                    amountsOut[i] = amountOut - feeAmount;
                } else {
                    amountsOut[i] = request.amountOutExpected[i];
                }
            } else {
                require(
                    amountOut >= (request.amountOutExpected[i] * (10000 - request.slippage[i])) / 10000,
                    "WOWMAX: Insufficient output amount"
                );
                amountsOut[i] = amountOut;
            }

            if (address(token) == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                WETH.withdraw(amountOut);
            }

            transfer(token, treasury, feeAmount);
            transfer(token, msg.sender, amountsOut[i]);
        }
    }

    /**
     * @dev transfers token to the recipient
     * @param token Token to be transferred
     * @param to Recipient address
     * @param amount Amount to be transferred
     */
    function transfer(IERC20 token, address to, uint256 amount) private {
        //slither-disable-next-line incorrect-equality
        if (amount == 0) {
            return;
        }
        if (address(token) == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            //slither-disable-next-line arbitrary-send-eth //recipient is either a msg.sender or a treasury
            (bool sent, ) = payable(to).call{ value: amount }("");
            require(sent, "Wowmax: Failed to send native tokens");
        } else {
            token.safeTransfer(to, amount);
        }
    }

    /**
     * @dev executes an exchange operation according to the provided route
     * @param exchangeRoute Route to be executed
     */
    function exchange(ExchangeRoute calldata exchangeRoute) private returns (uint256) {
        uint256 amountIn = IERC20(exchangeRoute.from).balanceOf(address(this));
        uint256 amountOut;
        for (uint256 i = 0; i < exchangeRoute.swaps.length; i++) {
            amountOut += executeSwap(
                exchangeRoute.from,
                (amountIn * exchangeRoute.swaps[i].part) / exchangeRoute.parts,
                exchangeRoute.swaps[i]
            );
        }
        return amountOut;
    }

    /**
     * @dev executes a swap operation according to the provided parameters
     * @param from Token to be swapped
     * @param amountIn Amount to be swapped
     * @param swapData Swap data that contains the swap parameters
     */
    function executeSwap(address from, uint256 amountIn, Swap calldata swapData) private returns (uint256) {
        if (swapData.family == UNISWAP_V3) {
            return UniswapV3.swap(amountIn, swapData);
        } else if (swapData.family == HASHFLOW) {
            return Hashflow.swap(from, amountIn, swapData);
        } else if (swapData.family == WOMBAT) {
            return Wombat.swap(from, amountIn, swapData);
        } else if (swapData.family == LEVEL) {
            return Level.swap(from, amountIn, swapData);
        } else if (swapData.family == DODO_V2) {
            return DODOV2.swap(from, amountIn, swapData);
        } else if (swapData.family == DODO_V3) {
            return DODOV3.swap(from, amountIn, swapData);
        } else if (swapData.family == WOOFI) {
            return WooFi.swap(from, amountIn, swapData);
        } else if (swapData.family == UNISWAP_V2) {
            return UniswapV2.swap(from, amountIn, swapData);
        } else if (swapData.family == CURVE) {
            return Curve.swap(from, amountIn, swapData);
        } else if (swapData.family == CURVE_TRICRYPTO) {
            return CurveTricrypto.swap(from, amountIn, swapData);
        } else if (swapData.family == PANCAKESWAP_STABLE) {
            return PancakeSwapStable.swap(from, amountIn, swapData);
        } else if (swapData.family == DODO_V1) {
            return DODOV1.swap(from, amountIn, swapData);
        } else if (swapData.family == BALANCER_V2) {
            return BalancerV2.swap(from, amountIn, swapData);
        } else if (swapData.family == MAVERICK_V1) {
            return MaverickV1.swap(amountIn, swapData);
        } else if (swapData.family == SADDLE) {
            return Saddle.swap(from, amountIn, swapData);
        } else if (swapData.family == FULCROM) {
            return Fulcrom.swap(from, amountIn, swapData);
        } else if (swapData.family == UNISWAP_V2_ROUTER) {
            return UniswapV2.routerSwap(from, amountIn, swapData);
        } else if (swapData.family == ELASTIC) {
            return Elastic.swap(from, amountIn, swapData);
        } else if (swapData.family == ALGEBRA_V1) {
            return AlgebraV1.swap(from, amountIn, swapData);
        } else if (swapData.family == ALGEBRA_V1_9) {
            return AlgebraV1.swap(from, amountIn, swapData);
        } else if (swapData.family == SYNCSWAP) {
            return SyncSwap.swap(from, amountIn, swapData);
        } else if (swapData.family == VOOI) {
            return Vooi.swap(from, amountIn, swapData);
        } else if (swapData.family == VELOCORE_V2) {
            return VelocoreV2.swap(address(WETH), from, amountIn, swapData);
        } else if (swapData.family == IZISWAP) {
            return Iziswap.swap(from, amountIn, swapData);
        } else if (swapData.family == VELODROME) {
            return Velodrome.swap(from, amountIn, swapData);
        } else if (swapData.family == WRAPPED_NATIVE) {
            return WrappedNative.swap(from, amountIn, swapData);
        } else if (swapData.family == LIQUIDITY_BOOK_V2_1) {
            return LiquiditybookV2_1.swap(from, amountIn, swapData);
        } else if (swapData.family == MAVERICK_V2) {
            return MaverickV2.swap(amountIn, swapData);
        } else if (swapData.family == SWAAP_V2) {
            return SwaapV2.swap(from, amountIn, swapData);
        } else {
            revert("WOWMAX: Unknown DEX family");
        }
    }

    // Checks and verifications

    /**
     * @dev checks the swap request parameters
     * @param request Exchange request to be checked
     */
    function checkRequest(ExchangeRequest calldata request) private view {
        require(request.to.length > 0, "WOWMAX: No output tokens specified");
        require(request.to.length == request.amountOutExpected.length, "WOWMAX: Wrong amountOutExpected length");
        require(request.to.length == request.slippage.length, "WOWMAX: Wrong slippage length");
        for (uint256 i = 0; i < request.to.length; i++) {
            require(request.to[i] != address(0), "WOWMAX: Wrong output token address");
            require(request.amountOutExpected[i] > 0, "WOWMAX: Wrong amountOutExpected value");
            require(request.slippage[i] <= maxSlippage, "WOWMAX: Slippage is too high");
        }
    }
}