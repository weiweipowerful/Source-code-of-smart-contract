// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {ERC20} from "./tokens/ERC20.sol";
import {IHedron} from "./interfaces/IHedron.sol";
import {IHEX} from "./interfaces/IHEX.sol";

contract StakeHousePool is ERC20 {
    // mint duration is measured in unixtimestamp seconds
    uint256 public MINT_START_TIME;
    uint256 public MINT_END_TIME;

    // all days are measured in terms of the HEX contract day number
    uint256 public STAKE_LENGTH;
    uint256 public STAKE_START_DAY;
    uint256 public STAKE_END_DAY;

    uint256 public CREATOR_FEE; // % scaled by 100
    address public POOL_CREATOR;
    uint256 public GAS_PRICE;
    address public STAKE_STARTER;
    address public STAKE_ENDER;
    uint256 public STAKE_END_GAS;

    bool public STAKE_STARTED;
    bool public STAKE_ENDED;

    uint256 public HEX_BLEED_DAY;

    address BUFFET;
    address HEX;
    address HEDRON;

    event Initialized(
        uint256 mint_duration,
        uint256 stake_duration,
        uint256 creator_fee,
        address creator
    );
    event StartedStake();
    event EndedStake();

    function initialize(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _mint_duration, // In Unix Timestamp
        uint256 _stake_duration, // In number of HEX Stake Days
        uint256 _creator_fee,
        address _pool_creator,
        address _buffet,
        address _hex,
        address _hedron
    ) external {
        require(MINT_START_TIME == 0, "Already initialized");

        _initialize(_name, _symbol, _decimals); // Initialize the pool token

        require(_mint_duration <= 369 hours, "Mint Duration Exceeded");
        MINT_START_TIME = block.timestamp;
        MINT_END_TIME = MINT_START_TIME + _mint_duration;

        STAKE_LENGTH = _stake_duration;
        STAKE_STARTED = false;
        STAKE_ENDED = false;

        require(_creator_fee <= 100, "Creator Fee Exceeded");
        CREATOR_FEE = _creator_fee;
        POOL_CREATOR = _pool_creator;
        GAS_PRICE = block.basefee;

        BUFFET = _buffet;
        HEX = _hex;
        HEDRON = _hedron;

        emit Initialized(
            _mint_duration,
            _stake_duration,
            _creator_fee,
            _pool_creator
        );
    }

    /**********************************************
     *** POOL ISSUANCE AND REDEMPTION FUNCTIONS ***
     **********************************************/

    /**
     * @dev Deposit HEX to Pool
     * @param amount HEX to Deposit
     */
    function depositHEX(uint256 amount) external payable {
        require(msg.value == 3690 * GAS_PRICE, "Insufficient Fees"); // 3690 gwei fees per transaction
        require(block.timestamp <= MINT_END_TIME, "Minting Phase is Done");

        SafeTransferLib.safeTransferFrom(
            ERC20(HEX),
            msg.sender,
            address(this),
            amount
        );
        _mint(msg.sender, amount);
    }

    /**
     * @dev Withdraw HEX from Pool
     * @param amount HEX to Withdraw
     */
    function withdrawHEX(uint256 amount) external payable {
        require(msg.value == 3690 * GAS_PRICE, "Insufficient Fees"); // 3690 gwei fees per transaction
        require(STAKE_STARTED == false, "Stake Already Started");

        _burn(msg.sender, amount);
        SafeTransferLib.safeTransfer(ERC20(HEX), msg.sender, amount);
    }

    /**
     * @dev Redeem matured HEX and HEDRON from Pool
     * @param amount SH Tokens being redeemed
     */
    function redeemSH(uint256 amount) external payable {
        require(STAKE_ENDED == true, "Stake Not Ended");

        uint256 totalPool = totalSupply;
        uint256 stakeEnderFees = (amount * STAKE_END_GAS) / totalPool;
        uint256 protocolFees = STAKE_END_GAS / 20;

        require(
            msg.value == stakeEnderFees + protocolFees,
            "Insufficient Fees"
        );

        _burn(msg.sender, amount); // burn will revert if balance < amount

        uint256 hedronBalance = ERC20(HEDRON).balanceOf(address(this));
        uint256 hexBalance = ERC20(HEX).balanceOf(address(this));
        uint256 hedronAmount = (amount * hedronBalance) / totalPool;
        uint256 hexAmount = (amount * hexBalance) / totalPool;

        SafeTransferLib.safeTransferETH(STAKE_ENDER, stakeEnderFees);
        SafeTransferLib.safeTransferETH(BUFFET, protocolFees);

        // *** REDEEM HEDRON ***
        if (hedronBalance > 0) {
            uint256 protocolHedron = (2000 * hedronAmount) / 10000; // 20% of Hedron to Protocol
            SafeTransferLib.safeTransfer(ERC20(HEDRON), BUFFET, protocolHedron);
            SafeTransferLib.safeTransfer(
                ERC20(HEDRON),
                msg.sender,
                hedronAmount - protocolHedron
            );
        }

        // *** REDEEM HEX ***
        if (hexBalance > 0) {
            uint256 creatorHex = (CREATOR_FEE * hexAmount) / 10000;
            SafeTransferLib.safeTransfer(ERC20(HEX), POOL_CREATOR, creatorHex);
            SafeTransferLib.safeTransfer(
                ERC20(HEX),
                msg.sender,
                hexAmount - creatorHex
            );
        }
    }

    /*************************
     *** STAKING FUNCTIONS ***
     *************************/

    /**
     * @dev Starts the HEX stake
     */
    function startStake() external {
        require(STAKE_STARTED == false, "Stake Already Started");
        require(block.timestamp > MINT_END_TIME, "Minting Not Ended");

        //start stake
        uint256 amount = ERC20(HEX).balanceOf(address(this));
        IHEX(HEX).stakeStart(amount, STAKE_LENGTH);

        //update state variables
        STAKE_STARTED = true;
        STAKE_STARTER = msg.sender;
        uint256 current_day = IHEX(HEX).currentDay();
        STAKE_START_DAY = current_day;
        STAKE_END_DAY = current_day + STAKE_LENGTH;

        //transfer fees to buffet
        uint256 fees = address(this).balance;
        SafeTransferLib.safeTransferETH(BUFFET, fees);

        emit StartedStake();
    }

    /**
     * @dev Mints Hedron, ends the HEX stake and updates the redemption rates.
     */
    function endStake() external {
        require(msg.sender == tx.origin, "Only EOA");
        require(IHEX(HEX).currentDay() > STAKE_END_DAY, "Stake Ongoing");
        require(STAKE_ENDED == false, "Stake Already Ended"); // No need to check for stake started. Hex does that.

        // *** START GAS TRACKING ***
        uint256 gasInit = gasleft();

        (uint40 stakeId, , , , , , ) = IHEX(HEX).stakeLists(address(this), 0);
        IHedron(HEDRON).mintNative(0, stakeId);
        IHEX(HEX).stakeEnd(0, stakeId);
        STAKE_ENDED = true;

        // *** END GAS TRACKING ***
        uint256 gasFinal = gasleft();

        STAKE_END_GAS = (gasInit - gasFinal) * block.basefee;
        STAKE_ENDER = msg.sender;

        //Increase Stake End Gas by 10% to account for priority fees and residual gas calculation
        STAKE_END_GAS = (STAKE_END_GAS * 110) / 100;

        emit EndedStake();
    }

    /***********************
     *** BLEED FUNCTIONS ***
     ***********************/

    /**
     * @dev Bleeds Unclaimed Hedron
     */
    function bleedHedron() external {
        require(IHEX(HEX).currentDay() > STAKE_END_DAY + 6, "No Bleed Yet");

        uint256 hedronBalance = ERC20(HEDRON).balanceOf(address(this)); //Bleeds all
        uint256 bleedShare = hedronBalance / 2; // 50% of balance

        SafeTransferLib.safeTransfer(ERC20(HEDRON), STAKE_ENDER, bleedShare);
        SafeTransferLib.safeTransfer(ERC20(HEDRON), BUFFET, bleedShare);
    }

    /**
     * @dev Bleeds Unclaimed Hex
     */
    function bleedHex() external {
        require(IHEX(HEX).currentDay() > STAKE_END_DAY + 6, "No Bleed Yet");

        if (HEX_BLEED_DAY == 0) {
            HEX_BLEED_DAY = STAKE_END_DAY + 7;
        }

        uint currentDay = IHEX(HEX).currentDay();
        uint256 bleedRate = currentDay - HEX_BLEED_DAY; // Bleeds at 1% per day
        bleedRate = bleedRate > 100 ? 100 : bleedRate; // Cap at 100%

        uint256 hexBalance = ERC20(HEX).balanceOf(address(this));
        uint256 bleedShare = (bleedRate * hexBalance) / 100;
        uint256 creatorShare = (CREATOR_FEE * bleedShare) / 10000;
        uint256 protocolShare = bleedShare - creatorShare;

        HEX_BLEED_DAY = currentDay;

        SafeTransferLib.safeTransfer(ERC20(HEX), POOL_CREATOR, creatorShare);
        SafeTransferLib.safeTransfer(ERC20(HEX), BUFFET, protocolShare);
    }
}