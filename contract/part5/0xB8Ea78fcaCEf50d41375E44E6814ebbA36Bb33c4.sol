// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "solady/tokens/ERC721.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ERC2981} from "solady/tokens/ERC2981.sol";

import {ICreatorToken} from "./interfaces/ICreatorToken.sol";
import {IGVC} from "./interfaces/IGVC.sol";

/**
 * @title GVC (Good Vibes Club)
 * @dev ERC721 token with:
 * - Minting controls
 * - Transfer controls
 * - Owner-managed URI
 * - ERC2981 royalties support
 * - ERC721C transfer validation support
 */
contract GVC is ERC721, Ownable, ERC2981, IGVC, ICreatorToken {
    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => bool) private minters;
    uint256 public immutable maxTokenCount;
    string public baseURI;
    bool public transfersDisabled;
    uint256 private currentSupply;

    // Transfer validator address
    address private validator;

    // Whether transfers from validator are automatically approved
    bool public autoApproveTransfersFromValidator;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MaxSupplyReached();
    error ThouShallNotMint();
    error TransfersDisabled();
    error ArrayLengthMismatch();
    error InvalidValidator();
    error ValidatorCalledFailed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AutomaticApprovalOfTransferValidatorSet(bool autoApproved);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyMinter() {
        require(minters[msg.sender], "Not authorized: Minter role required");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(uint256 _maxTokenCount, address _royaltyReceiver) {
        _initializeOwner(msg.sender);
        _setDefaultRoyalty(_royaltyReceiver, 500); // 5% royalty to owner
        minters[msg.sender] = true; // Owner is a minter by default
        transfersDisabled = true; // Transfers disabled by default
        maxTokenCount = _maxTokenCount;

        // Set default validator (LimitBreak's default validator)
        address defaultValidator = address(
            0x721C002B0059009a671D00aD1700c9748146cd1B
        );
        _setValidator(defaultValidator);
    }

    /*//////////////////////////////////////////////////////////////
                            MINTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function vibeMint(address to, uint256 quantity) public onlyMinter {
        if (currentSupply + quantity > maxTokenCount) revert MaxSupplyReached();

        unchecked {
            for (uint256 i = 1; i <= quantity; ++i) {
                _safeMint(to, currentSupply + i);
            }
        }
        currentSupply += quantity;
    }

    /// @dev Airdrop tokens to specified addresses with corresponding quantities
    /// @param accounts Array of addresses to receive tokens
    /// @param quantities Array of quantities for each address
    /// Requirements:
    /// - Caller must have minter role
    /// - Arrays must have matching lengths
    /// - Total quantity must not exceed max supply
    function airdrop(
        address[] calldata accounts,
        uint256[] calldata quantities
    ) external onlyMinter {
        uint256 len = accounts.length;
        if (len != quantities.length) revert ArrayLengthMismatch();

        uint256 totalQuantity;
        unchecked {
            for (uint256 i; i < len; ) {
                totalQuantity += quantities[i];
                ++i;
            }
        }

        if (currentSupply + totalQuantity > maxTokenCount)
            revert MaxSupplyReached();

        uint256 currentIndex = currentSupply;
        unchecked {
            for (uint256 i; i < len; ) {
                uint256 quantity = quantities[i];
                for (uint256 j = 1; j <= quantity; ) {
                    _safeMint(accounts[i], currentIndex + j);
                    ++j;
                }
                currentIndex += quantity;
                ++i;
            }
            currentSupply = currentIndex;
        }
    }

    /**
     * @dev Returns the total number of tokens minted since the start of the contract
     * @return The current token index
     */
    function totalSupply() external view returns (uint256) {
        return currentSupply;
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        // Allow minting (from = 0) and burning (to = 0) when transfers are disabled
        if (from != address(0) && to != address(0)) {
            // Check if transfers are disabled globally
            if (transfersDisabled) {
                revert TransfersDisabled();
            }

            // Validate transfer with validator if set and caller is not the validator
            address _validator = validator;
            if (_validator != address(0) && msg.sender != _validator) {
                (bool success, ) = _validator.call(
                    abi.encodeWithSignature(
                        "validateTransfer(address,address,address,uint256)",
                        msg.sender,
                        from,
                        to,
                        tokenId
                    )
                );
                if (!success) revert ValidatorCalledFailed();
            }
        }
    }

    /// @dev Override isApprovedForAll to auto-approve validator if configured
    function isApprovedForAll(
        address owner,
        address operator
    ) public view virtual override returns (bool isApproved) {
        isApproved = super.isApprovedForAll(owner, operator);
        if (!isApproved && autoApproveTransfersFromValidator) {
            isApproved = operator == address(validator);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             URI HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @dev The URI for a token.
    function tokenURI(uint256 id) public view override returns (string memory) {
        /// Revert if token `id` does not exist.
        if (_exists(id) == false) {
            revert TokenDoesNotExist();
        }
        return LibString.concat(baseURI, LibString.toString(id));
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    /*//////////////////////////////////////////////////////////////
                            ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function grantMinterRole(address _minter) external onlyOwner {
        minters[_minter] = true;
    }

    function revokeMinterRole(address _minter) external onlyOwner {
        minters[_minter] = false;
    }

    /*//////////////////////////////////////////////////////////////
                          TRANSFER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setTransfersEnabled() external onlyOwner {
        transfersDisabled = false;
    }

    /*//////////////////////////////////////////////////////////////
                       TRANSFER VALIDATOR FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the validator of the collection
    function getTransferValidator() public view returns (address) {
        return validator;
    }

    /// @dev Returns the function signature for transfer validation
    function getTransferValidationFunction()
        public
        pure
        returns (bytes4 functionSignature, bool isViewFunction)
    {
        functionSignature = bytes4(
            keccak256("validateTransfer(address,address,address,uint256)")
        );
        isViewFunction = true;
    }

    /// @dev Sets the validator for the collection
    function setTransferValidator(address _validator) external onlyOwner {
        _setValidator(_validator);
    }

    /// @dev Sets automatic approval for transfers from validator
    function setAutomaticApprovalOfTransfersFromValidator(
        bool autoApprove
    ) external onlyOwner {
        autoApproveTransfersFromValidator = autoApprove;
        emit AutomaticApprovalOfTransferValidatorSet(autoApprove);
    }

    /// @dev Internal function to set validator and register token type
    function _setValidator(address _validator) internal {
        emit TransferValidatorUpdated(validator, _validator);
        validator = _validator;

        if (_validator != address(0)) {
            // Register token type (721 for ERC721)
            (bool success, ) = _validator.call(
                abi.encodeWithSignature(
                    "setTokenTypeOfCollection(address,uint16)",
                    address(this),
                    721
                )
            );
            if (!success) revert InvalidValidator();
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 METADATA
    //////////////////////////////////////////////////////////////*/

    function name() public pure virtual override returns (string memory) {
        return "Good Vibes Club";
    }

    function symbol() public pure virtual override returns (string memory) {
        return "GVC";
    }

    /*//////////////////////////////////////////////////////////////
                            ROYALTY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Sets the royalty information for all tokens
    function setRoyaltyInfo(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721, ERC2981) returns (bool) {
        return
            type(ICreatorToken).interfaceId == interfaceId ||
            ERC721.supportsInterface(interfaceId) ||
            super.supportsInterface(interfaceId);
    }
}