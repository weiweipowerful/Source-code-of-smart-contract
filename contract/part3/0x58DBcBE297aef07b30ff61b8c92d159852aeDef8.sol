// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "IUniswapV3Pool.sol";
import "TickMath.sol";
import "FixedPoint96.sol";
import "FullMath.sol";
import "SafeMath.sol";
import "Ownable.sol";

contract TWAPCalculator is Ownable {
    using SafeMath for uint256;
    
    /* ========== Twap Data Storage Struct ========== */

    struct TwapStruct {
        uint256 timestamp;
        uint256 humanReadableTwap;
    }


    /* ========== Constants and State Variables ========== */

    uint32 public constant TWAP_INTERVAL = 900; //900 seconds in the past
    address public uniswapV3Pool = 0x23655ec96b201Bf1574316783f3d943A955Ce5Fe; //Initalized with WETH/EEFI pool
    TwapStruct[] public twapData;


    /**
     * @dev Update Uniswap V3 pool address
     * Only callable by Owner
     * @param newPoolAddress New UniswapV3 EEFI/WETH pool address
     */
    function updateUniswapV3PoolAddress(address newPoolAddress) public onlyOwner {
        uniswapV3Pool = newPoolAddress;
    }

    /**
     * @dev Calculate tick price using standard twap interval 
     * @param uniswapV3Pool UniswapV3 EEFI/WETH pool address
     * @param twapInterval Standard twap interval
    */
    function getSqrtTwapX96(address uniswapV3Pool, uint32 twapInterval) internal view returns (uint160 sqrtPriceX96) {
        if (twapInterval == 0) {
            // Return the current price if twapInterval == 0
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapV3Pool).slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval; // from (before)
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives, ) = IUniswapV3Pool(uniswapV3Pool).observe(secondsAgos);

            // Tick(imprecise as it's an integer) to price
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives[1] - tickCumulatives[0]) / twapInterval)
            );
        }
    }

    /**
     * @dev Calculate tick price (from square root tick price)
     * @param sqrtPriceX96 Tick price 
    */
    function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns(uint256 priceX96) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    /**
     * @dev Generate current block time and human readable twap
    */
    function getCurrentBlockTimeAndHumanReadableTwap() public view returns (uint256, uint256) {
        uint160 sqrtTwapX96 = getSqrtTwapX96(uniswapV3Pool, TWAP_INTERVAL);
        uint256 priceX96 = getPriceX96FromSqrtPriceX96(sqrtTwapX96);
        
        uint256 humanReadablePrice = priceX96.mul(1e18).div(2**96);
        
        return (block.timestamp, humanReadablePrice);
    }

    /**
     * @dev Store Twap Data
     * Only callable by Owner
    */
    function storeTwapData() public onlyOwner {
        (uint256 currentTime, uint256 humanReadableTwap) = getCurrentBlockTimeAndHumanReadableTwap();
        twapData.push(TwapStruct(currentTime, humanReadableTwap));
    }

    /**
     * @dev For a given time period, calculate average Twap
    */
    function calculateAverageTwap(uint256 startTimeUNIX, uint256 endTimeUNIX) public view returns (uint256 averageTwap) {
        uint256 sumTwap = 0;
        uint256 count = 0;
        
        for (uint256 i = 0; i < twapData.length; i++) {
            if (twapData[i].timestamp >= startTimeUNIX && twapData[i].timestamp <= endTimeUNIX) {
                sumTwap += twapData[i].humanReadableTwap;
                count++;
            }
        }
        
        require(count > 0, "TWAPCalculator: No TWAP data in the given time frame");
        
        return sumTwap.div(count);
    }

}