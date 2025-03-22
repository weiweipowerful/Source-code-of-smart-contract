// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {sqrt, wmul} from "@utils/Math.sol";
import {Constants} from "@const/Constants.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {IMatriX, IMatrixAuction, IMatrixBuyAndBurn} from "@interfaces/IMatrix.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

/**
 * @title MatriX
 * @dev ERC20 token contract for MATRIX tokens.
 * @notice It can be minted by MatrixAuction during auction days
 */
contract MatriX is ERC20Burnable, IMatriX {
    IMatrixAuction public auction;
    IMatrixBuyAndBurn public bnb;

    uint256 public totalBurnt;
    uint256 public totalMinted;

    modifier onlyAuction() {
        _onlyAuction();
        _;
    }

    constructor(address _hyper, address _v3PositionManager) ERC20("MATRIX.WIN", "MATRIX") {
        _createUniswapV3Pool(_hyper, _v3PositionManager);

        uint256 toMint = wmul(Constants.TOTAL_SUPPLY, uint256(0.02e18));

        _mint(Constants.LIQUIDITY_BONDING, toMint);

        totalMinted += toMint;
    }

    /// @inheritdoc IMatriX
    function setAuction(IMatrixAuction _auction) external {
        require(address(auction) == address(0), CanOnlyBeSetOnce());
        auction = _auction;
    }

    /// @inheritdoc IMatriX
    function setBnb(IMatrixBuyAndBurn _bnb) external {
        require(address(bnb) == address(0), CanOnlyBeSetOnce());
        bnb = _bnb;
    }

    /// @inheritdoc IMatriX
    function mint(address _to, uint256 _amount) external onlyAuction {
        totalMinted += _amount;
        emit MatrixMinted(_to, _amount);
        _mint(_to, _amount);
    }

    /// @inheritdoc IMatriX
    function burn(uint256 amount) public override(IMatriX, ERC20Burnable) {
        totalBurnt += amount;
        super.burn(amount);
    }

    /// @inheritdoc IMatriX
    function burnFrom(address from, uint256 amount) public override(IMatriX, ERC20Burnable) {
        totalBurnt += amount;
        super.burnFrom(from, amount);
    }

    function _onlyAuction() internal view {
        require(msg.sender == address(auction), OnlyAuction());
    }

    function _createUniswapV3Pool(address _hyper, address UNISWAP_V3_POSITION_MANAGER)
        internal
        returns (address _pool)
    {
        address _matrix = address(this);

        uint256 hyperAmount = 2000e18;
        uint256 matrixAmount = 1e18;

        (address token0, address token1) = _matrix < _hyper ? (_matrix, _hyper) : (_hyper, _matrix);

        (uint256 amount0, uint256 amount1) =
            token0 == _hyper ? (hyperAmount, matrixAmount) : (matrixAmount, hyperAmount);

        uint160 sqrtPX96 = uint160((sqrt((amount1 * 1e18) / amount0) * 2 ** 96) / 1e9);

        INonfungiblePositionManager manager = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER);

        _pool = manager.createAndInitializePoolIfNecessary(token0, token1, Constants.POOL_FEE, sqrtPX96);

        IUniswapV3Pool(_pool).increaseObservationCardinalityNext(uint16(100));
    }
}