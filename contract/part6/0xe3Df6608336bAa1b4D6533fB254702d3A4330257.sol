// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC721Lockable} from "../interfaces/IERC721Lockable.sol";
import {LibMap} from "solady/src/utils/LibMap.sol";
import {IDelegateRegistry} from "../interfaces/IDelegateRegistry.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";

contract TokenLocking is OwnableRoles {
    using LibMap for LibMap.Uint64Map;

    error AlreadyLocked();
    error NotOwnerOrDelegate();
    error OwnerAddressMismatch();
    error AdminLockDisabled();
    error NoTokensSpecified();

    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);

    IDelegateRegistry public constant DELEGATE_REGISTRY =
        IDelegateRegistry(0x00000000000000447e69651d841bD8D104Bed493);

    IERC721Lockable public immutable NIPPY;
    
    bool private _adminLockEnabled;

    LibMap.Uint64Map private _lastLockedAt;

    constructor(address nippy) {
        _initializeOwner(tx.origin);
        NIPPY = IERC721Lockable(nippy);
        _adminLockEnabled = true;
    }

    /**
     * PUBLIC FUNCTIONS
     */

    function lock(uint256 tokenId) external {
        _ensureOwnerOrDelegate(tokenId);
        NIPPY.lock(tokenId);
        _lastLockedAt.set(tokenId, uint64(block.timestamp));
        emit Locked(tokenId);
    }

    function batchLock(uint256[] calldata tokenIds) external {
        uint256 length = tokenIds.length;
        if (length == 0) {
            revert NoTokensSpecified();
        }

        uint256 tokenId = tokenIds[0];
        address firstTokenOwner = _ensureOwnerOrDelegate(tokenId);
        _lastLockedAt.set(tokenId, uint64(block.timestamp));
        emit Locked(tokenId);

        for (uint256 i = 1; i < length; ++i) {
            tokenId = tokenIds[i];
            _ensureMatchingOwner(tokenId, firstTokenOwner);
            _lastLockedAt.set(tokenId, uint64(block.timestamp));
            emit Locked(tokenId);
        }
        NIPPY.lock(tokenIds);
    }

    function unlock(uint256 tokenId) external {
        _ensureOwnerOrDelegate(tokenId);
        NIPPY.unlock(tokenId);
        _lastLockedAt.set(tokenId, 0);
        emit Unlocked(tokenId);
    }

    function batchUnlock(uint256[] calldata tokenIds) external {
        uint256 length = tokenIds.length;
        if (length == 0) {
            revert NoTokensSpecified();
        }

        uint256 tokenId = tokenIds[0];
        address firstTokenOwner = _ensureOwnerOrDelegate(tokenId);
        _lastLockedAt.set(tokenId, 0);
        emit Unlocked(tokenId);

        for (uint256 i = 1; i < length; ++i) {
            tokenId = tokenIds[i];
            _ensureMatchingOwner(tokenId, firstTokenOwner);
            _lastLockedAt.set(tokenId, 0);
            emit Unlocked(tokenId);
        }
        NIPPY.unlock(tokenIds);
    }

    /**
     * ADMIN FUNCTIONS
     */

    function adminLock(uint256[] calldata tokenIds) external onlyOwnerOrRoles(1) {
        if (!_adminLockEnabled) {
            revert AdminLockDisabled();
        }

        NIPPY.lock(tokenIds);

        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            _lastLockedAt.set(tokenId, uint64(block.timestamp));
            emit Locked(tokenId);
        }
    }

    function adminUnlock(uint256[] calldata tokenIds) external onlyOwnerOrRoles(1) {
        NIPPY.unlock(tokenIds);

        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            _lastLockedAt.set(tokenId, 0);
            emit Unlocked(tokenId);
        }
    }

    function disableAdminLock() external onlyOwner {
        _adminLockEnabled = false;
    }

    /**
     * VIEW ONLY FUNCTIONS
     */
    function isLocked(uint256 tokenId) public view returns (bool) {
        return NIPPY.locked(tokenId);
    }

    function lockDuration(uint256 tokenId) public view returns (uint64) {
        uint64 lastLockedAt = _lastLockedAt.get(tokenId);
        if (lastLockedAt == 0) {
            return 0;
        }
        return uint64(block.timestamp) - lastLockedAt;
    }

    function isLocked(uint256[] calldata tokenIds) external view returns (bool[] memory) {
        uint256 length = tokenIds.length;
        bool[] memory results = new bool[](length);
        for (uint256 i = 0; i < length; ++i) {
            results[i] = isLocked(tokenIds[i]);
        }
        return results;
    }

    function lockDuration(uint256[] calldata tokenIds) external view returns (uint64[] memory) {
        uint256 length = tokenIds.length;
        uint64[] memory results = new uint64[](length);
        for (uint256 i = 0; i < length; ++i) {
            results[i] = lockDuration(tokenIds[i]);
        }
        return results;
    }

    /** 
     * Internal view functions 
     */

    function _ensureMatchingOwner(uint256 tokenId, address expectedOwner) internal view {
        address tokenOwner = NIPPY.ownerOf(tokenId);
        if (tokenOwner != expectedOwner) {
            revert OwnerAddressMismatch();
        }
    }

    function _ensureOwnerOrDelegate(uint256 tokenId) internal view returns (address) {
        address tokenOwner = NIPPY.ownerOf(tokenId);
        if (tokenOwner != msg.sender) {
            if (
                !DELEGATE_REGISTRY.checkDelegateForContract(
                    msg.sender, tokenOwner, address(NIPPY), 0x0
                )
            ) {
                revert NotOwnerOrDelegate();
            }
        }
        return tokenOwner;
    }
}