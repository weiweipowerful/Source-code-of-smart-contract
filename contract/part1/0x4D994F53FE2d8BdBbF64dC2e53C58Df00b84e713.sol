// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@const/Constants.sol";
import "@actions/SwapActions.sol";
import {Time} from "@utils/Time.sol";
import {Errors} from "@utils/Errors.sol";
import {wdiv, wmul} from "@utils/Math.sol";
import {IVyper} from "@interfaces/IVyper.sol";
import {VyperBoostTreasury} from "@core/Treasury.sol";
import {VyperBoostBuyAndBurn} from "@core/BuyAndBurn.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

struct DailyStatistic {
    uint128 vyperEmitted;
    uint128 dragonXDeposited;
}

/**
 * @title VyperBoostAuction
 */
contract VyperBoostAuction is Errors {
    using SafeERC20 for *;

    IVyper public immutable vyper;
    ERC20Burnable public immutable dragonX;
    uint32 public immutable startTimestamp;
    address public immutable voltBurn;
    VyperBoostTreasury public immutable treasury;
    VyperBoostBuyAndBurn immutable bnb;

    mapping(address => mapping(uint32 day => uint256 amount)) public depositOf;
    mapping(uint32 day => DailyStatistic) public dailyStats;

    error OnlyClaimableTheNextDay();
    error LiquidityAlreadyAdded();
    error NotStartedYet();
    error NothingToClaim();
    error TreasuryVoltIsEmpty();
    error MustStartAt2PMUTC();

    event UserDeposit(address indexed user, uint256 indexed amount, uint32 indexed day);
    event UserClaimed(address indexed user, uint256 indexed vyperAmount, uint32 indexed day);

    constructor(uint32 _startTimestamp, address _vyper, address _dragonX, VyperBoostBuyAndBurn _bnb, address _voltBurn)
        notAddress0(_vyper)
        notAddress0(_dragonX)
        notAddress0(_voltBurn)
        notAddress0(address(_bnb))
    {
        if ((_startTimestamp - 14 hours) % 1 days != 0) revert MustStartAt2PMUTC();

        vyper = IVyper(_vyper);
        voltBurn = _voltBurn;
        bnb = _bnb;
        dragonX = ERC20Burnable(_dragonX);

        treasury = new VyperBoostTreasury(address(this), address(vyper));
        startTimestamp = _startTimestamp;
    }

    function deposit(uint192 _amount) external notAmount0(_amount) {
        if (startTimestamp > Time.blockTs()) revert NotStartedYet();

        _updateAuction();

        uint32 daySinceStart = Time.dayGap(startTimestamp, Time.blockTs()) + 1;

        DailyStatistic storage stats = dailyStats[daySinceStart];

        dragonX.safeTransferFrom(msg.sender, address(this), _amount);

        _distribute(_amount);

        depositOf[msg.sender][daySinceStart] += _amount;

        stats.dragonXDeposited += uint128(_amount);

        emit UserDeposit(msg.sender, _amount, daySinceStart);
    }

    function claim(uint32 _day) public {
        uint32 daySinceStart = Time.dayGap(startTimestamp, Time.blockTs()) + 1;
        if (_day == daySinceStart) revert OnlyClaimableTheNextDay();

        uint256 toClaim = amountToClaim(msg.sender, _day);

        if (toClaim == 0) revert NothingToClaim();

        emit UserClaimed(msg.sender, toClaim, _day);

        vyper.transfer(msg.sender, toClaim);

        depositOf[msg.sender][_day] = 0;
    }

    function batchClaim(uint32[] calldata _days) external {
        for (uint256 i; i < _days.length; ++i) {
            claim(_days[i]);
        }
    }

    function batchClaimableAmount(address _user, uint32[] calldata _days) public view returns (uint256 toClaim) {
        for (uint256 i; i < _days.length; ++i) {
            toClaim += amountToClaim(_user, _days[i]);
        }
    }

    function amountToClaim(address _user, uint32 _day) public view returns (uint256 toClaim) {
        uint32 daySinceStart = Time.dayGap(startTimestamp, Time.blockTs()) + 1;

        if (_day == daySinceStart) return 0;
        uint256 depositAmount = depositOf[_user][_day];

        DailyStatistic memory stats = dailyStats[_day];

        return (depositAmount * stats.vyperEmitted) / stats.dragonXDeposited;
    }

    ///@notice - Distributes the tokens
    function _distribute(uint256 _amount) internal {
        dragonX.transfer(DEAD_ADDR, wmul(_amount, DX_BURN));

        dragonX.transfer(LIQUIDITY_BONDING_ADDR, wmul(_amount, TO_LP));
        dragonX.transfer(DEV_WALLET, wmul(_amount, TO_DEV_WALLET));
        dragonX.transfer(GENESIS_WALLET, wmul(_amount, TO_GENESIS));
        dragonX.transfer(voltBurn, wmul(_amount, TO_VOLT_BURN));

        dragonX.approve(address(bnb), wmul(_amount, TO_BNB));
        bnb.distributeDragonXForBurning(wmul(_amount, TO_BNB));
    }

    ///@notice Emits the needed VYPER
    function _updateAuction() internal {
        uint32 daySinceStart = Time.dayGap(startTimestamp, Time.blockTs()) + 1;

        if (dailyStats[daySinceStart].vyperEmitted != 0) return;

        if (vyper.balanceOf(address(treasury)) == 0) revert TreasuryVoltIsEmpty();

        uint256 emitted = treasury.emitForAuction();

        dailyStats[daySinceStart].vyperEmitted = uint128(emitted);
    }
}