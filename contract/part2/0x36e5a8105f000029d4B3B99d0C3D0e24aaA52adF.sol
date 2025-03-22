// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* == OZ == */
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/* == CORE == */
import {Flux} from "@core/Flux.sol";
import {FluxStaking} from "@core/Staking.sol";
import {FluxBuyAndBurn} from "@core/FluxBuyAndBurn.sol";

/* == ACTIONS == */
import {SwapActions} from "@actions/SwapActions.sol";

/* == UTILS == */
import {Time} from "@utils/Time.sol";
import {wdiv, wmul, sub, wpow} from "@utils/Math.sol";

/* == CONST == */
import "@const/Constants.sol";

/* == UNIV3 == */
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

/* == INTERFACES == */
import {IInferno} from "@interfaces/IInferno.sol";
import {IDragonX} from "@interfaces/IDragonX.sol";

///@notice Struct is packed to take up exatctly 1 storage slot
struct UserAuction {
    uint32 ts;
    uint32 day;
    uint192 amount;
}

///@notice Struct is packed to take up exatctly 1 storage slot
struct DailyStatistic {
    uint128 fluxEmitted;
    uint128 titanXDeposited;
}

///@notice Struct is packed to take up half a storage slot
struct LP {
    bool hasLP;
    bool isFluxToken0;
    uint240 tokenId;
}

/**
 * @title FluxAuction
 * @author Zyntek
 * @dev Contract to auction ERC20 to earn a proportional amount of FLUX
 */
