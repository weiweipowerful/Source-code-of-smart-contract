// SPDX-License-Identifier: GPL-3.0
// solhint-disable-next-line
pragma solidity 0.8.20;

import "./ERC721A.sol";
import "./interfaces/IERC20_USDT.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RoughRyderNFT is ERC721A, Ownable, ReentrancyGuard {
    using Strings for uint256;

    string baseURI;

    /// @notice Max supply of roughryder to be minted
    uint256 public constant MAX_SUPPLY = 3000;

    /// @notice Max supply of roughryder to be minted using ERC-20
    uint256 public nonEthMaxSupply = 500;

    /// @notice current supply of token minted using ERC-20
    uint256 public nonEthCurrentSupply = 0;

    /// @notice Max minting limit per wallet
    uint256 public totalMintLimit = 15;

    /// @notice Max minting limit using ERC20 per wallet
    uint256 public nonEthMintLimit = 3;

    /// @notice Timestamp of reveal date
    uint256 public revealTimestamp;

    /// @notice Maximum mint per tier per wallet
    uint256[] public maxMintPerTier = [5, 15, 15];

    /// @notice Signer address for encrypted signatures
    address public secret;

    /// @notice Address of treasury
    address public treasury;

    /// @notice USDT token address
    address public usdtTokenAddress =
        0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /// @notice Total NFT amount minted per wallet
    mapping(address => uint256) public totalMintedAmount;

    /// @notice NFT Amount minted per wallet using ERC20 tokens
    mapping(address => uint256) public nonEthMintedAmount;

    /// @notice Track ETH minted for each tier per wallet
    mapping(address => mapping(uint256 => uint256)) public ethMintedPerTier;

    /// @notice Whitelisted ERC20 that can bypass the nonEthMintLimit
    mapping(address => bool) public whitelistedERC20;

    /// @notice Refund flag for each roughryder
    mapping(uint256 => bool) public notRefundable;

    /// @notice Authorization flag for orchestrators
    mapping(address => bool) public isOrchestrator;

    /// @notice Mapping for used signatures
    mapping(bytes => bool) public usedSignatures;

    struct PurchaseInfo {
        uint256 quantity;
        address paymentToken;
        uint256 priceOrTier;
    }

    event Purchased(
        address operator,
        address user,
        uint256 currentSupply,
        PurchaseInfo[] purchases,
        uint256 timestamp
    );

    event Refunded(address user, uint256 tokenId);

    event Erc20TokenWhitelisted(address[] tokenAddresses, bool status);

    event MaxMintPerTierUpdated(uint256[] newMaxMintPerTier);

    event MintLimitChanged(
        uint256 newTotalMintLimit,
        uint256 newNonEthLimit,
        uint256 newNonEthMaxSupply,
        address operator
    );

    event Received(address, uint256);

    /// @param secretAddress Signer address
    /// @dev Create ERC721A token: Rough Ryders - RoughRyders
    constructor(address secretAddress) ERC721A("Rough Ryders", "RRYDER") {
        secret = secretAddress;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Check if caller is an orchestrator
    /// @dev Revert transaction is msg.sender is not Authorized
    modifier onlyOrchestrator() {
        require(isOrchestrator[msg.sender], "Operator not allowed");
        _;
    }

    /// @notice Check if the wallet is valid
    /// @dev Revert transaction if zero address
    modifier noZeroAddress(address _address) {
        require(_address != address(0), "Cannot send to zero address");
        _;
    }

    /// @notice Purchase an RoughRyder using whitelisted ECR20 tokens or ETH
    /// @param to Address to send the tokens
    /// @param totalQuantity Total amount of tokens to be minted
    /// @param purchases Array of PurchaseInfo struct
    /// @param signature Encrypted signature to verify the minting
    function purchase(
        address to,
        uint256 totalQuantity,
        PurchaseInfo[] memory purchases,
        bytes memory signature
    ) external payable {
        require(
            _verifyHashSignature(
                keccak256(abi.encode(to, purchases, msg.value)),
                signature
            ),
            "purchase: Signature is invalid"
        );
        require(
            totalMintedAmount[to] + totalQuantity <= totalMintLimit,
            "purchase: Exceed mint limit per wallet"
        );

        uint256 currentSupply = _totalMinted();

        require(
            totalQuantity + currentSupply <= MAX_SUPPLY,
            "purchase: Supply limit"
        );

        for (uint256 i = 0; i < purchases.length; i++) {
            PurchaseInfo memory purchaseInfo = purchases[i];

            _validateMintingParameters(
                to,
                purchaseInfo.paymentToken,
                purchaseInfo.priceOrTier,
                purchaseInfo.quantity
            );
        }

        totalMintedAmount[to] += totalQuantity;

        _safeMint(to, totalQuantity);

        emit Purchased(
            msg.sender,
            to,
            currentSupply,
            purchases,
            block.timestamp
        );
    }

    /// @notice Mint free RoughRyder for whitelisted addresses
    /// @param to Address to send the tokens
    /// @param quantity Amount of tokens to be minted
    /// @param signature Encrypted signature to verify the minting
    function claimFreeMint(
        address to,
        uint256 quantity,
        bytes memory signature
    ) external {
        require(
            _verifyHashSignature(
                keccak256(abi.encode(to, quantity, "Rough Ryders free mint")),
                signature
            ),
            "claimFreeMint: Signature is invalid"
        );
        require(!usedSignatures[signature], "claimFreeMint: Signature used");
        require(
            totalMintedAmount[to] + quantity <= totalMintLimit,
            "claimFreeMint: Exceed mint limit per wallet"
        );

        uint256 currentSupply = _totalMinted();

        // Create an array to store purchase information
        PurchaseInfo[] memory purchases = new PurchaseInfo[](1);

        // Add the purchase information to the array
        purchases[0] = PurchaseInfo(quantity, address(0), 3);

        require(
            quantity + currentSupply <= MAX_SUPPLY,
            "claimFreeMint: Supply limit"
        );

        usedSignatures[signature] = true;

        totalMintedAmount[to] += quantity;

        _safeMint(to, quantity);

        emit Purchased(
            msg.sender,
            to,
            currentSupply,
            purchases,
            block.timestamp
        );
    }

    /// @notice ETH back function
    /// @param depositAddress Address to refund the funds
    /// @param tokenId RoughRyder NFT ID to be refunded
    /// @param tokenAddress tokenAddress of the token to be refunded with
    /// @param balance balance to be refunded
    /// @dev Can only be called by authorized orchestrators during refund period
    function refund(
        address depositAddress,
        uint256 tokenId,
        address tokenAddress,
        uint256 balance
    ) external onlyOrchestrator noZeroAddress(depositAddress) {
        require(
            !notRefundable[tokenId],
            "Refund: The token is not available for refund"
        );
        require(
            ownerOf(tokenId) == depositAddress,
            "Refund: Address is not the token owner"
        );

        safeTransferFrom(depositAddress, treasury, tokenId);

        if (tokenAddress == address(0)) {
            (bool success, ) = depositAddress.call{value: balance}("");
            require(success, "Refund: ETH transfer failed");
        } else {
            require(
                IERC20(tokenAddress).transfer(depositAddress, balance),
                "Refund: ERC20 token transfer failed"
            );
        }

        emit Refunded(depositAddress, tokenId);
    }

    /// INTERNAL FUNCTIONS

    function _validateMintingParameters(
        address to,
        address tokenAddress,
        uint256 priceOrTier,
        uint256 quantity
    ) internal {
        if (tokenAddress == address(0)) {
            require(
                ethMintedPerTier[to][priceOrTier] + quantity <=
                    maxMintPerTier[priceOrTier],
                "_validateMintingParameters: Exceed tier mint limit"
            );
            ethMintedPerTier[to][priceOrTier] += quantity;
        } else {
            if (!whitelistedERC20[tokenAddress]) {
                require(
                    quantity + nonEthCurrentSupply <= nonEthMaxSupply,
                    "_validateMintingParameters: ERC-20 Supply limit exceed"
                );
                require(
                    nonEthMintedAmount[to] + quantity <= nonEthMintLimit,
                    "_validateMintingParameters: Exceed mint limit"
                );

                nonEthMintedAmount[to] += quantity;
                nonEthCurrentSupply += quantity;
            }

            if (usdtTokenAddress == tokenAddress) {
                IERC20_USDT(tokenAddress).transferFrom(
                    msg.sender,
                    address(this),
                    priceOrTier
                );
            } else {
                require(
                    IERC20(tokenAddress).transferFrom(
                        msg.sender,
                        address(this),
                        priceOrTier
                    ),
                    "_validateMintingParameters: Token transfer failed"
                );
            }
        }
    }

    /// @notice Verify that message is signed by secret wallet
    function _verifyHashSignature(
        bytes32 freshHash,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 hash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", freshHash)
        );

        bytes32 r;
        bytes32 s;
        uint8 v;

        if (signature.length != 65) {
            return false;
        }
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) {
            v += 27;
        }

        address signer = address(0);
        if (v == 27 || v == 28) {
            // solium-disable-next-line arg-overflow
            signer = ecrecover(hash, v, r, s);
        }
        return secret == signer;
    }

    /// OWNABLE FUNCTIONS

    function addWhitelistedERC20(
        address[] memory tokenAddresses,
        bool status
    ) external onlyOwner {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            whitelistedERC20[tokenAddresses[i]] = status;
        }

        emit Erc20TokenWhitelisted(tokenAddresses, status);
    }

    function setMintLimit(
        uint256 newTotalMintLimit,
        uint256 newNonEthLimit,
        uint256 newNonEthMaxSupply
    ) external onlyOwner {
        totalMintLimit = newTotalMintLimit;
        nonEthMintLimit = newNonEthLimit;
        nonEthMaxSupply = newNonEthMaxSupply;

        emit MintLimitChanged(
            newTotalMintLimit,
            newNonEthLimit,
            newNonEthMaxSupply,
            msg.sender
        );
    }

    function setMaxMintPerTier(
        uint256[] memory newMaxMintPerTier
    ) external onlyOwner {
        require(
            newMaxMintPerTier.length == maxMintPerTier.length,
            "Invalid array length"
        );

        for (uint256 i = 0; i < newMaxMintPerTier.length; i++) {
            maxMintPerTier[i] = newMaxMintPerTier[i];
        }

        emit MaxMintPerTierUpdated(newMaxMintPerTier);
    }

    /// @notice Change the Base URI
    /// @param newURI new URI to be set
    /// @dev Can only be called by the contract owner
    function setBaseURI(string memory newURI) external onlyOwner {
        baseURI = newURI;
    }

    /// @notice Change the signer address
    /// @param secretAddress new signer for encrypted signatures
    /// @dev Can only be called by the contract owner
    function setSecret(
        address secretAddress
    ) external onlyOwner noZeroAddress(secretAddress) {
        secret = secretAddress;
    }

    /// @notice Change the treasury address
    /// @param treasuryAddress new treasury address
    /// @dev Can only be called by the contract owner
    function setTreasury(
        address treasuryAddress
    ) external onlyOwner noZeroAddress(treasuryAddress) {
        treasury = treasuryAddress;
    }

    /// @notice Add new authorized orchestrators
    /// @param operator Orchestrator address
    /// @param status set authorization true or false
    /// @dev Can only be called by the contract owner
    function setOrchestrator(
        address operator,
        bool status
    ) external onlyOwner noZeroAddress(operator) {
        isOrchestrator[operator] = status;
    }

    /// @notice Set reveal timestamp
    /// @dev Can only be called by the contract owner
    function setRevealTimestamp() external onlyOwner {
        require(revealTimestamp == 0, "Reveal timestamp already set");
        revealTimestamp = block.timestamp;
    }

    /// @notice Send ETH to specific address
    /// @param to Address to send the funds
    /// @param amount ETH amount to be sent
    /// @dev Can only be called by the contract owner
    function withdrawETH(
        address to,
        uint256 amount
    ) public nonReentrant onlyOwner noZeroAddress(to) {
        require(amount <= address(this).balance, "Insufficient funds");

        (bool success, ) = to.call{value: amount}("");

        require(success, "withdrawETH: ETH transfer failed");
    }

    /// @notice Send ERC20 tokens to specific address
    /// @param to Address to send the funds
    /// @param tokenAddresses Addresses of the tokens to be sent
    /// @dev Can only be called by the contract owner
    function withdrawERC20(
        address to,
        address[] memory tokenAddresses
    ) public nonReentrant onlyOwner noZeroAddress(to) {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            IERC20 token = IERC20(tokenAddresses[i]);
            uint256 tokenBalance = token.balanceOf(address(this));
            if (tokenBalance > 0) {
                token.transfer(to, tokenBalance);
            }
        }
    }

    /// VIEW FUNCTIONS

    /// @notice Return total minted amount
    function minted() external view returns (uint256) {
        return _totalMinted();
    }

    /// @notice Return Base URI
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    /// @notice Inherit from ERC721, return token URI, revert is tokenId doesn't exist
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        return string(abi.encodePacked(baseURI, tokenId.toString()));
    }

    /// @notice Inherit from ERC721, checks if a token exists
    function exists(uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }

    /// OVERRIDE FUNCTIONS

    /// @notice Inherit from ERC721, added check of transfer period for refund
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        _checkTransferPeriod(tokenId);
        super.transferFrom(from, to, tokenId);
    }

    /// @notice Inherit from ERC721, added check of transfer period for refund
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        _checkTransferPeriod(tokenId);
        super.safeTransferFrom(from, to, tokenId, "");
    }

    /// @notice Checks transfer after allow period to invalidate refund
    function _checkTransferPeriod(uint256 tokenId) internal {
        if (
            !notRefundable[tokenId] &&
            revealTimestamp != 0 &&
            block.timestamp > revealTimestamp + 1 hours
        ) {
            notRefundable[tokenId] = true;
        }
    }
}