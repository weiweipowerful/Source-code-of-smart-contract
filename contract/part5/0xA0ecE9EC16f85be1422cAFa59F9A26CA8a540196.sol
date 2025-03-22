// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ITriaSaleNFT} from "./interfaces/ITriaSaleNFT.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Rounds} from "./Rounds.sol";
import {ZeroValue, TokenDisallowed, InsufficientETHSent, InvalidSignature, TokenIdDoesNotExist, ETH_PRICE_FEED_PRECISION, WEI_PRECISION, USD_PRECISION, PriceNotUpdated, InsufficientBalance, DeadlineExpired} from "./utils/Common.sol";

/// @title TriaSale contract
/// @notice Implements sale of the TriaSaleNFT with ETH, USDC and USDT
/// @notice The sale contract allows you to purchase TriaSaleNFT with allowed tokens with a round system
/// @custom:security-contact [email protected]
contract TriaSale is Rounds, ReentrancyGuard, Pausable, Nonces {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using SafeCast for int256;

    /// @notice The address of the treasury wallet
    address public treasuryWallet;

    /// @notice The address of signer wallet
    address public signerWallet;

    /// @notice Struct for signature parameters
    struct SignatureParams {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Struct for user information
    struct UserInfo {
        uint256 deadline;
        string txUUID;
        string referralCode;
    }

    /// @notice Struct for NFT Mint event data
    struct NFTMintData {
        address to;
        uint256[] tokenIds;
        uint256[] quantities;
        IERC20 token;
        uint256 amountInToken;
        uint256 amountInUSD;
        uint256 timestamp;
        uint32 round;
        string txUUID;
        string referralCode;
    }

    /// @notice Emitted when NFTs are minted
    event NFTsMinted(NFTMintData _nftMintData);

    /// @notice Emitted when address of signer is updated
    event SignerUpdated(address _newSigner);

    /// @notice Emitted when address of treasury wallet is updated
    event TreasuryWalletUpdated(address _newTreasuryWallet);

    /// @notice Constructor
    /// @param _treasuryWalletAddress The address of treasury wallet
    /// @param _signerAddress The address of signer wallet
    /// @param _ethUsdPriceFeed The ETH/USDC price feed
    /// @param _usdc The USDC token address
    /// @param _usdt The USDT token address
    /// @param _triaSaleNFT The TriaSaleNFT contract address
    constructor(
        address _treasuryWalletAddress,
        address _signerAddress,
        AggregatorV3Interface _ethUsdPriceFeed,
        IERC20 _usdc,
        IERC20 _usdt,
        ITriaSaleNFT _triaSaleNFT
    )
        Rounds(_ethUsdPriceFeed, _usdc, _usdt, _triaSaleNFT)
        isValidAddress(_treasuryWalletAddress)
        isValidAddress(_signerAddress)
    {
        treasuryWallet = _treasuryWalletAddress;
        signerWallet = _signerAddress;
    }

    /// @notice Pauses the sale
    function pauseBuy() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the sale
    function unpauseBuy() external onlyOwner {
        _unpause();
    }

    /// @notice Changes signer wallet address
    /// @param _newSignerWallet The address of the new signer wallet
    function updateSignerWallet(
        address _newSignerWallet
    ) external onlyOwner isValidAddress(_newSignerWallet) {
        signerWallet = _newSignerWallet;
        emit SignerUpdated(_newSignerWallet);
    }

    /// @notice Changes treasury wallet address
    /// @param _newTreasuryWallet The address of the new treasury wallet
    function updateTreasuryWallet(
        address _newTreasuryWallet
    ) external onlyOwner isValidAddress(_newTreasuryWallet) {
        treasuryWallet = _newTreasuryWallet;
        emit TreasuryWalletUpdated(_newTreasuryWallet);
    }

    /**
     * @notice Withdraws funds from the contract to an external account.
     * @param _account The recipient's address.
     * @param _token The token to withdraw.
     * @param _amount The amount to withdraw.
     */
    function emergencyWithdrawFunds(
        address _account,
        address _token,
        uint256 _amount
    ) external onlyOwner isValidAddress(_account) {
        if (_token == address(ETH)) {
            if (address(this).balance < _amount) revert InsufficientBalance();
            payable(_account).sendValue(_amount);
        } else {
            if (IERC20(_token).balanceOf(address(this)) < _amount)
                revert InsufficientBalance();

            IERC20(_token).safeTransfer(_account, _amount);
        }
    }

    /// @notice Purchases TriaSaleNFT with ETH
    /// @param _round The round in which user wants to purchase
    /// @param _tokenIds The tokenIds of the NFTs
    /// @param _quantities The quantities of the NFTs
    /// @param _userInfo The user information (txUUID, referralCode, deadline)
    /// @param _signatureParams The signature parameters (v, r, s)
    function purchaseWithETH(
        uint32 _round,
        uint256[] calldata _tokenIds,
        uint256[] calldata _quantities,
        UserInfo calldata _userInfo,
        SignatureParams calldata _signatureParams
    )
        external
        payable
        nonReentrant
        whenNotPaused
        validateArrayLengths(_tokenIds.length, _quantities.length)
    {
        // The input must have been signed by the signer address
        _validatePurchaseWithToken(ETH, _round, _userInfo, _signatureParams);

        (
            uint256 totalRequiredETH,
            uint256 totalUSDAmount
        ) = calculateTotalCostRequired(ETH, _round, _tokenIds, _quantities);

        if (msg.value < totalRequiredETH) revert InsufficientETHSent(msg.value);

        _transferETHToTreasury(totalRequiredETH);

        // This contract has the minter role.
        triaSaleNFT.mintBatch(msg.sender, _tokenIds, _quantities, "");

        // Refund excess ETH to minter
        uint256 refundAmount = msg.value - totalRequiredETH;
        if (refundAmount > 0) {
            payable(msg.sender).sendValue(refundAmount);
        }

        emit NFTsMinted(
            NFTMintData(
                msg.sender,
                _tokenIds,
                _quantities,
                ETH,
                totalRequiredETH,
                totalUSDAmount,
                block.timestamp,
                _round,
                _userInfo.txUUID,
                _userInfo.referralCode
            )
        );
    }

    /// @notice Purchases TriaSaleNFT with Stablecoins
    /// @param _token The purchase token
    /// @param _round The round in which user wants to purchase
    /// @param _tokenIds The tokenIds of the NFTs
    /// @param _quantities The quantities of the NFTs
    /// @param _userInfo The user information (txUUID, referralCode, deadline)
    /// @param _signatureParams The signature parameters (v, r, s)
    function purchaseWithToken(
        IERC20 _token,
        uint32 _round,
        uint256[] calldata _tokenIds,
        uint256[] calldata _quantities,
        UserInfo calldata _userInfo,
        SignatureParams calldata _signatureParams
    )
        external
        nonReentrant
        whenNotPaused
        validateArrayLengths(_tokenIds.length, _quantities.length)
    {
        // The input must have been signed by the presale signer
        _validatePurchaseWithToken(_token, _round, _userInfo, _signatureParams);

        (
            uint256 totalRequiredTokenAmount,
            uint256 totalUSDAmount
        ) = calculateTotalCostRequired(_token, _round, _tokenIds, _quantities);

        _transferTokenToTreasury(_token, totalRequiredTokenAmount);

        // This contract has the minter role.
        triaSaleNFT.mintBatch(msg.sender, _tokenIds, _quantities, "");

        emit NFTsMinted(
            NFTMintData(
                msg.sender,
                _tokenIds,
                _quantities,
                _token,
                totalRequiredTokenAmount,
                totalUSDAmount,
                block.timestamp,
                _round,
                _userInfo.txUUID,
                _userInfo.referralCode
            )
        );
    }

    /// @notice Calculates total cost required for purchasing TriaSaleNFTs
    /// @param _token The purchase token
    /// @param _round The round in which user wants to purchase
    /// @param _tokenIds The tokenIds of the NFTs
    /// @param _quantities The quantities of the NFTs
    /// @return totalRequiredTokenAmount The total cost required for the purchase
    /// @return totalUSDAmount The total cost in USD for the purchase
    function calculateTotalCostRequired(
        IERC20 _token,
        uint32 _round,
        uint256[] calldata _tokenIds,
        uint256[] calldata _quantities
    )
        public
        view
        returns (uint256 totalRequiredTokenAmount, uint256 totalUSDAmount)
    {
        uint256 tokenLength = _tokenIds.length;
        for (uint256 i = 0; i < tokenLength; ) {
            uint256 tokenId = _tokenIds[i];
            uint256 quantity = _quantities[i];

            if (!triaSaleNFT.tokenIdExists(tokenId))
                revert TokenIdDoesNotExist(tokenId);
            if (quantity == 0) revert ZeroValue();

            uint256 roundPrice = _getRoundTokenPrice(_round, tokenId);
            uint256 tokenAmount = _token == ETH
                ? calculateETHAmount(roundPrice)
                : calculateUSDAmount(roundPrice);
            totalRequiredTokenAmount += tokenAmount * quantity;
            totalUSDAmount += roundPrice * quantity;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Gets the latest ETH/USD price
    /// @return The latest ETH/USD price from chainlink price feed
    function getLatestEthUSDPrice() public view returns (uint256) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int price,
            /*uint startedAt*/,
            uint updatedAt,
            /*uint80 answeredInRound*/
        ) = ethUsdPriceFeed.latestRoundData();

        if (price <= 0) revert ZeroValue();

        if (
            updatedAt == 0 ||
            block.timestamp - updatedAt > ethUsdPriceFeedTolerance
        ) {
            revert PriceNotUpdated();
        }

        return price.toUint256();
    }

    /// @notice Calculates the ETH amount in WEI_PRECISION
    /// @param _dollarValue The dollar value
    /// @return The ETH amount in WEI_PRECISION
    function calculateETHAmount(
        uint256 _dollarValue
    ) public view returns (uint256) {
        uint256 ethUsdPrice = getLatestEthUSDPrice();
        return
            (_dollarValue * ETH_PRICE_FEED_PRECISION * WEI_PRECISION) /
            ethUsdPrice;
    }

    /// @notice Calculates the USD amount in USD_PRECISION
    /// @param _dollarValue The dollar value
    /// @return The USD amount
    function calculateUSDAmount(
        uint256 _dollarValue
    ) public pure returns (uint256) {
        return (_dollarValue * USD_PRECISION);
    }

    /// @notice Validates token and round and deadline
    /// @param _round The round to validate
    /// @param _deadline The deadline to validate
    /// @param _token The token to validate
    function _validatePurchase(
        uint32 _round,
        uint256 _deadline,
        IERC20 _token
    ) private view {
        if (block.timestamp > _deadline) {
            revert DeadlineExpired();
        }
        _verifyInRound(_round);

        if (!isTokenAllowed(_token)) {
            revert TokenDisallowed();
        }
    }

    /// @notice The helper function which verifies signature, signed by signerWallet, reverts if Invalid
    /// @param _userInfo The user information
    /// @param _signatureParams The signature parameters
    function _verifyCode(
        UserInfo calldata _userInfo,
        SignatureParams calldata _signatureParams
    ) private {
        bytes32 encodedMessageHash = keccak256(
            abi.encodePacked(
                msg.sender,
                _userInfo.txUUID,
                _userInfo.referralCode,
                _userInfo.deadline,
                _useNonce(msg.sender)
            )
        );
        _verifyMessage(encodedMessageHash, _signatureParams);
    }

    /// @notice Verifies the address that signed a hashed message (`hash`) with
    /// `signature`
    /// @param _encodedMessageHash The encoded message hash
    /// @param _signatureParams The signature parameters
    function _verifyMessage(
        bytes32 _encodedMessageHash,
        SignatureParams calldata _signatureParams
    ) private view {
        if (
            signerWallet !=
            ECDSA.recover(
                MessageHashUtils.toEthSignedMessageHash(_encodedMessageHash),
                _signatureParams.v,
                _signatureParams.r,
                _signatureParams.s
            )
        ) {
            revert InvalidSignature();
        }
    }

    /// @notice Validates round, deadline and signature
    /// @param _token The token to validate
    /// @param _round The round to validate
    /// @param _userInfo The user information
    /// @param _signatureParams The signature parameters
    function _validatePurchaseWithToken(
        IERC20 _token,
        uint32 _round,
        UserInfo calldata _userInfo,
        SignatureParams calldata _signatureParams
    ) private {
        _validatePurchase(_round, _userInfo.deadline, _token);
        _verifyCode(_userInfo, _signatureParams);
    }

    /// @notice Distribute ETH to treasury wallet
    /// @param _amount The amount to transfer
    function _transferETHToTreasury(uint256 _amount) private {
        payable(treasuryWallet).sendValue(_amount);
    }

    /// @notice Distribute token to treasury wallet
    /// @param _token The token to transfer
    /// @param _amount The amount to transfer
    function _transferTokenToTreasury(IERC20 _token, uint256 _amount) private {
        _token.safeTransferFrom(msg.sender, treasuryWallet, _amount);
    }
}