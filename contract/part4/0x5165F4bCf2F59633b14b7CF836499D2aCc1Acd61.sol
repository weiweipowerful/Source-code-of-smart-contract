// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// LayerZero imports
import { EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";

// OZ imports
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WOFTAdapter
 * @notice The WOFTAdapter contract implementation.
 */
contract WOFTAdapter is OFTAdapter {
    uint8 internal constant DEFAULT_SHARED_DECIMALS = 6;
    uint8 internal immutable SHARED_DECIMALS;

    address public immutable FACTORY;

    error OnlyOwnerOrFactory(address);

    /**
     * @dev Constructs a Wrapped Asset Bridge OFT Adapter.
     * @param _token The ERC20 token to wrap in adapter.
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
     * @param _factory The factory address.
     */
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate,
        address _factory
    ) OFTAdapter(_token, _lzEndpoint, _delegate) Ownable(_delegate) {
        FACTORY = _factory;

        // Determine shared decimals
        uint8 localDecimals = IERC20Metadata(_token).decimals();
        SHARED_DECIMALS = DEFAULT_SHARED_DECIMALS > localDecimals ? localDecimals : DEFAULT_SHARED_DECIMALS;

        decimalConversionRate = 10 ** (localDecimals - SHARED_DECIMALS);
    }

    /**
     * @dev Throws if called by any account other than the owner or factory.
     */
    modifier onlyFactoryOrOwner() {
        if (_msgSender() != FACTORY && _msgSender() != owner()) {
            revert OnlyOwnerOrFactory(_msgSender());
        }
        _;
    }

    /**
     * @notice Sets the enforced options.
     * @param _enforcedOptions Options to use when sending from adapter.
     *
     * @dev Only the factory or owner of the OApp can call this function.
     */
    function setEnforcedOptions(EnforcedOptionParam[] calldata _enforcedOptions) public override onlyFactoryOrOwner {
        _setEnforcedOptions(_enforcedOptions);
    }

    /**
     * @notice Sets the peer address (OApp instance) for a corresponding endpoint.
     * @param _eid The endpoint ID.
     * @param _peer The address of the peer to be associated with the corresponding endpoint.
     *
     * @dev Only the factory or owner of the OApp can call this function.
     * @dev Indicates that the peer is trusted to send LayerZero messages to this OApp.
     * @dev Set this to bytes32(0) to remove the peer address.
     * @dev Peer is a bytes32 to accommodate non-evm chains.
     */
    function setPeer(uint32 _eid, bytes32 _peer) public override onlyFactoryOrOwner {
        _setPeer(_eid, _peer);
    }

    /**
     * @notice Retrieves the shared decimals of the WOFTAdapter.
     * @return uint8 The shared decimals of the WOFTAdapter.
     */
    function sharedDecimals() public view virtual override returns (uint8) {
        return SHARED_DECIMALS;
    }
}