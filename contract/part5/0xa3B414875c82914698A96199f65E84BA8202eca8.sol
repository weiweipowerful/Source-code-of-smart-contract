// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./YieldBase.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC1363} from "@openzeppelin/contracts/interfaces/IERC1363.sol";
import {ERC1363Utils} from "@openzeppelin/contracts/token/ERC20/utils/ERC1363Utils.sol";

/**
 * @title YieldTokenProtocol
 * @dev A smart contract for managing yield tokens and rewards in an Ethereum-based yield system.
 * Inherits from ERC20, YieldBase, ReentrancyGuard, Ownable, Pausable, ERC165, and IERC1363.
 *
 * Events:
 * - FixYield(uint256 index, uint256 yield, uint256 totalSupply): Emitted when yield is added.
 * - ClaimRewards(uint256 amount, address indexed claimerAddress): Emitted when rewards are claimed.
 * - DestroyedBlackFunds(address _blackListedUser, uint _balance): Emitted when blacklisted funds are destroyed.
 * - AddedBlackList(address _user): Emitted when an address is added to the blacklist.
 * - RemovedBlackList(address _user): Emitted when a user is removed from the blacklist.
 * - Mint(uint256 amount): Emitted when tokens are minted.
 * - Burn(uint256 amount): Emitted when tokens are burned.
 *
 * Errors:
 * - ERC1363TransferFailed(address receiver, uint256 value): Thrown if the transferAndCall operation fails.
 * - ERC1363TransferFromFailed(address sender, address receiver, uint256 value): Thrown if the transferFromAndCall operation fails.
 * - ERC1363ApproveFailed(address spender, uint256 value): Thrown if the approveAndCall operation fails.
 * - YieldIsNull: Thrown if the provided yield is zero.
 * - AmountIsNull: Thrown if the amount is zero.
 * - AddressIsNull: Thrown if the address is null.
 * - LevelIsWrong(uint256 level): Thrown if the provided level is incorrect.
 * - InsufficientBalance: Thrown if there are insufficient funds.
 * - ValuesAreTooLarge: Thrown if the values are too large.
 *
 * Constants:
 * - N: The constant value used for yield calculations.
 * - DENOMINATOR: The denominator used for reward calculations.
 *
 * State Variables:
 * - yield_tails: An array storing yield tails.
 * - packedIndexesRewards: A mapping of addresses to packed index rewards.
 * - min_rewards_amount: The minimum amount of rewards.
 * - isBlackListed: A mapping of addresses to their blacklist status.
 *
 * Constructor:
 * - Initializes the contract with a name, symbol, and initial supply.
 *
 * Functions:
 * - setMinRewardsAmount(uint256 newMinRewardsAmount): Allows the owner to change the minimum rewards amount.
 * - fixYield(uint256 yield): Fixes the yield by adding the provided yield value to the yields array and updating the yield tails.
 * - getYieldsLength(uint256 level): Returns the length of the yields array for a given level.
 * - getYield(uint256 level, uint256 index): Retrieves the yield value for a given level and index.
 * - getYieldByIndex(uint256 i): Calculates the yield sum for a given index.
 * - getAccumulatedReward(address accountAddress): Calculates the accumulated reward for a given account.
 * - pause(): Triggers stopped state.
 * - unpause(): Unpauses the contract, allowing all functions to be called.
 * - getBlackListStatus(address _maker): Checks if the given address is blacklisted.
 * - addBlackList(address _evilUser): Adds an address to the blacklist.
 * - removeBlackList(address _clearedUser): Removes an address from the blacklist.
 * - destroyBlackFunds(address _blackListedUser): Destroys the funds of a blacklisted user.
 * - mint(uint256 amount): Mints a specified amount of tokens to the owner's address.
 * - burn(uint256 amount): Burns a specific amount of tokens.
 * - transfer(address to, uint256 value): Transfers `value` tokens from the caller's account to the `to` address.
 * - transferFrom(address from, address to, uint256 value): Transfers tokens from one address to another.
 * - setPackedIndexesRewards(address user, uint256 value1, uint256 value2): Sets the packed indexes rewards for a given user.
 * - getPackedIndexesRewards(address user): Retrieves the packed index rewards for a given user.
 * - getClaimableRewards(address accountAddress): Retrieves the total claimable rewards for a given account.
 * - claimRewards(): Allows users to claim their accumulated rewards.
 * - transferAndCall(address to, uint256 value): Transfers tokens and calls a function on the recipient.
 * - transferAndCall(address to, uint256 value, bytes memory data): Transfers tokens and calls a function on the recipient with additional data.
 * - transferFromAndCall(address from, address to, uint256 value): Transfers tokens from one address to another and calls a function on the recipient.
 * - transferFromAndCall(address from, address to, uint256 value, bytes memory data): Transfers tokens from one address to another and calls a function on the recipient with additional data.
 * - approveAndCall(address spender, uint256 value): Sets the allowance and calls a function on the spender.
 * - approveAndCall(address spender, uint256 value, bytes memory data): Sets the allowance and calls a function on the spender with additional data.
 * - supportsInterface(bytes4 interfaceId): Checks if the contract supports a given interface.
 */
