// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import { Rounds, Ownable } from "./Rounds.sol";
import { ILockup, IPreSale } from "./ILockup.sol";
import { IClaims, ClaimInfo } from "./IClaims.sol";

import { ETH, PPM, ZeroAddress, ZeroLengthArray, IdenticalValue, ArrayLengthMismatch, InvalidSignature, InvalidData } from "./Common.sol";

/// @title PreSale contract
/// @notice Implements presale of the token
/// @dev The presale contract allows you to purchase presale token with allowed tokens
/// and there will be certain rounds
contract PreSale is IPreSale, Rounds, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @member nftAmounts The nft amounts
    /// @member roundPrice The round number
    struct ClaimNFT {
        uint256[] nftAmounts;
        uint256 roundPrice;
    }

    /// @member price The price of token from price feed
    /// @member normalizationFactorForToken The normalization factor to achieve return value of 18 decimals ,while calculating token purchases and always with different token decimals
    /// @member normalizationFactorForNFT The normalization factor is the value which helps us to convert decimals of USDT to purchase token decimals and always with different token decimals
    struct TokenInfo {
        uint256 latestPrice;
        uint8 normalizationFactorForToken;
        uint8 normalizationFactorForNFT;
    }

    /// @member projectAmount The amount tansferred to project wallet
    /// @member platformAmount The amount tansferred to platform wallet
    /// @member burnAmount The amount tansferred to burn wallet
    /// @member equivalence The amount tansferred to claims contract
    struct TransferInfo {
        uint256 projectAmount;
        uint256 platformAmount;
        uint256 burnAmount;
        uint256 equivalence;
    }

    /// @dev To achieve return value of required decimals during calculation
    uint256 private constant NORMALIZARION_FACTOR = 1e30;

    /// @dev The constant value helps in calculating project amount
    uint256 private constant PROJECT_PERCENTAGE_PPM = 630_000;

    /// @dev The constant value helps in calculating discount
    uint256 private constant FIRST_ROUND_PPM = 200_000;

    /// @dev The constant value helps in calculating discount
    uint256 private constant OTHER_ROUND_PPM = 70_000;

    /// @dev The constant value helps in calculating amount
    uint256 private constant CLAIMS_PERCENTAGE_PPM = 250_000;

    /// @dev The constant value helps in calculating plaform amount
    uint256 private constant PLATFORM_PERCENTAGE_PPM = 100_000;

    /// @dev The constant value helps in calculating burn amount
    uint256 private constant BURN_PERCENTAGE_PPM = 20_000;

    /// @dev The max leader's wallet length
    uint256 private constant LEADERS_LENGTH = 5;

    /// @notice The maximum number of tokens that will be sold in presale
    uint256 public immutable maxCap;

    /// @notice The address of claims contract
    IClaims public immutable claimsContract;

    /// @notice The address of lockup contract
    ILockup public immutable lockup;

    /// @notice That buyEnabled or not
    bool public buyEnabled = true;

    /// @notice The address of signer wallet
    address public signerWallet;

    /// @notice The address of the project wallet
    address public projectWallet;

    /// @notice The address of the platform wallet
    address public platformWallet;

    /// @notice The address of the burn wallet
    address public burnWallet;

    /// @notice The address of the insurance funds wallet
    address public insuranceWallet;

    /// @notice Sum of tokens purchased in presale
    uint256 public totalPurchases;

    /// @notice The insurance fee in PPM
    uint256 public insuranceFeePPM;

    /// @notice The array of prices of each nft
    uint256[] public nftPricing;

    /// @notice Gives claim info of user in every round
    mapping(address => mapping(uint32 => uint256)) public claims;

    /// @notice Gives info about address's permission
    mapping(address => bool) public blacklistAddress;

    /// @notice Gives claim info of user nft in every round
    mapping(address => mapping(uint32 => ClaimNFT[])) public claimNFT;

    /// @dev Emitted when token is purchased with ETH
    event PurchasedWithETH(
        address indexed by,
        string code,
        uint256 amountPurchasedETH,
        uint32 indexed round,
        address[] leaders,
        uint256[] percentages,
        uint256 indexed roundPrice,
        uint256 tokenPurchased,
        bool isInsured,
        uint256 insuranceAmount
    );

    /// @dev Emitted when presale tokens are purchased with any token
    event PurchasedWithToken(
        IERC20 indexed token,
        uint256 tokenPrice,
        address indexed by,
        string code,
        uint256 amountPurchased,
        uint256 tokenPurchased,
        uint32 indexed round,
        address[] leaders,
        uint256[] percentages,
        bool isInsured,
        uint256 insuranceAmount
    );

    /// @dev Emitted when NFT is purchased with ETH
    event PurchasedWithETHForNFT(
        address indexed by,
        string code,
        uint256 amountInETH,
        uint256 ethPrice,
        uint32 indexed round,
        address[] leaders,
        uint256[] percentages,
        uint256 roundPrice,
        uint256[] nftAmounts,
        bool isInsured,
        uint256 insuranceAmount
    );

    /// @dev Emitted when NFT is purchased with any token
    event PurchasedWithTokenForNFT(
        IERC20 indexed token,
        uint256 tokenPrice,
        address indexed by,
        string code,
        uint256 amountPurchased,
        uint32 indexed round,
        address[] leaders,
        uint256[] percentages,
        uint256 roundPrice,
        uint256[] nftAmounts,
        bool isInsured,
        uint256 insuranceAmount
    );

    /// @dev Emitted when tokens are purchased with claim amount
    event PurchasedWithClaimAmount(
        address indexed by,
        uint256 amount,
        IERC20 token,
        uint32 indexed round,
        uint256 indexed tokenPrice,
        uint256 tokenPurchased
    );

    /// @dev Emitted when address of signer is updated
    event SignerUpdated(address oldSigner, address newSigner);

    /// @dev Emitted when insurance fee is updated
    event InsuranceFeeUpdated(uint256 oldInsuranceFee, uint256 newInsuranceFee);

    /// @dev Emitted when address of platform wallet is updated
    event PlatformWalletUpdated(address oldPlatformWallet, address newPlatformWallet);

    /// @dev Emitted when address of project wallet is updated
    event ProjectWalletUpdated(address oldProjectWallet, address newProjectWallet);

    /// @dev Emitted when address of burn wallet is updated
    event BurnWalletUpdated(address oldBurnWallet, address newBurnWallet);

    /// @dev Emitted when address of insurance funds wallet is updated
    event InsuranceFundsWalletUpdated(address oldInsuranceFundsWallet, address newInsuranceFundsWallet);

    /// @dev Emitted when blacklist access of address is updated
    event BlacklistUpdated(address which, bool accessNow);

    /// @dev Emitted when buying access changes
    event BuyEnableUpdated(bool oldAccess, bool newAccess);

    /// @dev Emitted when NFT prices are updated
    event PricingUpdated(uint256[] oldPrices, uint256[] newPrices);

    /// @notice Thrown when address is blacklisted
    error Blacklisted();

    /// @notice Thrown when buy is disabled
    error BuyNotEnabled();

    /// @notice Thrown when sign deadline is expired
    error DeadlineExpired();

    /// @notice Thrown when Eth price suddenly drops while purchasing tokens
    error UnexpectedPriceDifference();

    /// @notice Thrown when value to transfer is zero
    error ZeroValue();

    /// @notice Thrown when price from price feed returns zero
    error PriceNotFound();

    /// @notice Thrown when max cap is reached
    error MaxCapReached();

    /// @notice Thrown when caller is not claims contract
    error OnlyClaims();

    /// @notice Thrown when purchase amount is less than required
    error InvalidPurchase();

    /// @notice Thrown when both price feed and reference price are non zero
    error CodeSyncIssue();

    /// @notice Thrown if the price is not updated
    error PriceNotUpdated();

    /// @notice Thrown if the sum of agents percentage is greater than required
    error InvalidPercentage();

    /// @notice Thrown if the roundId of price is not updated
    error RoundIdNotUpdated();

    /// @notice Thrown when array length of leaders are greater than required
    error InvalidArrayLength();

    /// @notice Thrown when array is not sorted
    error ArrayNotSorted();

    /// @dev Restricts when updating wallet/contract address with zero address
    modifier checkAddressZero(address which) {
        _checkAddressZero(which);
        _;
    }

    /// @dev Ensures that buy is enabled when buying
    modifier canBuy() {
        _canBuy();
        _;
    }

    /// @dev Constructor
    /// @param projectWalletAddress The address of project wallet
    /// @param platformWalletAddress The address of platform wallet
    /// @param burnWalletAddress The address of burn wallet
    /// @param insuranceWalletAddress The address of insurance funds wallet
    /// @param signerAddress The address of signer wallet
    /// @param claimsContractAddress The address of claim contract
    /// @param lockupContractAddress The address of lockup contract
    /// @param owner The address of owner wallet
    /// @param lastRound The last round created
    /// @param nftPrices The prices of nfts
    /// @param initMaxCap The max cap of gems token
    /// @param insuranceFeePPMInit The insurance fee
    constructor(
        address projectWalletAddress,
        address platformWalletAddress,
        address burnWalletAddress,
        address insuranceWalletAddress,
        address signerAddress,
        IClaims claimsContractAddress,
        ILockup lockupContractAddress,
        address owner,
        uint32 lastRound,
        uint256[] memory nftPrices,
        uint256 initMaxCap,
        uint256 insuranceFeePPMInit
    )
        Rounds(lastRound)
        Ownable(owner)
        checkAddressZero(signerAddress)
        checkAddressZero(address(claimsContractAddress))
        checkAddressZero(address(lockupContractAddress))
        checkAddressZero(projectWalletAddress)
        checkAddressZero(platformWalletAddress)
        checkAddressZero(burnWalletAddress)
        checkAddressZero(insuranceWalletAddress)
    {
        if (nftPrices.length == 0 || insuranceFeePPMInit == 0) {
            revert ZeroLengthArray();
        }

        for (uint256 i = 0; i < nftPrices.length; ++i) {
            _checkValue(nftPrices[i]);
        }

        projectWallet = projectWalletAddress;
        platformWallet = platformWalletAddress;
        burnWallet = burnWalletAddress;
        insuranceWallet = insuranceWalletAddress;
        signerWallet = signerAddress;
        claimsContract = claimsContractAddress;
        lockup = lockupContractAddress;
        nftPricing = nftPrices;
        _checkValue(initMaxCap);
        maxCap = initMaxCap;
        insuranceFeePPM = insuranceFeePPMInit;
    }

    /// @notice Changes access of buying
    /// @param enabled The decision about buying
    function enableBuy(bool enabled) external onlyOwner {
        if (buyEnabled == enabled) {
            revert IdenticalValue();
        }

        emit BuyEnableUpdated({ oldAccess: buyEnabled, newAccess: enabled });
        buyEnabled = enabled;
    }

    /// @notice Changes signer wallet address
    /// @param newSigner The address of the new signer wallet
    function changeSigner(address newSigner) external checkAddressZero(newSigner) onlyOwner {
        address oldSigner = signerWallet;

        if (oldSigner == newSigner) {
            revert IdenticalValue();
        }

        emit SignerUpdated({ oldSigner: oldSigner, newSigner: newSigner });
        signerWallet = newSigner;
    }

    /// @notice Changes platform wallet address
    /// @param newPlatformWallet The address of the new platform wallet
    function updatePlatformWallet(address newPlatformWallet) external checkAddressZero(newPlatformWallet) onlyOwner {
        address oldPlatformWallet = platformWallet;

        if (oldPlatformWallet == newPlatformWallet) {
            revert IdenticalValue();
        }

        emit PlatformWalletUpdated({ oldPlatformWallet: oldPlatformWallet, newPlatformWallet: newPlatformWallet });
        platformWallet = newPlatformWallet;
    }

    /// @notice Changes project wallet address
    /// @param newProjectWallet The address of the new project wallet
    function updateProjectWallet(address newProjectWallet) external checkAddressZero(newProjectWallet) onlyOwner {
        address oldProjectWallet = projectWallet;

        if (oldProjectWallet == newProjectWallet) {
            revert IdenticalValue();
        }

        emit ProjectWalletUpdated({ oldProjectWallet: oldProjectWallet, newProjectWallet: newProjectWallet });
        projectWallet = newProjectWallet;
    }

    /// @notice Changes burn wallet address
    /// @param newBurnWallet The address of the new burn wallet
    function updateBurnWallet(address newBurnWallet) external checkAddressZero(newBurnWallet) onlyOwner {
        address oldBurnWallet = burnWallet;

        if (oldBurnWallet == newBurnWallet) {
            revert IdenticalValue();
        }

        emit BurnWalletUpdated({ oldBurnWallet: oldBurnWallet, newBurnWallet: newBurnWallet });
        burnWallet = newBurnWallet;
    }

    /// @notice Changes insurance funds wallet address
    /// @param newInsuranceFundsWallet The address of the new insurance funds wallet
    function updateInsuranceFundsWallet(
        address newInsuranceFundsWallet
    ) external checkAddressZero(newInsuranceFundsWallet) onlyOwner {
        address oldInsuranceFundsWallet = insuranceWallet;

        if (oldInsuranceFundsWallet == newInsuranceFundsWallet) {
            revert IdenticalValue();
        }

        emit InsuranceFundsWalletUpdated({
            oldInsuranceFundsWallet: oldInsuranceFundsWallet,
            newInsuranceFundsWallet: newInsuranceFundsWallet
        });

        insuranceWallet = newInsuranceFundsWallet;
    }

    /// @notice Changes the insurance fee
    /// @param newInsuranceFee The new Insurance fee
    function updateInsuranceFee(uint256 newInsuranceFee) external onlyOwner {
        uint256 oldInsuranceFee = insuranceFeePPM;

        if (newInsuranceFee == oldInsuranceFee) {
            revert IdenticalValue();
        }

        if (newInsuranceFee == 0) {
            revert ZeroValue();
        }

        emit InsuranceFeeUpdated({ oldInsuranceFee: oldInsuranceFee, newInsuranceFee: newInsuranceFee });

        insuranceFeePPM = newInsuranceFee;
    }

    /// @notice Changes the access of any address in contract interaction
    /// @param which The address for which access is updated
    /// @param access The access decision of `which` address
    function updateBlackListedUser(address which, bool access) external checkAddressZero(which) onlyOwner {
        bool oldAccess = blacklistAddress[which];

        if (oldAccess == access) {
            revert IdenticalValue();
        }

        emit BlacklistUpdated({ which: which, accessNow: access });
        blacklistAddress[which] = access;
    }

    /// @notice Changes the nft prices
    /// @param newPrices The new prices of nfts
    function updatePricing(uint256[] calldata newPrices) external onlyOwner {
        for (uint256 i = 0; i < newPrices.length; ++i) {
            _checkValue(newPrices[i]);
        }

        emit PricingUpdated({ oldPrices: nftPricing, newPrices: newPrices });

        nftPricing = newPrices;
    }

    /// @notice Purchases presale token with ETH
    /// @param code The code is used to verify signature of the user
    /// @param round The round in which user wants to purchase
    /// @param deadline The deadline is validity of the signature
    /// @param minAmountToken The minAmountToken user agrees to purchase
    /// @param indexes The indexes at which user has locked tokens
    /// @param leaders The indexes of leaders
    /// @param percentages The indexes of leaders percentage
    /// @param isInsured The decision about insurance
    /// @param v The `v` signature parameter
    /// @param r The `r` signature parameter
    /// @param s The `s` signature parameter
    function purchaseTokenWithETH(
        string memory code,
        uint32 round,
        uint256 deadline,
        uint256 minAmountToken,
        uint256[] calldata indexes,
        address[] calldata leaders,
        uint256[] calldata percentages,
        bool isInsured,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable nonReentrant canBuy {
        uint256 purchaseAmount = msg.value;
        uint256 insuranceAmount;

        if (isInsured) {
            purchaseAmount = (msg.value * PPM) / (PPM + insuranceFeePPM);
            insuranceAmount = (purchaseAmount * insuranceFeePPM) / PPM;
        }

        if (msg.value < (purchaseAmount + insuranceAmount)) {
            revert InvalidPurchase();
        }

        uint256 amountUnused = msg.value - (purchaseAmount + insuranceAmount);

        if (amountUnused > 0) {
            payable(msg.sender).sendValue(amountUnused);
        }

        // The input must have been signed by the presale signer
        _validatePurchaseWithETH(purchaseAmount, round, deadline, code, isInsured, v, r, s);
        uint256 roundPrice = _getRoundPriceForToken(msg.sender, indexes, round, ETH);
        TokenInfo memory tokenInfo = getLatestPrice(ETH);

        if (tokenInfo.latestPrice == 0) {
            revert PriceNotFound();
        }

        TransferInfo memory transferInfo = _calculateTransferAmounts(purchaseAmount, leaders, percentages);
        uint256 toReturn = _calculateAndUpdateTokenAmount(
            purchaseAmount,
            tokenInfo.latestPrice,
            tokenInfo.normalizationFactorForToken,
            roundPrice
        );

        if (toReturn < minAmountToken) {
            revert UnexpectedPriceDifference();
        }

        _transferFundsETH(transferInfo, isInsured, insuranceAmount);
        claims[msg.sender][round] += toReturn;
        _updateCommissions(leaders, percentages, purchaseAmount, round, ETH);

        emit PurchasedWithETH({
            by: msg.sender,
            code: code,
            amountPurchasedETH: purchaseAmount,
            round: round,
            leaders: leaders,
            percentages: percentages,
            roundPrice: roundPrice,
            tokenPurchased: toReturn,
            isInsured: isInsured,
            insuranceAmount: insuranceAmount
        });
    }

    /// @notice Purchases presale token with any token
    /// @param token The purchase token
    /// @param referenceNormalizationFactor The normalization factor
    /// @param referenceTokenPrice The current price of token in 10 decimals
    /// @param purchaseAmount The purchase amount
    /// @param minAmountToken The minAmountToken user agrees to purchase
    /// @param indexes The indexes at which user has locked tokens
    /// @param leaders The indexes of leaders
    /// @param percentages The indexes of leaders percentage
    /// @param isInsured The decision about insurance
    /// @param code The code is used to verify signature of the user
    /// @param round The round in which user wants to purchase
    /// @param deadline The deadline is validity of the signature
    /// @param v The `v` signature parameter
    /// @param r The `r` signature parameter
    /// @param s The `s` signature parameter
    function purchaseTokenWithToken(
        IERC20 token,
        uint8 referenceNormalizationFactor,
        uint256 referenceTokenPrice,
        uint256 purchaseAmount,
        uint256 minAmountToken,
        uint256[] calldata indexes,
        address[] calldata leaders,
        uint256[] calldata percentages,
        bool isInsured,
        string memory code,
        uint32 round,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external canBuy nonReentrant {
        uint256 insuranceAmount;

        if (isInsured) {
            purchaseAmount = (purchaseAmount * PPM) / (PPM + insuranceFeePPM);
            insuranceAmount = (purchaseAmount * insuranceFeePPM) / PPM;
        }

        // The input must have been signed by the presale signer
        _validatePurchaseWithToken(
            token,
            round,
            deadline,
            code,
            referenceTokenPrice,
            referenceNormalizationFactor,
            isInsured,
            v,
            r,
            s
        );
        uint256 roundPrice = _getRoundPriceForToken(msg.sender, indexes, round, token);
        (uint256 latestPrice, uint8 normalizationFactor) = _validatePrice(
            token,
            referenceTokenPrice,
            referenceNormalizationFactor
        );
        TransferInfo memory transferInfo = _calculateTransferAmounts(purchaseAmount, leaders, percentages);
        uint256 toReturn = _calculateAndUpdateTokenAmount(purchaseAmount, latestPrice, normalizationFactor, roundPrice);

        if (toReturn < minAmountToken) {
            revert UnexpectedPriceDifference();
        }

        _transferFundsToken(token, transferInfo, isInsured, insuranceAmount);
        claims[msg.sender][round] += toReturn;
        _updateCommissions(leaders, percentages, purchaseAmount, round, token);

        emit PurchasedWithToken({
            token: token,
            tokenPrice: latestPrice,
            by: msg.sender,
            code: code,
            amountPurchased: purchaseAmount,
            tokenPurchased: toReturn,
            round: round,
            leaders: leaders,
            percentages: percentages,
            isInsured: isInsured,
            insuranceAmount: insuranceAmount
        });
    }

    /// @notice Purchases NFT with ETH
    /// @param code The code is used to verify signature of the user
    /// @param round The round in which user wants to purchase
    /// @param nftAmounts The nftAmounts is array of nfts selected
    /// @param deadline The deadline is validity of the signature
    /// @param indexes The indexes at which user has locked tokens
    /// @param leaders The indexes of leaders
    /// @param percentages The indexes of leaders percentage
    /// @param isInsured The decision about insurance
    /// @param v The `v` signature parameter
    /// @param r The `r` signature parameter
    /// @param s The `s` signature parameter
    function purchaseNFTWithETH(
        string memory code,
        uint32 round,
        uint256[] calldata nftAmounts,
        uint256 deadline,
        uint256[] calldata indexes,
        address[] calldata leaders,
        uint256[] calldata percentages,
        bool isInsured,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable canBuy nonReentrant {
        uint256[] memory nftPrices = nftPricing;
        _validateArrays(nftAmounts.length, nftPrices.length);
        // The input must have been signed by the presale signer
        _validatePurchaseWithETH(msg.value, round, deadline, code, isInsured, v, r, s);
        TokenInfo memory tokenInfo = getLatestPrice(ETH);

        if (tokenInfo.latestPrice == 0) {
            revert PriceNotFound();
        }

        (uint256 roundPrice, uint256 value) = _processPurchaseNFT(
            ETH,
            tokenInfo.latestPrice,
            tokenInfo.normalizationFactorForNFT,
            round,
            indexes,
            nftAmounts,
            nftPrices
        );

        TransferInfo memory transferInfo = _calculateTransferAmounts(value, leaders, percentages);
        uint256 insuranceAmount;

        if (isInsured) {
            insuranceAmount = (value * insuranceFeePPM) / PPM;
        }

        if (msg.value < (value + insuranceAmount)) {
            revert InvalidPurchase();
        }

        uint256 amountUnused = msg.value - (value + insuranceAmount);

        if (amountUnused > 0) {
            payable(msg.sender).sendValue(amountUnused);
        }

        _transferFundsETH(transferInfo, isInsured, insuranceAmount);
        _updateCommissions(leaders, percentages, value, round, ETH);

        emit PurchasedWithETHForNFT({
            by: msg.sender,
            code: code,
            amountInETH: value,
            ethPrice: tokenInfo.latestPrice,
            round: round,
            leaders: leaders,
            percentages: percentages,
            roundPrice: roundPrice,
            nftAmounts: nftAmounts,
            isInsured: isInsured,
            insuranceAmount: insuranceAmount
        });
    }

    /// @notice Purchases NFT with any token
    /// @param token The purchase token
    /// @param referenceTokenPrice The current price of token in 10 decimals
    /// @param referenceNormalizationFactor The normalization factor
    /// @param code The code is used to verify signature of the user
    /// @param round The round in which user wants to purchase
    /// @param leaders The indexes of leaders
    /// @param percentages The indexes of leaders percentage
    /// @param isInsured The decision about insurance
    /// @param nftAmounts The nftAmounts is array of nfts selected
    /// @param deadline The deadline is validity of the signature
    /// @param indexes The indexes at which user has locked tokens
    /// @param v The `v` signature parameter
    /// @param r The `r` signature parameter
    /// @param s The `s` signature parameter
    function purchaseNFTWithToken(
        IERC20 token,
        uint256 referenceTokenPrice,
        uint8 referenceNormalizationFactor,
        string memory code,
        uint32 round,
        uint256[] calldata nftAmounts,
        uint256 deadline,
        uint256[] calldata indexes,
        address[] calldata leaders,
        uint256[] calldata percentages,
        bool isInsured,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external canBuy nonReentrant {
        uint256[] memory nftPrices = nftPricing;
        _validateArrays(nftAmounts.length, nftPrices.length);
        // The input must have been signed by the presale signer
        _validatePurchaseWithToken(
            token,
            round,
            deadline,
            code,
            referenceTokenPrice,
            referenceNormalizationFactor,
            isInsured,
            v,
            r,
            s
        );
        TokenInfo memory tokenInfo = getLatestPrice(token);

        if (tokenInfo.latestPrice != 0) {
            if (referenceTokenPrice != 0 || referenceNormalizationFactor != 0) {
                revert CodeSyncIssue();
            }
        }

        //  If price feed isn't available,we fallback to the reference price
        if (tokenInfo.latestPrice == 0) {
            if (referenceTokenPrice == 0 || referenceNormalizationFactor == 0) {
                revert ZeroValue();
            }

            tokenInfo.latestPrice = referenceTokenPrice;
            tokenInfo.normalizationFactorForNFT = referenceNormalizationFactor;
        }

        (uint256 roundPrice, uint256 value) = _processPurchaseNFT(
            token,
            tokenInfo.latestPrice,
            tokenInfo.normalizationFactorForNFT,
            round,
            indexes,
            nftAmounts,
            nftPrices
        );

        uint256 insuranceAmount = (value * insuranceFeePPM) / PPM;

        TransferInfo memory transferInfo = _calculateTransferAmounts(value, leaders, percentages);
        _transferFundsToken(token, transferInfo, isInsured, insuranceAmount);
        _updateCommissions(leaders, percentages, value, round, token);

        emit PurchasedWithTokenForNFT({
            token: token,
            tokenPrice: tokenInfo.latestPrice,
            by: msg.sender,
            code: code,
            amountPurchased: value,
            round: round,
            leaders: leaders,
            percentages: percentages,
            roundPrice: roundPrice,
            nftAmounts: nftAmounts,
            isInsured: isInsured,
            insuranceAmount: insuranceAmount
        });
    }

    /// @inheritdoc IPreSale
    function purchaseWithClaim(
        IERC20 token,
        uint256 referenceTokenPrice,
        uint8 referenceNormalizationFactor,
        uint256 amount,
        uint256 minAmountToken,
        uint256[] calldata indexes,
        address recipient,
        uint32 round
    ) external payable canBuy nonReentrant {
        if (msg.sender != address(claimsContract)) {
            revert OnlyClaims();
        }

        _checkBlacklist(recipient);

        if (!allowedTokens[round][token].access) {
            revert TokenDisallowed();
        }

        uint256 roundPrice = _getRoundPriceForToken(recipient, indexes, round, token);
        (uint256 latestPrice, uint8 normalizationFactor) = _validatePrice(
            token,
            referenceTokenPrice,
            referenceNormalizationFactor
        );
        uint256 toReturn = _calculateAndUpdateTokenAmount(amount, latestPrice, normalizationFactor, roundPrice);

        if (toReturn < minAmountToken) {
            revert UnexpectedPriceDifference();
        }

        claims[recipient][round] += toReturn;
        uint256 platformAmount = (amount * PLATFORM_PERCENTAGE_PPM) / PPM;

        if (token == ETH) {
            payable(platformWallet).sendValue(platformAmount);
            payable(projectWallet).sendValue(amount - platformAmount);
        } else {
            token.safeTransferFrom(msg.sender, platformWallet, platformAmount);
            token.safeTransferFrom(msg.sender, projectWallet, amount - platformAmount);
        }

        emit PurchasedWithClaimAmount({
            by: recipient,
            amount: amount,
            token: token,
            round: round,
            tokenPrice: latestPrice,
            tokenPurchased: toReturn
        });
    }

    /// @notice The Chainlink inherited function, give us tokens live price
    function getLatestPrice(IERC20 token) public view returns (TokenInfo memory) {
        PriceFeedData memory data = tokenData[token];
        TokenInfo memory tokenInfo;

        if (address(data.priceFeed) == address(0)) {
            return tokenInfo;
        }
        (
            uint80 roundId,
            /*uint80 roundID*/ int price /*uint256 startedAt*/ /*uint80 answeredInRound*/,
            ,
            uint256 updatedAt,

        ) = /*uint256 timeStamp*/ data.priceFeed.latestRoundData();

        if (roundId == 0) {
            revert RoundIdNotUpdated();
        }

        if (updatedAt == 0 || block.timestamp - updatedAt > data.tolerance) {
            revert PriceNotUpdated();
        }

        return
            TokenInfo({
                latestPrice: uint256(price),
                normalizationFactorForToken: data.normalizationFactorForToken,
                normalizationFactorForNFT: data.normalizationFactorForNFT
            });
    }

    /// @dev Checks value, if zero then reverts
    function _checkValue(uint256 value) private pure {
        if (value == 0) {
            revert ZeroValue();
        }
    }

    /// @dev Validates blacklist address, round and deadline
    function _validatePurchase(uint32 round, uint256 deadline, IERC20 token) private view {
        if (block.timestamp > deadline) {
            revert DeadlineExpired();
        }

        _checkBlacklist(msg.sender);

        if (!allowedTokens[round][token].access) {
            revert TokenDisallowed();
        }

        _verifyInRound(round);
    }

    /// @dev The helper function which verifies signature, signed by signerWallet, reverts if Invalid
    function _verifyCode(
        string memory code,
        uint256 deadline,
        bool isInsured,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private view {
        bytes32 encodedMessageHash = keccak256(abi.encodePacked(msg.sender, code, deadline, isInsured));
        _verifyMessage(encodedMessageHash, v, r, s);
    }

    /// @dev The helper function which verifies signature, signed by signerWallet, reverts if Invalid
    function _verifyCodeWithPrice(
        string memory code,
        uint256 deadline,
        uint256 referenceTokenPrice,
        IERC20 token,
        uint256 normalizationFactor,
        bool isInsured,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private view {
        bytes32 encodedMessageHash = keccak256(
            abi.encodePacked(msg.sender, code, referenceTokenPrice, deadline, token, normalizationFactor, isInsured)
        );
        _verifyMessage(encodedMessageHash, v, r, s);
    }

    /// @dev Verifies the address that signed a hashed message (`hash`) with
    /// `signature`
    function _verifyMessage(bytes32 encodedMessageHash, uint8 v, bytes32 r, bytes32 s) private view {
        if (signerWallet != ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(encodedMessageHash), v, r, s)) {
            revert InvalidSignature();
        }
    }

    /// @dev Process nft purchase by calculating nft prices and purchase amount
    function _processPurchaseNFT(
        IERC20 token,
        uint256 price,
        uint256 normalizationFactor,
        uint32 round,
        uint256[] calldata indexes,
        uint256[] calldata nftAmounts,
        uint256[] memory nftPrices
    ) private returns (uint256, uint256) {
        uint256 value;
        uint256 totalNFTPrices = 0;

        for (uint256 i = 0; i < nftPrices.length; ++i) {
            uint256 nfts = nftAmounts[i];
            uint256 prices = nftPrices[i];
            //  (10**0 * 10**6 +10**10) -10**10 = 6 decimals
            value += (nfts * prices * (10 ** (normalizationFactor))) / price;
            totalNFTPrices += nfts * prices;
        }

        uint256 roundPrice = _getRoundPriceForToken(msg.sender, indexes, round, token);
        _updateTokenPurchases((totalNFTPrices * NORMALIZARION_FACTOR) / roundPrice);
        claimNFT[msg.sender][round].push(ClaimNFT({ nftAmounts: nftAmounts, roundPrice: roundPrice }));

        return (roundPrice, value);
    }

    /// @dev Checks that address is blacklisted or not
    function _checkBlacklist(address which) private view {
        if (blacklistAddress[which]) {
            revert Blacklisted();
        }
    }

    /// @dev Checks max cap and updates total purchases
    function _updateTokenPurchases(uint256 newPurchase) private {
        if (newPurchase + totalPurchases > maxCap) {
            revert MaxCapReached();
        }

        totalPurchases += newPurchase;
    }

    /// @dev Validates round, deadline and signature
    function _validatePurchaseWithETH(
        uint256 amount,
        uint32 round,
        uint256 deadline,
        string memory code,
        bool isInsured,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private view {
        _checkValue(amount);
        _validatePurchase(round, deadline, ETH);
        _verifyCode(code, deadline, isInsured, v, r, s);
    }

    /// @dev Validates round, deadline and signature
    function _validatePurchaseWithToken(
        IERC20 token,
        uint32 round,
        uint256 deadline,
        string memory code,
        uint256 referenceTokenPrice,
        uint256 normalizationFactor,
        bool isInsured,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private view {
        _validatePurchase(round, deadline, token);
        _verifyCodeWithPrice(code, deadline, referenceTokenPrice, token, normalizationFactor, isInsured, v, r, s);
    }

    /// @dev Checks discounted round price if eligible else returns round price
    function _getRoundPriceForToken(
        address user,
        uint256[] memory indexes,
        uint32 round,
        IERC20 token
    ) private view returns (uint256) {
        uint256 customPrice = allowedTokens[round][token].customPrice;
        uint256 roundPrice = customPrice > 0 ? customPrice : rounds[round].price;
        uint256 lockedAmount;
        uint256 indexLength = indexes.length;

        if (indexLength == 0) {
            return roundPrice;
        }

        for (uint256 i; i < indexLength; ++i) {
            if (indexLength != i + 1) {
                if (indexes[i] >= indexes[i + 1]) {
                    revert ArrayNotSorted();
                }
            }

            (uint256 amount, ) = lockup.stakes(user, indexes[i]);
            lockedAmount += amount;

            if (lockedAmount >= lockup.minStakeAmount()) {
                if (round == 1) {
                    roundPrice -= ((roundPrice * FIRST_ROUND_PPM) / PPM);
                } else {
                    roundPrice -= ((roundPrice * OTHER_ROUND_PPM) / PPM);
                }

                break;
            }
        }

        return roundPrice;
    }

    /// @dev Calculates and update the token amount
    function _calculateAndUpdateTokenAmount(
        uint256 purchaseAmount,
        uint256 referenceTokenPrice,
        uint256 normalizationFactor,
        uint256 roundPrice
    ) private returns (uint256) {
        // toReturn= (10**11 * 10**10 +10**15) -10**18 = 18 decimals
        uint256 toReturn = (purchaseAmount * referenceTokenPrice * (10 ** normalizationFactor)) / roundPrice;
        _updateTokenPurchases(toReturn);

        return toReturn;
    }

    /// @dev Provides us live price of token from price feed or returns reference price and reverts if price is zero
    function _validatePrice(
        IERC20 token,
        uint256 referenceTokenPrice,
        uint8 referenceNormalizationFactor
    ) private view returns (uint256, uint8) {
        TokenInfo memory tokenInfo = getLatestPrice(token);
        if (tokenInfo.latestPrice != 0) {
            if (referenceTokenPrice != 0 || referenceNormalizationFactor != 0) {
                revert CodeSyncIssue();
            }
        }
        //  If price feed isn't available,we fallback to the reference price
        if (tokenInfo.latestPrice == 0) {
            if (referenceTokenPrice == 0 || referenceNormalizationFactor == 0) {
                revert ZeroValue();
            }

            tokenInfo.latestPrice = referenceTokenPrice;
            tokenInfo.normalizationFactorForToken = referenceNormalizationFactor;
        }

        return (tokenInfo.latestPrice, tokenInfo.normalizationFactorForToken);
    }

    /// @dev Distribute ETH to multiple recipients
    function _transferFundsETH(TransferInfo memory transferInfo, bool isInsured, uint256 insuranceAmount) private {
        payable(projectWallet).sendValue(transferInfo.projectAmount);
        payable(platformWallet).sendValue(transferInfo.platformAmount);
        payable(burnWallet).sendValue(transferInfo.burnAmount);
        payable(address(claimsContract)).sendValue(transferInfo.equivalence);

        if (isInsured) {
            payable(insuranceWallet).sendValue(insuranceAmount);
        }
    }

    /// @dev Distribute token to multiple recipients
    function _transferFundsToken(
        IERC20 token,
        TransferInfo memory transferInfo,
        bool isInsured,
        uint256 insuranceAmount
    ) private {
        token.safeTransferFrom(msg.sender, projectWallet, transferInfo.projectAmount);
        token.safeTransferFrom(msg.sender, platformWallet, transferInfo.platformAmount);
        token.safeTransferFrom(msg.sender, burnWallet, transferInfo.burnAmount);
        token.safeTransferFrom(msg.sender, address(claimsContract), transferInfo.equivalence);

        if (isInsured) {
            token.safeTransferFrom(msg.sender, insuranceWallet, insuranceAmount);
        }
    }

    /// @dev Checks zero address, if zero then reverts
    /// @param which The `which` address to check for zero address
    function _checkAddressZero(address which) private pure {
        if (which == address(0)) {
            revert ZeroAddress();
        }
    }

    /// @dev Checks buyEnabled, if not then reverts
    function _canBuy() private view {
        if (!buyEnabled) {
            revert BuyNotEnabled();
        }
    }

    /// @dev Calculates transfer amounts
    function _calculateTransferAmounts(
        uint256 amount,
        address[] memory leaders,
        uint256[] memory percentages
    ) private pure returns (TransferInfo memory transferInfo) {
        _checkValue(amount);
        transferInfo.burnAmount = (amount * BURN_PERCENTAGE_PPM) / PPM;
        transferInfo.platformAmount = (amount * PLATFORM_PERCENTAGE_PPM) / PPM;
        transferInfo.projectAmount = (amount * PROJECT_PERCENTAGE_PPM) / PPM;

        uint256 toLength = leaders.length;
        uint256 sumPercentage;

        if (toLength == 0) {
            revert InvalidData();
        }

        if (toLength > LEADERS_LENGTH) {
            revert InvalidArrayLength();
        }

        if (toLength != percentages.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 j; j < toLength; ++j) {
            sumPercentage += percentages[j];
        }

        if (sumPercentage == 0) {
            revert ZeroValue();
        }

        if (sumPercentage > CLAIMS_PERCENTAGE_PPM) {
            revert InvalidPercentage();
        }

        transferInfo.equivalence = (amount * sumPercentage) / PPM;

        if (sumPercentage < CLAIMS_PERCENTAGE_PPM) {
            transferInfo.platformAmount += (((amount * CLAIMS_PERCENTAGE_PPM) / PPM) - transferInfo.equivalence);
        }
    }

    /// @dev Updates the amounts of agents
    /// @param leaders The indexes of leaders
    /// @param percentages The indexes of leaders percentage
    /// @param amount The amount used to calculate leaders comission
    /// @param round The round in which user wants to purchase
    /// @param token The token address in which comissions will be set
    function _updateCommissions(
        address[] memory leaders,
        uint256[] memory percentages,
        uint256 amount,
        uint32 round,
        IERC20 token
    ) private {
        uint256 toLength = leaders.length;
        ClaimInfo[] memory claimInfo = new ClaimInfo[](toLength);

        for (uint256 i = 0; i < toLength; ++i) {
            claimInfo[i] = ClaimInfo({ token: token, amount: (amount * percentages[i]) / PPM });
        }

        claimsContract.addClaimInfo(leaders, round, claimInfo);
    }
}