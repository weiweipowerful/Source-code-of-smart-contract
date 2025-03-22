// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin5/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin5/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Context} from "@openzeppelin5/contracts/utils/Context.sol";
import {IDelegationRegistry} from "contracts/utils/delegation_registry/IDelegationRegistry.sol";
import {IDelegateRegistry} from "contracts/utils/delegation_registry/IDelegateRegistry.sol";
import {ClaimType, NFTCollectionClaimRequest} from "./lib/Structs.sol";

import {MemecoinDelegatable} from "../delegate/MemecoinDelegatable.sol";

error NoClaimableToken();
error InvalidDelegate();

interface IMemecoinClaim {
    function claimFromMulti(address _requester, ClaimType[] calldata _claimTypes) external;
    function claimInNFTsFromMulti(
        address _requester,
        NFTCollectionClaimRequest[] calldata _nftCollectionClaimRequests,
        bool _withWalletRewards
    ) external;
}

interface IStakeland {
    function stakeFor(address from, uint256 amount, bytes calldata permit) external;
}

contract MemecoinMultiClaim is Context, MemecoinDelegatable {
    event ClaimedToStakeland(address indexed user, uint256 amount, uint256 claimedAt);

    IMemecoinClaim public immutable presaleClaim;
    IMemecoinClaim public immutable airdropClaim;
    IDelegationRegistry public immutable dc;
    IDelegateRegistry public immutable dcV2;
    IERC20 public immutable memecoin;
    IStakeland public immutable stakeland;

    constructor(address _presaleClaim, address _airdropClaim, address _memecoin, address _delegate, address _stakeland)
        MemecoinDelegatable(_delegate)
    {
        presaleClaim = IMemecoinClaim(_presaleClaim);
        airdropClaim = IMemecoinClaim(_airdropClaim);
        dc = IDelegationRegistry(0x00000000000076A84feF008CDAbe6409d2FE638B);
        dcV2 = IDelegateRegistry(0x00000000000000447e69651d841bD8D104Bed493);
        memecoin = IERC20(_memecoin);
        if (!memecoin.approve(_delegate, type(uint256).max)) revert("Memecoin: approve failed");
        stakeland = IStakeland(_stakeland);
    }

    /// @notice Cross contract claim on Presale, OPTIONALLY ON NFTAirdrop/NFTRewards/WalletRewards
    /// @param _vault Vault address of delegate.xyz; pass address(0) if not using delegate wallet
    /// @param _claimTypes Array of ClaimType to claim
    /// @param _nftCollectionClaimRequests Array of NFTCollectionClaimRequest that consists collection ID of the NFT, token ID(s) the owner owns, array of booleans to indicate NFTAirdrop/NFTRewards claim for each token ID
    /// @param _withWalletRewards Boolean to dictate if claimer will claim WalletRewards as well
    function multiClaim(
        address _vault,
        ClaimType[] calldata _claimTypes,
        NFTCollectionClaimRequest[] calldata _nftCollectionClaimRequests,
        bool _withWalletRewards
    ) external {
        address requester = _getRequester(_vault);
        presaleClaim.claimFromMulti(requester, _claimTypes);
        airdropClaim.claimInNFTsFromMulti(requester, _nftCollectionClaimRequests, _withWalletRewards);
    }

    /// @dev Support both v1 and v2 delegate wallet during the v1 to v2 migration
    /// @dev Given _vault (cold wallet) address, verify whether _msgSender() is a permitted delegate to operate on behalf of it
    /// @param _vault Address to verify against _msgSender
    function _getRequester(address _vault) private view returns (address) {
        if (_vault == address(0)) return _msgSender();
        bool isDelegateValid = dcV2.checkDelegateForAll(_msgSender(), _vault, "");
        if (isDelegateValid) return _vault;
        isDelegateValid = dc.checkDelegateForAll(_msgSender(), _vault);
        if (!isDelegateValid) revert InvalidDelegate();
        return _vault;
    }

    /// @notice Cross contract claim to Stakeland
    /// @param _amount Amount to claim to Stakeland
    /// @param _presaleClaims Array of ClaimType to claim
    /// @param _airdropClaims Array of NFTCollectionClaimRequest that consists collection ID of the NFT, token ID(s) the owner owns, array of booleans to indicate NFTAirdrop/NFTRewards claim for each token ID
    /// @param _permit Encoded permit data
    function multiClaimToStakeland(
        uint256 _amount,
        ClaimType[] calldata _presaleClaims,
        NFTCollectionClaimRequest[] calldata _airdropClaims,
        bytes calldata _permit
    ) external {
        address user = _msgSender();
        uint256 balance = memecoin.balanceOf(user);

        if (_presaleClaims.length != 0) presaleClaim.claimFromMulti(user, _presaleClaims);
        if (_airdropClaims.length != 0) airdropClaim.claimInNFTsFromMulti(user, _airdropClaims, false);

        uint256 claimAmount = memecoin.balanceOf(user) - balance;
        if (claimAmount == 0) revert NoClaimableToken();

        if (_permit.length != 0) _delegatePermit(_permit);
        if (claimAmount > _amount) claimAmount = _amount;
        _delegateTransfer(address(this), claimAmount);

        stakeland.stakeFor(user, claimAmount, "");

        emit ClaimedToStakeland(user, claimAmount, block.timestamp);
    }
}