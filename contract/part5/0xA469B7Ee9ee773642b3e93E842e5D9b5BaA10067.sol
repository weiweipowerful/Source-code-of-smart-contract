// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";

import "./utils/SafeMath.sol";

import "./interfaces/ISPCTPool.sol";
import "./interfaces/ISPCTPriceOracle.sol";

/**
 * @title Stablecoin backed by RWA for Anzen protocol.
 */
contract USDz is OFT, ERC20Permit, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");

    // Migration mode (disable deposits)
    bool public mode; // false by default

    // Used to calculate total pooled SPCT.
    uint256 public totalPooledSPCT;
    // Used to calculate collateral rate.
    uint256 public constant collateralRate = 1;

    // Fee Zone
    uint256 public constant FEE_COEFFICIENT = 1e8;
    // Fee should be less than 1%.
    uint256 public constant maxMintFeeRate = FEE_COEFFICIENT / 100;
    uint256 public constant maxRedeemFeeRate = FEE_COEFFICIENT / 100;
    uint256 public mintFeeRate;
    uint256 public redeemFeeRate;
    // Protocol treasury should be a mulsig wallet.
    address public treasury;
    // Make owner transfer 2 step.
    address private _pendingOwner;

    // Lend token
    IERC20 public immutable usdc;
    // Collateral token
    ISPCTPool public immutable spct;
    // Price oracle
    ISPCTPriceOracle public oracle;

    /**
     * @dev Blacklist.
     */
    mapping(address => bool) private _blacklist;

    event ModeSwitch(bool mode);

    event Deposit(address indexed user, uint256 indexed amount);
    event Redeem(address indexed user, uint256 indexed amount);
    event Mint(address indexed user, uint256 indexed amount);
    event Burn(address indexed user, uint256 indexed amount);

    event MintFeeRateChanged(uint256 indexed newFeeRate);
    event RedeemFeeRateChanged(uint256 indexed newFeeRate);
    event TreasuryChanged(address indexed newTreasury);
    event OracleChanged(address newOracle);

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    constructor(address _admin, address _endpoint, IERC20 _usdc, ISPCTPool _spct, ISPCTPriceOracle _oracle)
        OFT("USDz", "USDz", _endpoint, _admin)
        ERC20Permit("USDz")
        Ownable(_admin)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        usdc = _usdc;
        spct = _spct;
        oracle = _oracle;
    }

    // @dev Sets an implicit cap on the amount of tokens, over uint64.max() will need some sort of outbound cap / totalSupply cap
    // Lowest common decimal denominator between chains.
    // Defaults to 6 decimal places to provide up to 18,446,744,073,709.551615 units (max uint64).
    // For tokens exceeding this totalSupply(), they will need to override the sharedDecimals function with something smaller.
    // ie. 4 sharedDecimals would be 1,844,674,407,370,955.1615
    function sharedDecimals() public pure override returns (uint8) {
        return 8;
    }

    modifier checkCollateralRate() {
        _checkCollateralRate();
        _;
    }

    /**
     * @notice Check collateral rate.
     */
    function _checkCollateralRate() internal view {
        require(oracle.getPrice() / 1e18 >= collateralRate, "UNDER_COLLATERAL_RATE,SMART_CONTRACT_IS_PAUSED_NOW");
    }

    /**
     * @notice Pause the contract. Revert if already paused.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract. Revert if already unpaused.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Switch to interest mode.
     * Emits a `ModeSwitch` event.
     */
    function switchMode() external onlyRole(DEFAULT_ADMIN_ROLE) {
        mode = !mode;
        emit ModeSwitch(mode);
    }

    /**
     * @notice deposit USDC. (borrow USDC from user and deposit collateral)
     * Emits a `Deposit` event.
     *
     * @param _amount the amount of USDC
     */
    function deposit(uint256 _amount) external whenNotPaused checkCollateralRate {
        if (mode) revert("PLEASE_MIGRATE_TO_NEW_VERSION");
        require(_amount > 0, "DEPOSIT_AMOUNT_IS_ZERO");
        require(!_blacklist[msg.sender], "RECIPIENT_IN_BLACKLIST");

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(usdc).safeIncreaseAllowance(address(spct), _amount); // approve for depositing collateral

        // Due to different precisions, convert it to USDz.
        uint256 convertToSPCT = _amount.mul(1e12);
        // Get mint rate from spct for calculating.
        uint256 spctMintFeeRate = spct.mintFeeRate();

        // calculate fee with USDz
        if (mintFeeRate == 0) {
            if (spctMintFeeRate == 0) {
                _mintUSDz(msg.sender, convertToSPCT);

                spct.deposit(_amount);
            } else {
                uint256 spctFeeAmount = convertToSPCT.mul(spctMintFeeRate).div(FEE_COEFFICIENT);
                uint256 spctAmountAfterFee = convertToSPCT.sub(spctFeeAmount);

                _mintUSDz(msg.sender, spctAmountAfterFee);

                spct.deposit(_amount);
            }
        } else {
            if (spctMintFeeRate == 0) {
                uint256 feeAmount = convertToSPCT.mul(mintFeeRate).div(FEE_COEFFICIENT);
                uint256 amountAfterFee = convertToSPCT.sub(feeAmount);

                _mintUSDz(msg.sender, amountAfterFee);

                if (feeAmount != 0) {
                    _mintUSDz(treasury, feeAmount);
                }

                spct.deposit(_amount);
            } else {
                uint256 spctFeeAmount = convertToSPCT.mul(spctMintFeeRate).div(FEE_COEFFICIENT);
                uint256 spctAmountAfterFee = convertToSPCT.sub(spctFeeAmount);
                uint256 feeAmount = spctAmountAfterFee.mul(mintFeeRate).div(FEE_COEFFICIENT);
                uint256 amountAfterFee = spctAmountAfterFee.sub(feeAmount);

                _mintUSDz(msg.sender, amountAfterFee);

                if (feeAmount != 0) {
                    _mintUSDz(treasury, feeAmount);
                }

                spct.deposit(_amount);
            }
        }

        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice deposit SPCT. (deposit collateral to mint USDz)
     * Emits a `Deposit` event.
     *
     * @param _amount the amount of SPCT
     */
    function depositBySPCT(uint256 _amount) external whenNotPaused checkCollateralRate {
        require(mode == false, "PLEASE_MIGRATE_TO_NEW_VERSION");
        require(_amount > 0, "DEPOSIT_AMOUNT_IS_ZERO");
        require(!_blacklist[msg.sender], "RECIPIENT_IN_BLACKLIST");

        IERC20(address(spct)).safeTransferFrom(msg.sender, address(this), _amount);

        // calculate fee with USDz
        if (mintFeeRate == 0) {
            _mintUSDz(msg.sender, _amount);
        } else {
            uint256 feeAmount = _amount.mul(mintFeeRate).div(FEE_COEFFICIENT);
            uint256 amountAfterFee = _amount.sub(feeAmount);

            _mintUSDz(msg.sender, amountAfterFee);

            if (feeAmount != 0) {
                _mintUSDz(treasury, feeAmount);
            }
        }

        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice redeem USDz. (get back USDC from borrower and release collateral)
     * 18 decimal input
     * Emits a `Redeem` event.
     *
     * @param _amount the amount of USDz.
     */
    function redeem(uint256 _amount) external whenNotPaused checkCollateralRate {
        require(spct.reserveUSD().mul(1e12) >= _amount, "RESERVE_INSUFFICIENT");
        require(_amount > 0, "REDEEM_AMOUNT_IS_ZERO");
        require(!_blacklist[msg.sender], "RECIPIENT_IN_BLACKLIST");

        // Due to different precisions, convert it to USDz.
        uint256 convertToUSDC;
        // Get redeem rate from spct for calculating.
        uint256 spctRedeemFeeRate = spct.redeemFeeRate();

        // calculate fee with USDz
        if (redeemFeeRate == 0) {
            if (spctRedeemFeeRate == 0) {
                _burnUSDz(msg.sender, _amount);

                spct.redeem(_amount);
                convertToUSDC = _amount.div(1e12);
                IERC20(usdc).safeTransfer(msg.sender, convertToUSDC);
            } else {
                uint256 spctFeeAmount = _amount.mul(spctRedeemFeeRate).div(FEE_COEFFICIENT);
                uint256 spctAmountAfterFee = _amount.sub(spctFeeAmount);

                _burnUSDz(msg.sender, _amount);

                spct.redeem(_amount);
                convertToUSDC = spctAmountAfterFee.div(1e12);
                IERC20(usdc).safeTransfer(msg.sender, convertToUSDC);
            }
        } else {
            if (spctRedeemFeeRate == 0) {
                uint256 feeAmount = _amount.mul(redeemFeeRate).div(FEE_COEFFICIENT);
                uint256 amountAfterFee = _amount.sub(feeAmount);

                _burnUSDz(msg.sender, amountAfterFee);

                if (feeAmount != 0) {
                    _transfer(msg.sender, treasury, feeAmount);
                }

                spct.redeem(amountAfterFee);
                convertToUSDC = amountAfterFee.div(1e12);
                IERC20(usdc).safeTransfer(msg.sender, convertToUSDC);
            } else {
                uint256 feeAmount = _amount.mul(redeemFeeRate).div(FEE_COEFFICIENT);
                uint256 amountAfterFee = _amount.sub(feeAmount);
                uint256 spctFeeAmount = amountAfterFee.mul(spctRedeemFeeRate).div(FEE_COEFFICIENT);
                uint256 spctAmountAfterFee = amountAfterFee.sub(spctFeeAmount);

                _burnUSDz(msg.sender, amountAfterFee);

                if (feeAmount != 0) {
                    _transfer(msg.sender, treasury, feeAmount);
                }

                spct.redeem(amountAfterFee);
                convertToUSDC = spctAmountAfterFee.div(1e12);
                IERC20(usdc).safeTransfer(msg.sender, convertToUSDC);
            }
        }

        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice redeem USDz. (get back SPCT)
     * Emits a `Redeem` event.
     *
     * @param _amount the amount of USDz.
     */
    function redeemBackSPCT(uint256 _amount) external whenNotPaused checkCollateralRate {
        require(_amount > 0, "REDEEM_AMOUNT_IS_ZERO");
        require(!_blacklist[msg.sender], "SENDER_IN_BLACKLIST");

        // calculate fee with SPCT
        if (redeemFeeRate == 0) {
            _burnUSDz(msg.sender, _amount);
            IERC20(address(spct)).safeTransfer(msg.sender, _amount);
        } else {
            uint256 feeAmount = _amount.mul(redeemFeeRate).div(FEE_COEFFICIENT);
            uint256 amountAfterFee = _amount.sub(feeAmount);

            _burnUSDz(msg.sender, amountAfterFee);

            if (feeAmount != 0) {
                _transfer(msg.sender, treasury, feeAmount);
            }

            IERC20(address(spct)).safeTransfer(msg.sender, amountAfterFee);
        }

        emit Redeem(msg.sender, _amount);
    }

    /**
     * @dev mint USDz for _receiver.
     * Emits `Mint` and `Transfer` event.
     *
     * @param _receiver address to receive SPCT.
     * @param _amount the amount of SPCT.
     */
    function _mintUSDz(address _receiver, uint256 _amount) internal {
        _mint(_receiver, _amount);
        totalPooledSPCT = totalPooledSPCT.add(_amount);
        emit Mint(msg.sender, _amount);
    }

    /**
     * @dev burn USDz from _receiver.
     * Emits `Burn` and `Transfer` event.
     *
     * @param _account address to burn USDz from.
     * @param _amount the amount of USDz.
     */
    function _burnUSDz(address _account, uint256 _amount) internal {
        _burn(_account, _amount);

        totalPooledSPCT = totalPooledSPCT.sub(_amount);
        emit Burn(msg.sender, _amount);
    }

    /**
     * @notice Moves `_amount` tokens from `_sender` to `_recipient`.
     * Emits a `Transfer` event.
     */
    function _update(address _sender, address _recipient, uint256 _amount) internal override {
        require(!_blacklist[_sender], "SENDER_IN_BLACKLIST");
        require(!_blacklist[_recipient], "RECIPIENT_IN_BLACKLIST");

        super._update(_sender, _recipient, _amount);
    }

    /**
     * @return true if user in list.
     */
    function isBlacklist(address _user) external view returns (bool) {
        return _blacklist[_user];
    }

    function addToBlacklist(address _user) external onlyRole(POOL_MANAGER_ROLE) {
        _blacklist[_user] = true;
    }

    function addBatchToBlacklist(address[] calldata _users) external onlyRole(POOL_MANAGER_ROLE) {
        uint256 numUsers = _users.length;
        for (uint256 i; i < numUsers; ++i) {
            _blacklist[_users[i]] = true;
        }
    }

    function removeFromBlacklist(address _user) external onlyRole(POOL_MANAGER_ROLE) {
        _blacklist[_user] = false;
    }

    function removeBatchFromBlacklist(address[] calldata _users) external onlyRole(POOL_MANAGER_ROLE) {
        uint256 numUsers = _users.length;
        for (uint256 i; i < numUsers; ++i) {
            _blacklist[_users[i]] = false;
        }
    }

    /**
     * @notice Mint fee.
     *
     * @param newMintFeeRate new mint fee rate.
     */
    function setMintFeeRate(uint256 newMintFeeRate) external onlyRole(POOL_MANAGER_ROLE) {
        require(newMintFeeRate <= maxMintFeeRate, "SHOULD_BE_LESS_THAN_OR_EQUAL_TO_1P");
        mintFeeRate = newMintFeeRate;
        emit MintFeeRateChanged(mintFeeRate);
    }

    /**
     * @notice Redeem fee.
     *
     * @param newRedeemFeeRate new redeem fee rate.
     */
    function setRedeemFeeRate(uint256 newRedeemFeeRate) external onlyRole(POOL_MANAGER_ROLE) {
        require(newRedeemFeeRate <= maxRedeemFeeRate, "SHOULD_BE_LESS_THAN_OR_EQUAL_TO_1P");
        redeemFeeRate = newRedeemFeeRate;
        emit RedeemFeeRateChanged(redeemFeeRate);
    }

    /**
     * @notice Treasury address.
     *
     * @param newTreasury new treasury address.
     */
    function setTreasury(address newTreasury) external onlyRole(POOL_MANAGER_ROLE) {
        require(newTreasury != address(0), "SET_UP_TO_ZERO_ADDR");
        treasury = newTreasury;
        emit TreasuryChanged(treasury);
    }

    /**
     * @notice Oracle address.
     *
     * @param newOracle new Oracle address.
     */
    function setOracle(address newOracle) external onlyRole(POOL_MANAGER_ROLE) {
        require(newOracle != address(0), "SET_UP_TO_ZERO_ADDR");
        oracle = ISPCTPriceOracle(newOracle);
        emit OracleChanged(newOracle);
    }

    // override to allow pausing
    function _debit(uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        override
        whenNotPaused
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        return super._debit(_amountLD, _minAmountLD, _dstEid);
    }

    // override to allow pausing
    function _credit(address _to, uint256 _amountLD, uint32 _srcEid)
        internal
        override
        whenNotPaused
        returns (uint256 amountReceivedLD)
    {
        return super._credit(_to, _amountLD, _srcEid);
    }

    /* -------------------------------------------------------------------------- */
    /*                                Ownable2Step                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view returns (address) {
        return _pendingOwner;
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() public {
        address sender = _msgSender();
        if (pendingOwner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
        _transferOwnership(sender);
    }

    /* --------------------------- End of Ownable2Step -------------------------- */

    /**
     * @notice Rescue ERC20 tokens locked up in this contract.
     * @param token ERC20 token contract address.
     * @param to recipient address.
     * @param amount amount to withdraw.
     */
    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyRole(POOL_MANAGER_ROLE) {
        // If is SPCT, check total pooled amount first.
        if (address(token) == address(spct)) {
            require(amount <= spct.balanceOf(address(this)).sub(totalPooledSPCT), "SPCT_RESCUE_AMOUNT_EXCEED_DEBIT");
        }
        token.safeTransfer(to, amount);
    }
}