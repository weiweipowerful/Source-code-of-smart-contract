// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./PoW.sol";

contract DuckAI is ERC20, PoW, Ownable {
    uint256 public MINT_DURATION_BLOCKS;
    uint256 public startBlock;
    uint256 public DIFFICULTY = 100_000;
    uint256 public constant MINT_FEE = 0.00069 ether;
    uint256 public constant MAX_MINTS_PER_ADDRESS = 10;
    
    uint256 public DIFFICULTY_ADJUSTMENT_INTERVAL;
    uint256 public MAX_SUPPLY;
    uint256 public MINT_AMOUNT_PER_TX;

    struct DifficultyAdjustment {
        uint256 step;
        uint256 level;
    }

    mapping(uint256 => uint256) public difficultyMap;
    uint256 public lastDifficultyAdjustmentBlock;

    mapping(address => uint256) public mintCount;
    IUniswapV2Router02 public uniswapRouter;

    constructor(
        uint256 maxSupply,
        uint256 tokenPerMint,
        uint256 mintDurationBlocks,
        uint256 difficultyAdjustmentInterval,
        uint256 _startBlock,
        DifficultyAdjustment[] memory _difficultyAdjustments,
        address _uniswapRouter
    ) ERC20("DuckAI", "DUCKAI") Ownable(msg.sender) {
        MAX_SUPPLY = maxSupply;
        MINT_AMOUNT_PER_TX = tokenPerMint;
        MINT_DURATION_BLOCKS = mintDurationBlocks;
        startBlock = _startBlock;
        DIFFICULTY_ADJUSTMENT_INTERVAL = difficultyAdjustmentInterval;
         for (uint256 i = 0; i < _difficultyAdjustments.length; i++) {
            difficultyMap[_difficultyAdjustments[i].step] = _difficultyAdjustments[i].level;
        }

        uint256 initialMintAmount = (maxSupply * 25) / 100;
        _mint(address(this), initialMintAmount);

         uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    function mint(uint256 nonce) external payable {
        require(block.number >= startBlock, "Minting has not started yet");
        require(msg.sender == tx.origin, "Deny contract mint");
        require(totalSupply() + MINT_AMOUNT_PER_TX <= MAX_SUPPLY, "Max supply reached");
        require(mintCount[msg.sender] < MAX_MINTS_PER_ADDRESS, "Mint limit reached for the address");
        require(msg.value == MINT_FEE, "Insufficient mint fee");

        uint256 blocksElapsed = block.number - startBlock;
        if (blocksElapsed > MINT_DURATION_BLOCKS) {
            MAX_SUPPLY = totalSupply(); 
            payable(msg.sender).transfer(msg.value); // refund the mint fee to msg.sender
            return;
        }

        _verifyPoW(nonce, DIFFICULTY);
        mintCount[msg.sender]++;
        _mint(msg.sender, MINT_AMOUNT_PER_TX);

        if (blocksElapsed > lastDifficultyAdjustmentBlock) {
            uint256 adjustmentBlock = (blocksElapsed / DIFFICULTY_ADJUSTMENT_INTERVAL) * DIFFICULTY_ADJUSTMENT_INTERVAL;
            uint256 newDifficulty = difficultyMap[adjustmentBlock];
            if (newDifficulty != 0 && newDifficulty != DIFFICULTY) {
                DIFFICULTY = newDifficulty;
                lastDifficultyAdjustmentBlock = adjustmentBlock;
            }
        }
    }

    function addLiquidity() external {
        require(totalSupply() ==  MAX_SUPPLY, "Minting is still active");
        uint256 tokenBalance = balanceOf(address(this));
        uint256 ethBalance = address(this).balance;

        require(tokenBalance > 0, "No tokens to add to liquidity");
        require(ethBalance > 0, "No ETH to add to liquidity");

        _approve(address(this), address(uniswapRouter), tokenBalance);
        uniswapRouter.addLiquidityETH{value: ethBalance}(
            address(this),
            tokenBalance,
            0,
            0,
            0x0000000000000000000000000000000000000000, // burn LP tokens
            block.timestamp
        );
    }

    function transferOwnership(address /* newOwner */) public override onlyOwner {
        // transfer ownership to vitalik.eth
        super.transferOwnership(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045);
    }
}