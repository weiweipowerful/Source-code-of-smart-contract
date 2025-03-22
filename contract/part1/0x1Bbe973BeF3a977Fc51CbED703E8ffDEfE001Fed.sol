// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title PortalToken
 * @dev Extension of ERC20 functionalities with permit, pausable, and burnable features.
 */
contract PortalToken is ERC20,Ownable, ERC20Permit, ERC20Burnable, ERC20Pausable {
    
    /// @notice Struct to hold initial deposits for vesting
    struct InitialDeposits {
        address addr;
        uint256 amount;
    }

    /// @notice State variable
    bool public permitEnabled;
    address public proxy;

    /// @notice Emitted when permit functionality is enabled or disabled
    event PermitEnabled(bool isEnabled);
    /// @notice Emitted when proxy address is set or updated
    event ProxyAddressSet(address proxy);

    /// @notice Custom error for handling permit functionality
    error PermitDisabled();

    /**
     * @notice Constructor to initialize the contract with initial deposits
     * @param name Name of the token
     * @param symbol Symbol of the token
     * @param treasury Address of the treasury
     * @param owner Address of the owner
     * @param vestingDeposits Array of initial deposits for vesting (potential address duplication is mitigated by the deployment scripts)
     */
    constructor(
        string memory name,
        string memory symbol,
        address treasury,
        address owner,
        InitialDeposits[] memory vestingDeposits
    )
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        permitEnabled = true;

        uint256 totalAmountToMint = 1e9 ether;
        uint256 totalMinted;
        
        for (uint256 i = 0; i < vestingDeposits.length; i++) {
            totalMinted += vestingDeposits[i].amount;
            _mint(vestingDeposits[i].addr, vestingDeposits[i].amount);
        }

        _mint(treasury, totalAmountToMint - totalMinted);

        transferOwnership(owner);
    }

    /**
     * @notice Function to get circulating supply based on the proxy contract balance.
     * If proxy address is not set, it will return the total supply.
     * @dev Proxy contract is being used for X-chain functionality. If tokens are transferred to the proxy contract,
     * they are considered as burned on a given chain.
     * @return uint256 Circulating supply
     */
    function totalSupply() public view virtual override returns (uint256) {
        if (proxy == address(0)) {
            return super.totalSupply();
        }
        return super.totalSupply() - balanceOf(proxy);
    }

    /**
     * @notice Function to handle permit functionality with conditional custom check
     * @dev Reffer to ERC-20 Permit extension for more details
    */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        virtual
        override(ERC20Permit)
    {
        if (!permitEnabled) {
            revert PermitDisabled();
        }
        super.permit(owner, spender, value, deadline, v, r, s);
    }

    /**
     * @notice Function to handle pausing/unpausing of token transfers. Can only be called by the owner.
     * @dev Reffer to ERC-20 Pausable extension for more details
     * @param shouldPause Boolean to indicate whether to pause or unpause the token
    */
    function pause(bool shouldPause) external onlyOwner {
        if (shouldPause) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @notice Function to enable or disable permit functionality
     * @dev Enabled by default
     * @param isEnabled Boolean to indicate whether to enable or disable the permit functionality
    */
    function disablePermit(bool isEnabled) external onlyOwner {
        permitEnabled = isEnabled;
        emit PermitEnabled(isEnabled);
    }

    /**
     * @notice Function to set the proxy address (X-chain functionality)
     * @param _proxy Address of the proxy contract
    */
    function setProxyAddress(address _proxy) external onlyOwner {
        proxy = _proxy;
        emit ProxyAddressSet(_proxy);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes minting and burning.
    */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    )
        internal
        override(ERC20, ERC20Pausable)
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}