contract YieldTokenProtocol is ERC20, YieldBase, ReentrancyGuard, Ownable, Pausable, ERC165, IERC1363 {
    /**
     * @dev Event emitted when yield is added
     * @param index Current index, e.g. length of yields[0]
     * @param yield The amount of yield
     * @param totalSupply Current totalSupply value
     */
    event FixYield(uint256 index, uint256 yield, uint256 totalSupply);

    /**
     * @dev Event emitted when rewards is claimed
     * @param amount The amount of the rewards claimed
     * @param claimerAddress The address of the claimer
     */
    event ClaimRewards(uint256 amount, address indexed claimerAddress);

    /**
     * @dev Emitted when blacklisted funds are destroyed.
     * @param _blackListedUser The address of the blacklisted user.
     * @param _balance The balance of the blacklisted user that was destroyed.
     */
    event DestroyedBlackFunds(address _blackListedUser, uint _balance);

    /**
     * @dev Emitted when an address is added to the blacklist.
     * @param _user The address that was added to the blacklist.
     */
    event AddedBlackList(address _user);

    /**
     * @dev Emitted when a user is removed from the blacklist.
     * @param _user The address of the user that was removed from the blacklist.
     */
    event RemovedBlackList(address _user);

    /**
     * @dev Event emitted when tokens are minted.
     * @param amount The amount of tokens minted.
     */
    event Mint(uint256 amount);

    /**
     * @dev Event emitted when tokens are burned.
     * @param amount The amount of tokens burned.
     */
    event Burn(uint256 amount);

    /**
     * @dev Error if the provided yield is zero
     */
    error YieldIsNull();

    /**
     * @dev Error if the amount is zero
     */
    error AmountIsNull();

    /**
     * @dev Error if the address is null
     */
    error AddressIsNull();

    /**
     * @dev Incorrect level
     */
    error LevelIsWrong(uint256 level);

    /**
     * @dev Insufficient funds
     */
    error InsufficientBalance();

    /**
     * @dev Values are too large
     */
    error ValuesAreTooLarge();

    /**
     * @dev Indicates a failure within the {transfer} part of a transferAndCall operation.
     * @param receiver Address to which tokens are being transferred.
     * @param value Amount of tokens to be transferred.
     */
    error ERC1363TransferFailed(address receiver, uint256 value);

    /**
     * @dev Indicates a failure within the {transferFrom} part of a transferFromAndCall operation.
     * @param sender Address from which to send tokens.
     * @param receiver Address to which tokens are being transferred.
     * @param value Amount of tokens to be transferred.
     */
    error ERC1363TransferFromFailed(address sender, address receiver, uint256 value);

    /**
     * @dev Indicates a failure within the {approve} part of a approveAndCall operation.
     * @param spender Address which will spend the funds.
     * @param value Amount of tokens to be spent.
     */
    error ERC1363ApproveFailed(address spender, uint256 value);

    // Constants
    uint256 private constant N = 5;
    uint256 private immutable DENOMINATOR = 1 * (10 ** decimals());

    // Variables
    uint256[] public yield_tails;
    mapping(address => uint256) private packedIndexesRewards;
    uint256 public min_rewards_amount;
    mapping(address => bool) public isBlackListed;

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) ERC20(_name, _symbol) Ownable(msg.sender) {
        _mint(msg.sender, _initialSupply * (10 ** decimals()));
        yields.push();
        yield_tails.push();
    }

    /**
     * @notice Allows the owner to change the minimum rewards amount.
     * @param newMinRewardsAmount The new minimum rewards amount to be set.
     * @dev This function can only be called by the owner of the contract.
     */
    function setMinRewardsAmount(uint256 newMinRewardsAmount) external onlyOwner {
        min_rewards_amount = newMinRewardsAmount;
    }

    /**
     * @notice Fixes the yield by adding the provided yield value to the yields array and updating the yield tails.
     * @dev This function performs several checks and updates to maintain the integrity of the yields array and yield tails.
     * @param yield The yield value to be fixed. Must be non-zero.
     * @custom:events Emits a `FixYield` event with the provided yield value and a fixed value of 1.
     * @custom:requirements The yield value must be non-zero.
     * @custom:updates Updates the `yields` and `yield_tails` arrays based on the provided yield value.
     * @custom:reverts Reverts with `YieldIsNull` if the provided yield value is zero.
     */
    function fixYield(uint256 yield) external onlyOwner {
        if (yield == 0) {
            revert YieldIsNull();
        }

        if (yields.length == 0) {
            yields.push();
        }

        yields[0].push(yield);

        uint256 levels = yields.length;
        uint256 size = 1;
        for (uint256 level = 0; level < levels; level++) {
            uint256 length = yields[level].length;
            uint256 sum = 0;
            uint256 i = (length % N == 0) ? length - N : length - (length % N);

            for (; i < length; i++) {
                sum += yields[level][i];
            }

            if (length % N == 0) {
                if (yields.length == level + 1) {
                    yields.push();
                    yield_tails.push();
                }
                if (yields[0].length % size == 0) {
                    yields[level + 1].push(sum);
                }
                sum = 0;
            }

            if (level + 1 < yield_tails.length) yield_tails[level + 1] = yield_tails[level] + sum;

            if (length < N) break;
            size *= N;
        }

        emit FixYield(yields[0].length, yield, totalSupply());
    }

    /**
     * @notice Returns the length of the yields array for a given level.
     * @param level The index of the yields array to query.
     * @return length The length of the yields array at the specified level.
     * @dev Reverts with `LevelIsWrong` if the provided level is out of bounds.
     */
    function getYieldsLength(uint256 level) external view returns (uint256 length) {
        if (level >= yields.length) {
            revert LevelIsWrong(level);
        }
        return yields[level].length;
    }

    /**
     * @notice Retrieves the yield value for a given level and index.
     * @param level The level of the yield to retrieve.
     * @param index The index within the specified level to retrieve the yield from.
     * @return yield The yield value at the specified level and index.
     * @dev If the level is out of bounds, the function reverts with a LevelIsWrong error.
     *      If the index is out of bounds, the function returns 0.
     */
    function getYield(uint256 level, uint256 index) external view returns (uint256 yield) {
        if (level >= yields.length) {
            revert LevelIsWrong(level);
        }
        if (index >= yields[level].length) {
            return 0;
        }
        return yields[level][index];
    }

    /**
     * @notice Calculates the yield sum for a given index.
     * @param i The index for which to calculate the yield sum.
     * @return sum The total yield sum for the given index.
     *
     * This function iterates through the levels of the `yields` array and sums up the yields
     * for the specified index. It handles different levels and groups of yields, summing up
     * the yields of remaining periods in each level's group until the specified index is reached.
     * If the top level is reached, it continues summing up the yields for the remaining indices
     * in that level. Finally, it adds the yield tail for the last level to the sum and returns it.
     */
    function getYieldByIndex(uint256 i) public view returns (uint256 sum) {
        require(i <= yields[0].length, "Index out of bounds");
        sum = 0;
        uint256 level = 0;
        uint256 length;
        for (;;) {
            length = yields[level].length;

            // sum up yields of remaining periods in this level's group  (e.g. upto i multiple of N)
            for (; i % N > 0 && i < length; i++) sum += yields[level][i];

            // if we reach top right corner, then leave
            if (i == length) break;

            // continue on next level
            if (level + 1 < yields.length) {
                level++;
                i = i / N;
            } else {
                // or loop on top level
                for (; i < length; i++) sum += yields[level][i];
                break;
            }
        }
        return sum + yield_tails[level];
    }

    /**
     * @notice Calculates the accumulated reward for a given account.
     * @param accountAddress The address of the account to calculate the reward for.
     * @return reward The accumulated reward for the specified account.
     *
     * This function returns 0 if the account has no balance. Otherwise, it calculates
     * the reward based on the account's yield and balance.
     */
    function getAccumulatedReward(address accountAddress) public view returns (uint256 reward) {
        if (balanceOf(accountAddress) == 0) return 0;
        uint256 accountYield = getYieldByIndex(packedIndexesRewards[accountAddress] >> 128);
        reward = (accountYield * balanceOf(accountAddress)) / DENOMINATOR;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The caller must be the owner.
     *
     * This function pauses the contract, preventing state-changing operations.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, allowing all functions to be called.
     * @dev This function can only be called by the owner of the contract.
     * It calls the internal _unpause function to change the paused state.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Checks if the given address is blacklisted.
     * @param _maker The address to check for blacklist status.
     * @return bool Returns true if the address is blacklisted, false otherwise.
     */
    function getBlackListStatus(address _maker) external view returns (bool) {
        return isBlackListed[_maker];
    }

    /**
     * @notice Adds an address to the blacklist.
     * @dev Only the owner can call this function.
     * @param _evilUser The address to be added to the blacklist.
     */
    function addBlackList(address _evilUser) public onlyOwner {
        isBlackListed[_evilUser] = true;
        emit AddedBlackList(_evilUser);
    }

    /**
     * @notice Remove an address from the blacklist.
     * @dev Only the owner can call this function.
     * @param _clearedUser The address to be added to the blacklist.
     */
    function removeBlackList(address _clearedUser) public onlyOwner {
        isBlackListed[_clearedUser] = false;
        emit RemovedBlackList(_clearedUser);
    }

    /**
     * @notice Destroys the funds of a blacklisted user.
     * @dev This function can only be called by the owner. It checks if the user is blacklisted,
     * retrieves their balance, burns the funds, and emits a DestroyedBlackFunds event.
     * @param _blackListedUser The address of the blacklisted user whose funds are to be destroyed.
     */
    function destroyBlackFunds(address _blackListedUser) public onlyOwner {
        require(isBlackListed[_blackListedUser], "Address is not blacklisted");
        uint dirtyFunds = balanceOf(_blackListedUser);
        _burn(_blackListedUser, dirtyFunds);
        emit DestroyedBlackFunds(_blackListedUser, dirtyFunds);
    }

    /**
     * @notice Mints a specified amount of tokens to the owner's address.
     * @dev This function can only be called by the contract owner.
     * @param amount The amount of tokens to mint.
     */
    function mint(uint256 amount) public onlyOwner {
        _mint(owner(), amount);
        emit Mint(amount);
    }

    /**
     * @notice Burns a specific amount of tokens.
     * @dev This function can only be called by the owner of the contract.
     * @param amount The amount of tokens to be burned.
     */
    function burn(uint256 amount) public onlyOwner {
        _burn(owner(), amount);
        emit Burn(amount);
    }

    /**
     * @notice Transfers `value` tokens from the caller's account to the `to` address.
     * @dev Overrides the transfer function to include yield reward calculations.
     * Updates the packedIndexesRewards for both the sender and the recipient with the accumulated rewards.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to transfer.
     * @return bool Returns true if the transfer was successful.
     */
    function transfer(address to, uint256 value) public override(ERC20, IERC20) whenNotPaused returns (bool) {
        address sender = _msgSender();
        require(!isBlackListed[sender], "Blacklisted address");
        uint256 packed = (yields[0].length << 128);
        packedIndexesRewards[sender] = packed | ((packedIndexesRewards[sender] & ((1 << 128) - 1)) + getAccumulatedReward(sender));
        packedIndexesRewards[to] = packed | ((packedIndexesRewards[to] & ((1 << 128) - 1)) + getAccumulatedReward(to));
        _transfer(sender, to, value);
        return true;
    }

    /**
     * @notice Transfers tokens from one address to another.
     * @dev Overrides the transferFrom function to include reward accumulation logic.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to transfer.
     * @return bool Returns true if the transfer was successful.
     */
    function transferFrom(address from, address to, uint256 value) public override(ERC20, IERC20) whenNotPaused returns (bool) {
        require(!isBlackListed[from], "Blacklisted address");
        address spender = _msgSender();
        uint256 packed = (yields[0].length << 128);
        packedIndexesRewards[spender] = packed | ((packedIndexesRewards[spender] & ((1 << 128) - 1)) + getAccumulatedReward(spender));
        packedIndexesRewards[to] = packed | ((packedIndexesRewards[to] & ((1 << 128) - 1)) + getAccumulatedReward(to));
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @notice Sets the packed indexes rewards for a given user.
     * @dev Combines two 128-bit values into a single 256-bit value and stores it in the packedIndexesRewards mapping.
     *      Reverts if either value1 or value2 is greater than or equal to 2^128.
     * @param user The address of the user for whom the packed indexes rewards are being set.
     * @param value1 The first 128-bit value to be packed.
     * @param value2 The second 128-bit value to be packed.
     */
    function setPackedIndexesRewards(address user, uint256 value1, uint256 value2) internal {
        if (value1 >= 2 ** 128 || value2 >= 2 ** 128) {
            revert ValuesAreTooLarge();
        }
        packedIndexesRewards[user] = (value1 << 128) | value2;
    }

    /**
     * @notice Retrieves the packed index rewards for a given user.
     * @param user The address of the user whose packed index rewards are being retrieved.
     * @return value1 The first 128-bit value extracted from the packed index rewards.
     * @return value2 The second 128-bit value extracted from the packed index rewards.
     */
    function getPackedIndexesRewards(address user) public view returns (uint256, uint256) {
        uint256 packed = packedIndexesRewards[user];
        uint256 value1 = packed >> 128;
        uint256 value2 = packed & ((1 << 128) - 1);
        return (value1, value2);
    }

    /**
     * @notice Retrieves the total claimable rewards for a given account.
     * @param accountAddress The address of the account to query rewards for.
     * @return reward The total amount of claimable rewards for the specified account.
     */
    function getClaimableRewards(address accountAddress) public view returns (uint256 reward) {
        (, reward) = getPackedIndexesRewards(accountAddress);
        return reward += getAccumulatedReward(accountAddress);
    }

    /**
     * @notice Allows users to claim their accumulated rewards.
     * @dev This function is protected against reentrancy attacks using the nonReentrant modifier.
     * It calculates the total rewards for the caller, ensures the contract has enough balance,
     * updates the reward indexes, and transfers the rewards to the caller.
     * require The caller must have rewards available to claim.
     * require The contract must have sufficient balance to fulfill the reward claim.
     * emit ClaimRewards Emitted when rewards are successfully claimed.
     */
    function claimRewards() external nonReentrant whenNotPaused {
        address claimer = _msgSender();
        (, uint256 rewards) = getPackedIndexesRewards(claimer);
        rewards += getAccumulatedReward(claimer);
        // Ensure rewards not null
        require(rewards > 0, "No rewards available for claim");
        // Ensure the reward amount more or equal to min_rewards_amount
        require(rewards >= min_rewards_amount, "Rewards amount is less than minimum rewards amount");
        // Ensure the contract has enough balance
        require(balanceOf(address(this)) >= rewards, "Insufficient balance for claim rewards");
        // Update the index before transferring to prevent reentrancy
        setPackedIndexesRewards(claimer, yields[0].length, 0);
        // Transfer the tokens
        _transfer(address(this), claimer, rewards);
        // Emit the event
        emit ClaimRewards(rewards, claimer);
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1363).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     *
     * Requirements:
     *
     * - The target has code (i.e. is a contract).
     * - The target `to` must implement the {IERC1363Receiver} interface.
     * - The target must return the {IERC1363Receiver-onTransferReceived} selector to accept the transfer.
     * - The internal {transfer} must succeed (returned `true`).
     */
    function transferAndCall(address to, uint256 value) public returns (bool) {
        return transferAndCall(to, value, "");
    }

    /**
     * @dev Variant of {transferAndCall} that accepts an additional `data` parameter with
     * no specified format.
     */
    function transferAndCall(address to, uint256 value, bytes memory data) public virtual returns (bool) {
        if (!transfer(to, value)) {
            revert ERC1363TransferFailed(to, value);
        }
        ERC1363Utils.checkOnERC1363TransferReceived(_msgSender(), _msgSender(), to, value, data);
        return true;
    }

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     *
     * Requirements:
     *
     * - The target has code (i.e. is a contract).
     * - The target `to` must implement the {IERC1363Receiver} interface.
     * - The target must return the {IERC1363Receiver-onTransferReceived} selector to accept the transfer.
     * - The internal {transferFrom} must succeed (returned `true`).
     */
    function transferFromAndCall(address from, address to, uint256 value) public returns (bool) {
        return transferFromAndCall(from, to, value, "");
    }

    /**
     * @dev Variant of {transferFromAndCall} that accepts an additional `data` parameter with
     * no specified format.
     */
    function transferFromAndCall(address from, address to, uint256 value, bytes memory data) public virtual returns (bool) {
        if (!transferFrom(from, to, value)) {
            revert ERC1363TransferFromFailed(from, to, value);
        }
        ERC1363Utils.checkOnERC1363TransferReceived(_msgSender(), from, to, value, data);
        return true;
    }

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     *
     * Requirements:
     *
     * - The target has code (i.e. is a contract).
     * - The target `spender` must implement the {IERC1363Spender} interface.
     * - The target must return the {IERC1363Spender-onApprovalReceived} selector to accept the approval.
     * - The internal {approve} must succeed (returned `true`).
     */
    function approveAndCall(address spender, uint256 value) public returns (bool) {
        return approveAndCall(spender, value, "");
    }

    /**
     * @dev Variant of {approveAndCall} that accepts an additional `data` parameter with
     * no specified format.
     */
    function approveAndCall(address spender, uint256 value, bytes memory data) public virtual returns (bool) {
        if (!approve(spender, value)) {
            revert ERC1363ApproveFailed(spender, value);
        }
        ERC1363Utils.checkOnERC1363ApprovalReceived(_msgSender(), spender, value, data);
        return true;
    }
}