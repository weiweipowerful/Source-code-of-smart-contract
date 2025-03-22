// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AxelarExecutable} from "./axelar/AxelarExecutable.sol";
import {IAxelarGateway} from "./interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import {InterchainAddressTracker} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/utils/InterchainAddressTracker.sol";

import {OApp, Origin, MessagingFee} from "./oapp/OApp.sol";
import {ILayerZeroEndpointV2} from "./oapp/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ISquidMulticall} from "./interfaces/ISquidMulticall.sol";
import {IPermit2} from "./interfaces/IPermit2.sol";
import {ISpoke} from "./interfaces/ISpoke.sol";
import {Utils} from "./libraries/Utils.sol";

contract Spoke is ISpoke, OApp, AxelarExecutable, Initializable, InterchainAddressTracker, ReentrancyGuard, EIP712 {
    using Address for address payable;
    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;

    /// @dev token address => fee amount collected in this token
    mapping(address => uint256) public tokenToCollectedFees;
    mapping(bytes32 => OrderStatus) public orderHashToStatus;
    mapping(bytes32 => SettlementStatus) public settlementToStatus;

    IAxelarGasService public gasService;
    IPermit2 public permit2;
    ISquidMulticall public squidMulticall;
    address public feeCollector;
    /// @dev Chain name must follow Axelar format
    /// https://docs.axelar.dev/dev/reference/mainnet-contract-addresses
    string public hubChainName;
    string public hubAddress;
    /// @dev Endpoint must follow LayerZero format
    /// https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
    uint32 public hubEndpoint;
    bytes32 public hubAddressBytes32;

    modifier onlyFeeCollector() {
        if (msg.sender != feeCollector) revert OnlyFeeCollector();
        _;
    }

    modifier onlyTrustedAddress(string calldata fromChainName, string calldata fromContractAddress) {
        if (!isTrustedAddress(fromChainName, fromContractAddress)) revert OnlyTrustedAddress();
        _;
    }

    constructor() 
        AxelarExecutable(0xC012A11111111111111111111111111111111111)
        EIP712("Spoke", "1")
        OApp(0xC012A11111111111111111111111111111111111, msg.sender)
        Ownable(msg.sender)
    {}

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                        Initializer                       //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @notice One-time use initialize function for the protocol. This function is required to be called
    /// within the deploying transaction to set the initial state of the Spoke.sol contract. These parameters
    /// cannot be updated after initialization.
    /// @notice The _hubChainName and _hubAddress will be set as the trusted chain and address for Axelar
    /// general message passing. Only the trusted Hub.sol contract can execute interchain transactions
    /// in the Spoke.sol contract.
    /// @param _axelarGateway Address of the relevant Axelar's AxelarGateway.sol contract deployment.
    /// @param _axelarGasService Address of the relevant Axelar's AxelarGasService.sol contract deployment.
    /// @param _permit2 Address of the relevant Uniswap's Permit2.sol contract deployment
    /// Can be zero address if not available on current network.
    /// @param _squidMulticall Address of the relevant Squid's SquidMulticall.sol contract deployment.
    /// @param _feeCollector Address of the EOA that would collect fees from the protocol. Recommended to use
    /// a multisig wallet.
    /// @param _hubChainName Chain name of the chain the Hub.sol contract will be deployed to, must follow
    /// Axelar's chain name format. This chain name will be passed to the Axelar Gateway to determine the
    /// target chain for general message passing from the Spoke.
    /// @param _hubAddress String for the address of the relevant Hub.sol contract, this should be computed
    /// deterministically using the CREATE2 opcode to remain permissionless.
    /// @param _endpoint Address of the LayerZero EndpointV2 contract, responsible for managing cross-chain
    /// communications.
    /// @param _owner Address set as the owner of the Spoke.sol contract upon deployment.
    /// @param _hub Address of the relevant Hub.sol contract, this should be computed deterministically
    /// using the CREATE2 opcode to remain permissionless.
    /// @param _hubEndpoint Endpoint ID as specified by LayerZero:
    /// https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
    function initialize(
        IAxelarGateway _axelarGateway,
        IAxelarGasService _axelarGasService,
        IPermit2 _permit2,
        ISquidMulticall _squidMulticall,
        address _feeCollector,
        string memory _hubChainName,
        string memory _hubAddress,
        ILayerZeroEndpointV2 _endpoint,
        address _owner,
        address _hub,
        uint32 _hubEndpoint
    ) external initializer {
        transferOwnership(_owner);
        gateway = _axelarGateway;
        gasService = _axelarGasService;
        permit2 = _permit2;
        squidMulticall = _squidMulticall;
        feeCollector = _feeCollector;
        hubChainName = _hubChainName;
        hubAddress = _hubAddress;
        _setTrustedAddress(_hubChainName, _hubAddress);

        if (address(_endpoint) != 0x1111111111111111111111111111111111111111) {
            endpoint = _endpoint;
            _endpoint.setDelegate(_owner);
            hubEndpoint = _hubEndpoint;
            _setPeer(_hubEndpoint, addressToBytes32(_hub));
            hubAddressBytes32 = addressToBytes32(_hub);
        }
    
        emit SpokeInitialized(
            gateway,
            gasService,
            permit2,
            squidMulticall,
            feeCollector,
            hubChainName,
            hubAddress
        );
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                      Source endpoints                    //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISpoke
    function createOrder(Order calldata order) external payable {
        _createOrder(order, msg.sender);
    }

    /// @inheritdoc ISpoke
    function sponsorOrder(Order calldata order, bytes calldata signature) external {
        if (order.fromToken == Utils.NATIVE_TOKEN) revert NativeTokensNotAllowed();
        if (
            !SignatureChecker.isValidSignatureNow(
                order.fromAddress,
                _hashTypedDataV4(_hashOrderTyped(order)),
                signature
            )
        ) revert InvalidUserSignature();

        _createOrder(order, order.fromAddress);
    }

    /// @notice Executes the intent on the source chain, locking the ERC20 or native tokens in the
    /// Spoke.sol contract, setting the OrderStatus to CREATED, and making the order eligible
    /// to be filled on the destination chain.
    /// @dev Orders are tied to the keccak256 hash of the Order therefore each Order is unique 
    /// according to the parameters in the Order and can only be executed a single time.
    /// @param order Order to be executed by the Spoke.sol contract in the format of the Order struct.
    /// @param fromAddress Address of the holder of funds for a particular order.
    function _createOrder(Order calldata order, address fromAddress) private nonReentrant {
        bytes32 orderHash = keccak256(abi.encode(order));

        if (orderHashToStatus[orderHash] != OrderStatus.EMPTY) revert OrderAlreadyExists();
        if (block.timestamp > order.expiry) revert OrderExpired();
        if (order.fromChain != _getChainId()) revert InvalidSourceChain();
        if (order.fromToken != Utils.NATIVE_TOKEN && msg.value != 0) revert UnexpectedNativeToken();

        orderHashToStatus[orderHash] = OrderStatus.CREATED;

        if (order.fromToken == Utils.NATIVE_TOKEN) {
            if (msg.value != order.fromAmount) revert InvalidNativeAmount();
        } else {
            IERC20(order.fromToken).safeTransferFrom(fromAddress, address(this), order.fromAmount);
        }

        emit OrderCreated(orderHash, order);
    }

    /// @inheritdoc ISpoke
    function sponsorOrderUsingPermit2(
        Order calldata order,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 orderHash = keccak256(abi.encode(order));

        if (orderHashToStatus[orderHash] != OrderStatus.EMPTY) revert OrderAlreadyExists();
        if (block.timestamp > order.expiry) revert OrderExpired();
        if (order.fromChain != _getChainId()) revert InvalidSourceChain();
        if (order.fromToken == Utils.NATIVE_TOKEN) revert NativeTokensNotAllowed();

        orderHashToStatus[orderHash] = OrderStatus.CREATED;

        IPermit2.SignatureTransferDetails memory transferDetails;
        transferDetails.to = address(this);
        transferDetails.requestedAmount = order.fromAmount;

        bytes32 witness = _hashOrderTyped(order);
        permit2.permitWitnessTransferFrom(
            permit,
            transferDetails,
            order.fromAddress,
            witness,
            Utils.ORDER_WITNESS_TYPE_STRING,
            signature
        );

        emit OrderCreated(orderHash, order);
    }

    /// @inheritdoc ISpoke
    function refundOrder(Order calldata order) external nonReentrant {
        bytes32 orderHash = keccak256(abi.encode(order));

        if (orderHashToStatus[orderHash] != OrderStatus.CREATED) revert OrderStateNotCreated();
        if (msg.sender != order.filler) {
            if (!(block.timestamp > (order.expiry + 1 days))) revert OrderNotExpired();
        }
        if (order.fromChain != _getChainId()) revert InvalidSourceChain();

        orderHashToStatus[orderHash] = OrderStatus.REFUNDED;

        if (order.fromToken == Utils.NATIVE_TOKEN) {
            payable(order.fromAddress).sendValue(order.fromAmount);
        } else {
            IERC20(order.fromToken).safeTransfer(order.fromAddress, order.fromAmount);
        }

        emit OrderRefunded(orderHash);
    }

    /// @inheritdoc ISpoke
    function collectFees(address[] calldata tokens) external onlyFeeCollector {
        if (tokens.length == 0) revert InvalidArrayLength();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 feeAmount = tokenToCollectedFees[tokens[i]];
            if (feeAmount > 0) {
                tokenToCollectedFees[tokens[i]] = 0;
                if (tokens[i] == Utils.NATIVE_TOKEN) {
                    payable(feeCollector).sendValue(feeAmount);
                } else {
                    IERC20(tokens[i]).safeTransfer(feeCollector, feeAmount);
                }
            }

            emit FeesCollected(feeCollector, tokens[i], feeAmount);
        } 
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                   Destination endpoints                  //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISpoke
    function batchFillOrder(Order[] calldata orders, ISquidMulticall.Call[][] calldata calls) external payable {
        if (
            orders.length == 0 || 
            orders.length != calls.length
        ) revert InvalidArrayLength();

        uint256 remainingNativeTokenValue = msg.value;
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].toToken == Utils.NATIVE_TOKEN) {
                if (remainingNativeTokenValue < orders[i].fillAmount) revert InvalidTotalNativeAmount();
                remainingNativeTokenValue -= orders[i].fillAmount;
            }
            _fillOrder(orders[i], calls[i]);
        }
    }

    /// @inheritdoc ISpoke
    function fillOrder(Order calldata order, ISquidMulticall.Call[] calldata calls) public payable {
        if (order.toToken == Utils.NATIVE_TOKEN && msg.value != order.fillAmount) {
            revert InvalidNativeAmount();
        }

        _fillOrder(order, calls);
    }

    /// @notice Fills an order on the destination chain, transferring the order.fillAmount of
    /// order.toToken from the order.filler to the order.toAddress, setting the SettlementStatus to
    /// FILLED, and making the order eligible to be forwarded to the Hub for processing.
    /// @dev Orders that contain post hooks (postHookHash != bytes32(0)) require SquidMulticall calls
    /// to be provided during fill. These extra calls will be ran by SquidMulticall after filling the
    /// order during the same transaction.
    /// @dev Only the order.filler can fill any particular order.
    /// @param order Order to be filled by the Spoke.sol contract in the format of the Order struct.
    /// @param calls Calls to be ran by the multicall after fill, formatted to the SquidMulticall Call struct.
    function _fillOrder(Order memory order, ISquidMulticall.Call[] calldata calls) internal nonReentrant {
        bytes32 orderHash = keccak256(abi.encode(order));

        if (settlementToStatus[orderHash] != SettlementStatus.EMPTY) revert OrderAlreadySettled();
        if (msg.sender != order.filler) revert OnlyFillerCanSettle();
        if (order.toChain != _getChainId()) revert InvalidDestinationChain();

        settlementToStatus[orderHash] = SettlementStatus.FILLED;

        if (order.toToken == Utils.NATIVE_TOKEN) {
            if (order.postHookHash != bytes32(0)) {
                bytes memory callsData = abi.encode(calls);
                if (keccak256(callsData) != order.postHookHash) revert InvalidPostHookProvided();
                ISquidMulticall(squidMulticall).run{value: order.fillAmount}(calls);
            } else {
                payable(order.toAddress).sendValue(order.fillAmount);
            }
        } else {
            if (order.postHookHash != bytes32(0)) {
                bytes memory callsData = abi.encode(calls);
                if (keccak256(callsData) != order.postHookHash) revert InvalidPostHookProvided();

                IERC20(order.toToken).safeTransferFrom(
                    order.filler,
                    address(squidMulticall),
                    order.fillAmount
                );

                ISquidMulticall(squidMulticall).run(calls);
            } else {
                IERC20(order.toToken).safeTransferFrom(
                    order.filler,
                    order.toAddress,
                    order.fillAmount
                );
            }
        }

        emit OrderFilled(orderHash, order);
    }

    /// @inheritdoc ISpoke
    function forwardSettlements(
        bytes32[] calldata orderHashes,
        uint256 lzFee,
        uint128 gasLimit,
        Provider provider
    ) external payable nonReentrant {
        if (msg.value == 0) revert GasRequired();
        if (orderHashes.length == 0) revert InvalidArrayLength();

        for (uint256 i = 0; i < orderHashes.length; i++) {
            if (
                settlementToStatus[orderHashes[i]] == SettlementStatus.EMPTY
            ) revert OrderNotSettled();
            settlementToStatus[orderHashes[i]] = SettlementStatus.FORWARDED;

            emit SettlementForwarded(orderHashes[i]);
        }

        bytes memory payload = abi.encode(orderHashes);

        if (provider == Provider.AXELAR) {
            gasService.payNativeGasForContractCall{value: msg.value}(
                address(this),
                hubChainName,
                hubAddress,
                payload,
                msg.sender
            );
            gateway.callContract(hubChainName, hubAddress, payload);
        } else if (provider == Provider.LAYERZERO) {
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0);
            _lzSend(
                hubEndpoint,
                payload,
                options,
                MessagingFee(msg.value, lzFee),
                payable(msg.sender)
            );
        } else {
            revert InvalidProvider();
        }
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  Single chain endpoints                  //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @inheritdoc ISpoke
    function batchMultiTokenSingleChainSettlements(
        Order[] calldata orders,
        address[] calldata fromTokens,
        address filler
    ) external payable {
        if (orders.length == 0 || fromTokens.length < 2) revert InvalidArrayLength();

        bytes32[] memory orderHashes = new bytes32[](orders.length);
        uint256[] memory fromAmounts = new uint256[](fromTokens.length);
        uint256[] memory fees = new uint256[](fromTokens.length);

        for (uint256 i = 0; i < orders.length; i++) {
            bytes32 orderHash = keccak256(abi.encode(orders[i]));
            if (settlementToStatus[orderHash] != SettlementStatus.FILLED)
                revert OrderNotSettled();
            if (orders[i].fromChain != _getChainId()) revert InvalidDestinationChain();
            if (orders[i].toChain != _getChainId()) revert InvalidSourceChain();
            if (orders[i].filler != filler) revert InvalidSettlementFiller();

            uint256 tokenIndex = _findTokenIndex(orders[i].fromToken, fromTokens);
            if (tokenIndex == type(uint256).max) revert InvalidSettlementSourceToken();

            uint256 fee = (orders[i].fromAmount * orders[i].feeRate) / Utils.FEE_DIVISOR;

            settlementToStatus[orderHash] = SettlementStatus.FORWARDED;
            fees[tokenIndex] += fee;
            fromAmounts[tokenIndex] += orders[i].fromAmount - fee;
            orderHashes[i] = orderHash;
        }

        _releaseMultiTokenBatched(orderHashes, filler, fromAmounts, fees, fromTokens);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                 Message passing endpoints                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @notice Called by Axelar protocol when receiving a GMP on the destination chain from the Hub.
    /// Contains logic that will parse the payload and release tokens for eligible orders to the order.filler.
    /// @dev This method will only accept GMP's from the hubChain and hubAddress set within the Spoke.sol
    /// initializer at the time of contract deployment.
    /// @dev There are two options for FillType: SINGLE and MULTI
    /// SINGLE is used when a batch of orders only contains a single unique order.fromToken, and only requires
    /// a single transfer to release the tokens for the batch of orders to the order.filler.
    /// MULTI is used when a batch of orders contains multiple unique order.fromToken, and will use as many
    /// transfers as there are unique tokens in the batch.
    /// @param fromChain Chain name of the chain that sent the GMP according to Axelar's chain name format:
    /// https://docs.axelar.dev/dev/reference/mainnet-contract-addresses
    /// @param fromContractAddress Address that sent the GMP.
    /// @param payload Value provided by the Hub containing the aggregated data for the orders being processed.
    /// Expected format is: abi.encode(ICoral.FillType fillType, bytes32[] orderHashes, address filler,
    /// uint256[] fromAmounts, uint256[] fees, address[] fromTokens)
    function _execute(
        string calldata fromChain,
        string calldata fromContractAddress,
        bytes calldata payload
    ) internal virtual override onlyTrustedAddress(fromChain, fromContractAddress) {
        (
            FillType fillType,
            bytes32[] memory orderHashes,
            address filler,
            uint256[] memory fromAmounts,
            uint256[] memory processedFees,
            address[] memory fromTokens
        ) = abi.decode(
                payload,
                (FillType, bytes32[], address, uint256[], uint256[], address[])
            );

        if (fillType == FillType.SINGLE) {
            if (
                fromTokens.length != 1 || 
                fromAmounts.length != 1 ||
                processedFees.length != 1
            ) revert InvalidArrayLength();
            _releaseBatched(orderHashes, filler, fromAmounts[0], processedFees[0], fromTokens[0]);
        } else if (fillType == FillType.MULTI) {
            _releaseMultiTokenBatched(orderHashes, filler, fromAmounts, processedFees, fromTokens);
        } else {
            revert InvalidFillType();
        }
    }


    /// @notice Receives and processes a LayerZero message on the destination chain from the Hub.
    /// This function decodes the message payload and releases tokens for eligible orders to the order.filler.
    /// @dev This function will only accept messages originating from the hubEndpoint and hubAddressBytes32 
    /// that are configured during initialization.
    /// @dev Utilizes LayerZero's OApp standard for cross-chain messaging.
    /// @param _origin Struct containing the message's origin information, including the source chain's 
    /// Endpoint ID, the sender's address, and a message nonce.
    /// @param _guid A globally unique identifier for tracking the LayerZero message packet.
    /// @param payload The encoded message payload containing order details, formatted as:
    /// abi.encode(ICoral.FillType fillType, bytes32[] orderHashes, address filler,
    /// uint256[] fromAmounts, uint256[] fees, address[] fromTokens).
    /// @param _executor The address of the Executor contract that called EndpointV2's lzReceive function.
    /// This is primarily for auditing purposes and not utilized in logic.
    /// @param _extraData Additional arbitrary data appended by the Executor to accompany the message payload.
    /// It is not modified by the OApp and can include metadata or instructions for execution.
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata payload,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        if (_origin.sender != hubAddressBytes32) revert UnauthorizedOriginAddress();
        if (_origin.srcEid != hubEndpoint) revert UnauthorizedOriginEndpoint();
        (
            FillType fillType,
            bytes32[] memory orderHashes,
            address filler,
            uint256[] memory fromAmounts,
            uint256[] memory processedFees,
            address[] memory fromTokens
        ) = abi.decode(
                payload,
                (FillType, bytes32[], address, uint256[], uint256[], address[])
            );

        if (fillType == FillType.SINGLE) {
            if (
                fromTokens.length != 1 || 
                fromAmounts.length != 1 ||
                processedFees.length != 1
            ) revert InvalidArrayLength();
            _releaseBatched(orderHashes, filler, fromAmounts[0], processedFees[0], fromTokens[0]);
        } else if (fillType == FillType.MULTI) {
            _releaseMultiTokenBatched(orderHashes, filler, fromAmounts, processedFees, fromTokens);
        } else {
            revert InvalidFillType();
        }
    }

    /// @notice Checks the OrderStatus of each order hash provided to ensure all orders are set to CREATED,
    /// set the OrderStatus of all order hashes to SETTLED, increments the fees for the provided token and 
    /// processedFees, and transfers the fromAmount of ERC20 or native token from the Spoke.sol contract 
    /// to the filler in a single transfer for all orders in the batch.
    /// @dev The provided order hashes are computed on the Hub based on orders that were processed and had
    /// a matching order hash that was processed on the order.toChain of the particular orders. Orders are
    /// eligible on the Hub to be forwarded to the order.fromChain once they've been filled on the
    /// order.toChain. Cross chain messages secured by Axelar protocol allow this function to receive
    /// confirmation that derived from the order.toChain Spoke.sol contract.
    /// @dev This method is called by the SINGLE FillType, therefore this will process orders for a single
    /// unique filler and token.
    /// @param orderHashes Array of keccak256 hashes of Orders being finalized.
    /// @param filler Address of the order.filler for all orders in the particular batch.
    /// @param fromAmount Amount of order.fromToken to be released to the filler.
    /// @param processedFees Amount of order.fromToken to be reserved as protocol fees.
    /// @param fromToken Address of the order.fromToken for all orders in the particular batch.
    function _releaseBatched(
        bytes32[] memory orderHashes,
        address filler,
        uint256 fromAmount,
        uint256 processedFees,
        address fromToken
    ) internal nonReentrant {
        if (orderHashes.length == 0) revert InvalidArrayLength();
    
        for (uint256 i = 0; i < orderHashes.length; i++) {
            bytes32 orderHash = orderHashes[i];
            if (orderHashToStatus[orderHash] != OrderStatus.CREATED) revert OrderStateNotCreated();
            orderHashToStatus[orderHash] = OrderStatus.SETTLED;

            emit TokensReleased(orderHash);
        }

        tokenToCollectedFees[fromToken] += processedFees;

        if (fromToken == Utils.NATIVE_TOKEN) {
            payable(filler).sendValue(fromAmount);
        } else {
            IERC20(fromToken).safeTransfer(filler, fromAmount);
        }
    }

    /// @notice Checks the OrderStatus of each order hash provided to ensure all orders are set to CREATED,
    /// set the OrderStatus of all order hashes to SETTLED, increments the fees for each unique token provided
    /// and the related processedFees according to the array position, and transfers the fromAmounts of native
    /// token or each unique ERC20 token from the Spoke.sol contract to the filler with a transfer for each
    /// unique token in the particular batch.
    /// @dev The provided order hashes are computed on the Hub based on orders that were processed and had
    /// a matching order hash that was processed on the order.toChain of the particular orders. Orders are
    /// eligible on the Hub to be forwarded to the order.fromChain once they've been filled on the
    /// order.toChain. Cross chain messages secured by Axelar protocol allow this function to receive
    /// confirmation that derived from the order.toChain Spoke.sol contract.
    /// @dev This method is called by the MULTI FillType, therefore this will process orders for all unique
    /// tokens in the particular batch and a single filler.
    /// @param orderHashes Array of keccak256 hashes of Orders being finalized.
    /// @param filler Address of the order.filler for all orders in the particular batch.
    /// @param fromAmounts Array of amounts of order.fromToken to be released to the filler.
    /// @param processedFees Array of amounts of order.fromToken to be reserved as protocol fees.
    /// @param fromTokens Array of addresses for all unique order.fromToken in a particular batch.
    function _releaseMultiTokenBatched(
        bytes32[] memory orderHashes,
        address filler,
        uint256[] memory fromAmounts,
        uint256[] memory processedFees,
        address[] memory fromTokens
    ) internal nonReentrant {
        if (
            orderHashes.length == 0 ||
            fromAmounts.length != fromTokens.length ||
            processedFees.length != fromTokens.length ||
            fromTokens.length < 2
        ) revert InvalidArrayLength();

        for (uint256 i = 0; i < orderHashes.length; i++) {
            bytes32 orderHash = orderHashes[i];
            if (orderHashToStatus[orderHash] != OrderStatus.CREATED) revert OrderStateNotCreated();
            orderHashToStatus[orderHash] = OrderStatus.SETTLED;

            emit TokensReleased(orderHash);
        }

        for (uint256 i = 0; i < fromTokens.length; i++) {
            tokenToCollectedFees[fromTokens[i]] += processedFees[i];

            if (fromTokens[i] == Utils.NATIVE_TOKEN) {
                payable(filler).sendValue(fromAmounts[i]);
            } else {
                IERC20(fromTokens[i]).safeTransfer(filler, fromAmounts[i]);
            }
        }
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                        Utilities                         //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @notice Hashes the provided order using a typed EIP-712 struct.
    /// @param order Order struct containing information about the order to be hashed.
    /// @return bytes32 EIP-712 typed hash of the provided order.
    function _hashOrderTyped(Order calldata order) private pure returns (bytes32) {
        return keccak256(abi.encode(
            Utils.ORDER_TYPEHASH,
            order.fromAddress,
            order.toAddress,
            order.filler,
            order.fromToken,
            order.toToken,
            order.expiry,
            order.fromAmount,
            order.fillAmount,
            order.feeRate,
            order.fromChain,
            order.toChain,
            order.postHookHash
        ));
    }

    /// @notice Finds the index of a given token in an array of tokens.
    /// @param token Address of the token to find in the array.
    /// @param fromTokens Array of token addresses to search for the given token.
    /// @return uint256 Index of the token in the array, or the maximum value of uint256 if the token 
    /// is not found.
    function _findTokenIndex(
        address token,
        address[] calldata fromTokens
    ) private pure returns (uint256) {
        for (uint256 i = 0; i < fromTokens.length; i++) {
            if (fromTokens[i] == token) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /// @notice Retrieves the current chain ID.
    /// @return uint256 The current chain ID.
    function _getChainId() private view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    /// @notice Provides a gas fee estimate for sending a message to a specified destination chain
    /// through LayerZero.
    /// Computes fees required for executing a LayerZero cross-chain message considering the native and
    /// optional ZRO token fees.
    /// @param _dstEid Destination chain's Endpoint ID as specified by LayerZero documentation.
    /// @param orderHashes An array of order hashes to be encapsulated in the message payload for
    /// processing at the destination.
    /// @param gasLimit The gas limit to be used for executing the lzReceive function on the destination
    /// chain, affecting the fee.
    /// @param _payInLzToken A boolean indicating if part of the fee will be paid in LayerZero's ZRO
    /// token, impacting the fee structure.
    /// @return nativeFee The estimated fee in native tokens required for processing the message on
    /// the destination chain.
    /// @return lzTokenFee The estimated fee in ZRO tokens, if opted for payment through LayerZero's
    /// token mechanism.
    function quote(
        uint32 _dstEid,
        bytes32[] calldata orderHashes,
        uint128 gasLimit,
        bool _payInLzToken
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        bytes memory payload = abi.encode(orderHashes);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0);
        MessagingFee memory fee = _quote(_dstEid, payload, options, _payInLzToken);
        return (fee.nativeFee, fee.lzTokenFee);
    }
}