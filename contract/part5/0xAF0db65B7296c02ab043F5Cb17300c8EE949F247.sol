// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@const/Constants.sol";
import {sqrt} from "@utils/Math.sol";
import {ShaolinStaking} from "./Staking.sol";
import {ShaolinBuyAndBurn} from "./BuyAndBurn.sol";
import {OracleLibrary} from "@libs/OracleLibrary.sol";
import {WBTCPoolFeeder} from "@core/WBTCPoolFeeder.sol";
import {ShaolinMining, MiningStats} from "./Mining.sol";
import {SwapActionParams} from "./actions/SwapActions.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {LotusEdenBnBFeeder} from "@core/LotusEdenBnBFeeder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {PoolAddress} from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

/**
 * @title Shaolin
 * @dev ERC20 token contract for Shaolin tokens.
 */
contract Shaolin is OFT {
    address public immutable pool;
    ShaolinMining public mining;
    ShaolinStaking public staking;
    ShaolinBuyAndBurn public buyAndBurn;
    WBTCPoolFeeder public wbtcPoolFeeder;
    LotusEdenBnBFeeder public lotusEdenBnBFeeder;

    error Shaolin__OnlyMining();
    error Shaolin__OnlyMigrator();

    constructor(address _v3PositionManager, address _lzEndpoint, address _delegate, address _weth)
        OFT("SHAO", "SHAO", _lzEndpoint, _delegate)
        Ownable(msg.sender)
    {
        _mint(LIQUIDITY_BONDING, 33_333_340e18);
        pool = _createUniswapV3Pool(_weth, _v3PositionManager);
    }

    //=======MODIFIERS=========//

    modifier onlyMining() {
        _onlyMining();
        _;
    }

    function setBnB(ShaolinBuyAndBurn _bnb) external onlyOwner {
        buyAndBurn = _bnb;
    }

    function setStaking(ShaolinStaking _staking) external onlyOwner {
        staking = _staking;
    }

    function setMining(ShaolinMining _mining) external onlyOwner {
        mining = _mining;
    }

    function setWBTCPoolFeeder(WBTCPoolFeeder _wbtcPoolFeeder) external onlyOwner {
        wbtcPoolFeeder = _wbtcPoolFeeder;
    }

    function setLotusEdenBNBFeeder(LotusEdenBnBFeeder _lotusEdenBNBFeeder) external onlyOwner {
        lotusEdenBnBFeeder = _lotusEdenBNBFeeder;
    }

    function emitShaolin(address _receiver, uint256 _amount) external onlyMining {
        _mint(_receiver, _amount);
    }

    function burn(uint256 value) public virtual {
        _burn(_msgSender(), value);
    }

    function burnFrom(address account, uint256 value) public virtual {
        _spendAllowance(account, _msgSender(), value);
        _burn(account, value);
    }

    function _createUniswapV3Pool(address _weth, address UNISWAP_V3_POSITION_MANAGER)
        internal
        returns (address _pool)
    {
        address _shao = address(this);

        uint256 shaoAmount = INITIAL_SHAO_FOR_LP;
        uint256 wethAmount = INITIAL_ETH_FOR_LIQ;

        (address token0, address token1) = _shao < _weth ? (_shao, _weth) : (_weth, _shao);

        (uint256 amount0, uint256 amount1) = token0 == _weth ? (wethAmount, shaoAmount) : (shaoAmount, wethAmount);

        uint160 sqrtPX96 = uint160((sqrt((amount1 * 1e18) / amount0) * 2 ** 96) / 1e9);

        INonfungiblePositionManager manager = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER);

        _pool = manager.createAndInitializePoolIfNecessary(token0, token1, POOL_FEE, sqrtPX96);

        IUniswapV3Pool(_pool).increaseObservationCardinalityNext(uint16(100));
    }

    function _onlyMining() internal view {
        require(msg.sender == address(mining), Shaolin__OnlyMining());
    }
}