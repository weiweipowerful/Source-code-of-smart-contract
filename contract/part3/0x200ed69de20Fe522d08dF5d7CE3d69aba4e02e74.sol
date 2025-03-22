// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./utils/buyAndBurnConstants.sol";
import "./BlazeERC20.sol";
import "./library/oracle.sol";
import "./library/tickMath.sol";
import "./interfaces/IBuyBurn.sol";

/// @title BlazeAuction Protocol Contract
/// @notice This contract is used to participate in auctions and manage Blaze rewards and ETH fee distribution.
contract BlazeAuction is ReentrancyGuard, Ownable2Step {
    using SafeERC20 for BlazeERC20;

    /// @notice Token contract for Blaze rewards
    BlazeERC20 public blz;

    /// @notice Wallet address for distributing platform fees
    address public blazeWallet;

    /// @notice Contract address for Blaze staking functionality
    address public stakingContract;

    /// @notice Contract address for Blaze buyBurn functionality
    address public buyBurnContract;

    /// @notice ETH amount for each batch purchase
    uint256 public constant ETH_BATCH_AMOUNT = 2_000_000_000_000_000;

    /// @notice ETH amount for each batch purchase
    uint256 public constant BUY_BURN_ETH_IN_USD = 30000 ether;

    /// @notice Minimum time before fee claiming is allowed
    uint256 public constant EXCEPTION_PERIOD_DURATION = 3 days;

    /// @notice Timestamp of contract creation
    uint256 public immutable i_initialTimestamp;

    /// @notice Duration of each reward cycle
    uint256 public immutable i_periodDuration = 1 days;

    /// @notice Reward token amount allocated for the current reward cycle
    uint256 public currentCycleReward;

    /// @notice Index of the current reward cycle
    uint256 public currentCycle;
    
    /// @notice Total amount of batches purchased
    uint256 public totalNumberOfBatchesPurchased;

    uint32 private _usdcPriceTwa;

    /// @notice True if initial minting for buyburn has been done
    bool public isInitialBuyBurnMintDone;

    /// @notice True if initial 10 eth for buyburn has been transferred
    bool public isInitialBuyBurnLiquidityShared;

    /// @notice Tracks the total batches purchased by an account in the current cycle
    mapping(address => uint256) public accCycleBatchesPurchased;

    /// @notice Records the total batches purchased by an account in each cycle
    mapping(address => mapping(uint256 => uint256)) public accCycleAllBatchesPurchased;

    /// @notice Total number of batches purchased in each cycle
    mapping(uint256 => uint256) public cycleTotalBatchesPurchased;

    /// @notice Last active cycle for each account
    mapping(address => uint256) public lastActiveCycle;

    /// @notice Tracks unclaimed rewards per account
    mapping(address => uint256) public accRewards;

    /// @notice Reward tokens allocated per cycle
    mapping(uint256 => uint256) public rewardPerCycle;

    /// @notice Total accrued fees per cycle
    mapping(uint256 => uint256) public cycleAccruedFees;

    /// @notice Struct used for viewing user past auction records.
    struct Auctions {
        uint256 cycle;
        uint256 batchPower;
    }

    /// @notice Event emitted when rewards are claimed.
    event RewardsClaimed(uint256 indexed cycle, address indexed account, uint256 reward);

    /// @notice Event emitted when fees are claimed.
    event FeesClaimed(uint256 indexed cycle, address indexed account, uint256 reward);

    /// @notice Event emitted when a new cycle is started.
    event NewCycleStarted(uint256 indexed cycle, uint256 reward);
    
    /// @notice Event emitted when a new purchase is made.
    event Purchase(address indexed userAddress, uint256 batchNumber);
        
    /// @dev Initializes the contract with the specified wallet address.
    /// @param blazeWalletAddress Wallet address to initialize with.
    constructor(address blazeWalletAddress, bytes32 deploySalt) Ownable(_msgSender()) {
        address deploymentAddress = deployContract(deploySalt);
        blz = BlazeERC20(deploymentAddress);
        i_initialTimestamp = block.timestamp;
        currentCycleReward = 8888 * 1e18;
        rewardPerCycle[0] = currentCycleReward;
        blazeWallet = blazeWalletAddress;
        _usdcPriceTwa=15;
    }

    function deployContract(bytes32 deploySalt) internal returns (address) {
        bytes memory bytecode = type(BlazeERC20).creationCode;
        bytes32 bytecodeHash = keccak256(bytecode);
        address deploymentAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            deploySalt,
            bytecodeHash
        )))));
        address addr;
        bytes32 _salt = deploySalt;

        assembly {
            addr :=
                create2(
                    callvalue(), // wei sent with current call
                    // Actual code starts after skipping the first 32 bytes
                    add(bytecode, 0x20),
                    mload(bytecode), // Load the size of code contained in the first 32 bytes
                    _salt // Salt from function arguments
                )

            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
        return deploymentAddress;
    }

    /// @notice Allows users to purchase batches by paying ETH.
    /// @param batchNumber The number of batches to purchase.
    function purchaseBatch(uint256 batchNumber) external payable {
        require(batchNumber > 0, "Blaze: Invalid batch number");
        require(batchNumber <= 10000, "Blaze: Invalid batch number");
        uint256 requiredETHValue = batchNumber * ETH_BATCH_AMOUNT;
        require(msg.value >= requiredETHValue, "Blaze: Insufficient ETH amount");

        _updateCycle();
        _updateStats(_msgSender());
        
        totalNumberOfBatchesPurchased += batchNumber;
        cycleTotalBatchesPurchased[currentCycle] += batchNumber;
        accCycleBatchesPurchased[_msgSender()] += batchNumber;
        accCycleAllBatchesPurchased[_msgSender()][currentCycle] += batchNumber;
        cycleAccruedFees[currentCycle] += requiredETHValue;

        _refundExcess(msg.value - requiredETHValue);

        if(!isInitialBuyBurnLiquidityShared && 
                address(this).balance * getEthPrice() >= BUY_BURN_ETH_IN_USD){

            claimFees();
        }

        emit Purchase(_msgSender(), batchNumber);
    }

    /// @notice Claims accrued rewards for the caller.
    function claimRewards() external {
        require(block.timestamp >= EXCEPTION_PERIOD_DURATION + i_initialTimestamp, "Blaze: Claiming not allowed at this duration");
        
        _updateCycle();
        _updateStats(_msgSender());
        uint256 reward = accRewards[_msgSender()];
        require(reward > 0, "Blaze: No rewards");
        
        accRewards[_msgSender()] = 0;
        blz.mintReward(_msgSender(), reward);
        emit RewardsClaimed(currentCycle, _msgSender(), reward);
    }

    /// @notice Distributes accrued fees.
    function claimFees() public {
        require(buyBurnContract != address(0), "Blaze: BuyBurn Address not set");
        require(stakingContract != address(0), "Blaze: StakingContract Address not set");
        uint256 fees = address(this).balance;
        require(fees > 0, "Blaze: No ETH accrued");

        if(!isInitialBuyBurnLiquidityShared) {
            _exceptionCheck(fees);
            uint256 buyBurnPoolShare = BUY_BURN_ETH_IN_USD / getEthPrice();
            if (fees < buyBurnPoolShare){
                buyBurnPoolShare = fees;
            }
            _sendETH(buyBurnContract, buyBurnPoolShare);
            IBlazeBuyAndBurn(buyBurnContract).createLiquidityPool();
            IBlazeBuyAndBurn(buyBurnContract).createInitialLiquidity();
            isInitialBuyBurnLiquidityShared = true;
            fees -= buyBurnPoolShare;
        }

        uint256 stakingShare = (fees * 64) / 100;
        uint256 buyBurnShare = (fees * 20) / 100;
        uint256 foundersShare = fees - (buyBurnShare + stakingShare);
        
        _sendETH(blazeWallet, foundersShare );
        _sendETH(buyBurnContract, buyBurnShare);
        _sendETH(stakingContract, stakingShare);
        emit FeesClaimed(currentCycle, _msgSender(), fees);
    }

    /// @dev Update staking contract address by admin.
    function setStakingContract(address stakingContractAddress)
        external onlyOwner
    {
        require(stakingContract == address(0), "Blaze: Address already set");
        stakingContract = stakingContractAddress;
    }

    /// @dev Update buyBurn contract address by admin.
    function setBuyBurnContract(address buyBurnContractAddress)
        external onlyOwner
    {
        require(buyBurnContract == address(0), "Blaze: Address already set");
        buyBurnContract = buyBurnContractAddress;
    }

    /**
     * @notice set the TWA value used when calculting the ETH in USDC price. Only callable by owner address.
     * @param mins TWA in minutes
     */
    function setUSDCPriceTwa(uint32 mins) external onlyOwner {
        require(mins >= 5 && mins <= 60, "BlazeBuyAndBurn:5m-1h only");
        _usdcPriceTwa = mins;
    }

    /// @dev Update buyBurn contract address by admin.
    function mintBlazeTokensForLP()
        external 
    {
        require(_msgSender() == buyBurnContract, "Blaze: Caller not BuyBurnContract");
        require(!isInitialBuyBurnMintDone, "Blaze: Already Minted");
        blz.mintReward(buyBurnContract, 14000 ether);
        isInitialBuyBurnMintDone = true;
    }

    /// @dev Returns the index of the cycle at the current block time.
    function getCurrentCycle() public view returns (uint256) {
        return (block.timestamp - i_initialTimestamp) / i_periodDuration;
    }
    /**
     * @dev Unclaimed rewards represent the amount of blaze reward tokens 
     * that were allocated but were not withdrawn by a given account.
     * 
     * @param account the address to query the unclaimed rewards for
     * @return the amount in wei
     */
    function getUnclaimedRewards(address account)
        public
        view
        returns (uint256)
    {
        uint256 currentRewards = accRewards[account];
        uint256 calculatedCycle = getCurrentCycle();

       if (
            calculatedCycle > lastActiveCycle[account] &&
            accCycleBatchesPurchased[account] != 0
        ) {
            uint256 lastCycleAccReward = (accCycleBatchesPurchased[account] *
                rewardPerCycle[lastActiveCycle[account]]) /
                cycleTotalBatchesPurchased[lastActiveCycle[account]];

            currentRewards += lastCycleAccReward;
        }

        return currentRewards;
    }

    function getAmountsInRangeWithStructs(address user, uint256 startCycle, uint256 endCycle) 
        external view returns (Auctions[] memory) {
        require(endCycle >= startCycle, "Blaze: Invalid cycle numbers");

        Auctions[] memory cycleAmounts = new Auctions[](endCycle - startCycle + 1);
        for (uint256 _cycle = startCycle; _cycle <= endCycle; ++_cycle) {
            cycleAmounts[_cycle - startCycle] = 
                Auctions({cycle: _cycle, batchPower: accCycleAllBatchesPurchased[user][_cycle]});
        }
        
        return cycleAmounts;
    }

    function getEthPrice() public view returns (uint256) {
        uint256 usdcAmountPerEth= _getUSDCQuoteForEth();
        uint8 decimals=IERC20Metadata(USDC_ADDRESS).decimals();
        return usdcAmountPerEth/10**decimals;
    }

    function _getUSDCQuoteForEth() private view returns (uint256 _quote) {
        address poolAddress=ETH_USDC_POOL;
        uint256 baseAmount=1 ether;
        uint32 secondsAgo = _usdcPriceTwa * 60;
        uint32 oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(
            poolAddress
        );

        // Limit to oldest observation
        if (oldestObservation < secondsAgo) {
            secondsAgo = oldestObservation;
        }

        uint160 sqrtPriceX96;
        if (secondsAgo == 0) {
            // Default to current price
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            (sqrtPriceX96, , , , , , ) = pool.slot0();
        } else {
            // Consult the Oracle Library for TWAP
            (int24 arithmeticMeanTick, ) = OracleLibrary.consult(
                poolAddress,
                secondsAgo
            );

            // Convert tick to sqrtPriceX96
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        }

        return
            OracleLibrary.getQuoteForSqrtRatioX96(
                sqrtPriceX96,
                baseAmount,
                WETH9,
                USDC_ADDRESS
            );
    }

    /// @dev Internal function to handle excess ETH refunds.
    function _exceptionCheck(uint256 fees) private view{
        //Claiming is only allowed after either 3 days have passed, or minimum of 30000 usd worth eth have been accumulated
        require(fees * getEthPrice() >= BUY_BURN_ETH_IN_USD || block.timestamp >= EXCEPTION_PERIOD_DURATION + i_initialTimestamp, 
            "Blaze: Claiming not allowed at this duration");
    }

    /// @dev Internal function to handle excess ETH refunds.
    function _refundExcess(uint256 amount) private {
        if (amount > 0) {
            (bool sent, ) = payable(_msgSender()).call{value: amount}("");
            require(sent, "Blaze: Refund failed");
        }
    }

    /// @dev Internal function to send ETH to a specified address.
    function _sendETH(address to, uint256 amount) private {
        (bool sent, ) = payable(to).call{value: amount}("");
        require(sent, "Blaze: Failed to send ETH");
    }

    /// @dev Internal function to update the current cycle and manage transitions between cycles.
    function _updateCycle() private {
        uint256 newCycle = (block.timestamp - i_initialTimestamp) / i_periodDuration;
        if (newCycle > currentCycle) {
            // lastCycleReward = currentCycleReward;
            currentCycleReward = (currentCycleReward * 9992) / 10000;
            rewardPerCycle[newCycle] = currentCycleReward;
            currentCycle = newCycle;
            emit NewCycleStarted(newCycle, currentCycleReward);
        }
    }

    /// @dev Internal function to update account statistics after an operation affecting the rewards.
    /// @param account The account for which to update statistics.
    function _updateStats(address account) private {
        if (lastActiveCycle[account] < currentCycle) {
            if (accCycleBatchesPurchased[account] > 0) {
                uint256 pastReward = (accCycleBatchesPurchased[account] * rewardPerCycle[lastActiveCycle[account]]) / cycleTotalBatchesPurchased[lastActiveCycle[account]];
                accRewards[account] += pastReward;
            }
            accCycleBatchesPurchased[account] = 0;
            lastActiveCycle[account] = currentCycle;
        }
    }


}