contract FluxAuction is SwapActions {
    using SafeERC20 for ERC20Burnable;

    FluxBuyAndBurn immutable buyAndBurn;
    IDragonX immutable dragonX;
    uint32 public immutable startTimestamp;
    //=========STORAGE==========//

    LP public lp;

    uint64 depositId;

    uint256 public sentToHelios;
    uint256 public sentToDragonX;

    uint256 public fluxFeesClaimed;
    uint256 public infernoFeesClaimed;

    mapping(address => mapping(uint64 id => UserAuction)) public depositOf;
    mapping(uint32 day => DailyStatistic) public dailyStats;

    //==========ERRORS==========//

    error FluxAuction__OnlyClaimableAfter24Hours();
    error FluxAuction__LiquidityAlreadyAdded();
    error FluxAuction__NotEnoughTitanXForLiquidity();
    error FluxAuction__NotStartedYet();
    error FluxAuction__AuctionIsOver();
    error FluxAuction__NothingToClaim();
    error FluxAuction__AuctionsMustStartAt5PMUTC();
    error FluxAuction__TransactionTooOld();

    //=========EVENTS==========//

    event UserDeposit(address indexed user, uint256 indexed amount, uint32 indexed day, uint248 id);
    event UserClaimed(address indexed user, uint256 indexed fluxAmount, uint248 indexed id);
    event AutoBoughtAndMaxStaked(
        uint256 indexed amount, address indexed forUser, uint256 indexed _stakingId, uint256 shares
    );
    event AddedLiquidity(uint256 indexed infernoAmount);

    //=======CONSTRUCTOR========//

    constructor(
        uint32 _startTimestamp,
        address _flux,
        IInferno _inferno,
        ERC20Burnable _titanX,
        address _owner,
        FluxBuyAndBurn _bnb,
        address _titanXInfernoPool,
        address _dragonXVault
    ) SwapActions(_flux, _titanX, _inferno, _titanXInfernoPool, _owner) {
        if ((_startTimestamp - 17 hours) % 1 days != 0) {
            revert FluxAuction__AuctionsMustStartAt5PMUTC();
        }

        dragonX = IDragonX(_dragonXVault);
        startTimestamp = _startTimestamp;

        buyAndBurn = _bnb;
    }

    //==========================//
    //=====EXTERNAL/PUBLIC======//
    //==========================//

    function deposit(uint192 _amount) external {
        if (startTimestamp > Time.blockTs()) revert FluxAuction__NotStartedYet();
        if (startTimestamp + 2922 days < Time.blockTs()) {
            revert FluxAuction__AuctionIsOver();
        }
        _updateAuction();

        UserAuction storage userDeposit = depositOf[msg.sender][++depositId];
        uint32 currentDay = Time.daysSince(startTimestamp);
        DailyStatistic storage stats = dailyStats[currentDay];

        titanX.safeTransferFrom(msg.sender, address(this), _amount);

        uint192 maxBuyStake = startTimestamp + 24 hours <= Time.blockTs() ? uint192(wmul(_amount, uint256(0.5e18))) : 0;

        uint192 amtToDeposit = _amount;

        if (maxBuyStake != 0) {
            amtToDeposit -= maxBuyStake;
            titanX.approve(address(buyAndBurn), maxBuyStake);
            buyAndBurn.distributeTitanXForBurning(maxBuyStake);
        }

        userDeposit.ts = Time.blockTs();
        userDeposit.amount = amtToDeposit;
        userDeposit.day = currentDay;
        stats.titanXDeposited += uint128(amtToDeposit);

        emit UserDeposit(msg.sender, amtToDeposit, currentDay, depositId);

        _ditributeTokens(amtToDeposit);
    }

    function claim(uint64 _id) public {
        UserAuction storage userDep = depositOf[msg.sender][_id];

        if (userDep.ts + 24 hours > Time.blockTs()) revert FluxAuction__OnlyClaimableAfter24Hours();

        uint256 toClaim = amountToClaim(msg.sender, _id);

        if (toClaim == 0) revert FluxAuction__NothingToClaim();

        if (userDep.day != 0) _maxStake(uint160(toClaim));

        emit UserClaimed(msg.sender, toClaim, _id);

        flux.transfer(msg.sender, toClaim);

        userDep.amount = 0;
    }

    function batchClaim(uint64[] calldata _ids) external {
        for (uint256 i; i < _ids.length; ++i) {
            claim(_ids[i]);
        }
    }

    function batchClaimableAmount(address _user, uint64[] calldata _ids) public view returns (uint256 toClaim) {
        for (uint256 i; i < _ids.length; ++i) {
            toClaim += amountToClaim(_user, _ids[i]);
        }
    }

    function amountToClaim(address _user, uint64 _id) public view returns (uint256 toClaim) {
        UserAuction storage userDep = depositOf[_user][_id];
        DailyStatistic memory stats = dailyStats[userDep.day];

        uint256 fluxPerTitanX = wdiv(stats.fluxEmitted, stats.titanXDeposited);

        return wmul(userDep.amount, fluxPerTitanX);
    }

    /**
     * @notice Adds liquidity to the INF/FLUX UniV3 Pool
     * @param _deadline The deadline for the liquidity addition
     */
    function addLiquidityToInfernoFluxPool(uint32 _deadline) external onlyOwner {
        if (lp.hasLP) revert FluxAuction__LiquidityAlreadyAdded();
        if (titanX.balanceOf(address(this)) < INITIAL_TITAN_X_FOR_LIQ) {
            revert FluxAuction__NotEnoughTitanXForLiquidity();
        }

        uint256 infernoReceived = _swapTitanXForInferno(INITIAL_TITAN_X_FOR_LIQ, _deadline);

        flux.emitFlux(address(this), INITIAL_FLUX_FOR_LP);

        (uint256 amount0, uint256 amount1, uint256 amount0Min, uint256 amount1Min, address token0, address token1) =
            _sortAmountsForLP(infernoReceived, INITIAL_FLUX_FOR_LP);

        ERC20Burnable(token0).approve(UNISWAP_V3_POSITION_MANAGER, amount0);
        ERC20Burnable(token1).approve(UNISWAP_V3_POSITION_MANAGER, amount1);

        // wake-disable-next-line
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: POOL_FEE,
            tickLower: (TickMath.MIN_TICK / TICK_SPACING) * TICK_SPACING,
            tickUpper: (TickMath.MAX_TICK / TICK_SPACING) * TICK_SPACING,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: _deadline
        });

        // wake-disable-next-line
        (uint256 tokenId,,,) = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER).mint(params);

        bool isFluxToken0 = token0 == address(flux);

        emit AddedLiquidity(infernoReceived);

        lp = LP({hasLP: true, tokenId: uint240(tokenId), isFluxToken0: isFluxToken0});
    }

    //==========================//
    //=========INTERNAL=========//
    //==========================//

    function _updateAuction() internal {
        uint32 currentDay = Time.daysSince(startTimestamp);

        if (dailyStats[currentDay].fluxEmitted == 0) {
            uint32 currWeek = Time.weekSince(startTimestamp);

            uint160 emitted = uint160(wmul(AUCTION_EMIT, wpow(sub(WAD, WEEKLY_EMISSION_DROP), currWeek, WAD)));

            flux.emitFlux(address(this), emitted);

            dailyStats[currentDay].fluxEmitted = uint128(emitted);
        }
    }

    function _ditributeTokens(uint256 _amount) private {
        if (!lp.hasLP) {
            uint256 titanXBalance = titanX.balanceOf(address(this));

            if (titanXBalance <= INITIAL_TITAN_X_FOR_LIQ) return;

            //@note - If there is no added liquidity, but the balance exceeds the initial for liquidity for distribution should be the difference
            _amount = uint192(titanXBalance - INITIAL_TITAN_X_FOR_LIQ);
        }

        uint256 _toDragonX = wmul(_amount, TITAN_X_DRAGON_X);
        uint256 _toHelios = wmul(_amount, TITAN_X_HELIOS);
        uint256 _toFluxBnB = wmul(_amount, FLUX_BUY_AND_BURN);
        uint256 _toStaking = wmul(_amount, REWARD_POOLS);
        uint256 _toGenesis = wmul(_amount, GENESIS);

        titanX.safeTransfer(address(dragonX), _toDragonX);
        dragonX.updateVault();

        sentToDragonX += _toDragonX;

        FluxStaking staking = flux.staking();

        titanX.approve(address(staking), _toStaking);
        staking.distribute(_toStaking);

        titanX.approve(address(buyAndBurn), _toFluxBnB);
        buyAndBurn.distributeTitanXForBurning(_toFluxBnB);

        titanX.safeTransfer(HELIOS_ADDR, _toHelios);

        sentToHelios += _toHelios;

        titanX.safeTransfer(GENESIS_WALLET, _toGenesis);
    }

    /**
     * @notice Sends the fees acquired from the UniswapV3 position
     * @return amount0 The amount of token0 collected
     * @return amount1 The amount of token1 collected
     */
    function collectFees() external returns (uint256 amount0, uint256 amount1) {
        LP memory _lp = lp;

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: _lp.tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER).collect(params);

        (uint256 fluxAmount, uint256 infernoAmount) = _lp.isFluxToken0 ? (amount0, amount1) : (amount1, amount0);

        infernoFeesClaimed += infernoAmount;
        fluxFeesClaimed += fluxAmount;

        inferno.transfer(FEES_WALLET, infernoAmount);
        flux.transfer(FEES_WALLET, fluxAmount);
    }

    function _maxStake(uint160 _fluxAmount) private {
        flux.emitFlux(address(this), _fluxAmount);

        FluxStaking staking = flux.staking();

        flux.approve(address(staking), _fluxAmount);
        (uint256 _tokenId, uint144 shares) = staking.stake(staking.MAX_DURATION(), _fluxAmount);

        emit AutoBoughtAndMaxStaked(_fluxAmount, msg.sender, _tokenId, shares);
        //Approve the user to be able to claim when the time comes
        staking.approve(msg.sender, _tokenId);
    }
}