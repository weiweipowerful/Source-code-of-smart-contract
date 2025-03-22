// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// ================================================================
// │                          INTERFACES                          │
// ================================================================
/**
 * @dev Uniswap v2 router interface
 *
 * NOTE: This interface only imports the {WETH} function
 */
interface IUniswapV2Router02 {
    function WETH() external pure returns (address);
}

/**
 * @dev Uniswap v2 factory interface
 *
 * NOTE: This interface only imports the {createPair} function
 */
interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

contract Pngvn2 is ERC20, Ownable {
    // ================================================================
    // │                    CONSTANTS & STORAGE                       │
    // ================================================================
    /**
     * @dev Variable representing the Uniswap v2 factory as constant
     */
    IUniswapV2Factory public constant UNISWAP_FACTORY =
        IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    /**
     * @dev Variable representing the Uniswap v2 router as constant
     */
    IUniswapV2Router02 public constant UNISWAP_ROUTER =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    /**
     * @dev Variable representing the v2 pair address once created as storage
     */
    address public UNISWAP_V2_PAIR;

    /**
     * @dev Variable representing the maximum supply cap for the token as constant
     */
    uint256 constant TOTAL_SUPPLY = 250_000_000 ether;

    // ================================================================
    // │                        CONSTRUCTOR                           │
    // ================================================================
    /**
     * @dev {constructor}
     *
     * @param initialOwner Project owner address to be forwarded to {Ownable} constructor function.
     */
    constructor(
        address initialOwner
    ) Ownable(initialOwner) ERC20("Pngvn2", "PNGVN2") {
        _mint(initialOwner, TOTAL_SUPPLY);
        _approve(initialOwner, address(UNISWAP_ROUTER), type(uint256).max);
        _approve(address(this), address(UNISWAP_ROUTER), type(uint256).max);
        _approve(initialOwner, address(this), type(uint256).max);
    }

    // ================================================================
    // │                         FUNCTIONS                            │
    // ================================================================
    /**
     * @dev function {createDexPair}
     *
     * Creates a Uniswap v2 token pair.
     */
    function createDexPair() external payable onlyOwner {
        require(UNISWAP_V2_PAIR == address(0), "Pair already created");

        UNISWAP_V2_PAIR = UNISWAP_FACTORY.createPair(
            address(this),
            UNISWAP_ROUTER.WETH()
        );
    }

    /**
     * @dev function {burn}
     *
     * Burns a specified amount of tokens from the caller's balance.
     *
     * NOTE: Token amount set to burn will be completely removed and deducted from the token total supply.
     *
     * @param value Amount of tokens to burn.
     */
    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}