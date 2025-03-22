// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IPreCollateralizedMinter} from "src/interfaces/IPreCollateralizedMinter.sol";
import {IUSDf} from "src/interfaces/IUSDf.sol";

contract PreCollateralizedMinter is IPreCollateralizedMinter, AccessControl, EIP712 {

    using MessageHashUtils for bytes32;
    using BitMaps for BitMaps.BitMap;

    // Immutable USDf token contract
    IUSDf public immutable USDF;

    // Role for minter
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Nonce tracking
    BitMaps.BitMap private _usedNonces;

    // TypeHash for preCollateralizedMint
    bytes32 private constant PRE_COLLATERALIZED_MINT_TYPEHASH = keccak256(
        "PreCollateralizedMint(bytes32 collateralRef,address recipient,uint256 amount,uint256 nonce,uint256 expiry)"
    );

    constructor(address admin, address usdf, address minter) EIP712("USDf Pre-Collateralized Minter", "1") {
        require(usdf != address(0), ZeroAddress());
        require(minter != address(0), ZeroAddress());
        require(admin != address(0), ZeroAddress());

        USDF = IUSDf(usdf);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
    }

    /// @inheritdoc IPreCollateralizedMinter
    function preCollateralizedMint(MintParams calldata params, bytes calldata signature) external {
        require(params.collateralRef != bytes32(0), EmptyCollateralRef());
        require(params.amount > 0, ZeroAmount());
        require(params.recipient != address(0), ZeroAddress());
        require(params.expiry > block.timestamp, Expired());
        require(!_usedNonces.get(params.nonce), NonceAlreadyUsed());

        // Mark nonce as used
        _usedNonces.set(params.nonce);

        // Build and verify signature
        bytes32 structHash = keccak256(
            abi.encode(
                PRE_COLLATERALIZED_MINT_TYPEHASH,
                params.collateralRef,
                params.recipient,
                params.amount,
                params.nonce,
                params.expiry
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);
        require(hasRole(MINTER_ROLE, ECDSA.recover(hash, signature)), InvalidSignature());

        // Mint USDf
        USDF.mint(params.recipient, params.amount);

        emit MintExecuted(params.collateralRef, params.recipient, params.amount, params.nonce);
    }

    /// @inheritdoc IPreCollateralizedMinter
    function isNonceUsed(uint256 nonce) external view returns (bool) {
        return _usedNonces.get(nonce);
    }

}