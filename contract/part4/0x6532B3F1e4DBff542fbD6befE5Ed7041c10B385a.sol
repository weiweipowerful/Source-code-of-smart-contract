// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

// OpenZeppelin
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/introspection/ERC165.sol';

// Interfaces
import './interfaces/IIncentiveToken.sol';
import './interfaces/IOutputToken.sol';

/**
 * @title TitanX Incentive Token (TINC)
 *
 *  ████████╗██╗████████╗ █████╗ ███╗   ██╗██╗  ██╗    ██╗███╗   ██╗ ██████╗
 *  ╚══██╔══╝██║╚══██╔══╝██╔══██╗████╗  ██║╚██╗██╔╝    ██║████╗  ██║██╔════╝
 *     ██║   ██║   ██║   ███████║██╔██╗ ██║ ╚███╔╝     ██║██╔██╗ ██║██║
 *     ██║   ██║   ██║   ██╔══██║██║╚██╗██║ ██╔██╗     ██║██║╚██╗██║██║
 *     ██║   ██║   ██║   ██║  ██║██║ ╚████║██╔╝ ██╗    ██║██║ ╚████║╚██████╗
 *     ╚═╝   ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝    ╚═╝╚═╝  ╚═══╝ ╚═════╝
 *
 * @dev Implementation of the TitanX Incentive Token (TINC) in the TitanX ecosystem.
 * This token serves as an incentive mechanism within the TitanX Farms protocol.
 * After deployment, ownership is transferred to the FarmKeeper contract,
 * which then mints TINC to farmers as rewards.
 */
contract TINC is ERC20Permit, Ownable, IIncentiveToken, IOutputToken, ERC165 {
  /**
   * @dev Initializes the TINC contract.
   * Sets the token name, symbol, and initial owner.
   */
  constructor()
    ERC20('Titan Farms Incentive Token', 'TINC')
    ERC20Permit('Titan Farms Incentive Token')
    Ownable(msg.sender)
  {}

  /**
   * @dev Burns a specific amount of tokens from the caller's account.
   * @param amount The amount of tokens to burn.
   */
  function burn(uint256 amount) external {
    _burn(msg.sender, amount);
  }

  /**
   * @dev Mints a specific amount of tokens to a given account.
   * Can only be called by the contract owner (typically the FarmKeeper).
   * @param account The address that will receive the minted tokens.
   * @param amount The amount of tokens to mint.
   */
  function mint(address account, uint256 amount) external onlyOwner {
    _mint(account, amount);
  }

  /**
   * @dev Consumes the current nonce for the caller to invalidate a signature.
   * This allows a user to cancel a signature that they no longer want to be valid.
   */
  function useNonce() external {
    _useNonce(msg.sender);
  }

  /**
   * @dev Returns the current nonce for an address for use in permit.
   * @param owner_ The address to query the nonce for.
   * @return The current nonce for the given address.
   */
  function nonces(address owner_) public view virtual override(ERC20Permit, IERC20Permit) returns (uint256) {
    return super.nonces(owner_);
  }

  /**
   * @dev Returns the address of the current owner.
   * This function overrides the owner() function from both Ownable and IIncentiveToken
   * to resolve any ambiguity in the inheritance structure.
   * @return address The address of the current owner.
   */
  function owner() public view virtual override(Ownable, IIncentiveToken) returns (address) {
    return super.owner();
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   * @param interfaceId The interface identifier to check.
   * @return bool True if the contract supports the interface, false otherwise.
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return
      interfaceId == type(IERC20).interfaceId ||
      interfaceId == type(IERC20Permit).interfaceId ||
      interfaceId == type(IIncentiveToken).interfaceId ||
      interfaceId == type(IOutputToken).interfaceId ||
      super.supportsInterface(interfaceId);
  }
}