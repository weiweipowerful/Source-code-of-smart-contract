// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./AGRT.sol";
import "./DEXNFT.sol";
import "./a1/ISwapRouter02.sol";


contract DEXIndex is ERC20 {
    address constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    ISwapRouter02 constant uniswapRouter2 = ISwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    AGRT  constant esdt = AGRT(0x28741655c578c888Bca330aAe9d7f176DA1346DF);
    DEXNFT public dexNFT = DEXNFT(0x5C05d05446F9544218E075607BeF4448b853d8Bf);
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    /*
     * Events are emitted the three main public functions
     */
    event Buy(
        address indexed _from,
        uint256 _totalESDTAmount,
        uint256 _depositAmount,
        uint256 tokenId,
        address create,
        uint256[] tokenAmounts
    );

    // -------  State ------- //
    address[] public tokenAddresses;
    uint256[] public percentageHoldings;
    uint256 public ownerFee;
    address public owner;

    // --------------------------  Functions  ------------------------- //
    /*
     * Create a new Portfolio token representing a set of underlying assets.
     *
     * @param  name_   the name of the Portfolio
     * @param  symbol_   the symbol for the Portfolio token
     * @param  tokenAddresses_   the addresses of the ERC20 tokens that make up the Portfolio
     * @param  percentageHoldings_   the desired percentage holding for each token specified in tokenAddresses_
     * @param  owner_   the address of the Portfolio owner
     * @param  ownerFee_   the size of the fee paid to the owner by buyers (in basis points)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory tokenAddresses_,
        uint256[] memory percentageHoldings_,
        address owner_,
        uint256 ownerFee_
    ) ERC20(name_, symbol_) {
        require(
            tokenAddresses_.length == percentageHoldings_.length,
            "Please specify the same number of token addresses as percentage holdings"
        );
        require(
            sum(percentageHoldings_) == 1000000,
            "Percentage holdings must sum to 1000000"
        );
        require(
            ownerFee >= 0 && ownerFee < 1000000,
            "Owner Fee must be between 0 (0%) and 1000000 (100%)"
        );
        tokenAddresses = tokenAddresses_;
        percentageHoldings = percentageHoldings_;
        owner = owner_;
        ownerFee = ownerFee_; // Number from 0-1000000 (where 1000000 represents 100%)
    }

    // ---------------------  Initalise Portfolio --------------------- //

    function initialisePortfolio(
        uint256 esdtAmount
    ) public onlyOwner  {
        require(esdtAmount > 0, "ESDT required");
        _mint(owner, esdtAmount);
    }

    // -------------------------- Buy & Deposit ----------------------- //

    /*
     * Purchase underlying assets with ESDT and issue new Portfolio tokens to the buyer.
     *
     * @param  esdtAmount   the amount of ESDT to spend
     */
    function buy(uint256 esdtAmount, uint256 fee, string memory uri) public nonZeroTotalSupply {
        require(esdtAmount >= 1000000, "value you entered is too small");
        require(
            esdt.allowance(msg.sender, address(this)) >= esdtAmount + fee,
            "Insufficient allowance"
        );
        require(
            esdt.balanceOf(msg.sender) >= esdtAmount + fee,
            "Insufficient balance"
        );
        require(fee >= (esdtAmount * ownerFee / 1000000), "Fee not enough.");
        esdt.transferFrom(msg.sender, address(this), esdtAmount);
        esdt.transferFrom(msg.sender, owner, fee);
        uint256 usdtAmount = esdtAmount / 10**12; // Assuming 1:1 ratio for simplicity
        _transferUSDTFromOwner(usdtAmount);
        uint256[] memory acquiredTokens = deposit(usdtAmount);
        (uint256 tokenId, address create, uint256 amount) = dexNFT.safeMint(msg.sender, uri, esdtAmount, address(this), acquiredTokens);
        emit Buy(msg.sender, esdtAmount + fee, amount, tokenId, create, acquiredTokens);
        _burn(owner, esdtAmount);
    }

    function usdtBuy(uint256 usdtAmount, uint256 fee, string memory uri) public nonZeroTotalSupply {
        require(usdtAmount >= 0, "value you entered is too small");
        require(
            ERC20(USDT_ADDRESS).balanceOf(msg.sender) >= usdtAmount + fee,
            "Insufficient balance"
        );
        require(fee >= ((usdtAmount * ownerFee) / 1000000), "Fee not enough.");
        TransferHelper.safeTransferFrom(USDT_ADDRESS, msg.sender, address(this), usdtAmount);
        TransferHelper.safeTransferFrom(USDT_ADDRESS, msg.sender, owner, fee);
        uint256[] memory acquiredTokens = deposit(usdtAmount);
        (uint256 tokenId, address create, uint256 amount) = dexNFT.safeMint(msg.sender, uri, usdtAmount, address(this), acquiredTokens);
        emit Buy(msg.sender, usdtAmount + fee, amount, tokenId, create, acquiredTokens);
        _burn(owner, usdtAmount);
    }

    function _transferUSDTFromOwner(uint256 usdtAmount) private {
        require(
            IERC20(USDT_ADDRESS).allowance(owner, address(this)) >= usdtAmount,
            "Insufficient USDT allowance"
        );
        require(
            IERC20(USDT_ADDRESS).balanceOf(owner) >= usdtAmount,
            "Insufficient USDT balance"
        );
        TransferHelper.safeTransferFrom(USDT_ADDRESS, owner, address(this), usdtAmount);
    }

    /*
     * Spend ESDT held by this contract on the tokens required by the portfolio.
     *
     * @param  _totalESDTAmount   the amount of ESDT to spend
     * @return                    the value of the Portfolio's holdings prior to the deposit
     */
    function deposit(uint256 _totalUSDTAmount) private returns (uint256[] memory) {
        uint256[] memory acquiredTokensArray = new uint256[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            uint256 esdtToSpend = (_totalUSDTAmount * percentageHoldings[i]) / 1000000;
            if (tokenAddresses[i] == WETH_ADDRESS) {
                uint256 wethAmount1 = swapIn(USDT_ADDRESS,WETH_ADDRESS,esdtToSpend,address(this));
                acquiredTokensArray[i] = wethAmount1;
                continue;
            }
            uint256 wethAmount = swapIn(USDT_ADDRESS,WETH_ADDRESS,esdtToSpend,address(this));
            uint256 acquiredTokens = swapIn(
                WETH_ADDRESS,
                tokenAddresses[i],
                wethAmount,
                address(this)
            );
            acquiredTokensArray[i] = acquiredTokens;
        }
        return acquiredTokensArray;
    }

    // -------------------- Sell & Redeem Mechanisms ------------------ //


    function redeem(uint256 tokenId,address nftOwner,uint256 percent) public onlyNFTContract {
        require(nftOwner != address(0), "Invalid NFT owner");
        (uint256 purchaseAmount, ,uint256[] memory acquiredTokens) = dexNFT.getPurchaseDetails(tokenId);
        require(purchaseAmount > 0, "Invalid purchase amount");
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            uint256 tokenAmount = acquiredTokens[i];
            uint256 fee = tokenAmount *  percent / 1000000;
            // TransferHelper.safeTransferFrom(tokenAddresses[i],address(this),owner,fee);
            if (tokenAddresses[i] == WETH_ADDRESS){
                //直接转
                IERC20(tokenAddresses[i]).transfer(nftOwner,tokenAmount-fee);
                if (fee > 0){
                    IERC20(tokenAddresses[i]).transfer(owner,fee);
                }
            }else{
                uint256 inAmount =  swapIn(
                tokenAddresses[i],
                WETH_ADDRESS,
                tokenAmount-fee,
                address(this)
                );
                // TransferHelper.safeTransferFrom(tokenAddresses[i],address(this),nftOwner,tokenAmount-fee);
                swapIn(
                    WETH_ADDRESS,
                    tokenAddresses[i],
                    inAmount,
                    nftOwner
                );
                if (fee > 0){
                    swapIn(
                    tokenAddresses[i],
                    WETH_ADDRESS,
                    fee,
                    owner
                    );
                }
            }
           
        }
        _mint(owner,purchaseAmount);
    }

    function redeemEsdt(uint256 tokenId,address nftOwner) public onlyNFTContract {
        require(nftOwner != address(0), "Invalid NFT owner");
        (uint256 purchaseAmount, ,uint256[] memory acquiredTokens) = dexNFT.getPurchaseDetails(tokenId);
        require(purchaseAmount > 0, "Invalid purchase amount");
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            uint256 tokenAmount = acquiredTokens[i];
            if (tokenAddresses[i] == WETH_ADDRESS){
                //直接转
                IERC20(tokenAddresses[i]).transfer(owner,tokenAmount);
            }else{
                swapIn(
                    tokenAddresses[i],
                    WETH_ADDRESS,
                    tokenAmount,
                    owner
                );
            }
            // TransferHelper.safeTransferFrom(tokenAddresses[i],address(this),owner,tokenAmount);
        }
        _mint(owner,purchaseAmount);
    }




    modifier onlyNFTContract() {
        require(msg.sender == address(dexNFT), "Only the NFT contract can call this function.");
        _;
    }


    // --------------------------- Swap tokens ------------------------ //

    function swapIn(
        address tokenIn,
        address tokenOut,
        uint256 tokenInAmount,
        address recipient
    ) private returns (uint256) {
        uint256 _numTokensAcquired = 0;
        if (tokenOut == address(esdt)) {
            _numTokensAcquired = tokenInAmount;
        } else {
            _numTokensAcquired = callUniswap2(
                tokenIn,
                tokenOut,
                tokenInAmount,
                recipient
            );
        }
        return _numTokensAcquired;
    }

    

    function callUniswap2(
        address _tokenIn,
        address _tokenOut,
        uint256 _tokenInAmount,
        address _recipient
    ) private returns (uint256) {
        TransferHelper.safeApprove(
            _tokenIn,
            address(uniswapRouter2),
            _tokenInAmount
        );
        ISwapRouter02.ExactInputSingleParams memory params = IV3SwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: 3000,
                recipient: _recipient,
                amountIn: _tokenInAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        uint256 numTokensAcquired = uniswapRouter2.exactInputSingle(params);
        return numTokensAcquired;
    }

    // ------------------------- Misc Functions ----------------------- //

    function sum(uint256[] memory list) private pure returns (uint256) {
        uint256 s = 0;
        for (uint256 i = 0; i < list.length; i++) {
            s += list[i];
        }
        return s;
    }

    function getBalance(
        address _tokenAddress,
        address _address
    ) private view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(_address);
    }

    // --------------------------- Modifiers -------------------------- //

    modifier onlyOwner() {
        require(
            owner == msg.sender,
            "Only the owner can initialise the Portfolio."
        );
        _;
    }

    modifier nonZeroTotalSupply() {
        require(
            totalSupply() > 0,
            "Total supply is 0.  Contract must be initialised."
        );
        _;
    }

    modifier zeroTotalSupply() {
        require(
            totalSupply() == 0,
            "Total supply is greater than 0 and does not need to be initialised."
        );
        _;
    }

    function getTokenAddresses() public view returns (address[] memory) {
        return tokenAddresses;
    }

    function getPercentageHoldings() public view returns (uint256[] memory) {
        return percentageHoldings;
    }

    // function setTokenAddresses(
    //     address[] memory _tokenAddresses
    // ) public onlyOwner {
    //     tokenAddresses = _tokenAddresses;
    // }

    // function setPercentageHoldings(
    //     uint256[] memory _percentageHoldings
    // ) public onlyOwner {
    //     percentageHoldings = _percentageHoldings;
    // }
}