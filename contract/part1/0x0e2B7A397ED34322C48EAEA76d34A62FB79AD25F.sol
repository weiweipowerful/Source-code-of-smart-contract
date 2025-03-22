// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISuccinctBridge} from "./interfaces/ISuccinctBridge.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from
    "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @title Succinct Prover Network Bridge
/// @author Succinct Labs
/// @notice A bridge that allows for deposits and withdrawals of USDC for usage in
///         the Succinct Prover Network.
contract SuccinctBridge is Ownable, Pausable, ISuccinctBridge {
    using SafeERC20 for IERC20;

    /// @dev The USDC token address, which is used as the underlying asset for this bridge.
    address internal immutable USDC;

    constructor(address _owner, address _USDC) Ownable(_owner) {
        USDC = _USDC;
    }

    /// @inheritdoc ISuccinctBridge
    function usdc() external view override returns (address) {
        return USDC;
    }

    /// @inheritdoc ISuccinctBridge
    function permitAndDeposit(
        address _from,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override whenNotPaused {
        IERC20Permit(USDC).permit(_from, address(this), _amount, _deadline, _v, _r, _s);

        _deposit(_from, _amount);
    }

    /// @inheritdoc ISuccinctBridge
    function deposit(uint256 _amount) public override whenNotPaused {
        _deposit(msg.sender, _amount);
    }

    /// @inheritdoc ISuccinctBridge
    function withdraw(address _to, uint256 _amount) external override onlyOwner {
        IERC20(USDC).safeTransfer(_to, _amount);

        emit Withdrawal(_to, _amount);
    }

    /// @inheritdoc ISuccinctBridge
    function pause() external override onlyOwner whenNotPaused {
        _pause();
    }

    /// @inheritdoc ISuccinctBridge
    function unpause() external override onlyOwner whenPaused {
        _unpause();
    }

    /// @dev Transfers USDC from the specified address to this contract.
    function _deposit(address _from, uint256 _amount) internal {
        IERC20(USDC).safeTransferFrom(_from, address(this), _amount);

        emit Deposit(_from, _amount);
    }
}