// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libraries/BoringERC20.sol";

/**
 * @title Redemption
 * @notice Allows users to redeem a specific ERC20 token (`fromToken`) for multiple other ERC20 tokens (`toTokens`) based on predefined exchange rates.
 * @dev Inherits from Ownable, Pausable, and ReentrancyGuard for access control, pausing functionality, and security against reentrancy attacks.
 */
contract Redemption is Ownable, Pausable, ReentrancyGuard {
    using BoringERC20 for IERC20;

    /// @dev The ERC20 token users can redeem from.
    IERC20 public fromToken;

    /// @dev List of ERC20 tokens users can redeem to.
    address[] public toTokens;

    /// @dev Denominator based on the decimals of `fromToken` used for exchange rate calculations.
    uint256 public immutable fromDenominator;

    /// @dev Mapping from target token address to its exchange rate.
    mapping(address => uint256) public exchangeRates;

    /**
     * @dev Emitted when a user redeems `fromToken` for a `toToken`.
     * @param user The address of the user who performed the redemption.
     * @param toToken The address of the token that was redeemed to.
     * @param amount The amount of `toToken` redeemed.
     */
    event Redeemed(
        address indexed user,
        address indexed toToken,
        uint256 amount
    );

    /**
     * @dev Emitted when a new token is added to the redemption list.
     * @param token The address of the token that was added.
     * @param exchangeRate The exchange rate set for the new token.
     */
    event TokenAdded(address indexed token, uint256 exchangeRate);

    /**
     * @dev Emitted when a token is removed from the redemption list.
     * @param token The address of the token that was removed.
     */
    event TokenRemoved(address indexed token);

    /**
     * @dev Emitted when the exchange rate of a token is updated.
     * @param token The address of the token whose exchange rate was changed.
     * @param exchangeRate The new exchange rate of the token.
     */
    event ExchangeRateChanged(address indexed token, uint256 exchangeRate);

    /**
     * @notice Initializes the Redemption contract with the specified tokens and their exchange rates.
     * @param _fromToken The ERC20 token that users will redeem from.
     * @param _toTokens An array of ERC20 token addresses that users can redeem to.
     * @param _exchangeRates An array of exchange rates corresponding to each `toToken`.
     */
    constructor(
        IERC20 _fromToken,
        address[] memory _toTokens,
        uint256[] memory _exchangeRates
    ) {
        require(
            _toTokens.length == _exchangeRates.length,
            "Array lengths must be equal"
        );
        fromToken = _fromToken;
        fromDenominator = 10 ** fromToken.safeDecimals();
        toTokens = _toTokens;
        for (uint256 i = 0; i < toTokens.length; i++) {
            require(_exchangeRates[i] > 0, "Invalid exchange rate");
            exchangeRates[toTokens[i]] = _exchangeRates[i];
        }
    }

    /**
     * @notice Redeems a specified amount of `fromToken` for each supported `toToken`.
     * @param amount The amount of `fromToken` to be redeemed.
     * @dev Transfers `amount` of `fromToken` from the caller to the contract, then distributes equivalent `toTokens` based on exchange rates.
     */
    function redeem(uint256 amount) public whenNotPaused nonReentrant {
        require(
            fromToken.safeBalanceOf(msg.sender) >= amount,
            "Insufficient balance"
        );

        fromToken.safeTransferFrom(msg.sender, address(this), amount);

        for (uint256 i = 0; i < toTokens.length; i++) {
            uint256 toAmount = (amount * exchangeRates[toTokens[i]]) / fromDenominator;
            require(toAmount > 0, "Amount not enough");
            require(
                IERC20(toTokens[i]).safeBalanceOf(address(this)) >= toAmount,
                "Insufficient balance of contract"
            );
            IERC20(toTokens[i]).safeTransfer(msg.sender, toAmount);
            emit Redeemed(msg.sender, toTokens[i], toAmount);
        }
    }

    /**
     * @notice Adds a new supported ERC20 token with its exchange rate.
     * @param token The address of the token being added.
     * @param exchangeRate The exchange rate of the new token.
     * @dev Ensures the token is not already added and sets its exchange rate based on its decimals.
     */
    function addToken(address token, uint256 exchangeRate) public onlyOwner {
        require(token != address(0), "Token address cannot be zero");
        require(exchangeRate > 0, "ExchangeRate cannot be 0");
        require(exchangeRates[token] == 0, "Token already exists");

        toTokens.push(token);
        exchangeRates[token] = exchangeRate;
        emit TokenAdded(token, exchangeRate);
    }

    /**
     * @notice Removes a supported ERC20 token by its index.
     * @param index The index of the token being removed.
     * @dev Deletes the exchange rate and removes the token from the `toTokens` array.
     */
    function removeToken(uint256 index) public onlyOwner {
        address _token = toTokens[index];
        delete exchangeRates[_token];
        toTokens[index] = toTokens[toTokens.length - 1];
        toTokens.pop();
        emit TokenRemoved(_token);
    }

    /**
     * @notice Sets the exchange rate for a supported ERC20 token.
     * @param token The address of the token for which the exchange rate is being set.
     * @param exchangeRate The new exchange rate of the token.
     * @dev Updates the exchange rate based on the token's decimals.
     */
    function setExchangeRate(
        address token,
        uint256 exchangeRate
    ) public onlyOwner {
        require(exchangeRate > 0, "Token rate cannot be zero");
        require(exchangeRates[token] > 0, "Token does not exist");
        exchangeRates[token] = exchangeRate;
        emit ExchangeRateChanged(token, exchangeRate);
    }

    /**
     * @notice Toggles the paused state of the contract.
     * @dev If the contract is paused, it will be unpaused and vice versa.
     */
    function pause() public onlyOwner {
        paused() ? _unpause() : _pause();
    }

    /**
     * @notice Withdraws all of a specific ERC20 token to the owner in case of emergency.
     * @param token The ERC20 token to withdraw.
     * @dev Transfers the entire balance of the specified `token` to the contract owner.
     */
    function emergencyWithdraw(IERC20 token) external onlyOwner {
        token.safeTransfer(owner(), token.safeBalanceOf(address(this)));
    }

    /**
     * @notice Calculates the amounts of each `toToken` that can be redeemed for a given `fromToken` amount.
     * @param amount The amount of `fromToken` to be redeemed.
     * @return address[] An array of `toToken` addresses.
     * @return uint256[] An array of redeemable amounts for each `toToken`.
     * @dev Ensures that each calculated redeemable amount is greater than zero.
     */
    function calculateRedeem(
        uint256 amount
    ) external view returns (address[] memory, uint256[] memory) {
        uint[] memory toAmount = new uint[](toTokens.length);
        for (uint256 i = 0; i < toTokens.length; i++) {
            toAmount[i] = (amount * exchangeRates[toTokens[i]]) / fromDenominator;
            require(toAmount[i] > 0, "Amount not enough");
        }

        return (toTokens, toAmount);
    }
}