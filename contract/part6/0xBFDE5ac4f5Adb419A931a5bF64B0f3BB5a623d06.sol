// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* === OZ === */
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/* = SYSTEM =  */
import {FluxAuction} from "@core/FluxAuction.sol";
import {FluxBuyAndBurn} from "@core/FluxBuyAndBurn.sol";
import {FluxStaking} from "@core/Staking.sol";

/* = UNIV3 = */
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";

/* == UTILS ==  */
import {sqrt} from "@utils/Math.sol";

/* = CONST = */
import "@const/Constants.sol";

/* = INTERFACES = */

import {IInferno} from "@interfaces/IInferno.sol";

/**
 * @title Flux
 * @author Zyntek
 * @dev ERC20 token contract for FLUX tokens.
 */
contract Flux is ERC20Burnable, Ownable {
    FluxAuction public auction;
    FluxBuyAndBurn public buyAndBurn;
    FluxStaking public staking;
    address public immutable pool;

    //===========ERRORS===========//

    error FluX__OnlyAuction();

    //=======CONSTRUCTOR=========//

    constructor(IInferno _inferno, ERC20Burnable _titanX, address _titanXInfernoPool)
        ERC20("FLUX", "FLUX")
        Ownable(msg.sender)
    {
        pool = _createUniswapV3Pool(address(_titanX), address(_inferno), _titanXInfernoPool);
    }

    function setBnB(address _bnb) external onlyOwner {
        buyAndBurn = FluxBuyAndBurn(_bnb);
    }

    function setStaking(address _staking) external onlyOwner {
        staking = FluxStaking(_staking);
    }

    function setAuction(address _auction) external onlyOwner {
        auction = FluxAuction(_auction);
    }

    //=======MODIFIERS=========//

    modifier onlyAuction() {
        _onlyAuction();
        _;
    }

    //==========================//
    //==========PUBLIC==========//
    //==========================//

    function emitFlux(address _receiver, uint256 _amount) external onlyAuction {
        _mint(_receiver, _amount);
    }

    //==========================//
    //=========INTERNAL=========//
    //==========================//

    function _onlyAuction() internal view {
        if (msg.sender != address(auction)) revert FluX__OnlyAuction();
    }

    function _createUniswapV3Pool(address _titanX, address _inferno, address _titanXInfernoPool)
        internal
        returns (address _pool)
    {
        address _flux = address(this);

        IQuoter quoter = IQuoter(UNISWAP_V3_QUOTER);

        bytes memory path = abi.encodePacked(address(_titanX), POOL_FEE, address(_inferno));

        uint256 infernoAmount = quoter.quoteExactInput(path, INITIAL_TITAN_X_FOR_LIQ);

        uint256 fluxAmount = INITIAL_FLUX_FOR_LP;

        (address token0, address token1) = _flux < _inferno ? (_flux, _inferno) : (_inferno, _flux);

        (uint256 amount0, uint256 amount1) =
            token0 == _inferno ? (infernoAmount, fluxAmount) : (fluxAmount, infernoAmount);

        uint160 sqrtPX96 = uint160((sqrt((amount1 * 1e18) / amount0) * 2 ** 96) / 1e9);

        INonfungiblePositionManager manager = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER);

        _pool = manager.createAndInitializePoolIfNecessary(token0, token1, POOL_FEE, sqrtPX96);

        IUniswapV3Pool(_titanXInfernoPool).increaseObservationCardinalityNext(uint16(100));
        IUniswapV3Pool(_pool).increaseObservationCardinalityNext(uint16(100));
    }
}