// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "solady/auth/Ownable.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {IERC721} from "../external/IERC721.sol";

interface IUniversalRouter {
    error InsufficientETH();

    /// @notice Executes encoded commands along with provided inputs. Reverts if deadline has expired.
    /// @param commands A set of concatenated commands, each 1 byte in length
    /// @param inputs An array of byte strings containing abi encoded inputs for each command
    /// @param deadline The deadline by which the transaction must be executed
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline)
        external
        payable;
}

interface IBT404 {
    function setSkipNFT(bool skipNFT) external returns (bool);
    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);
}

interface IBT404Mirror {
    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or
     *   {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC-721
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /// @dev Returns the owned token ids of `account` from the base BT404 contract.
    function ownedIds(address account, uint256 begin, uint256 end)
        external
        view
        returns (uint256[] memory);

    function balanceOf(address nftOwner) external view returns (uint256 result);

    function exchange(uint256 idX, uint256 idY) external returns (uint256 exchangeFee);

    function updateLockState(uint256[] memory ids, bool lock) external;
}

contract BT404DexEntry is Ownable, UUPSUpgradeable, ReentrancyGuard {
    /// @dev Throw when buying but the nft balance of `this` is not matched with requested.
    error NFTAmountNotMatch();
    /// @dev Throw when buying but the bt404 token balance of `msg.sender` is not matched with requested.
    error TokenAmountNotMatch();

    IUniversalRouter public immutable UNIVERSAL_ROUTER;
    ISignatureTransfer public immutable PERMIT2;

    struct UniversalRouterExecute {
        bytes commands;
        bytes[] inputs;
        uint256 deadline;
    }

    struct SignaturePermitTransfer {
        ISignatureTransfer.PermitBatchTransferFrom permit;
        ISignatureTransfer.SignatureTransferDetails[] transfers;
        bytes signature;
        address bt404;
        /// @dev If it is not zero,
        ///      we will check if the bt404 balance is equal to the requested
        ///      to prevent unexpected NFT burning.
        uint256 bt404Balance;
    }

    struct BT404NFTTransfer {
        uint256[] nftIds;
    }

    constructor(address universalRouter, address permit2) payable {
        UNIVERSAL_ROUTER = IUniversalRouter(universalRouter);
        PERMIT2 = ISignatureTransfer(permit2);
        _initializeOwner(tx.origin);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _guardInitializeOwner() internal pure virtual override(Ownable) returns (bool) {
        return true;
    }

    function initialize() public payable {
        _initializeOwner(msg.sender);
    }

    function unsetSkipNFT(address addr404) public payable nonReentrant {
        IBT404(addr404).setSkipNFT(false);
    }

    function sell(
        address token404,
        address nft404,
        uint256[] calldata nftIds,
        UniversalRouterExecute calldata swapParam
    ) public payable nonReentrant {
        IBT404Mirror bt404Mirror = IBT404Mirror(nft404);
        _transferNFTToThis(bt404Mirror, msg.sender, nftIds);
        bt404Mirror.updateLockState(nftIds, false);

        SafeTransferLib.safeTransferAll(token404, address(UNIVERSAL_ROUTER));
        UNIVERSAL_ROUTER.execute(swapParam.commands, swapParam.inputs, swapParam.deadline);
    }

    function buy(
        address nft404,
        uint256[] calldata nftIds,
        address nftRecipient,
        bytes calldata tokenTransfer,
        bytes calldata nftExchange,
        bytes calldata swapParam
    ) public payable nonReentrant {
        IBT404Mirror bt404Mirror = IBT404Mirror(nft404);
        uint256 nftBalance = bt404Mirror.balanceOf(address(this));

        if (tokenTransfer.length > 0) {
            SignaturePermitTransfer memory transfer =
                abi.decode(tokenTransfer, (SignaturePermitTransfer));
            if (
                transfer.bt404Balance > 0
                    && IBT404(transfer.bt404).balanceOf(msg.sender) != transfer.bt404Balance
            ) {
                revert TokenAmountNotMatch();
            }
            // 1. User can transfer 404 tokens to `this`.
            // 2. Transfer payment tokens of the swap to `UniversalRouter`
            PERMIT2.permitTransferFrom(
                transfer.permit, transfer.transfers, msg.sender, transfer.signature
            );
        }
        if (nftExchange.length > 0) {
            BT404NFTTransfer memory transfer = abi.decode(nftExchange, (BT404NFTTransfer));
            _transferNFTToThis(bt404Mirror, msg.sender, transfer.nftIds);
            bt404Mirror.updateLockState(transfer.nftIds, false);
        }
        if (swapParam.length > 0) {
            // Buy specified amount of ERC20 tokens.
            UniversalRouterExecute memory swap = abi.decode(swapParam, (UniversalRouterExecute));
            UNIVERSAL_ROUTER.execute{value: msg.value}(swap.commands, swap.inputs, swap.deadline);
        }

        // Get nft ids which will be exchanged.
        uint256 numToBuy = nftIds.length;
        uint256[] memory idsToExchange =
            bt404Mirror.ownedIds(address(this), nftBalance, nftBalance + numToBuy);
        if (idsToExchange.length != numToBuy) revert NFTAmountNotMatch();

        // Exchange the specified NFTs and transfer to the recipient.
        // Iterating in reverse order as some nfts maybe burned due to fee deductions.
        for (uint256 i = numToBuy; i > 0;) {
            unchecked {
                --i;
            }

            uint256 targetId = nftIds[i];
            bt404Mirror.exchange(idsToExchange[i], targetId);
            bt404Mirror.safeTransferFrom(address(this), nftRecipient, targetId);
        }
    }

    function withdraw(address token) public payable onlyOwner nonReentrant {
        if (token == address(0)) SafeTransferLib.safeTransferAllETH(msg.sender);
        else SafeTransferLib.safeTransferAll(token, msg.sender);
    }

    function withdraw(address collection, uint256 tokenId) public payable onlyOwner nonReentrant {
        IERC721(collection).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory)
        public
        pure
        virtual
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    function _transferNFTToThis(IBT404Mirror bt404Mirror, address from, uint256[] memory nftIds)
        private
    {
        uint256 len = nftIds.length;
        for (uint256 i; i < len;) {
            bt404Mirror.transferFrom(from, address(this), nftIds[i]);
            unchecked {
                ++i;
            }
        }
    }
}