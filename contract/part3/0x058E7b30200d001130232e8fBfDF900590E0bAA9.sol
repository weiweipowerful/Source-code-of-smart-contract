// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import "./lib/Constants.sol";
import "./interfaces/IERC20Burnable.sol";

/// @title E280 Token Contract
contract E280 is OFT {
    using SafeERC20 for IERC20Burnable;

    // -------------------------- STATE VARIABLES -------------------------- //

    address public HLX_DAO;
    address public GENESIS;
    address public TAX_DESTINATION;
    address public E280_BUY_BURN;
    address public REWARD_DEPOSITOR;
    address public LP_DEPOSITOR;

    /// @notice Is minting enabled.
    bool public mintingEnabled;

    /// @notice Basis point incentive fee paid out for calling Distribute function.
    uint16 public incentiveFeeBps = 30;

    /// @notice Total E280 tokens burned to date.
    uint256 public totalBurned;

    /// @notice Are transcations to provided address exempt from taxes.
    mapping(address => bool) public whitelistTo;

    /// @notice Are transcations from provided address exempt from taxes.
    mapping(address => bool) public whitelistFrom;

    // ------------------------------- EVENTS ------------------------------ //

    event Distribution();

    // ------------------------------- ERRORS ------------------------------ //

    error Prohibited();
    error InsufficientBalance();
    error ZeroAddress();
    error ZeroInput();

    // ----------------------------- CONSTRUCTOR --------------------------- //

    constructor(
        address _owner,
        address _lzEndpoint,
        address _lpDeployer,
        address _hlxDao,
        address _genesis
    ) OFT("E280", "E280", _lzEndpoint, _owner) Ownable(_owner) {
        if (_lpDeployer == address(0)) revert ZeroAddress();
        if (_hlxDao == address(0)) revert ZeroAddress();
        if (_genesis == address(0)) revert ZeroAddress();

        HLX_DAO = _hlxDao;
        GENESIS = _genesis;

        whitelistTo[address(0)] = true;
        whitelistFrom[address(0)] = true;
        whitelistFrom[_lpDeployer] = true;

        _mint(_lpDeployer, 481_000_000_000 ether);
    }

    // --------------------------- PUBLIC FUNCTIONS ------------------------ //

    /// @notice Mints E280 by transforming user's ELMNT into E280.
    function mintWithElmnt(uint256 amount) external {
        if (!mintingEnabled) revert Prohibited();
        if (amount == 0) revert ZeroInput();
        IERC20Burnable(ELMNT).safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    /// @notice Burns the specified amount of tokens from the user's balance.
    /// @param value The amount of tokens in wei.
    function burn(uint256 value) public virtual {
        totalBurned += value;
        _burn(msg.sender, value);
    }

    /// @notice Distributes ELMNT from mints to its destinations.
    function distribute() external {
        IERC20Burnable elmnt = IERC20Burnable(ELMNT);
        uint256 balance = elmnt.balanceOf(address(this));
        if (balance == 0) revert InsufficientBalance();
        uint256 incentive = _applyBps(balance, incentiveFeeBps);
        balance -= incentive;

        uint256 daoAmount = _applyBps(balance, DAO_ALLOCATION);
        uint256 genesisAmount = _applyBps(balance, GENESIS_ALLOCATION);
        uint256 elmntBurnAmount = _applyBps(balance, ELMNT_BURN_ALLOCATION);
        uint256 e280BuyBurnAmount = _applyBps(balance, BUY_BURN_ALLOCATION);
        uint256 lpDepositorAmount = _applyBps(balance, LP_DEPOSITOR_ALLOCATION);
        uint256 rewardDepositorAmount = balance -
            daoAmount -
            genesisAmount -
            elmntBurnAmount -
            e280BuyBurnAmount -
            lpDepositorAmount;

        _mint(HLX_DAO, daoAmount);
        elmnt.safeTransfer(HLX_DAO, daoAmount);
        elmnt.safeTransfer(GENESIS, genesisAmount);
        elmnt.burn(elmntBurnAmount);
        elmnt.safeTransfer(E280_BUY_BURN, e280BuyBurnAmount);
        elmnt.safeTransfer(LP_DEPOSITOR, lpDepositorAmount);
        elmnt.safeTransfer(REWARD_DEPOSITOR, rewardDepositorAmount);
        elmnt.safeTransfer(msg.sender, incentive);

        emit Distribution();
    }

    // ----------------------- ADMINISTRATIVE FUNCTIONS -------------------- //

    /// @notice Sets protocol addresses after deployment.
    function setProtocolAddresses(
        address _e280BuyBurn,
        address _rewardDepositor,
        address _lpDepositor
    ) external onlyOwner {
        if (_e280BuyBurn == address(0)) revert ZeroAddress();
        if (_rewardDepositor == address(0)) revert ZeroAddress();
        if (_lpDepositor == address(0)) revert ZeroAddress();

        E280_BUY_BURN = _e280BuyBurn;
        REWARD_DEPOSITOR = _rewardDepositor;
        LP_DEPOSITOR = _lpDepositor;
    }

    /// @notice Sets new HLX DAO address.
    function setHlxDao(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        HLX_DAO = _address;
    }

    /// @notice Sets new Genesis address.
    function setGenesis(address _address) external {
        if (msg.sender != GENESIS) revert Prohibited();
        if (_address == address(0)) revert ZeroAddress();
        GENESIS = _address;
    }

    /// @notice Sets the whitelist status for a specified address.
    /// @param _address The address which whitelist status will be modified.
    /// @param _to Will the transfer to the address be whitelisted.
    /// @param _from Will the transfer from the address be whitelisted.
    /// @dev Can only be called by the owner.
    function setWhitelistStatus(address _address, bool _to, bool _from) external onlyOwner {
        whitelistTo[_address] = _to;
        whitelistFrom[_address] = _from;
    }

    /// @notice Sets the address where taxes from transfers will be sent.
    /// @dev Can only be called by the owner.
    function setTaxDestination(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        TAX_DESTINATION = _address;
        whitelistTo[TAX_DESTINATION] = true;
        whitelistFrom[TAX_DESTINATION] = true;
    }

    /// @notice Starts public minting.
    function startMint() external onlyOwner {
        if (
            E280_BUY_BURN == address(0) ||
            REWARD_DEPOSITOR == address(0) ||
            LP_DEPOSITOR == address(0) ||
            TAX_DESTINATION == address(0)
        ) revert ZeroAddress();
        mintingEnabled = true;
    }

    /// @notice Sets a new incentive fee basis points.
    /// @param bps Incentive fee in basis points (1% = 100 bps).
    function setIncentiveFee(uint16 bps) external onlyOwner {
        if (bps < 30 || bps > 10_00) revert Prohibited();
        incentiveFeeBps = bps;
    }

    // -------------------------- INTERNAL FUNCTIONS ----------------------- //

    function _update(address from, address to, uint256 amount) internal override {
        if (whitelistFrom[from] || whitelistTo[to]) {
            super._update(from, to, amount);
        } else {
            (uint256 taxAmount, uint256 amountAfterTax) = _applyTax(amount);
            super._update(from, TAX_DESTINATION, taxAmount);
            super._update(from, to, amountAfterTax);
        }
    }

    function _applyTax(uint256 amount) internal pure returns (uint256 taxAmount, uint256 amountAfterTax) {
        taxAmount = _applyBps(amount, TAX_BPS);
        amountAfterTax = amount - taxAmount;
    }

    function _applyBps(uint256 amount, uint16 bps) internal pure returns (uint256) {
        return (amount * bps) / BPS_BASE;
    }
}