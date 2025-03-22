// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IArcade.sol";
import "./interfaces/IXArcade.sol";

contract ArcadeSwap is Initializable, AccessControl, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using SafeERC20 for IArcade;
  using SafeERC20 for IXArcade;

  /**
   * @notice The max supply of xArcade and Arcade token allowed
   */
  uint256 private immutable MAX_SUPPLY = 800_000_000 * 10 ** 18;

  /**
   * @notice The max supply of xArcade token allowed
   */
  uint256 public immutable FEE_BASIS_POINT = 10_000;

  /**
   * @notice The max swap fee rate allowed
   */
  uint256 public immutable MAX_SWAP_FEE_RATE = 500;

  /**
   * @notice The Arcade token address stored as an IERC20. Used in
   *      interfacing with the burn and mint functions on the
   *      arcade token contract
   */
  IERC20 public ARCADE_CONTRACT;

  /**
   * @notice The xArcade token address stored as an IERC20. Used in
   *      interfacing with the burn and mint functions on the
   *      xArcade token contract
   */
  IERC20 public X_ARCADE_CONTRACT;

  /**
   * @notice The swap fee rate for Arcade to xArcade
   */
  uint256 public ARCADE_SWAP_FEE_RATE;

  /**
   * @notice The swap fee rate for xArcade to Arcade
   */
  uint256 public XARCADE_SWAP_FEE_RATE;

  /**
   * @notice The address vault receiver for all swap fees
   */
  address public SWAP_FEE_RECEIVER;

  /**
   * @notice Initialize the contract
   * @param _arcadeToken Address of the Arcade ERC20 token contract
   * @param _xArcadeToken Address of the xArcade ERC20 token contract
   * @param _initialSwapFee The initial swap fee rate for the contract
   * @param _swapFeeReceiver The address to be the receiver for swap fees
   */
  function initialize(
    address _arcadeToken,
    address _xArcadeToken,
    uint256 _initialSwapFee,
    address _swapFeeReceiver
  ) public initializer {
    require(_initialSwapFee <= MAX_SWAP_FEE_RATE, "ArcadeSwap: Invalid swap fee rate");
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    ARCADE_CONTRACT = IERC20(_arcadeToken);
    X_ARCADE_CONTRACT = IERC20(_xArcadeToken);
    ARCADE_SWAP_FEE_RATE = _initialSwapFee;
    XARCADE_SWAP_FEE_RATE = _initialSwapFee;
    SWAP_FEE_RECEIVER = payable(_swapFeeReceiver);
  }

  /**
   * @dev Fired in swapArcadeToXArcade()
   *
   * @param account the wallet address that swapped $ARC for $xARC
   * @param amount the amount of $xARC tokens swapped for
   * @param swapFee the $ARC fee charged for the swap
   */
  event SwapArcadeToXArcade(
    address indexed account,
    uint256 amount,
    uint256 swapFee
  );

  /**
   * @dev Fired in swapXArcadeToArcade()
   *
   * @param account the wallet address that swapped $xARC for $ARC
   * @param amount the amount of $ARC tokens swapped for
   * @param swapFee the $xARC fee charged for the swap
   */
  event SwapXArcadeToArcade(
    address indexed account,
    uint256 amount,
    uint256 swapFee
  );

  /**
   * @dev Fired in forwardArcadeFees()
   *
   * @param fee the amount of $ARC fees forwarded
   */
  event ArcadeFeesForward(uint256 fee);

  /**
   * @dev Fired in forwardxArcadeFees()
   *
   * @param fee the amount of $xARC fees forwarded
   */
  event XArcadeFeesForward(uint256 fee);

  /**
   * @dev Fired in updateSwapFee()
   *
   * @param newFee the new fee for swaps on the contract
   */
  event SwapFeeUpdated(uint256 newFee);

  /**
   * @dev Fired in updateFeeReceiver()
   *
   * @param newReceiver the new fee receiver for swaps on the contract
   */
  event FeeReceiverUpdated(address indexed newReceiver);

  /**
   * @dev Fired in updateArcadeContract()
   *
   * @param newAddress the new address of Arcade contract
   */
  event ArcadeContractUpdated(address indexed newAddress);

  /**
   * @dev Fired in updateXArcadeContract()
   *
   * @param newAddress the new address of xArcade contract
   */
  event XArcadeContractUpdated(address indexed newAddress);

  /**
   * @notice Swap Arcade ERC20 tokens for xArcade ERC20 tokens.
   *      User is charged at the SWAP_FEE_RATE for Arcade => xArcade
   *
   * @dev Throws on the following restriction errors:
   *      * Caller does not have enough Arcade to swap for xArcade
   *      * Swap will exceed total Arcade/xArcade supply cap
   *      * Caller has not approved token for swap
   *
   * @param _amount The amount of Arcade tokens to swap for xArcade
   */
  function swapArcadeToXArcade(uint256 _amount) public nonReentrant {
    uint256 swapFee = (_amount * ARCADE_SWAP_FEE_RATE) / FEE_BASIS_POINT;

    uint256 taxedSwap = _amount - swapFee;

    // Transfer tokens to be burned to swap contract
    ARCADE_CONTRACT.safeTransferFrom(msg.sender, address(this), _amount);

    // Burns Arcade Token
    IArcade(address(ARCADE_CONTRACT)).burnArcade(taxedSwap);

    // Mints xArcade Token
    IXArcade(address(X_ARCADE_CONTRACT)).mintXArcade(taxedSwap);

    // Transfer tokens minted to user from swap contract
    X_ARCADE_CONTRACT.safeTransfer(msg.sender, taxedSwap);

    // Forwards swap fee to swap fee receiver
    forwardArcadeSwapFees(swapFee);

    emit SwapArcadeToXArcade(msg.sender, taxedSwap, swapFee);
  }

  /**
   * @notice Swap xArcade ERC20 tokens for Arcade ERC20 tokens.
   *      User is charged at the SWAP_FEE_RATE for xArcade => Arcade
   *
   * @dev Throws on the following restriction errors:
   *      * Caller does not have enough xArcade to swap for Arcade
   *      * Swap will exceed total Arcade/xArcade supply cap
   *      * Caller has not approved token for swap
   *
   * @param _amount The amount of Arcade tokens to swap for xArcade
   */
  function swapXArcadeToArcade(uint256 _amount) public nonReentrant {
    uint256 swapFee = (_amount * XARCADE_SWAP_FEE_RATE) / FEE_BASIS_POINT;

    uint256 taxedSwap = _amount - swapFee;

    // Transfer tokens to be burned to swap contract
    X_ARCADE_CONTRACT.safeTransferFrom(msg.sender, address(this), _amount);

    // Burns xArcade Token
    IXArcade(address(X_ARCADE_CONTRACT)).burnXArcade(taxedSwap);

    // Mints Arcade Token
    IArcade(address(ARCADE_CONTRACT)).mintArcade(taxedSwap);

    // Transfer tokens minted to user from swap contract
    ARCADE_CONTRACT.safeTransfer(msg.sender, taxedSwap);

    // Forwards swap fee to swap fee receiver
    forwardXArcadeSwapFees(swapFee);

    emit SwapXArcadeToArcade(msg.sender, taxedSwap, swapFee);
  }

  /**
   * @notice Forward swap Arcade token fees to swap fee receiver
   *      Called by swapArcadeToXArcade() and swapXArcadeToArcade()
   *
   * @param _fee amount of fees to forward
   */
  function forwardArcadeSwapFees(uint256 _fee) internal {
    ARCADE_CONTRACT.safeTransfer(SWAP_FEE_RECEIVER, _fee);
    emit ArcadeFeesForward(_fee);
  }

  /**
   * @notice Forward swap xArcade token fees to swap fee receiver
   *      Called by swapArcadeToXArcade() and swapXArcadeToArcade()
   *
   * @param _fee amount of fees to forward
   */
  function forwardXArcadeSwapFees(uint256 _fee) internal {
    X_ARCADE_CONTRACT.safeTransfer(SWAP_FEE_RECEIVER, _fee);
    emit XArcadeFeesForward(_fee);
  }

  /**
   * @notice Update the Arcade swap fee rate for the contract
   *
   * @dev Throws on the following restriction errors:
   *      * Caller is not the Contract Admin
   *
   * @param _newFee the updated fee for swaps
   */
  function updateArcadeSwapFee(uint256 _newFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_newFee <= MAX_SWAP_FEE_RATE, "ArcadeSwap: Invalid Arcade Swap fee rate");
    ARCADE_SWAP_FEE_RATE = _newFee;

    emit SwapFeeUpdated(_newFee);
  }

  /**
   * @notice Update the xArcade swap fee rate for the contract
   *
   * @dev Throws on the following restriction errors:
   *      * Caller is not the Contract Admin
   *
   * @param _newFee the updated fee for swaps
   */
  function updateXArcadeSwapFee(uint256 _newFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_newFee <= MAX_SWAP_FEE_RATE, "ArcadeSwap: Invalid xArcade Swap fee rate");
    XARCADE_SWAP_FEE_RATE = _newFee;

    emit SwapFeeUpdated(_newFee);
  }

  /**
   * @notice Update the swap fee receiver for the contract
   *
   * @dev Throws on the following restriction errors:
   *      * Caller is not the Contract Admin
   *
   * @param _newReceiver the updated account receiver for swap fees
   */
  function updateFeeReceiver(
    address _newReceiver
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    SWAP_FEE_RECEIVER = payable(_newReceiver);

    emit FeeReceiverUpdated(_newReceiver);
  }

  /**
   * @notice Update the address of Arcade contract
   *
   * @dev Throws on the following restriction errors:
   *      * Caller is not the Contract Admin
   *
   * @param _arcadeToken address of the Arcade Token
   */
  function updateArcadeContract(
    address _arcadeToken
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    ARCADE_CONTRACT = IERC20(_arcadeToken);

    emit ArcadeContractUpdated(_arcadeToken);
  }

  /**
   * @notice Update the address of Arcade contract
   *
   * @dev Throws on the following restriction errors:
   *      * Caller is not the Contract Admin
   *
   * @param _xArcadeToken address of the xArcade Token
   */
  function updateXArcadeContract(
    address _xArcadeToken
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    X_ARCADE_CONTRACT = IERC20(_xArcadeToken);

    emit XArcadeContractUpdated(_xArcadeToken);
  }
}