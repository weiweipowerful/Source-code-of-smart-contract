/**
 *Submitted for verification at Etherscan.io on 2025-03-03
*/

// SPDX-License-Identifier: MIT
// File: @openzeppelin/contracts/security/ReentrancyGuard.sol


// OpenZeppelin Contracts (last updated v4.9.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.28;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

// File: NewProxy.sol


pragma solidity ^0.8.28;


interface INFTMintingContract {
    function batchMint(address[] calldata recipients) external;
    function batchMintMultiple(address[] calldata recipients, uint256 quantity) external;
    function pauseMint() external;
    function unpauseMint() external;
    function setBaseURI(string calldata newBaseURI) external;
    function setMarketplaceListingEnabled(bool enabled) external;
    function setMaxMintPerWallet(uint256 newMaxMintPerWallet) external;
    function transferOwnership(address newOwner) external;
    function totalSupply() external view returns (uint256);
}

contract BatchMintProxy is ReentrancyGuard {
    INFTMintingContract public nftContract;
    address public owner;

    // Tiered mint prices (in wei)
    uint256 public publicMintPrice;
    uint256 public whitelistMintPrice;

    // Whitelist functionality.
    bool public whitelistEnabled;
    mapping(address => bool) public whitelist;

    // Mint pause control for the proxy.
    bool public mintPaused;

    // ========== Events ==========
    event MintMultiple(address indexed user, uint256 quantity);
    event OwnershipReturned(address indexed newOwner);
    event PublicMintPriceUpdated(uint256 newPrice);
    event WhitelistMintPriceUpdated(uint256 newPrice);
    event WhitelistStatusChanged(bool enabled);
    event AddressWhitelisted(address indexed addr);
    event AddressRemovedFromWhitelist(address indexed addr);
    event BatchAddressesWhitelisted(address[] addrs);
    event BatchAddressesRemoved(address[] addrs);
    event MintPaused();
    event MintUnpaused();
    event BaseURIUpdated(string newBaseURI);
    event MarketplaceListingStatusChanged(bool enabled);
    event MaxMintPerWalletUpdated(uint256 newMaxMintPerWallet);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _nftContractAddress, uint256 _publicMintPrice, uint256 _whitelistMintPrice) {
        nftContract = INFTMintingContract(_nftContractAddress);
        owner = msg.sender;
        publicMintPrice = _publicMintPrice;
        whitelistMintPrice = _whitelistMintPrice;
        // By default, whitelist enforcement is off and minting is not paused.
        whitelistEnabled = false;
        mintPaused = false;
    }

    /**
     * @notice Allows a user to mint multiple NFTs in one transaction.
     * The required ETH is calculated as:
     * - quantity * whitelistMintPrice if whitelist is enabled and the user is whitelisted,
     * - otherwise quantity * publicMintPrice.
     * @param quantity The number of NFTs the user wishes to mint.
     */
    function mintMultiple(uint256 quantity) external payable nonReentrant {
        require(!mintPaused, "Minting is paused"); // New check on the proxy level.
        require(quantity > 0, "Quantity must be positive");

        uint256 price = publicMintPrice;
        if (whitelistEnabled && whitelist[msg.sender]) {
            price = whitelistMintPrice;
        }
        require(msg.value >= quantity * price, "Insufficient payment");

        // Build an array with the caller's address repeated 'quantity' times.
        address[] memory recipients = new address[](quantity);
        for (uint256 i = 0; i < quantity; i++) {
            recipients[i] = msg.sender;
        }
        nftContract.batchMint(recipients);
        emit MintMultiple(msg.sender, quantity);
    }

    // ========== Administrative Wrapper Functions ==========
    function batchMintMultiple(address[] calldata recipients, uint256 quantity) external onlyOwner nonReentrant {
        nftContract.batchMintMultiple(recipients, quantity);
    }

    function pauseMint() external onlyOwner nonReentrant {
        nftContract.pauseMint();
        emit MintPaused();
    }

    function unpauseMint() external onlyOwner nonReentrant {
        nftContract.unpauseMint();
        emit MintUnpaused();
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner nonReentrant {
        nftContract.setBaseURI(newBaseURI);
        emit BaseURIUpdated(newBaseURI);
    }

    function setMarketplaceListingEnabled(bool enabled) external onlyOwner nonReentrant {
        nftContract.setMarketplaceListingEnabled(enabled);
        emit MarketplaceListingStatusChanged(enabled);
    }

    function setMaxMintPerWallet(uint256 newMaxMintPerWallet) external onlyOwner nonReentrant {
        nftContract.setMaxMintPerWallet(newMaxMintPerWallet);
        emit MaxMintPerWalletUpdated(newMaxMintPerWallet);
    }

    // Tiered pricing and whitelist management wrappers.
    function setPublicMintPrice(uint256 newPrice) external onlyOwner {
        publicMintPrice = newPrice;
        emit PublicMintPriceUpdated(newPrice);
    }

    function setWhitelistMintPrice(uint256 newPrice) external onlyOwner {
        whitelistMintPrice = newPrice;
        emit WhitelistMintPriceUpdated(newPrice);
    }

    function setWhitelistEnabled(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
        emit WhitelistStatusChanged(enabled);
    }

    function addToWhitelist(address _addr) external onlyOwner {
        whitelist[_addr] = true;
        emit AddressWhitelisted(_addr);
    }

    function removeFromWhitelist(address _addr) external onlyOwner {
        whitelist[_addr] = false;
        emit AddressRemovedFromWhitelist(_addr);
    }

    function batchAddToWhitelist(address[] calldata addrs) external onlyOwner {
        uint256 len = addrs.length;
        for (uint256 i = 0; i < len; i++) {
            whitelist[addrs[i]] = true;
        }
        emit BatchAddressesWhitelisted(addrs);
    }

    function batchRemoveFromWhitelist(address[] calldata addrs) external onlyOwner {
        uint256 len = addrs.length;
        for (uint256 i = 0; i < len; i++) {
            whitelist[addrs[i]] = false;
        }
        emit BatchAddressesRemoved(addrs);
    }

    // ========== Ownership & Withdraw Wrappers ==========
    function returnOwnership(address newOwner) external onlyOwner nonReentrant {
        require(newOwner != address(0), "Invalid new owner");
        nftContract.transferOwnership(newOwner);
        emit OwnershipReturned(newOwner);
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    // ========== Proxy Mint Pause Control ==========
    /**
     * @notice Sets the proxy minting pause state.
     * @param paused True to pause minting; false to unpause.
     */
    function setMintPaused(bool paused) external onlyOwner nonReentrant {
        mintPaused = paused;
        if (paused) {
            emit MintPaused();
        } else {
            emit MintUnpaused();
        }
    }
}