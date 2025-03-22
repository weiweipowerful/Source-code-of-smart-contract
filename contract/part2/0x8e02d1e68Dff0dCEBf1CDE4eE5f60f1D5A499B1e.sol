// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "solady/tokens/ERC721.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";

/// @author Onchain Heroes (https://onchainheroes.xyz/)
contract GenesisRing is Ownable, ReentrancyGuardTransient, ERC721 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The Merkle proof is not valid.
    error IncorrectProof();

    /// @dev The user already minted for phase.
    error AlreadyMinted();

    /// @dev The `msg.value` is incorrect.
    error IncorrectPrice();

    /// @dev The public sale is started.
    error PublicSaleStarted();

    /// @dev The phase not started yet.
    error NotStarted();

    /// @dev The total supply reached MAX_SUPPLY.
    error MaxSupplyReached();

    /// @dev Can't allow to do action.
    error NotAllowed();

    /// @dev The minting phase has started.
    error PhaseAlreadyStarted();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Maximum supply of tokens.
    uint64 public constant MAX_SUPPLY = 1000;

    /// @dev Current supply of tokens.
    uint64 public currentSupply;

    /// @dev Mint price for a mint.
    uint64 public mintPrice;

    /// @dev OG whitelist mint start timestamp.
    uint40 public OG_MINT_TIMESTAMP;

    /// @dev Hero whitelist mint start timestamp.
    uint40 public HERO_MINT_TIMESTAMP;

    /// @dev Public sale mint start timestamp.
    uint40 public PUBLIC_MINT_TIMESTAMP;

    /// @dev Flag for a allow to transfer/trade.
    uint8 startTransfer;

    /// @dev The merkle root for og whiltelist.
    bytes32 public ogMerkleRoot;

    /// @dev The merkle root for hero whitelist.
    bytes32 public heroMerkleRoot;

    /// @dev The baseURI for a token.
    string internal baseURI;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(bytes32 ogMerkleRoot_, bytes32 heroMerkleRoot_, uint64 mintPrice_) {
        ogMerkleRoot = ogMerkleRoot_;
        heroMerkleRoot = heroMerkleRoot_;
        OG_MINT_TIMESTAMP = type(uint40).max;
        HERO_MINT_TIMESTAMP = type(uint40).max;
        PUBLIC_MINT_TIMESTAMP = type(uint40).max;
        mintPrice = mintPrice_;

        _initializeOwner(msg.sender);

        unchecked {
            for (uint256 i; i < 30;) {
                _mint(msg.sender, i + 1);
                ++i;
            }
            currentSupply = 30;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Modifier for the checking transfer is allowed.
    modifier _isTransferable() {
        if (startTransfer == 0) revert NotAllowed();
        _;
    }

    /// @dev The name of the token.
    function name() public pure override returns (string memory) {
        return "OCH Genesis Ring";
    }

    /// @dev The symbol of the token.
    function symbol() public pure override returns (string memory) {
        return "OGR";
    }

    /// @dev The URI for a token.
    function tokenURI(uint256 id) public view override returns (string memory) {
        /// Revert if token `id` does not exist.
        if (_exists(id) == false) {
            revert TokenDoesNotExist();
        }
        return LibString.concat(baseURI, LibString.toString(id));
    }

    /// @dev The baseURI for a token.
    /// Requirements:
    /// - Caller must be the owner.
    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    /// @dev Sets the `ogMerkleRoot` or `heroMerkelroot` for whitelist mint.
    function setRoot(bytes32 ogRoot, bytes32 heroRoot) external onlyOwner {
        if (ogRoot != ogMerkleRoot) {
            if (block.timestamp >= OG_MINT_TIMESTAMP) revert NotAllowed();
            ogMerkleRoot = ogRoot;
        }
        if (heroRoot != heroMerkleRoot) {
            if (block.timestamp >= HERO_MINT_TIMESTAMP) revert NotAllowed();
            heroMerkleRoot = heroRoot;
        }
    }

    /// @dev Set flag to allow transfers/trading.
    /// Note: Once the owner allows transfer, it cannot be undo.
    function allowTransfer() external onlyOwner {
        startTransfer = uint8(1);
    }

    /// @dev Sets the sale phase timestamps.
    /// Note:
    ///     Once phase started then nobody can changed timestamp for this.
    function setTimestamp(uint256 phase, uint40 newTimeStamp) external onlyOwner {
        if (phase == 0) {
            if (block.timestamp >= OG_MINT_TIMESTAMP) {
                revert PhaseAlreadyStarted();
            }
            OG_MINT_TIMESTAMP = newTimeStamp;
        } else if (phase == 1) {
            if (block.timestamp >= HERO_MINT_TIMESTAMP) {
                revert PhaseAlreadyStarted();
            }
            HERO_MINT_TIMESTAMP = newTimeStamp;
        } else {
            if (block.timestamp >= PUBLIC_MINT_TIMESTAMP) {
                revert PhaseAlreadyStarted();
            }
            PUBLIC_MINT_TIMESTAMP = newTimeStamp;
        }
    }

    /// @dev Sets the mint price.
    /// Requirements:
    /// - Caller must be the owner.
    function setMintPrice(uint64 price) external onlyOwner {
        mintPrice = price;
    }

    /// @dev Withdraws all available ethers to `to`.
    function withdrawETH(address to) external onlyOwner {
        SafeTransferLib.safeTransferAllETH(to);
    }

    /// @dev Airdrop tokens to specified addresses
    /// Requirements:
    /// - Caller must be the owner.
    function airdrop(address[] calldata accounts) external onlyOwner {
        if (block.timestamp >= PUBLIC_MINT_TIMESTAMP) revert PublicSaleStarted();
        uint256 len = accounts.length;
        if ((currentSupply + len) > MAX_SUPPLY) revert MaxSupplyReached();
        unchecked {
            for (uint64 i; i < len;) {
                _safeMint(accounts[i], currentSupply + i + 1);
                ++i;
            }
            currentSupply += uint64(len);
        }
    }

    /// @dev Checks token is transferable or not.
    function isTransferable() external view returns (bool) {
        return startTransfer != 0;
    }

    function ogMint(address to, bytes32[] calldata _proof) external payable {
        unchecked {
            // If public sale started then revert
            if (OG_MINT_TIMESTAMP <= block.timestamp && block.timestamp < HERO_MINT_TIMESTAMP) {
                // Revert if `to` already minted.
                if (_getAux(to) != uint224(0)) {
                    revert AlreadyMinted();
                }

                if (++currentSupply > MAX_SUPPLY) revert MaxSupplyReached();

                // Revert if msg.value is incorrect.
                if (msg.value != mintPrice) {
                    revert IncorrectPrice();
                }

                // Revert if given proof is not valid.
                if (!MerkleProofLib.verify(_proof, ogMerkleRoot, keccak256(abi.encodePacked(to)))) {
                    revert IncorrectProof();
                }
                // Set flag to `to` for whitelist mint.
                _setAux(to, 1);
                _safeMint(to, uint256(currentSupply));
                return;
            }
            revert NotAllowed();
        }
    }

    /// @dev Herolist mint to `to` address.
    /// Requirements:
    /// - The public sale has not started yet.
    /// - The given proof is valid.
    /// - The `msg.value` is correct.
    /// - The user has not already minted for this phase.
    function herolistMint(address to, bytes32[] calldata _proof) external payable {
        unchecked {
            // If public sale started then revert
            if (HERO_MINT_TIMESTAMP <= block.timestamp && block.timestamp < PUBLIC_MINT_TIMESTAMP) {
                // Revert if `to` already minted.
                if (_getAux(to) == uint224(2)) {
                    revert AlreadyMinted();
                }

                if (++currentSupply > MAX_SUPPLY) revert MaxSupplyReached();

                // Revert if msg.value is incorrect.
                if (msg.value != mintPrice) {
                    revert IncorrectPrice();
                }

                // Revert if given proof is not valid.
                if (!MerkleProofLib.verify(_proof, heroMerkleRoot, keccak256(abi.encodePacked(to)))) {
                    revert IncorrectProof();
                }
                // Set flag to `to` for whitelist mint.
                _setAux(to, 2);
                _safeMint(to, uint256(currentSupply));
                return;
            }
            revert NotAllowed();
        }
    }

    /// @dev Public mint to `msg.sender`.
    /// Requirements:
    /// - The public sale has started.
    /// - The `msg.value` is correct.
    /// - Only allows 1 mint per address.
    function publicMint() external payable nonReentrant {
        if (PUBLIC_MINT_TIMESTAMP > block.timestamp) revert NotStarted();

        unchecked {
            if (++currentSupply > MAX_SUPPLY) revert MaxSupplyReached();

            /// Revert if `msg.sender` already minted
            if (_getAux(msg.sender) == 3) revert AlreadyMinted();

            if (msg.value != mintPrice) {
                revert IncorrectPrice();
            }

            // Set flag to `msg.sender` for whitelist mint.
            _setAux(msg.sender, 3);

            _safeMint(msg.sender, uint256(currentSupply));
        }
    }

    /// @dev Transfers token `id` from `from` to `to`.
    /// Note: Requires `startTransfer != 0`.
    function transferFrom(address from, address to, uint256 id) public payable override _isTransferable {
        super.transferFrom(from, to, id);
    }

    /// @dev Override for using transient storage.
    function _useTransientReentrancyGuardOnlyOnMainnet() internal pure override returns (bool) {
        return false;
    }
}