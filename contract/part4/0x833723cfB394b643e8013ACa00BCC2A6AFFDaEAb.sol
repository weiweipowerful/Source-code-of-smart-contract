// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {ISynthToken} from "./interfaces/ISynthToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DecimalsCorrectionLib} from "../trade/components/DecimalsCorrectionLib.sol";
import {Permitable} from "../trade/components/Permitable.sol";
import {IAllowanceTransfer} from "../interfaces/IAllowanceTransfer.sol";

contract SynthToken is ERC20, ISynthToken, ERC2771Context, ERC20Permit, Permitable, ERC20Pausable {
    /// @inheritdoc ISynthToken
    address public immutable override underlyingAsset;
    /// @inheritdoc ISynthToken
    address public immutable override treasury;
    /// @inheritdoc ISynthToken
    address public immutable override factory;

    modifier onlyFactory() {
        if (_msgSender() != factory) revert OnlyFactory();
        _;
    }

    modifier checkZeroAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    /**
     * @dev Constructor
     * @param name_ The name of the synth token
     * @param symbol_ The symbol of the synth token
     * @param trustedForwarder_ The trusted forwarder address
     * @param underlyingAsset_ The underlying asset address
     * @param treasury_ The treasury address
     * @param _permit2 The permit2 address
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address trustedForwarder_,
        address underlyingAsset_,
        address treasury_,
        address _permit2
    ) ERC20(name_, symbol_) ERC2771Context(trustedForwarder_) Permitable(_permit2) ERC20Permit(name_) {
        if (underlyingAsset_ == address(0)) revert ZeroAddress();
        underlyingAsset = underlyingAsset_;

        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;

        factory = _msgSender();
    }

    /// @inheritdoc ISynthToken
    function wrap(
        uint256 amount,
        address recipient,
        IAllowanceTransfer.PermitSingle calldata permitSingleStruct,
        bytes calldata permitSingleSignature,
        TokenPermitSignatureDetails calldata tokenPermitSignatureDetails
    ) external override {
        // make the token permit to Permit2 contract
        _makeTokenPermit(permitSingleStruct.details.token, tokenPermitSignatureDetails);

        wrap(amount, recipient, permitSingleStruct, permitSingleSignature);
    }

    /// @inheritdoc ISynthToken
    function wrap(
        uint256 amount,
        address recipient,
        IAllowanceTransfer.PermitSingle calldata permitSingleStruct,
        bytes calldata permitSingleSignature
    ) public override {
        // make the permit2 to this contract
        _makePermit2(permitSingleStruct, permitSingleSignature);

        wrap(amount, recipient);
    }

    /// @inheritdoc ISynthToken
    function wrap(uint256 amount, address recipient) public override checkZeroAmount(amount) {
        // this case is needed for private swaps
        if (amount == type(uint256).max) amount = IERC20(underlyingAsset).balanceOf(_msgSender());
        
        // transfer underlying asset to treasury
        if (IERC20(underlyingAsset).allowance(_msgSender(), address(this)) >= amount) {
            // the case for standard ERC20 approve/transferFrom (e.g. ProxyTrade will use this)
            SafeERC20.safeTransferFrom(IERC20(underlyingAsset), _msgSender(), treasury, amount);
        } else {
            // the case for Permit2
            _receivePayment(underlyingAsset, treasury, amount);
        }

        // mint synth tokens to recipient
        // recipient is checked in ERC20._mint
        uint256 correctedAmount = DecimalsCorrectionLib.decimalsCorrection(IERC20Metadata(underlyingAsset).decimals(), 18, amount);
        _mint(recipient, correctedAmount);

        emit Wrapped(_msgSender(), recipient, correctedAmount);
    }

    /// @inheritdoc ISynthToken
    function unwrap(uint256 amount, address recipient) external override checkZeroAmount(amount) {
        // this case is needed for private swaps
        if (amount == type(uint256).max && balanceOf(_msgSender()) != 0) amount = balanceOf(_msgSender());

        uint256 correctedAmount = DecimalsCorrectionLib.decimalsCorrection(18, IERC20Metadata(underlyingAsset).decimals(), amount);
        // treasury must have enough allowance
        if (IERC20(underlyingAsset).allowance(treasury, address(this)) < correctedAmount) revert NotEnoughTreasuryAllowance();

        // transfer underlying asset to recipient
        // recipient is checked in ERC20._transfer
        SafeERC20.safeTransferFrom(IERC20(underlyingAsset), treasury, recipient, correctedAmount);

        // burn synth tokens from sender
        // sender is checked in ERC20._burn
        _burn(_msgSender(), amount);

        emit Unwrapped(_msgSender(), recipient, amount);
    }

    /**
     * @notice Pauses token transfers, minting and burning
     * @dev Sender must be the factory
     */
    function pause() external onlyFactory {
        _pause();
    }

    /**
     * @notice When paused, unpauses token transfers, minting and burning
     * @dev Sender must be the factory
     */
    function unpause() external onlyFactory {
        _unpause();
    }

    /**
     * @notice Overrides the function from inherited smart-contracts: `ERC20`, `ERC20Pausable`
     * @dev See {ERC20-_update}, {ERC20Pausable-_update}
     */
    function _update(address _from, address _to, uint256 _value) internal virtual override(ERC20, ERC20Pausable) {
        super._update(_from, _to, _value);
    }

    /**
     * @notice Overrides the function from inherited smart-contracts: `Context`, `ERC2771Context`
     * @dev The requirement from the ERC2771Context
     */
    function _msgSender() internal view virtual override(Context, ERC2771Context) returns (address) {
        return super._msgSender();
    }

    /**
     * @notice Overrides the function from inherited smart-contracts: `Context`, `ERC2771Context`
     * @dev The requirement from the ERC2771Context
     */
    function _msgData() internal view virtual override(Context, ERC2771Context) returns (bytes calldata) {
        return super._msgData();
    }

    /**
     * @notice Overrides the function from inherited smart-contracts: `Context`, `ERC2771Context`
     * @dev The requirement from the ERC2771Context
     */
    function _contextSuffixLength() internal view virtual override(Context, ERC2771Context) returns (uint256) {
        return super._contextSuffixLength();
    }
    
    /**
     * @notice Hashes the struct data, see [eip712 docs](https://eips.ethereum.org/EIPS/eip-712)
     * @param structHash - Hash of the struct
     */
    function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
        return super._hashTypedDataV4(structHash);
    }
}