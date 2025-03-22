// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {
    SimpleAccount
} from "@account-abstraction/contracts/samples/SimpleAccount.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    IPaymaster
} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {
    UserOperation
} from "@account-abstraction/contracts/interfaces/UserOperation.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    Create2ForwarderFactory
} from "./forwarder/Create2ForwarderFactory.sol";
import {
    BridgeParams,
    CheckoutPoolInterface,
    CheckoutState,
    SwapParams
} from "./interfaces/CheckoutPoolInterface.sol";
import {
    CheckoutPoolEventsAndErrors
} from "./interfaces/CheckoutPoolEventsAndErrors.sol";
import {
    InspectablePaymasterInterface
} from "./interfaces/InspectablePaymasterInterface.sol";
import { CheckoutPaymaster } from "./paymaster/CheckoutPaymaster.sol";
import { GuardianOwnable } from "./utils/GuardianOwnable.sol";
import { WETH9Interface } from "./interfaces/WETH9Interface.sol";

contract CheckoutPool is
    GuardianOwnable,
    CheckoutPoolInterface,
    CheckoutPoolEventsAndErrors
{
    using SafeERC20 for IERC20;
    uint256 public timelockDuration = 1 days;

    IEntryPoint public immutable ENTRY_POINT;
    WETH9Interface public immutable WRAPPED_NATIVE_TOKEN;
    address public immutable NATIVE_TOKEN =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address public immutable USDT_TOKEN =
        address(0xdAC17F958D2ee523a2206206994597C13D831ec7);    
    Create2ForwarderFactory public FORWARDER_FACTORY;
    address public operator;
    address public paymaster;

    bool public _ALLOW_ALL_;
    mapping(address target => bool isAllowed) public _ALLOWED_SWAP_TARGETS_;
    mapping(address target => bool isAllowed) public _ALLOWED_BRIDGE_TARGETS_;
    mapping(uint256 chainId => bool isAllowed) public _ALLOWED_CHAIN_IDS_;
    mapping(IERC20 asset => uint256 excessAmount) public _POOL_EXCESS_;
    mapping(bytes32 => uint256) public _TIMELOCK_EXPIRATION_;

    /// @dev Active checkout accounts.
    mapping(address depositAddress => CheckoutState checkout)
        internal _CHECKOUTS_;

    modifier allowedSwapTarget(address target) {
        if (!(_ALLOW_ALL_ || _ALLOWED_SWAP_TARGETS_[target])) {
            revert SwapTargetNotAllowed(target);
        }
        _;
    }

    modifier allowedBridgeTarget(address target) {
        if (!(_ALLOW_ALL_ || _ALLOWED_BRIDGE_TARGETS_[target])) {
            revert BridgeTargetNotAllowed(target);
        }
        _;
    }

    modifier notExpired(uint256 expiration) {
        if (block.timestamp >= expiration) {
            revert CheckoutExpired();
        }
        _;
    }

    modifier Timelock() {
        bytes32 hash = getCallHash(msg.sender, msg.data);
        uint256 expiration = _TIMELOCK_EXPIRATION_[hash];
        if (expiration == 0) {
            _TIMELOCK_EXPIRATION_[hash] = block.timestamp + timelockDuration;
        } else if (block.timestamp < expiration) {
            revert TimelockNotExpired(hash, expiration);
        } else {
            delete _TIMELOCK_EXPIRATION_[hash];
            _;
        }
    }

    modifier onlyOperator() {
        if (msg.sender != operator) {
            revert OnlyOperatorAllowed(msg.sender, operator);
        }
        _;
    }

    modifier onlyPaymaster() {
        if (msg.sender != paymaster) {
            revert OnlyPaymasterAllowed(msg.sender, paymaster);
        }
        _;
    }

    receive() external payable {}

    constructor(
        address guardian,
        IEntryPoint entryPoint,
        WETH9Interface wrappedNativeToken
    ) {
        _transferOwnership(guardian);
        ENTRY_POINT = entryPoint;
        WRAPPED_NATIVE_TOKEN = wrappedNativeToken;
        paymaster = address(0);
    }

    function setAllowAll(bool isAllowed) external onlyOwner {
        _ALLOW_ALL_ = isAllowed;
    }

    function setTimelockDuration(uint256 duration) external onlyOwner {
        timelockDuration = duration;
    }

    function setForwarderFactory(
        Create2ForwarderFactory fowarderFactory
    ) external onlyOwner {
        FORWARDER_FACTORY = fowarderFactory;
    }

    function setPaymaster(address newPaymaster) external onlyOwner {
        paymaster = newPaymaster;
    }

    function addAllowedSwapTargets(
        address[] calldata targets
    ) external onlyOwner Timelock {
        _updateAllowedSwapTargets(targets, true);
    }

    function addAllowedBridgeTargets(
        address[] calldata targets
    ) external onlyOwner Timelock {
        _updateAllowedBridgeTargets(targets, true);
    }
    function addAllowedChainIds(
        uint256[] calldata chainIds
    ) external onlyOwner Timelock {
        _updateAllowedChainIds(chainIds, true);
    }

    function removeAllowedSwapTargets(
        address[] calldata targets
    ) external onlyOwner {
        _updateAllowedSwapTargets(targets, false);
    }

    function removeAllowedBridgeTargets(
        address[] calldata targets
    ) external onlyOwner {
        _updateAllowedBridgeTargets(targets, false);
    }

    function removeAllowedChainIds(
        uint256[] calldata chainIds
    ) external onlyOwner {
        _updateAllowedChainIds(chainIds, false);
    }

    function setOperator(address newOperator) external onlyOwner {
        operator = newOperator;
    }

    function addExcessToPool(IERC20 asset, uint256 amount) external {
        _POOL_EXCESS_[asset] += amount;

        asset.safeTransferFrom(msg.sender, address(this), amount);

        emit ExcessAdded(asset, amount);
    }

    function removeExcessFromPool(
        IERC20 asset,
        uint256 amount
    ) external onlyOwner {
        // Will revert if amount is greater than excess balance.
        _POOL_EXCESS_[asset] -= amount;

        asset.safeTransfer(msg.sender, amount);

        emit ExcessRemoved(asset, amount);
    }

    /**
     * @notice Deposit funds to create a checkout account.
     */
    function deposit(
        CheckoutState calldata checkout
    ) external notExpired(checkout.params.expiration) {
        address depositAddress = msg.sender;

        checkout.heldAsset.safeTransferFrom(
            depositAddress,
            address(this),
            checkout.heldAmount
        );

        _CHECKOUTS_[depositAddress] = checkout;

        emit Deposited(depositAddress, checkout.heldAsset, checkout.heldAmount);
    }

    function swap(
        address depositAddress,
        SwapParams calldata swapParams
    )
        external
        notExpired(_CHECKOUTS_[depositAddress].params.expiration)
        allowedSwapTarget(swapParams.target)
        onlyOperator
    {
        // Read checkout state from storage.
        CheckoutState storage checkout = _getCheckout(depositAddress);
        IERC20 heldAsset = checkout.heldAsset;
        uint256 heldAmount = checkout.heldAmount;

        // Set the allowance on the swap spender.
        //
        // Note: Using approve() instead of safeIncreaseAllowance() or forceApprove() under the
        // assumption that all allowances from this contract will be zero in between transactions.
        // We have a condition here if it is USDT, where we will perform a safeApprove as USDT does not return any value
        if (block.chainid == 1 && address(heldAsset) == USDT_TOKEN) {
            heldAsset.safeApprove(swapParams.spender, heldAmount);
        } else {
            heldAsset.approve(swapParams.spender, heldAmount);
        }

        // Get starting balance of the asset to receive from the swap.
        uint256 balanceBefore;
        if (address(swapParams.receivedAsset) == NATIVE_TOKEN) {
            balanceBefore = address(this).balance;
        } else {
            balanceBefore = IERC20(swapParams.receivedAsset).balanceOf(
                address(this)
            );
        }

        bool success;
        bytes memory returnData;
        // Execute the swap.
        if (swapParams.isETHSwap) {
            require(
                heldAsset == WRAPPED_NATIVE_TOKEN,
                "Held asset must be WETH for ETH swaps"
            );
            WETH9Interface(WRAPPED_NATIVE_TOKEN).withdraw(heldAmount);
            (success, returnData) = swapParams.target.call{value: heldAmount}(
                swapParams.callData
            );
        } else {
            // Set the allowance on the swap spender.
            //
            // Note: Using approve() instead of safeIncreaseAllowance() or forceApprove() under the
            // assumption that all allowances from this contract will be zero in between transactions.
            heldAsset.approve(swapParams.spender, heldAmount);

            (success, returnData) = swapParams.target.call(
                swapParams.callData
            );

            // Require that the full allowance was spent.
            //
            // IMPORTANT NOTE: We assume the swap contract supports spending an exact amount.
            //
            // Note: This check will fail with some ERC-20 implementations in the case
            // where heldAmount = type(uint256).max. We assume that this is impossible in practice.
            uint256 remainingAllowance = heldAsset.allowance(
                address(this),
                swapParams.spender
            );
            if (remainingAllowance != 0) {
                revert SwapDidNotSpendExactAmount(remainingAllowance);
            }
        }
        if (!success) {
            revert SwapReverted(returnData);
        }
        uint256 receivedAmount;
        IERC20 receivedAsset;
        if (address(swapParams.receivedAsset) == NATIVE_TOKEN) {
            // Note: The tx will revert if the received asset balance decreased.
            receivedAmount = address(this).balance - balanceBefore;
            WRAPPED_NATIVE_TOKEN.deposit{value: receivedAmount}();
            receivedAsset = WRAPPED_NATIVE_TOKEN;
        } else {
            uint256 balanceAfter = IERC20(swapParams.receivedAsset).balanceOf(
                address(this)
            );
            // Note: The tx will revert if the received asset balance decreased.
            receivedAmount = balanceAfter - balanceBefore;
            receivedAsset = IERC20(swapParams.receivedAsset);
        }

        // Write checkout state to storage.
        checkout.heldAsset = receivedAsset;
        checkout.heldAmount = receivedAmount;

        emit Swapped(
            depositAddress,
            swapParams.target,
            receivedAsset,
            receivedAmount
        );
    }

    function bridge(
        address depositAddress,
        BridgeParams calldata bridgeParams
    )
        external
        notExpired(_CHECKOUTS_[depositAddress].params.expiration)
        allowedBridgeTarget(bridgeParams.target)
        onlyOperator
    {
        // Read checkout state from storage.
        // Note: Read the whole thing into memory since we use it later.
        CheckoutState memory checkout = _getCheckout(depositAddress);
        IERC20 heldAsset = checkout.heldAsset;
        uint256 heldAmount = checkout.heldAmount;
        uint256 targetChainId = checkout.params.targetChainId;

        // Sanity check that we are not already on the target chain.
        if (targetChainId == block.chainid) {
            revert BridgeAlreadyOnTargetChain();
        }

        // Require that the chain ID is allowed/supported.
        if (!(_ALLOW_ALL_ || _ALLOWED_CHAIN_IDS_[targetChainId])) {
            revert BridgeChainIdNotAllowed(targetChainId);
        }

        // Set the allowance on the swap spender.
        //
        // Note: Using approve() instead of safeIncreaseAllowance() or forceApprove() under the
        // assumption that all allowances from this contract will be zero in between transactions.
        // We have a condition here if it is USDT, where we will perform a safeApprove as USDT does not return any value
        if (block.chainid == 1 && address(heldAsset) == USDT_TOKEN) {
            heldAsset.safeApprove(bridgeParams.spender, heldAmount);
        } else {
            heldAsset.approve(bridgeParams.spender, heldAmount);
        }

        bytes32 salt = keccak256(abi.encodePacked(blockhash(block.number - 1)));

        // Get the counterfactual deployment deposit address for the target chain.
        //
        // IMPORTANT NOTE: This implementation assumes that the forwarder factory has the same
        // address on each chain. This has to be ensured before a chain ID is added to the allowed
        // list of target chain IDs.
        CheckoutState memory bridgedCheckout = CheckoutState({
            params: checkout.params,
            heldAsset: bridgeParams.bridgeReceivedAsset,
            heldAmount: bridgeParams.minBridgeReceivedAmount
        });
        address targetChainDepositAddress = FORWARDER_FACTORY
            .getAddressForChain(bridgedCheckout, salt, targetChainId);

        // Execute the bridge call.
        _bridgeToRecipient(
            bridgeParams.target,
            bridgeParams.callData,
            targetChainDepositAddress
        );

        // Require that the full allowance was spent.
        //
        // IMPORTANT NOTE: We assume the bridge contract supports spending an exact amount.
        uint256 remainingAllowance = heldAsset.allowance(
            address(this),
            bridgeParams.spender
        );
        if (remainingAllowance != 0) {
            revert BridgeDidNotSpendExactAmount(remainingAllowance);
        }

        // Delete the checkout from storage.
        delete _CHECKOUTS_[depositAddress];

        emit Bridged(
            depositAddress,
            targetChainDepositAddress,
            bridgeParams.target,
            bridgeParams.bridgeReceivedAsset,
            bridgeParams.minBridgeReceivedAmount
        );
    }

    // apply to non userOp execution cases
    function forwardFund(
        address depositAddress
    )
        external
        notExpired(_CHECKOUTS_[depositAddress].params.expiration)
        onlyOperator
    {
        CheckoutState storage checkout = _getCheckout(depositAddress);

        if (block.chainid != checkout.params.targetChainId) {
            revert ForwardFundChainNotReady(block.chainid);
        }

        if (checkout.params.recipient == bytes32(0)) {
            revert ForwardFundRecipientNotSet();
        }

        if (checkout.params.userOpHash != bytes32(0)) {
            revert ForwardFundUserOpHashIsSet(checkout.params.userOpHash);
        }

        IERC20 heldAsset = checkout.heldAsset;
        uint256 heldAmount = checkout.heldAmount;

        uint256 forwardAmount = checkout.params.targetAmount;
        checkout.params.targetAmount = 0;
        if (forwardAmount < heldAmount) {
            _POOL_EXCESS_[heldAsset] += heldAmount - forwardAmount;
        } else if (forwardAmount > heldAmount) {
            uint256 oldExcessAmount = _POOL_EXCESS_[heldAsset];
            uint256 excessSpend = forwardAmount - heldAmount;
            if (oldExcessAmount < excessSpend) {
                revert ExecuteInsufficientExcessBalance(
                    oldExcessAmount,
                    forwardAmount,
                    heldAmount
                );
            }
            _POOL_EXCESS_[heldAsset] = oldExcessAmount - excessSpend;
        }

        address targetAssetAddr = address(
            uint160(uint256(checkout.params.targetAsset))
        );
        address recipientAddr = address(
            uint160(uint256(checkout.params.recipient))
        );
        if (targetAssetAddr == NATIVE_TOKEN) {
            if (heldAsset != WRAPPED_NATIVE_TOKEN) {
                revert ForwardFundAssetNotReady(heldAsset);
            } else {
                WRAPPED_NATIVE_TOKEN.withdraw(forwardAmount);
                (bool success, ) = payable(recipientAddr).call{
                    value: forwardAmount
                }("");
                require(success, "failed to forward fund");
            }
        } else if (heldAsset != IERC20(targetAssetAddr)) {
            revert ForwardFundAssetNotReady(heldAsset);
        } else if (heldAsset == IERC20(targetAssetAddr)) {
            heldAsset.safeTransfer(recipientAddr, forwardAmount);
        } else {
            revert ForwardFundAssetNotReady(heldAsset);
        }

        // Delete the checkout from storage.
        delete _CHECKOUTS_[depositAddress];

        emit FundForwarded(
            depositAddress,
            forwardAmount,
            checkout.params.recipient
        );
    }

    function executeWithPaymaster(
        CheckoutPaymaster _paymaster,
        address depositAddress,
        UserOperation[] calldata ops
    ) external onlyOperator {
        bytes memory callData = abi.encodeWithSelector(
            this.execute.selector,
            depositAddress,
            ops
        );
        _paymaster.activateAndCall(address(this), callData);
    }

    function execute(
        address depositAddress,
        UserOperation[] calldata ops
    )
        external
        notExpired(_CHECKOUTS_[depositAddress].params.expiration)
        onlyPaymaster
    {
        // Note: Currently having execute() take an array UserOperation[] in case this is more
        // gas efficient than creating the array explicitly in order to call handleOps(). (?)
        if (ops.length != 1) {
            revert ExecuteInvalidOpsLength();
        }

        CheckoutState storage checkout = _getCheckout(depositAddress);
        IERC20 heldAsset = checkout.heldAsset;
        uint256 heldAmount = checkout.heldAmount;

        if (block.chainid != checkout.params.targetChainId) {
            revert ExecuteChainNotReady(block.chainid);
        }

        bytes32 calculatedUserOpHash = ENTRY_POINT.getUserOpHash(ops[0]);
        if (calculatedUserOpHash != checkout.params.userOpHash) {
            revert ExecuteInvalidUserOp(calculatedUserOpHash);
        }

        // Add or subtract from the excess amount in the pool, depending on whether the
        // execution amount is greater or less than the held amount.
        uint256 executionAmount = checkout.params.targetAmount;
        checkout.params.targetAmount = 0;
        if (executionAmount < heldAmount) {
            _POOL_EXCESS_[heldAsset] += heldAmount - executionAmount;
        } else if (executionAmount > heldAmount) {
            uint256 oldExcessAmount = _POOL_EXCESS_[heldAsset];
            uint256 excessSpend = executionAmount - heldAmount;
            if (oldExcessAmount < excessSpend) {
                revert ExecuteInsufficientExcessBalance(
                    oldExcessAmount,
                    executionAmount,
                    heldAmount
                );
            }
            _POOL_EXCESS_[heldAsset] = oldExcessAmount - excessSpend;
        }

        address targetAssetAddr = address(
            uint160(uint256(checkout.params.targetAsset))
        );
        // Send the execution amount to the userOp sender and execute the userOp.
        if (targetAssetAddr == NATIVE_TOKEN) {
            if (heldAsset != WRAPPED_NATIVE_TOKEN) {
                revert ExecuteAssetNotReady(heldAsset);
            } else {
                WRAPPED_NATIVE_TOKEN.withdraw(executionAmount);
                (bool success, ) = payable(ops[0].sender).call{
                    value: executionAmount
                }("");
                require(success, "failed to send fund before execute userOp");
            }
        } else if (heldAsset != IERC20(targetAssetAddr)) {
            revert ExecuteAssetNotReady(heldAsset);
        } else if (heldAsset == IERC20(targetAssetAddr)) {
            heldAsset.safeTransfer(ops[0].sender, executionAmount);
        } else {
            revert ExecuteAssetNotReady(heldAsset);
        }

        ENTRY_POINT.handleOps(ops, payable(guardian()));

        // Revert if the userOp reverted.
        {
            address paymasterAddress = address(
                bytes20(ops[0].paymasterAndData[:20])
            );
            IPaymaster.PostOpMode userOpMode = InspectablePaymasterInterface(
                paymasterAddress
            ).getLastOpMode();
            if (userOpMode != IPaymaster.PostOpMode.opSucceeded) {
                revert ExecuteUserOpReverted(userOpMode);
            }
        }

        // Delete the checkout from storage.
        delete _CHECKOUTS_[depositAddress];

        emit Executed(depositAddress, executionAmount);
    }

    function checkoutExists(
        address depositAddress
    ) external view returns (bool) {
        return _CHECKOUTS_[depositAddress].params.targetAsset != bytes32(0);
    }

    function getCheckout(
        address depositAddress
    ) external view returns (CheckoutState memory) {
        return _getCheckout(depositAddress);
    }

    function getCheckoutOrZero(
        address depositAddress
    ) external view returns (CheckoutState memory) {
        return _CHECKOUTS_[depositAddress];
    }

    function _getCheckout(
        address depositAddress
    ) internal view returns (CheckoutState storage) {
        CheckoutState storage checkout = _CHECKOUTS_[depositAddress];
        if (checkout.params.targetAsset == bytes32(0)) {
            revert CheckoutDoesNotExist();
        }
        return checkout;
    }

    function _updateAllowedSwapTargets(
        address[] calldata targets,
        bool isAllowed
    ) internal {
        uint256 n = targets.length;
        for (uint256 i; i < n; ++i) {
            address target = targets[i];
            _ALLOWED_SWAP_TARGETS_[target] = isAllowed;
            emit UpdatedAllowedSwapTarget(target, isAllowed);
        }
    }

    function _updateAllowedBridgeTargets(
        address[] calldata targets,
        bool isAllowed
    ) internal {
        uint256 n = targets.length;
        for (uint256 i; i < n; ++i) {
            address target = targets[i];
            _ALLOWED_BRIDGE_TARGETS_[target] = isAllowed;
            emit UpdatedAllowedBridgeTarget(target, isAllowed);
        }
    }

    function _updateAllowedChainIds(
        uint256[] calldata chainids,
        bool isAllowed
    ) internal {
        uint256 n = chainids.length;
        for (uint256 i; i < n; ++i) {
            uint256 chainId = chainids[i];
            _ALLOWED_CHAIN_IDS_[chainId] = isAllowed;
            emit UpdatedAllowedChainIds(chainId, isAllowed);
        }
    }

    function _bridgeToRecipient(
        address target,
        bytes calldata callData,
        address targetChainDepositAddress
    ) internal {
        // as needed.
        (bool success, bytes memory returnData) = target.call(callData);
        if (!success) {
            revert BridgeReverted(returnData);
        }
    }

    function getCallHash(
        address sender,
        bytes calldata callData
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(sender, callData));
    }
}