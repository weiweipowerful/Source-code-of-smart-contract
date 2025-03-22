// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IClaims, ClaimInfo } from "./interfaces/IClaims.sol";
import { ITokenRegistry } from "./interfaces/ITokenRegistry.sol";
import { IMinerNft } from "./interfaces/IMinerNft.sol";
import { INodeNft } from "./interfaces/INodeNft.sol";

import { PPM, ETH, ZeroAddress, IdenticalValue, ArrayLengthMismatch, InvalidSignature, InvalidData, TokenInfo } from "./utils/Common.sol";

/// @title PreSale contract
/// @notice Implements presale of the node and miner nfts
/// @dev The presale contract allows you to purchase nodes and miners
contract PreSale is Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @dev The maximum discount percentage, applied to those purchasing with leader's code
    uint256 private constant DISCOUNT_PERCENTAGE_PPM = 500_000;

    /// @dev The constant value of one million in dollars
    uint256 private constant ONE_MILLION_DOLLAR = 1_000_000e6;

    /// @dev The max length of the leaders array
    uint256 private constant LEADERS_LENGTH = 5;

    /// @notice The maximum amount of money project hopes to raise
    uint256 public constant MAX_CAP = 40_000_000e6;

    /// @notice The maximum percentage of the leader's commissions
    uint256 public constant CLAIMS_PERCENTAGE_PPM = 250_000;

    /// @notice The address of claims contract
    IClaims public immutable claimsContract;

    /// @notice The address of the miner nft contract
    IMinerNft public immutable minerNft;

    /// @notice The address of the node nft contract
    INodeNft public immutable nodeNft;

    /// @notice The total usd raised
    uint256 public totalRaised;

    /// @notice The total purchases upto 1 million usd, it will reset after every million cap increased
    uint256 public accretionThreshold;

    /// @notice The insurance fee in PPM
    uint256 public insuranceFeePPM;

    /// @notice That buyEnabled or not
    bool public buyEnabled = true;

    /// @notice The address of the token registry contract
    ITokenRegistry public tokenRegistry;

    /// @notice The address of the signer wallet
    address public signerWallet;

    /// @notice The address of the node funds wallet
    address public nodeFundsWallet;

    /// @notice The address of the miner funds wallet
    address public minerFundsWallet;

    /// @notice The address of the insurance funds wallet
    address public insuranceFundsWallet;

    /// @notice The price of the node nft
    uint256 public nodeNFTPrice;

    /// @notice The miner price will be increased to this percent after every million raised
    uint256 public priceAccretionPercentagePPM;

    /// @notice The prices of the miner nfts
    uint256[3] public minerNFTPrices;

    /// @notice Gives info about address's permission
    mapping(address => bool) public blacklistAddress;

    /// @notice Gives access info of the given token
    mapping(IERC20 => bool) public allowedTokens;

    /// @dev Emitted when address of signer is updated
    event SignerUpdated(address oldSigner, address newSigner);

    /// @dev Emitted when address of node funds wallet is updated
    event NodeFundsWalletUpdated(address oldNodeFundsWallet, address newNodeFundsWallet);

    /// @dev Emitted when address of miner funds wallet is updated
    event MinerFundsWalletUpdated(address oldMinerFundsWallet, address newMinerFundsWallet);

    /// @dev Emitted when address of insurance funds wallet is updated
    event InsuranceFundsWalletUpdated(address oldInsuranceFundsWallet, address newInsuranceFundsWallet);

    /// @dev Emitted when blacklist access of address is updated
    event BlacklistUpdated(address which, bool accessNow);

    /// @dev Emitted when buying access changes
    event BuyEnableUpdated(bool oldAccess, bool newAccess);

    /// @dev Emitted when token's access is updated
    event AllowedTokenUpdated(IERC20 token, bool status);

    /// @dev Emitted when address of token registry contract is updated
    event TokenRegistryUpdated(ITokenRegistry oldTokenRegistry, ITokenRegistry newTokenRegistry);

    /// @dev Emitted when miner price accretion percentage is updated
    event PriceAccretionPercentageUpdated(uint256 oldPriceAccretionPercent, uint256 newPriceAccretionPercent);

    /// @dev Emitted when node price is updated
    event NodeNftPriceUpdated(uint256 oldPrice, uint256 newPrice);

    /// @dev Emitted when insurance fee is updated
    event InsuranceFeeUpdated(uint256 oldInsuranceFee, uint256 newInsuranceFee);

    /// @dev Emitted when node is purchased
    event NodeNftPurchased(IERC20 token, uint256 tokenPrice, address by, uint256 amountPurchased, uint256 quantity);

    /// @dev Emitted when miner is purchased
    event MinerNftPurchased(
        IERC20 token,
        uint256 tokenPrice,
        address by,
        uint256[3] minerPrices,
        uint256[3] quantities,
        uint256 amountPurchased,
        bool isInsured,
        uint256 insuranceAmount
    );

    /// @dev Emitted when miner is purchased on discounted price
    event MinerNftPurchasedDiscounted(
        IERC20 token,
        uint256 tokenPrice,
        address indexed by,
        uint256[3] minerPrices,
        uint256[3] quantities,
        string code,
        uint256 amountPurchased,
        address[] leaders,
        uint256[] percentages,
        uint256 discountPercentage,
        bool isInsured,
        uint256 insuranceAmount
    );

    /// @notice Thrown when address is blacklisted
    error Blacklisted();

    /// @notice Thrown when buy is disabled
    error BuyNotEnabled();

    /// @notice Thrown when sign deadline is expired
    error DeadlineExpired();

    /// @notice Thrown when value to transfer/updating is zero
    error ZeroValue();

    /// @notice Thrown when MAX_CAP is reached
    error MaxCapReached();

    /// @notice Thrown when both price feed and reference price are non zero
    error CodeSyncIssue();

    /// @notice Thrown if the sum of agents percentage is greater than required
    error InvalidPercentage();

    /// @notice Thrown when array length of leaders are greater than required
    error InvalidArrayLength();

    /// @notice Thrown when token is not allowed to use for purchases
    error TokenNotAllowed();

    /// @notice Thrown when discount percentage is invalid
    error InvalidDiscount();

    /// @dev Restricts when updating wallet/contract address with zero address
    modifier checkAddressZero(address which) {
        _checkAddressZero(which);
        _;
    }

    /// @dev Checks buyEnabled,token allowed, user not blacklisted and time less than deadline, if not then reverts
    modifier canBuy(IERC20 token, uint256 deadline) {
        _canBuy(token, deadline);
        _;
    }

    /// @dev Constructor
    /// @param nodeFundsWalletAddress The address of node funds wallet
    /// @param minerFundsWalletAddress The address of miner funds wallet
    /// @param insuranceFundsWalletAddress The address of insurance funds wallet
    /// @param signerAddress The address of signer wallet
    /// @param owner The address of owner wallet
    /// @param claimsAddress The address of claim contract
    /// @param minerNftAddress The address of miner nft contract
    /// @param nodeNftAddress The address of node nft contract
    /// @param tokenRegistryAddress The address of token registry contract
    /// @param nodeNftPriceInit The price of node nft
    /// @param prevAccretionThreshold The previous raised amount to check price accretion
    /// @param prevTotalRaised The previous raised amount
    /// @param priceAccretionPercentagePPMInit The price accretion percentage value, it can be zero
    /// @param insuranceFeePPMInit The insurance fee
    /// @param minerNftPricesInit The prices of miner nfts
    constructor(
        address nodeFundsWalletAddress,
        address minerFundsWalletAddress,
        address insuranceFundsWalletAddress,
        address signerAddress,
        address owner,
        IClaims claimsAddress,
        IMinerNft minerNftAddress,
        INodeNft nodeNftAddress,
        ITokenRegistry tokenRegistryAddress,
        uint256 nodeNftPriceInit,
        uint256 prevAccretionThreshold,
        uint256 prevTotalRaised,
        uint256 priceAccretionPercentagePPMInit,
        uint256 insuranceFeePPMInit,
        uint256[3] memory minerNftPricesInit
    )
        Ownable(owner)
        checkAddressZero(nodeFundsWalletAddress)
        checkAddressZero(minerFundsWalletAddress)
        checkAddressZero(insuranceFundsWalletAddress)
        checkAddressZero(signerAddress)
        checkAddressZero(address(claimsAddress))
        checkAddressZero(address(minerNftAddress))
        checkAddressZero(address(nodeNftAddress))
        checkAddressZero(address(tokenRegistryAddress))
    {
        if (nodeNftPriceInit == 0 || insuranceFeePPMInit == 0) {
            revert ZeroValue();
        }

        for (uint256 i; i < minerNftPricesInit.length; ++i) {
            if (minerNftPricesInit[i] == 0) {
                revert ZeroValue();
            }
        }

        nodeFundsWallet = nodeFundsWalletAddress;
        minerFundsWallet = minerFundsWalletAddress;
        insuranceFundsWallet = insuranceFundsWalletAddress;
        signerWallet = signerAddress;
        claimsContract = claimsAddress;
        minerNft = minerNftAddress;
        nodeNft = nodeNftAddress;
        tokenRegistry = tokenRegistryAddress;
        nodeNFTPrice = nodeNftPriceInit;
        priceAccretionPercentagePPM = priceAccretionPercentagePPMInit;
        minerNFTPrices = minerNftPricesInit;
        accretionThreshold = prevAccretionThreshold;
        insuranceFeePPM = insuranceFeePPMInit;
        totalRaised = prevTotalRaised;
    }

    /// @notice Purchases node with any token
    /// @param token The token used in the purchase
    /// @param quantity The amounts of nodes to purchase
    /// @param referenceTokenPrice The current price of token in 10 decimals
    /// @param deadline The deadline is validity of the signature
    /// @param referenceNormalizationFactor The normalization factor
    /// @param v The `v` signature parameter
    /// @param r The `r` signature parameter
    /// @param s The `s` signature parameter
    function purchaseNodeNFT(
        IERC20 token,
        uint256 quantity,
        uint256 referenceTokenPrice,
        uint256 deadline,
        uint8 referenceNormalizationFactor,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable canBuy(token, deadline) nonReentrant {
        // The input must have been signed by the presale signer
        _verifySignature(
            keccak256(abi.encodePacked(msg.sender, referenceNormalizationFactor, referenceTokenPrice, deadline, token)),
            v,
            r,
            s
        );

        (uint256 latestPrice, uint8 normalizationFactor) = _validatePrice(
            token,
            referenceTokenPrice,
            referenceNormalizationFactor
        );

        uint256 purchaseAmount = (quantity * nodeNFTPrice * (10 ** normalizationFactor)) / latestPrice;

        _checkZeroValue(purchaseAmount);

        if (token == ETH) {
            payable(nodeFundsWallet).sendValue(purchaseAmount);

            if (msg.value > purchaseAmount) {
                payable(msg.sender).sendValue(msg.value - purchaseAmount);
            }
        } else {
            token.safeTransferFrom(msg.sender, nodeFundsWallet, purchaseAmount);
        }

        nodeNft.mint(msg.sender, quantity);

        emit NodeNftPurchased({
            token: token,
            tokenPrice: latestPrice,
            by: msg.sender,
            amountPurchased: purchaseAmount,
            quantity: quantity
        });
    }

    /// @notice Purchases miner with any token
    /// @param token The token used in the purchase
    /// @param referenceTokenPrice The current price of token in 10 decimals
    /// @param deadline The deadline is validity of the signature
    /// @param quantities The amount of each miner that you want to purchase
    /// @param referenceNormalizationFactor The normalization factor
    /// @param isInsured The decision about insurance
    /// @param v The `v` signature parameter
    /// @param r The `r` signature parameter
    /// @param s The `s` signature parameter
    function purchaseMinerNFT(
        IERC20 token,
        uint256 referenceTokenPrice,
        uint256 deadline,
        uint256[3] calldata quantities,
        uint8 referenceNormalizationFactor,
        bool isInsured,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable canBuy(token, deadline) nonReentrant {
        // The input must have been signed by the presale signer
        _verifySignature(
            keccak256(
                abi.encodePacked(
                    msg.sender,
                    referenceNormalizationFactor,
                    referenceTokenPrice,
                    deadline,
                    token,
                    isInsured
                )
            ),
            v,
            r,
            s
        );

        uint256[3] memory minerPrices = minerNFTPrices;
        (uint256 purchaseAmount, uint256 latestPrice, uint256 insuranceAmount) = _processPurchase(
            token,
            referenceTokenPrice,
            0,
            quantities,
            referenceNormalizationFactor,
            isInsured
        );

        if (token == ETH) {
            if (isInsured) {
                payable(insuranceFundsWallet).sendValue(insuranceAmount);
            }

            payable(minerFundsWallet).sendValue(purchaseAmount);

            if (msg.value > (purchaseAmount + insuranceAmount)) {
                payable(msg.sender).sendValue(msg.value - (purchaseAmount + insuranceAmount));
            }
        } else {
            if (isInsured) {
                token.safeTransferFrom(msg.sender, insuranceFundsWallet, insuranceAmount);
            }

            token.safeTransferFrom(msg.sender, minerFundsWallet, purchaseAmount);
        }

        emit MinerNftPurchased({
            token: token,
            tokenPrice: latestPrice,
            by: msg.sender,
            minerPrices: minerPrices,
            quantities: quantities,
            amountPurchased: purchaseAmount,
            isInsured: isInsured,
            insuranceAmount: insuranceAmount
        });
    }

    /// @notice Purchases miner on discounted price
    /// @param token The token used in the purchase
    /// @param referenceTokenPrice The current price of token in 10 decimals
    /// @param deadline The deadline is validity of the signature
    /// @param discountPercentagePPM The discount percentage, applied to purchase
    /// @param quantities The amount of each miner that you want to purchase
    /// @param percentages The leader's percentages
    /// @param leaders The addresses of the leaders
    /// @param referenceNormalizationFactor The normalization factor
    /// @param isInsured The decision about insurance
    /// @param code The code is used to verify signature of the user
    /// @param v The `v` signature parameter
    /// @param r The `r` signature parameter
    /// @param s The `s` signature parameter
    function purchaseMinerNFTDiscount(
        IERC20 token,
        uint256 referenceTokenPrice,
        uint256 deadline,
        uint256 discountPercentagePPM,
        uint256[3] calldata quantities,
        uint256[] calldata percentages,
        address[] calldata leaders,
        uint8 referenceNormalizationFactor,
        bool isInsured,
        string memory code,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable canBuy(token, deadline) nonReentrant {
        // The input must have been signed by the presale signer
        _verifySignature(
            keccak256(
                abi.encodePacked(
                    msg.sender,
                    code,
                    percentages,
                    leaders,
                    discountPercentagePPM,
                    referenceNormalizationFactor,
                    referenceTokenPrice,
                    deadline,
                    token,
                    isInsured
                )
            ),
            v,
            r,
            s
        );

        uint256[3] memory minerPrices = minerNFTPrices;
        (uint256 purchaseAmount, uint256 latestPrice, uint256 insuranceAmount) = _processPurchase(
            token,
            referenceTokenPrice,
            discountPercentagePPM,
            quantities,
            referenceNormalizationFactor,
            isInsured
        );

        _transferAndUpdateCommissions(token, purchaseAmount, leaders, percentages, insuranceAmount, isInsured);

        emit MinerNftPurchasedDiscounted({
            token: token,
            tokenPrice: latestPrice,
            by: msg.sender,
            minerPrices: minerPrices,
            quantities: quantities,
            code: code,
            amountPurchased: purchaseAmount,
            leaders: leaders,
            percentages: percentages,
            discountPercentage: discountPercentagePPM,
            isInsured: isInsured,
            insuranceAmount: insuranceAmount
        });
    }

    /// @dev Processes miner nft purchase
    function _processPurchase(
        IERC20 token,
        uint256 referenceTokenPrice,
        uint256 discountPercentagePPM,
        uint256[3] calldata quantities,
        uint8 referenceNormalizationFactor,
        bool isInsured
    ) private returns (uint256, uint256, uint256) {
        (uint256 latestPrice, uint8 normalizationFactor) = _validatePrice(
            token,
            referenceTokenPrice,
            referenceNormalizationFactor
        );

        uint256 prices;
        uint256 insuranceAmount;
        uint256 quantityLength = quantities.length;
        uint256[3] memory minerPrices = minerNFTPrices;

        for (uint256 i; i < quantityLength; ++i) {
            uint256 quantity = quantities[i];

            if (quantity > 0) {
                prices += (minerPrices[i] * quantity);
                minerNft.mint(msg.sender, i, quantity);
            }
        }

        _checkZeroValue(prices);

        if (discountPercentagePPM != 0) {
            if (discountPercentagePPM > DISCOUNT_PERCENTAGE_PPM) {
                revert InvalidDiscount();
            }

            prices -= (prices * discountPercentagePPM) / PPM;
        }

        if (isInsured) {
            insuranceAmount = (prices * insuranceFeePPM) / PPM;
        }

        totalRaised += prices;

        if (totalRaised >= MAX_CAP) {
            revert MaxCapReached();
        }

        uint256 raised = accretionThreshold += prices;

        if (raised >= ONE_MILLION_DOLLAR) {
            uint256 repetitions = raised / ONE_MILLION_DOLLAR;
            accretionThreshold -= ONE_MILLION_DOLLAR * repetitions;

            for (uint256 i; i < quantityLength; ++i) {
                for (uint256 j; j < repetitions; ++j) {
                    minerNFTPrices[i] += (minerNFTPrices[i] * priceAccretionPercentagePPM) / PPM;
                }
            }
        }

        return (
            (prices * (10 ** normalizationFactor)) / latestPrice,
            latestPrice,
            (insuranceAmount * (10 ** normalizationFactor)) / latestPrice
        );
    }

    /// @notice Changes token registry contract address
    /// @param newTokenRegistry The address of the new token registry contract
    function updateTokenRegistry(
        ITokenRegistry newTokenRegistry
    ) external checkAddressZero(address(newTokenRegistry)) onlyOwner {
        ITokenRegistry oldTokenRegistry = tokenRegistry;

        if (oldTokenRegistry == newTokenRegistry) {
            revert IdenticalValue();
        }

        emit TokenRegistryUpdated({ oldTokenRegistry: oldTokenRegistry, newTokenRegistry: newTokenRegistry });

        tokenRegistry = newTokenRegistry;
    }

    /// @notice Changes the miner price accretion percentage
    /// @param newPriceAccretionPercent The new price accretion percentage value
    function updateMinerPriceAccretionPercent(uint256 newPriceAccretionPercent) external onlyOwner {
        uint256 oldPriceAccretionPercent = priceAccretionPercentagePPM;

        if (newPriceAccretionPercent == oldPriceAccretionPercent) {
            revert IdenticalValue();
        }

        emit PriceAccretionPercentageUpdated({
            oldPriceAccretionPercent: oldPriceAccretionPercent,
            newPriceAccretionPercent: newPriceAccretionPercent
        });

        priceAccretionPercentagePPM = newPriceAccretionPercent;
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

    /// @notice Changes node funds wallet address
    /// @param newNodeFundsWallet The address of the new funds wallet
    function updateNodeFundsWallet(address newNodeFundsWallet) external checkAddressZero(newNodeFundsWallet) onlyOwner {
        address oldNodeFundsWallet = nodeFundsWallet;

        if (oldNodeFundsWallet == newNodeFundsWallet) {
            revert IdenticalValue();
        }

        emit NodeFundsWalletUpdated({ oldNodeFundsWallet: oldNodeFundsWallet, newNodeFundsWallet: newNodeFundsWallet });

        nodeFundsWallet = newNodeFundsWallet;
    }

    /// @notice Changes miner funds wallet address
    /// @param newMinerFundsWallet The address of the new funds wallet
    function updateMinerFundsWallet(
        address newMinerFundsWallet
    ) external checkAddressZero(newMinerFundsWallet) onlyOwner {
        address oldMinerFundsWallet = minerFundsWallet;

        if (oldMinerFundsWallet == newMinerFundsWallet) {
            revert IdenticalValue();
        }

        emit MinerFundsWalletUpdated({
            oldMinerFundsWallet: oldMinerFundsWallet,
            newMinerFundsWallet: newMinerFundsWallet
        });

        minerFundsWallet = newMinerFundsWallet;
    }

    /// @notice Changes miner funds wallet address
    /// @param newInsuranceFundsWallet The address of the new insurance funds wallet
    function updateInsuranceFundsWallet(
        address newInsuranceFundsWallet
    ) external checkAddressZero(newInsuranceFundsWallet) onlyOwner {
        address oldInsuranceFundsWallet = insuranceFundsWallet;

        if (oldInsuranceFundsWallet == newInsuranceFundsWallet) {
            revert IdenticalValue();
        }

        emit InsuranceFundsWalletUpdated({
            oldInsuranceFundsWallet: oldInsuranceFundsWallet,
            newInsuranceFundsWallet: newInsuranceFundsWallet
        });

        insuranceFundsWallet = newInsuranceFundsWallet;
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

    /// @notice Changes the node nft prices
    /// @param newPrice The new price of node nft
    function updateNodeNftPrice(uint256 newPrice) external onlyOwner {
        uint256 oldPrice = nodeNFTPrice;

        if (newPrice == oldPrice) {
            revert IdenticalValue();
        }

        if (newPrice == 0) {
            revert ZeroValue();
        }

        emit NodeNftPriceUpdated({ oldPrice: oldPrice, newPrice: newPrice });

        nodeNFTPrice = newPrice;
    }

    /// @notice Changes the insurance
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

    /// @notice Updates the status of the tokens for purchases
    /// @param tokens The addresses of the tokens
    /// @param statuses The updated status of the tokens
    function updateAllowedTokens(IERC20[] calldata tokens, bool[] calldata statuses) external onlyOwner {
        uint256 tokensLength = tokens.length;

        if (tokensLength != statuses.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i; i < tokensLength; ++i) {
            IERC20 token = tokens[i];
            bool status = statuses[i];

            if (address(token) == address(0)) {
                revert ZeroAddress();
            }

            if (allowedTokens[token] == status) {
                revert IdenticalValue();
            }

            allowedTokens[token] = status;

            emit AllowedTokenUpdated({ token: token, status: status });
        }
    }

    /// @dev Checks value, if zero then reverts
    function _checkZeroValue(uint256 value) private pure {
        if (value == 0) {
            revert ZeroValue();
        }
    }

    /// @dev Verifies the address that signed a hashed message (`hash`) with `signature`
    function _verifySignature(bytes32 encodedMessageHash, uint8 v, bytes32 r, bytes32 s) private view {
        if (signerWallet != ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(encodedMessageHash), v, r, s)) {
            revert InvalidSignature();
        }
    }

    /// @dev Provides us live price of token from price feed or returns reference price and reverts if price is zero
    function _validatePrice(
        IERC20 token,
        uint256 referenceTokenPrice,
        uint8 referenceNormalizationFactor
    ) private view returns (uint256, uint8) {
        TokenInfo memory tokenInfo = tokenRegistry.getLatestPrice(token);
        if (tokenInfo.latestPrice != 0) {
            if (referenceTokenPrice != 0 || referenceNormalizationFactor != 0) {
                revert CodeSyncIssue();
            }
        }
        //  If price feed isn't available, we fallback to the reference price
        if (tokenInfo.latestPrice == 0) {
            if (referenceTokenPrice == 0 || referenceNormalizationFactor == 0) {
                revert ZeroValue();
            }

            tokenInfo.latestPrice = referenceTokenPrice;
            tokenInfo.normalizationFactor = referenceNormalizationFactor;
        }

        return (tokenInfo.latestPrice, tokenInfo.normalizationFactor);
    }

    /// @dev Checks zero address, if zero then reverts
    /// @param which The `which` address to check for zero address
    function _checkAddressZero(address which) private pure {
        if (which == address(0)) {
            revert ZeroAddress();
        }
    }

    /// @dev Checks buyEnabled,token allowed, user not blacklisted and time less than deadline, if not then reverts
    function _canBuy(IERC20 token, uint256 deadline) private view {
        if (!buyEnabled) {
            revert BuyNotEnabled();
        }

        if (blacklistAddress[msg.sender]) {
            revert Blacklisted();
        }

        if (!allowedTokens[token]) {
            revert TokenNotAllowed();
        }

        if (block.timestamp > deadline) {
            revert DeadlineExpired();
        }
    }

    /// @dev Calculates,transfers and update commissions
    function _transferAndUpdateCommissions(
        IERC20 token,
        uint256 amount,
        address[] calldata leaders,
        uint256[] calldata percentages,
        uint256 insuranceAmount,
        bool isInsured
    ) private {
        uint256 toLength = leaders.length;

        if (toLength == 0) {
            revert InvalidData();
        }

        if (toLength > LEADERS_LENGTH) {
            revert InvalidArrayLength();
        }

        if (toLength != percentages.length) {
            revert ArrayLengthMismatch();
        }

        ClaimInfo[] memory claimInfo = new ClaimInfo[](toLength);

        uint256 sumPercentage;

        for (uint256 i; i < toLength; ++i) {
            uint256 percentage = percentages[i];
            sumPercentage += percentage;
            claimInfo[i] = ClaimInfo({ token: token, amount: (amount * percentage) / PPM });
        }

        if (sumPercentage == 0) {
            revert ZeroValue();
        }

        if (sumPercentage > CLAIMS_PERCENTAGE_PPM) {
            revert InvalidPercentage();
        }

        uint256 equivalence = (amount * sumPercentage) / PPM;
        amount -= equivalence;

        if (token == ETH) {
            if (isInsured) {
                payable(insuranceFundsWallet).sendValue(insuranceAmount);
            }

            payable(minerFundsWallet).sendValue(amount);
            payable(address(claimsContract)).sendValue(equivalence);

            if (msg.value > (amount + equivalence + insuranceAmount)) {
                payable(msg.sender).sendValue(msg.value - (amount + equivalence + insuranceAmount));
            }
        } else {
            if (isInsured) {
                token.safeTransferFrom(msg.sender, insuranceFundsWallet, insuranceAmount);
            }

            token.safeTransferFrom(msg.sender, minerFundsWallet, amount);
            token.safeTransferFrom(msg.sender, address(claimsContract), equivalence);
        }

        claimsContract.addClaimInfo(leaders, claimInfo);
    }
}