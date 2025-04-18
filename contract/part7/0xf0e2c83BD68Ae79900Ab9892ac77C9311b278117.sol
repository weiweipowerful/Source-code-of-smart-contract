// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./modules/Ownable/Ownable.sol";
import "./modules/Upgradeable/Upgradeable.sol";
import "./TransferHelper.sol";
import "./IAvatarsEscrow.sol";
import "./IAvatarsRental.sol";
import "./IAvatars_ERC721.sol";
import "./AvatarsEscrowStorage.sol";

contract AvatarsEscrow is Context, ERC165, IAvatarsEscrow, Ownable, ReentrancyGuard, Upgradeable {
    using SafeCast for uint256;
    using ECDSA for bytes32;
    using EnumerableSet for EnumerableSet.UintSet;

    // ======== Admin functions ========

    constructor(address _rewardTokenAddress, address _avatars) {
        require(_rewardTokenAddress != address(0), "E0"); // E0: addr err
        require(address(_avatars) != address(0), "E0");
        AvatarsEscrowStorage.layout().rewardTokenAddress = _rewardTokenAddress;
        AvatarsEscrowStorage.layout().Avatars_ERC721 = IAvatars_ERC721(_avatars);
    }

    // Set a rewards schedule
    // rate is in wei per second for all users
    // This must be called AFTER some avatars are staked (or ensure at least 1 avatar is staked before the start timestamp)
    function setRewards(uint32 _start, uint32 _end, uint96 _rate) external onlyOwner checkForUpgrade {
        require(_start <= _end, "E1"); // E1: Incorrect input
        // some safeguard, value TBD. (2b over 5 years is 12.68 per sec)
        require(_rate > 0.03 ether && _rate < 30 ether, "E2"); // E2: Rate incorrect
        require(AvatarsEscrowStorage.layout().rewardTokenAddress != address(0), "E3"); // E3: Rewards token not set
        require(
            block.timestamp.toUint32() < AvatarsEscrowStorage.layout().rewardsPeriod.start
                || block.timestamp.toUint32() > AvatarsEscrowStorage.layout().rewardsPeriod.end,
            "E4"
        ); // E4: Rewards already set

        AvatarsEscrowStorage.layout().rewardsPeriod.start = _start;
        AvatarsEscrowStorage.layout().rewardsPeriod.end = _end;

        AvatarsEscrowStorage.layout().rewardsPerWeight.lastUpdated = _start;
        AvatarsEscrowStorage.layout().rewardsPerWeight.rate = _rate;

        emit RewardsSet(_start, _end, _rate);
    }

    function setWeight(uint256[] calldata _tokenIds, uint256[] calldata _weights) external onlyOwner checkForUpgrade {
        require(_tokenIds.length == _weights.length, "E6");
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            require(AvatarsEscrowStorage.layout().avatarInfo[tokenId].weight == 0, "E8");
            AvatarsEscrowStorage.layout().avatarInfo[tokenId].weight = _weights[i].toUint16();
        }
    }

    function setSigner(address _signer) external onlyOwner checkForUpgrade {
        AvatarsEscrowStorage.layout().signer = _signer;
    }

    function setRentalContract(IAvatarsRental _rental) external onlyOwner checkForUpgrade {
        require(_rental.supportsInterface(type(IAvatarsRental).interfaceId), "E0");
        AvatarsEscrowStorage.layout().AvatarsRental = _rental;
    }

    function setRewardTokenAddress(address _rewardTokenAddress) external onlyOwner checkForUpgrade {
        AvatarsEscrowStorage.layout().rewardTokenAddress = _rewardTokenAddress;
    }

    function setAvatarsERC721(IAvatars_ERC721 _avatars) external onlyOwner checkForUpgrade {
        AvatarsEscrowStorage.layout().Avatars_ERC721 = _avatars;
    }

    function setAvatarsRental(IAvatarsRental _rental) external onlyOwner checkForUpgrade {
        AvatarsEscrowStorage.layout().AvatarsRental = _rental;
    }

    // ======== Public functions ========

    // Stake avatars for a first time. You may optionally stake to a different wallet. Ownership will be transferred to the stakeTo address.
    // Initial weights passed as input parameters, which are secured by a dev signature. weight = 60003 - 3 * rank
    // When you stake you can set rental conditions for all of them.
    // Initialized and uninitialized stake can be mixed into one tx using this method.
    // If you set rentalPerDay to 0 and rentableUntil to some time in the future, then anyone can rent for free
    //    until the rentableUntil timestamp with no way of backing out
    function initialStake(
        uint256[] calldata _tokenIds,
        uint256[] calldata _weights,
        address _stakeTo,
        uint16 _deposit,
        uint16 _rentalPerDay,
        uint16 _minRentDays,
        uint32 _rentableUntil,
        uint32 _maxTimestamp,
        bytes calldata _signature
    ) external nonReentrant checkForUpgrade {
        require(uint256(_deposit) <= uint256(_rentalPerDay) * (uint256(_minRentDays) + 1), "ER"); // ER: Rental rate incorrect
        // security measure against input length attack
        require(_tokenIds.length == _weights.length, "E6"); // E6: Input length mismatch
        require(block.timestamp <= _maxTimestamp, "EX"); // EX: Signature expired
        // verifying signature here is much cheaper than verifying merkle root
        require(
            _verifySignerSignature(
                keccak256(abi.encode(_tokenIds, _weights, _msgSender(), _maxTimestamp, address(this))), _signature
            ),
            "E7"
        ); // E7: Invalid signature
        // ensure stakeTo is EOA or ERC721Receiver to avoid token lockup
        _ensureEOAorERC721Receiver(_stakeTo);
        require(_stakeTo != address(this), "ES"); // ES: Stake to escrow

        uint256 totalWeights = 0;
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            {
                // scope to avoid stack too deep errors
                uint256 tokenId = _tokenIds[i];
                uint256 _weight = AvatarsEscrowStorage.layout().avatarInfo[tokenId].weight;
                require(_weight == 0 || _weight == _weights[i], "E8"); // E8: Initialized weight cannot be changed
                require(AvatarsEscrowStorage.layout().Avatars_ERC721.ownerOf(tokenId) == _msgSender(), "E9"); // E9: Not your avatar
                AvatarsEscrowStorage.layout().Avatars_ERC721.safeTransferFrom(_msgSender(), address(this), tokenId);

                emit AvatarStaked(tokenId, _stakeTo);
            }
            AvatarsEscrowStorage.layout().avatarInfo[_tokenIds[i]] =
                AvatarInfo(_weights[i].toUint16(), _stakeTo, _deposit, _rentalPerDay, _minRentDays, _rentableUntil);
            AvatarsEscrowStorage.layout().userStakes[_stakeTo].add(_tokenIds[i]);
            totalWeights += _weights[i];
        }
        // update rewards
        _updateRewardsPerWeight(totalWeights.toUint32(), true);
        _updateUserRewards(_stakeTo, totalWeights.toUint32(), true);
    }

    // subsequent staking does not require dev signature
    function stake(
        uint256[] calldata _tokenIds,
        address _stakeTo,
        uint16 _deposit,
        uint16 _rentalPerDay,
        uint16 _minRentDays,
        uint32 _rentableUntil
    ) external nonReentrant checkForUpgrade {
        require(uint256(_deposit) <= uint256(_rentalPerDay) * (uint256(_minRentDays) + 1), "ER"); // ER: Rental rate incorrect
        // ensure stakeTo is EOA or ERC721Receiver to avoid token lockup
        _ensureEOAorERC721Receiver(_stakeTo);
        require(_stakeTo != address(this), "ES"); // ES: Stake to escrow

        uint256 totalWeights = 0;
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            uint16 _weight = AvatarsEscrowStorage.layout().avatarInfo[tokenId].weight;
            require(_weight != 0, "EA"); // EA: Weight not initialized
            require(AvatarsEscrowStorage.layout().Avatars_ERC721.ownerOf(tokenId) == _msgSender(), "E9"); // E9: Not your avatar
            AvatarsEscrowStorage.layout().Avatars_ERC721.safeTransferFrom(_msgSender(), address(this), tokenId);
            totalWeights += _weight;
            AvatarsEscrowStorage.layout().avatarInfo[tokenId] =
                AvatarInfo(_weight, _stakeTo, _deposit, _rentalPerDay, _minRentDays, _rentableUntil);
            AvatarsEscrowStorage.layout().userStakes[_stakeTo].add(tokenId);
            emit AvatarStaked(tokenId, _stakeTo);
        }
        // update rewards
        _updateRewardsPerWeight(totalWeights.toUint32(), true);
        _updateUserRewards(_stakeTo, totalWeights.toUint32(), true);
    }

    // Update rental conditions as long as therer's no ongoing rent.
    // setting rentableUntil to 0 makes the avatar unrentable.
    function updateRent(
        uint256[] calldata _tokenIds,
        uint16 _deposit,
        uint16 _rentalPerDay,
        uint16 _minRentDays,
        uint32 _rentableUntil
    ) external checkForUpgrade {
        require(uint256(_deposit) <= uint256(_rentalPerDay) * (uint256(_minRentDays) + 1), "ER"); // ER: Rental rate incorrect
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            AvatarInfo storage avatarInfo_ = AvatarsEscrowStorage.layout().avatarInfo[tokenId];
            require(avatarInfo_.weight != 0, "EA"); // EA: Weight not initialized
            require(
                AvatarsEscrowStorage.layout().Avatars_ERC721.ownerOf(tokenId) == address(this)
                    && avatarInfo_.owner == _msgSender(),
                "E9"
            ); // E9: Not your avatar
            require(!AvatarsEscrowStorage.layout().AvatarsRental.isRentActive(tokenId), "EB"); // EB: Ongoing rent
            avatarInfo_.deposit = _deposit;
            avatarInfo_.rentalPerDay = _rentalPerDay;
            avatarInfo_.minRentDays = _minRentDays;
            avatarInfo_.rentableUntil = _rentableUntil;
        }
    }

    // Extend rental period of ongoing rent
    function extendRentalPeriod(uint256 _tokenId, uint32 _rentableUntil) external checkForUpgrade {
        AvatarInfo storage avatarInfo_ = AvatarsEscrowStorage.layout().avatarInfo[_tokenId];
        require(avatarInfo_.weight != 0, "EA"); // EA: Weight not initialized
        require(
            AvatarsEscrowStorage.layout().Avatars_ERC721.ownerOf(_tokenId) == address(this)
                && avatarInfo_.owner == _msgSender(),
            "E9"
        ); // E9: Not your avatar
        avatarInfo_.rentableUntil = _rentableUntil;
    }

    function unstake(uint256[] calldata _tokenIds, address _unstakeTo) external nonReentrant checkForUpgrade {
        // ensure unstakeTo is EOA or ERC721Receiver to avoid token lockup
        _ensureEOAorERC721Receiver(_unstakeTo);
        require(_unstakeTo != address(this), "ES"); // ES: Unstake to escrow

        uint256 totalWeights = 0;
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            require(AvatarsEscrowStorage.layout().avatarInfo[tokenId].owner == _msgSender(), "E9"); // E9: Not your avatar
            require(!AvatarsEscrowStorage.layout().AvatarsRental.isRentActive(tokenId), "EB"); // EB: Ongoing rent
            AvatarsEscrowStorage.layout().Avatars_ERC721.safeTransferFrom(address(this), _unstakeTo, tokenId);
            uint16 _weight = AvatarsEscrowStorage.layout().avatarInfo[tokenId].weight;
            totalWeights += _weight;
            AvatarsEscrowStorage.layout().avatarInfo[tokenId] = AvatarInfo(_weight, address(0), 0, 0, 0, 0);
            AvatarsEscrowStorage.layout().userStakes[_msgSender()].remove(tokenId);

            emit AvatarUnstaked(tokenId, _msgSender()); // Avatar `id` unstaked from `address`
        }
        // update rewards
        _updateRewardsPerWeight(totalWeights.toUint32(), false);
        _updateUserRewards(_msgSender(), totalWeights.toUint32(), false);
    }

    function updateAvatar(
        uint256 _tokenId,
        string calldata _ipfsHash,
        uint256 _nonce,
        bytes calldata _updateApproverSignature
    ) external checkForUpgrade {
        require(
            (
                AvatarsEscrowStorage.layout().avatarInfo[_tokenId].owner == _msgSender()
                    && !AvatarsEscrowStorage.layout().AvatarsRental.isRentActive(_tokenId)
            )
                || (
                    AvatarsEscrowStorage.layout().avatarInfo[_tokenId].owner != address(0)
                        && AvatarsEscrowStorage.layout().AvatarsRental.getTenant(_tokenId) == _msgSender()
                ),
            "EH"
        ); // EH: Not your avatar or not rented
        AvatarsEscrowStorage.layout().Avatars_ERC721.updateAvatar(_tokenId, _ipfsHash, _nonce, _updateApproverSignature);
    }

    // Claim all rewards from caller into a given address
    function claim(address _to) external nonReentrant checkForUpgrade {
        _updateRewardsPerWeight(0, false);
        uint256 rewardAmount = _updateUserRewards(_msgSender(), 0, false);
        AvatarsEscrowStorage.layout().rewards[_msgSender()].accumulated = 0;
        TransferHelper.safeTransfer(AvatarsEscrowStorage.layout().rewardTokenAddress, _to, rewardAmount);
        emit RewardClaimed(_to, rewardAmount);
    }

    // ======== View only functions ========

    function getAvatarInfo(uint256 _tokenId) external view override returns (AvatarInfo memory) {
        return AvatarsEscrowStorage.layout().avatarInfo[_tokenId];
    }

    function checkUserRewards(address _user) external view returns (uint256) {
        RewardsPerWeight memory rewardsPerWeight_ = AvatarsEscrowStorage.layout().rewardsPerWeight;
        UserRewards memory userRewards_ = AvatarsEscrowStorage.layout().rewards[_user];

        // Find out the unaccounted time
        uint32 end = min(block.timestamp.toUint32(), AvatarsEscrowStorage.layout().rewardsPeriod.end);
        uint256 unaccountedTime = end - rewardsPerWeight_.lastUpdated; // Cast to uint256 to avoid overflows later on
        if (unaccountedTime != 0) {
            // Calculate and update the new value of the accumulator. unaccountedTime casts it into uint256, which is desired.
            // If the first mint happens mid-program, we don't update the accumulator, no one gets the rewards for that period.
            if (rewardsPerWeight_.totalWeight != 0) {
                rewardsPerWeight_.accumulated = (
                    rewardsPerWeight_.accumulated
                        + unaccountedTime * rewardsPerWeight_.rate / rewardsPerWeight_.totalWeight
                ).toUint96();
            }
        }
        // Calculate and update the new value user reserves. userRewards_.stakedWeight casts it into uint256, which is desired.
        return userRewards_.accumulated
            + userRewards_.stakedWeight * (rewardsPerWeight_.accumulated - userRewards_.checkpoint);
    }

    function rewardsPeriod() external view returns (IAvatarsEscrow.RewardsPeriod memory) {
        return AvatarsEscrowStorage.layout().rewardsPeriod;
    }

    function rewardsPerWeight() external view returns (IAvatarsEscrow.RewardsPerWeight memory) {
        return AvatarsEscrowStorage.layout().rewardsPerWeight;
    }

    function rewards(address user) external view returns (UserRewards memory) {
        return AvatarsEscrowStorage.layout().rewards[user];
    }

    function userStakedAvatars(address _user) external view returns (uint256[] memory) {
        uint256 length = AvatarsEscrowStorage.layout().userStakes[_user].length();
        uint256[] memory stakedAvatars = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            stakedAvatars[i] = AvatarsEscrowStorage.layout().userStakes[_user].at(i);
        }

        return stakedAvatars;
    }

    function supportsInterface(bytes4 _interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return _interfaceId == type(IAvatarsEscrow).interfaceId || super.supportsInterface(_interfaceId);
    }

    // ======== internal functions ========

    function _verifySignerSignature(bytes32 _hash, bytes calldata _signature) internal view returns (bool) {
        return _hash.toEthSignedMessageHash().recover(_signature) == AvatarsEscrowStorage.layout().signer;
    }

    function min(uint32 _x, uint32 _y) internal pure returns (uint32 z) {
        z = (_x < _y) ? _x : _y;
    }

    // Updates the rewards per weight accumulator.
    // Needs to be called on each staking/unstaking event.
    function _updateRewardsPerWeight(uint32 _weight, bool _increase) internal checkForUpgrade {
        RewardsPerWeight memory rewardsPerWeight_ = AvatarsEscrowStorage.layout().rewardsPerWeight;
        RewardsPeriod memory rewardsPeriod_ = AvatarsEscrowStorage.layout().rewardsPeriod;

        // We skip the update if the program hasn't started
        if (block.timestamp.toUint32() >= rewardsPeriod_.start) {
            // Find out the unaccounted time
            uint32 end = min(block.timestamp.toUint32(), rewardsPeriod_.end);
            uint256 unaccountedTime = end - rewardsPerWeight_.lastUpdated; // Cast to uint256 to avoid overflows later on
            if (unaccountedTime != 0) {
                // Calculate and update the new value of the accumulator.
                // If the first mint happens mid-program, we don't update the accumulator, no one gets the rewards for that period.
                if (rewardsPerWeight_.totalWeight != 0) {
                    rewardsPerWeight_.accumulated = (
                        rewardsPerWeight_.accumulated
                            + unaccountedTime * rewardsPerWeight_.rate / rewardsPerWeight_.totalWeight
                    ).toUint96();
                }
                rewardsPerWeight_.lastUpdated = end;
            }
        }
        if (_increase) {
            rewardsPerWeight_.totalWeight += _weight;
        } else {
            rewardsPerWeight_.totalWeight -= _weight;
        }
        AvatarsEscrowStorage.layout().rewardsPerWeight = rewardsPerWeight_;
        emit RewardsPerWeightUpdated(rewardsPerWeight_.accumulated);
    }

    // Accumulate rewards for an user.
    // Needs to be called on each staking/unstaking event.
    function _updateUserRewards(
        address _user,
        uint32 _weight,
        bool _increase
    ) internal checkForUpgrade returns (uint96) {
        UserRewards memory userRewards_ = AvatarsEscrowStorage.layout().rewards[_user];
        RewardsPerWeight memory rewardsPerWeight_ = AvatarsEscrowStorage.layout().rewardsPerWeight;

        // Calculate and update the new value user reserves.
        userRewards_.accumulated = userRewards_.accumulated
            + userRewards_.stakedWeight * (rewardsPerWeight_.accumulated - userRewards_.checkpoint);
        userRewards_.checkpoint = rewardsPerWeight_.accumulated;

        if (_weight != 0) {
            if (_increase) {
                userRewards_.stakedWeight += _weight;
            } else {
                userRewards_.stakedWeight -= _weight;
            }
            emit WeightUpdated(_user, _increase, _weight, block.timestamp);
        }
        AvatarsEscrowStorage.layout().rewards[_user] = userRewards_;
        emit UserRewardsUpdated(_user, userRewards_.accumulated, userRewards_.checkpoint);

        return userRewards_.accumulated;
    }

    function _ensureEOAorERC721Receiver(address _to) internal checkForUpgrade {
        uint32 size;
        assembly {
            size := extcodesize(_to)
        }
        if (size > 0) {
            try IERC721Receiver(_to).onERC721Received(address(this), address(this), 0, "") returns (bytes4 retval) {
                require(retval == IERC721Receiver.onERC721Received.selector, "ET"); // ET: neither EOA nor ERC721Receiver
            } catch (bytes memory) {
                revert("ET"); // ET: neither EOA nor ERC721Receiver
            }
        }
    }

    // ======== function overrides ========

    // Prevent sending ERC721 tokens directly to this contract
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external view override returns (bytes4) {
        from;
        tokenId;
        data; // supress solidity warnings
        if (operator == address(this)) {
            return this.onERC721Received.selector;
        } else {
            return 0x00000000;
        }
    }
}