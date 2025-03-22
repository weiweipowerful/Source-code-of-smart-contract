// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract ArcadeToken is ERC20Burnable, AccessControl {
  /**
   * @notice The Arcade Swap Contract is set as the only address that is
   *      allowed to mint or burn tokens after contract creation
   */
  address public ArcadeSwapContractAddress;

  /**
   * @notice The max supply of Arcade token allowed
   */
  uint256 private constant MAX_SUPPLY = 800_000_000 * 10 ** 18;

  /**
   * @notice Boolean for vaults being minted to
   */
  bool public vaultsMinted;


  /**
   * @notice Initialize the contract
   */
  constructor() ERC20("Arcade Token", "ARC") {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  /**
   * @notice Modifier that requires msg.sender to be Arcade Swap contract
   * @dev Required in mint and burn functions
   */
  modifier isArcadeSwapContract() {
    require(
      msg.sender == ArcadeSwapContractAddress,
      "Caller must be Arcade Swap contract"
    );
    _;
  }

  /**
   * @dev Fired in mintArcade()
   *
   * @param amount the amount of $ARC tokens minted
   */
  event ArcadeMinted(uint256 amount);

  /**
   * @dev Fired in burnArcade()
   *
   * @param amount the amount of $ARC tokens burned
   */
  event ArcadeBurned(uint256 amount);

  /**
   * @dev Fired in updateArcadeSwapContract()
   *
   * @param newAddress the new address of Arcade Swap contract
   */
  event ArcadeSwapContractUpdated(address indexed newAddress);

  /**
   * @dev Fired in updateVaultsMinted()
   *
   */
  event VaultsMinted();

  /**
   * @notice Mint and deposit `amount` $ARC tokens to message sender
   *
   * @dev Throws on the following restriction errors:
   *      * Caller is not Arcade Swap contract
   *      * Mint exceeds MAX_SUPPLY
   *
   * @param _amount The amount of tokens to be minted
   */
  function mintArcade(uint256 _amount) public isArcadeSwapContract {
    require(
      totalSupply() + _amount <= MAX_SUPPLY,
      "Amount to mint will exceed total supply"
    );
    _mint(ArcadeSwapContractAddress, _amount);

    emit ArcadeMinted(_amount);
  }

  /**
   * @notice Burn and destroy `amount` $ARC tokens from message sender
   *
   * @dev Throws on the following restriction errors:
   *      * Caller is not Arcade Swap contract
   *      * Total supply cannot be less than 0
   *
   * @param _amount The amount of tokens to be burned
   */
  function burnArcade(uint256 _amount) public isArcadeSwapContract {
    require(totalSupply() - _amount >= 0, "Cannot burn tokens below 0");
    _burn(address(msg.sender), _amount);

    emit ArcadeBurned(_amount);
  }

  /**
   * @notice Update the address of Arcade Swap contract
   *
   * @dev Throws on the following restriction errors:
   *      * Caller is not the Contract Admin
   *
   * @param _ArcadeSwapContractAddress address of the Arcade Swap contract
   */
  function updateArcadeSwapContract(
    address _ArcadeSwapContractAddress
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    ArcadeSwapContractAddress = _ArcadeSwapContractAddress;

    emit ArcadeSwapContractUpdated(_ArcadeSwapContractAddress);
  }

  /**
   * @notice Mint tokens to a specified vault
   * @param _vaultAddress Address of the vault to mint tokens to
   */
  function mintToVault(
    address _vaultAddress,
    uint256 _amount
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(
      totalSupply() + _amount <= MAX_SUPPLY,
      "Amount to mint will exceed total supply"
    );
    require(!vaultsMinted, "Vaults have already been minted");
    require(_vaultAddress != address(0), "Vault address cannot be 0x0");
    _mint(_vaultAddress, _amount);

    emit ArcadeMinted(_amount);
  }

  /**
   * @notice Update all vaults have been minted
   */
  function updateVaultsMinted() public onlyRole(DEFAULT_ADMIN_ROLE) {
    vaultsMinted = true;

    emit VaultsMinted();
  }
}