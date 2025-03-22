// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDepositPool } from "./IDepositPool.sol";
import { IVaultNav } from "../vaultNav/IVaultNav.sol";
import { MessageLib } from "../message-lib/MessageLib.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IAbridgeMessageHandler } from "../abridge/IAbridge.sol";
import { AbridgeMessageHandler } from "../abridge/AbridgeMessageHandler.sol";

/// @title DepositPool
/// @notice DepositPool accepts tokens and sends LSD token mint messages to Gravity.
/// The withdrawer is allowed to withdraw all deposited tokens treasury address.
/// No more deposits will be accepted once the deposit capacity is met.
/// ERC-2612 permit is supported if the asset token is an ERC20 token.
/// By default, LSD tokens will be minted to the receiver on the Gravity
/// chain upon successful deposit.
/// This contract is not upgradable but owner can easily use a new contract
/// to replace this one by:
/// 1. Pausing this contract.
/// 2. Withdrawer move all deposited tokens to treasury, as usual.
/// 3. New contract can read the public state variables of this contract
///    as they are just counters.
contract DepositPool is AbridgeMessageHandler, Pausable, Ownable2Step, IDepositPool {
    using SafeERC20 for IERC20;

    /// @notice Address of LSD token
    address public immutable LSD;
    /// @notice Address of token allowed to deposit
    address public immutable ASSET_TOKEN;
    /// @notice Decimals of deposit token
    uint256 public immutable ASSET_TOKEN_DECIMALS;
    /// @notice The address of SmartSavings contract on Gravity.
    address public smartSavingsOnGravity;

    /// @notice Accumulated deposited LSD token amount
    /// These are counters for the total amount of LSD minted to the owner
    /// on the default chain: Gravity.
    mapping(address owner => uint256 totalDeposits) public totalDeposits;

    /// @notice Pending deposit amount per owner.
    /// These are counters for the LSD that should be minted to the owner,
    /// but has not been minted yet.
    /// These alternative counters can be interpreted by future contracts
    /// to mint LSD to the owner on a different chain, inlcuding directly
    /// on Ethereum mainnet. Those contracts need to make sure that the
    /// counter amount shall not be spent twice. It can be done by maintaining
    /// another counter representing the "used" amount.
    mapping(address owner => uint256 amount) public pendingDeposits;

    /// @notice Total amount of LSD Token minted on chain
    uint256 public totalLsdMinted;
    /// @notice Accumulated deposit amount
    uint256 public accDepositAmount;
    /// @notice Capacity of deposit amount
    uint256 public depositCap;
    /// @notice Address of the account who is eligible to withdraw deposited assets to treasury
    address public withdrawer;
    /// @notice Address to hold the deposited assets
    address public treasury;

    /// @notice Gas limit to execute lzReceive function on destination chain using LayerZero
    uint128 public lzReceiveGasLimit = 100_000;

    /// @notice Address of VaultNav contract which is responsible for accounting NAV
    IVaultNav public vaultNav;

    /// @dev Ensures the deposit amount is valid and within the deposit cap
    /// @param _amount The amount to be deposited
    modifier onlyValidDepositAmount(uint256 _amount) {
        if (_amount == 0) {
            revert InvalidDepositAmount();
        }
        if (accDepositAmount + _amount > depositCap) {
            revert AmountExceedsDepositCap();
        }
        _;
    }

    /// @dev Restricts function access to the designated withdrawer
    modifier onlyWithdrawer() {
        if (msg.sender != withdrawer) {
            revert InvalidWithdrawer(msg.sender);
        }
        _;
    }

    /// @dev Initializes the DepositPool contract
    /// @param _lsd The address of the LSD token
    /// @param _token The address of asset token.
    /// @param _decimals The decimals of asset token.
    /// @param _vaultNav The address of VaultNav contract.
    /// @param _owner The owner/admin of this contract.
    /// @param _treasury The address to hold the deposited assets.
    /// @param _abridge The address of the Abridge contract.
    /// @param _smartSavingsOnGravity The address of SmartSavings contract on Gravity.
    constructor(
        address _lsd,
        address _token,
        uint8 _decimals,
        address _vaultNav,
        address _owner, // solhint-disable-line no-unused-vars
        address _treasury,
        address _abridge, // solhint-disable-line no-unused-vars
        address _smartSavingsOnGravity
    ) Ownable(_owner) AbridgeMessageHandler(_abridge) {
        if (_lsd == address(0)) {
            revert InvalidLSD();
        }
        LSD = _lsd;

        ASSET_TOKEN = _token;
        ASSET_TOKEN_DECIMALS = _decimals;
        if (_decimals > 18) {
            revert InvalidVaultToken();
        }

        if (_vaultNav == address(0)) {
            revert InvalidAddress(_vaultNav);
        }
        vaultNav = IVaultNav(_vaultNav);

        if (_treasury == address(0)) {
            revert InvalidAddress(_treasury);
        }
        treasury = _treasury;
        smartSavingsOnGravity = _smartSavingsOnGravity;
    }

    /// @notice Fallback function to receive native tokens as gas fees
    receive() external payable {}

    /// @notice Deposit `_amount` of `ASSET_TOKEN` for `_to`.
    /// @param _to The address to receive shares.
    /// @param _amount Amount of `ASSET_TOKEN` to be transferred to this contract.
    /// @param _mintOnGravity If true, mint LSD on Gravity chain, otherwise add to pending deposits.
    ///  It should be below the remaining deposit capacity.
    function deposit(
        address _to,
        uint256 _amount,
        bool _mintOnGravity
    ) external payable onlyValidDepositAmount(_amount) whenNotPaused {
        _deposit(_to, _amount, _mintOnGravity);
    }

    /// @notice Deposit `_amount` of `ASSET_TOKEN` for `_to` with ERC-2612 permit support.
    /// @param _to The address to receive shares.
    /// @param _amount Amount of `ASSET_TOKEN` to be deposited. It should be below the remaining deposit capacity.
    /// @param _permit The permit input data for ERC-2612.
    /// @param _mintOnGravity If true, mint LSD on Gravity chain, otherwise add to pending deposits.
    function depositWithPermit(
        address _to,
        uint256 _amount,
        bool _mintOnGravity,
        PermitInput calldata _permit
    ) external payable onlyValidDepositAmount(_amount) whenNotPaused {
        try
            IERC20Permit(ASSET_TOKEN).permit(
                msg.sender,
                address(this),
                _permit.value,
                _permit.deadline,
                _permit.v,
                _permit.r,
                _permit.s
            )
        {} catch {} // solhint-disable-line no-empty-blocks

        _deposit(_to, _amount, _mintOnGravity);
    }

    /// @notice Withdraw the deposited tokens to treasury.
    /// @dev Emits a `Withdrawn` event.
    /// @param _amount Amount of token to withdraw.
    function withdraw(uint256 _amount) external onlyWithdrawer {
        uint256 depositedAmount = 0;
        if (ASSET_TOKEN == address(0)) {
            depositedAmount = address(this).balance;
        } else {
            depositedAmount = IERC20(ASSET_TOKEN).balanceOf(address(this));
        }

        if (_amount == 0 || _amount > depositedAmount) {
            revert InvalidWithdrawalAmount(_amount);
        }

        // transfer token
        if (ASSET_TOKEN == address(0)) {
            (bool sent, ) = treasury.call{ value: _amount }("");
            if (!sent) revert SendFailed(treasury, _amount);
        } else {
            IERC20(ASSET_TOKEN).safeTransfer(treasury, _amount);
        }

        // withdraw event
        emit Withdrawn(treasury, ASSET_TOKEN, _amount, LSD);
    }

    /// @notice Stops accepting new deposits.
    /// @dev Emits a `Paused` event.
    function pause() external onlyOwner {
        _pause();
    }
    /// @notice Resumes accepting new deposits.
    /// @dev Emits an `Unpaused` event.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Withdraw unexpectedly received tokens.
    /// @param _token Address of the token to withdraw.
    /// @param _to Address to receive the withdrawn token.
    function rescueWithdraw(address _token, address _to) external onlyOwner {
        if (_token == address(0)) {
            uint256 amount = address(this).balance;
            (bool sent, ) = _to.call{ value: amount }("");
            if (!sent) {
                revert SendFailed(_to, amount);
            }
        } else {
            uint256 _amount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }

    /// @notice Sets the address of SmartSavings on the Ethereum
    /// @dev Emits a `SmartSavingOnGravityUpdated` event.
    /// @param _smartSavings The address of the SmartSavings contract on the Ethereum
    function setSmartSavingsOnGravity(address _smartSavings) external onlyOwner {
        smartSavingsOnGravity = _smartSavings;
        emit SmartSavingsOnGravityUpdated(_smartSavings);
    }

    /// @notice Sets the abridge address
    /// @param _abridge The address of the Abridge contract
    function setAbridge(address _abridge) external onlyOwner {
        _setAbridge(_abridge);
    }

    /// @notice Set lzReceiveGasLimit
    /// @param _gasLimit The gas limit to execute lzReceive function on destination chain using LayerZero.
    function setLzReceiveGasLimit(uint128 _gasLimit) external onlyOwner {
        lzReceiveGasLimit = _gasLimit;
        emit NewLzReceiveGasLimit(_gasLimit);
    }

    /// @notice Set new deposit cap.
    /// @dev Emits a `NewDepositCap` event.
    /// @param _amount New deposit cap.
    function setDepositCap(uint256 _amount) external onlyOwner {
        if (_amount < accDepositAmount) revert InvalidDepositCap(_amount);
        depositCap = _amount;
        emit NewDepositCap(_amount);
    }

    /// @notice Set new withdrawer.
    /// @dev Emits a `NewWithdrawer` event.
    /// @param _withdrawer Address of new withdrawer.
    function setWithdrawer(address _withdrawer) external onlyOwner {
        withdrawer = _withdrawer;
        emit NewWithdrawer(_withdrawer);
    }

    /// @notice Set new treasury.
    /// @dev Emits a `NewTreasury` event.
    /// @param _treasury Address of new treasury.
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) {
            revert InvalidAddress(_treasury);
        }
        treasury = _treasury;
        emit NewTreasury(_treasury);
    }

    /// @notice Set initial amount of LSD minted.
    //   Can only be set once and must be done before any deposits are received.
    /// @dev Emits a `TotalLsdMintedInitialized` event.
    /// @param _amount Initial amount of LSD minted.
    function setInitialLsdMinted(uint256 _amount) external onlyOwner {
        if (totalLsdMinted != 0 || _amount == 0) {
            revert InvalidInitialLsdMinted(_amount);
        }
        totalLsdMinted = _amount;
        emit TotalLsdMintedInitialized(_amount);
    }

    /// @notice DepositPool is designed exclusively for sending cross-chain messages and
    ///   will always revert when receiving any.
    function handleMessage(
        address /*_from*/,
        bytes calldata /*_message*/,
        bytes32 /*_guid*/
    ) external view override onlyAbridge returns (bytes4) {
        revert NotImplemented(IAbridgeMessageHandler.handleMessage.selector);
    }

    /// @notice Get remaining deposit capacity.
    /// @return Remaining deposit capacity.
    function remainingDepositCap() external view returns (uint256) {
        return depositCap - accDepositAmount;
    }

    /// @notice Estimate deposit message bridging fee.
    /// @param _to The address to receive minted LSD.
    /// @return Amount of deposit fee.
    function depositFee(address _to) public view returns (uint256) {
        (, uint256 amount) = abridge().estimateFee(
            smartSavingsOnGravity,
            lzReceiveGasLimit,
            MessageLib.pack(
                MessageLib.Message({
                    valueType: uint8(MessageLib.TOTAL_CLAIMS_TYPE),
                    value: totalDeposits[_to],
                    owner: _to,
                    timestamp: 0,
                    delta: 0
                })
            )
        );
        return amount;
    }

    /// @notice Internal function to implement deposit logic.
    /// @dev Emits a `Deposited` event.
    /// @param _to Address to receive LSD token.
    /// @param _amount Amount of `ASSET_TOKEN` deposited.
    /// @param _mintOnGravity If true, mint LSD on Gravity chain, otherwise add to pending deposits.
    function _deposit(address _to, uint256 _amount, bool _mintOnGravity) internal {
        // receive token
        uint256 actualAmount = _amount;
        uint256 messageFee = msg.value;
        if (ASSET_TOKEN == address(0)) {
            if (msg.value < _amount) {
                revert InvalidDepositAmount();
            }
            messageFee -= _amount;
        } else {
            // be compatible with reflection tokens
            uint256 balanceBefore = IERC20(ASSET_TOKEN).balanceOf(address(this));
            IERC20(ASSET_TOKEN).safeTransferFrom(msg.sender, address(this), _amount);
            uint256 balanceAfter = IERC20(ASSET_TOKEN).balanceOf(address(this));
            actualAmount = balanceAfter - balanceBefore;
        }

        // add accumulated deposited amount
        accDepositAmount += actualAmount;

        // calc LSD amount
        uint256 lsdAmount = vaultNav.tokenE18ToLsdAtTime(
            LSD,
            actualAmount * 10 ** (18 - ASSET_TOKEN_DECIMALS),
            uint48(block.timestamp)
        );
        if (lsdAmount == 0) {
            revert DepositAmountTooSmall(actualAmount);
        }
        totalLsdMinted += lsdAmount;

        if (!_mintOnGravity) {
            // add pending deposit amount, instead of mint to gravity chain.
            pendingDeposits[_to] += lsdAmount;
            emit Deposited(msg.sender, _to, ASSET_TOKEN, actualAmount, LSD, lsdAmount, block.timestamp, 0, 0);
        } else {
            // mint LSD on gravity by sending message.
            totalDeposits[_to] += lsdAmount;

            // check message fee
            uint256 _depositFee = depositFee(_to);
            if (messageFee < _depositFee) {
                revert InsufficientFee(_depositFee, messageFee);
            }
            // bridge message to gravity to mint LSD
            (bytes32 guid, uint256 nativeFee) = _deposited(_to, messageFee);

            emit Deposited(
                msg.sender,
                _to,
                ASSET_TOKEN,
                actualAmount,
                LSD,
                lsdAmount,
                block.timestamp,
                guid,
                nativeFee
            );
        }
    }

    /// @dev Send message `totalDeposits` of `_to` to destination chain to
    ///  trigger minting LSD tokens to `_to`.
    /// @param _to Address to receive LSD token.
    /// @param _messageFee Provided native fee for sending LayerZero message.
    /// @return _guid The unique identifier for the sent LayerZero message.
    /// @return _nativeFee The actually charged native fee for sending LayerZero message.
    function _deposited(address _to, uint256 _messageFee) internal returns (bytes32 _guid, uint256 _nativeFee) {
        bytes memory message = MessageLib.pack(
            MessageLib.Message({
                valueType: uint8(MessageLib.TOTAL_DEPOSITS_TYPE),
                value: totalDeposits[_to],
                owner: _to,
                timestamp: 0,
                delta: 0
            })
        );
        uint256 balanceBeforeSend = address(this).balance;
        // Send the message through the Abridge contract
        _guid = abridge().send{ value: _messageFee }(smartSavingsOnGravity, lzReceiveGasLimit, message);
        uint256 balanceAfterSend = address(this).balance;

        _nativeFee = balanceBeforeSend - balanceAfterSend;
        // refund the unused fee
        if (_nativeFee < _messageFee) {
            uint256 refundAmount = _messageFee - _nativeFee;
            (bool sent, ) = msg.sender.call{ value: refundAmount }("");
            if (!sent) revert SendFailed(msg.sender, refundAmount);
        }
    }
}