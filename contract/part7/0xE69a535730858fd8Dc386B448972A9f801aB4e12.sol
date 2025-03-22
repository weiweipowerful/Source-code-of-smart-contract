// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IZkCro} from "./interfaces/IZkCro.sol";
import {IBridgehub, L2TransactionRequestDirect} from "./interfaces/IBridgeHub.sol";

contract ZkCroMintAndBridge is
    Pausable,
    AccessControlEnumerable,
    ReentrancyGuard
{
    uint256 public chainId;
    uint256 public l2GasPerPubdataByteLimit;
    IZkCro public zkCro;
    IERC20 public cro;
    IBridgehub public bridgehub;

    using SafeERC20 for IERC20;

    error ZERO_ADDRESS();
    error ZERO_AMOUNT();
    error LOW_GAS_FEE();
    error INVALID_ID();

    event SetChainParameters(uint256 l2GasPerPubdataByteLimit);

    event MintAndBridge(
        address indexed sender,
        address indexed l2Receiver,
        uint256 zkCroBridgeAmount,
        uint256 totalCro,
        bytes32 canonicalTxHash
    );

    constructor(
        IZkCro _zkCro,
        IERC20 _cro,
        IBridgehub _bridgehub,
        uint256 _chainId
    ) {
        if (
            address(_zkCro) == address(0) ||
            address(_cro) == address(0) ||
            address(_bridgehub) == address(0)
        ) {
            revert ZERO_ADDRESS();
        }

        if (_chainId == 0) {
            revert INVALID_ID();
        }
        cro = _cro;
        zkCro = _zkCro;
        chainId = _chainId;
        bridgehub = _bridgehub;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setChainParameters(
        uint256 _l2GasPerPubdataByteLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        l2GasPerPubdataByteLimit = _l2GasPerPubdataByteLimit;
        emit SetChainParameters(l2GasPerPubdataByteLimit);
    }

    /**
     * @dev Toggles the pause state of the contract. In case of emergency
     */
    function togglePause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused() ? _unpause() : _pause();
    }

    /**
     * @dev mint zkcro from cro and bridge to cronos zkevm
     *
     * @param _l2Receiver The receiver that will receive the minted token on L2
     * @param _zkCroBridgeAmount The amount of zkCro to expect to receive
     * @param _l2GasLimit The estimated gas limit of the L2 tx
     * @param _totalCro The total cro needed for this operation, = _zkCroBridgeAmount + l2GasCost by the caller using bridgehubContract.l2TransactionBaseCost
     * @return canonicalTxHash The canonical L2 tx hash, which can be used to track the L2 tx status.
     */
    function mintAndBridge(
        address _l2Receiver,
        uint256 _zkCroBridgeAmount,
        uint256 _l2GasLimit,
        uint256 _totalCro
    ) external whenNotPaused nonReentrant returns (bytes32 canonicalTxHash) {
        if (_l2Receiver == address(0)) {
            revert ZERO_ADDRESS();
        }
        if (_zkCroBridgeAmount == 0 || _l2GasLimit == 0 || _totalCro == 0) {
            revert ZERO_AMOUNT();
        }

        cro.safeTransferFrom(msg.sender, address(this), _totalCro);

        // Mint zkCro to this contract
        cro.approve(address(zkCro), _totalCro);
        uint256 totalZkCro = zkCro.stake(address(this), _totalCro);

        if (totalZkCro <= _zkCroBridgeAmount) {
            revert LOW_GAS_FEE();
        }

        // Bridge zkCro for the l2 receiver
        bytes[] memory factoryDeps = new bytes[](0);
        zkCro.approve(address(bridgehub.sharedBridge()), totalZkCro);
        canonicalTxHash = bridgehub.requestL2TransactionDirect(
            L2TransactionRequestDirect({
                chainId: chainId,
                mintValue: totalZkCro,
                l2Contract: _l2Receiver,
                l2Value: _zkCroBridgeAmount,
                l2Calldata: "0x",
                l2GasLimit: _l2GasLimit,
                l2GasPerPubdataByteLimit: l2GasPerPubdataByteLimit,
                factoryDeps: factoryDeps,
                refundRecipient: _l2Receiver
            })
        );

        emit MintAndBridge(
            msg.sender,
            _l2Receiver,
            _zkCroBridgeAmount,
            _totalCro,
            canonicalTxHash
        );
    }
}