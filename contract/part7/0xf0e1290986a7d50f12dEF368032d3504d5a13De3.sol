// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Game.sol';
import './interfaces/ISoup.sol';
import './interfaces/ILiquidityPot.sol';
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

// Join us: https://soup.game

/**
 * @title Freezer
 * @dev Allows users to deposit (freeze) Soup tokens in time-based “batches” that gradually defrost, 
 * returning tokens to circulation under configurable conditions. Helps manage circulating supply by 
 * locking tokens until certain defrost or grace periods pass.
 *
 * Key Features:
 * - Users freeze Soup tokens in batches, each with a maximum size and grace period.
 * - Defrosting logic gradually transitions tokens from “solid” (locked) to “liquid” (usable), 
 *   while accounting for deflation.
 * - Removes oldest or expired batches if the freezer is at capacity.
 * - Provides safe, transparent retrieval methods for owners to reclaim or remove their tokens.
 */


contract Freezer is Ownable, ReentrancyGuard {
  using ABDKMath64x64 for int128;
  using SafeERC20 for IERC20;

  struct UserInfo {
    uint256 amount;
    uint256[] batchIds;
  }

  struct Info {
    uint256 nextSlotAvailableAt;
    uint256 batchDefrostTime;
    uint256 availableSlots;
    uint256 maxBatchSize;
    uint256 minBatchSize;
    uint256 usedCapacity;
    uint256 gracePeriod;
    uint256 totalSoup;
    uint256 capacity;
  }

  struct Batch {
    uint256 id;
    address user;
    uint256 size;
    uint256 frozenAt;
    uint256 removedAt;
    uint256 prevBatchId;
    uint256 nextBatchId;
    uint256 reclaimedAt;
    uint256 initialAmount;
    uint256 _amountLiquid;
    uint256 _currentAmount;
    uint256 amountRecovered;
    uint256 defrostDuration;
    uint256 _canBeRemovedAt;
    uint256 _fullyDefrostedAt;
    uint256 usersBatchIdIndex;
  }

  Batch[] public batches;

  uint256 public newestBatchId;
  uint256 public oldestBatchId;

  uint256 public maxDepositAmount;

  Game public game;
  ISoup public soup;
  ILiquidityPot public liquidityPot;

  bool public depositsEnabled;
  uint256 public usedCapacity;
  int128 public deflationRate;

  // Info of each user.
  mapping(address => UserInfo) public userInfo;

  // Events
  event Deposit(address indexed user, uint256 amount, uint256 batchId);
  event WithdrawBatch(address indexed user, uint256 amount, uint256 batchId);
  event ReclaimedLiquid(address indexed user, uint256 batchId, uint256 amount);
  event AddedToLiquidityPot(address indexed user, uint256 batchId, uint256 lpAmount, uint256 soupAmount, uint256 ethAmount);

  IUniswapV2Router02 public router;
  address public wethAddress;

  constructor(ISoup _soup, Game _game, ILiquidityPot _liquidityPot) {
    soup = _soup;
    game = _game;
    liquidityPot = _liquidityPot;
    deflationRate = soup.deflationRate();
    wethAddress = liquidityPot.wethAddress();
    router = IUniswapV2Router02(liquidityPot.router());
  }

  /**
   * @notice Get the maximum batch size
   * @return The maximum batch size
   */
  function maxBatchSize() public view returns (uint256) {
    return (soup.totalSupply() * game.get('maxBatchSize')) / 100_000;
  }

  /**
   * @notice Get the minimum batch size
   * @return The minimum batch size
   */
  function minBatchSize() public view returns (uint256) {
    return (soup.totalLiquidSupply() * game.get('minBatchSize')) / 100_000;
  }

  /**
   * @notice Deposit soup tokens into the freezer
   * @param _amount The amount of soup tokens to deposit
   */
  function deposit(uint256 _amount) external nonReentrant {
    require(game.get('publicDepositsEnabled') > 0, "deposits disabled");
    require(_amount >= minBatchSize(), "not enough soup");
    require(_amount <= maxBatchSize(), "too much soup");

    require(soup.balanceOf(msg.sender) >= _amount, "insufficient soup balance");
    require(soup.allowance(msg.sender, address(this)) >= _amount, "insufficient soup allowance");

    uint256 batchSize = getBatchSize(_amount);
    while (usedCapacity + batchSize > capacity())
      removeOldestBatch();

    UserInfo storage user = userInfo[msg.sender];
    IERC20(address(soup)).safeTransferFrom(msg.sender, address(this), _amount);
    soup.freeze(_amount);

    batches.push();
    uint256 batchId = batches.length - 1;
    Batch storage batch = batches[batchId];

    batch.defrostDuration = game.get('batchDefrostTime');
    batch.usersBatchIdIndex = user.batchIds.length;
    batch.prevBatchId = newestBatchId;
    batch.frozenAt = block.timestamp;
    batch.initialAmount = _amount;
    batch.user = msg.sender;
    batch.size = batchSize;
    batch.id = batchId;

    if (batchId != 0)
      batches[newestBatchId].nextBatchId = batchId;
    else oldestBatchId = batchId;

    newestBatchId = batchId;

    user.batchIds.push(batchId);

    usedCapacity += batchSize;

    emit Deposit(msg.sender, _amount, batchId);

    soup.debase();
  }

  /**
   * @notice Withdraw a batch of soup tokens
   * @param _batchId The ID of the batch to withdraw
   */
  function withdrawBatch(uint256 _batchId) external nonReentrant {
    Batch storage batch = batches[_batchId];
    require(batch.user == msg.sender, "not your batch");
    require(batch.removedAt == 0, "Batch already withdrawn");

    _removeBatch(batch);

    emit WithdrawBatch(msg.sender, batch.initialAmount, batch.id);

    soup.debase();
  }

  /**
   * @notice Add a batch of soup tokens to the liquidity pot
   * @param batchId The ID of the batch to add
   */
  function addToLiquidityPot(uint256 batchId) external payable nonReentrant {
    Batch storage batch = batches[batchId];

    require(batch.user == msg.sender, 'not your batch');

    uint256 availableAmount = _calculateLiquid(batch) + _calculateSolid(batch);

    address[] memory path = new address[](2);
    path[0] = wethAddress; path[1] = address(soup);
    uint256[] memory amounts = router.getAmountsOut(msg.value, path);
    require(amounts[1] > (availableAmount * liquiditySlippage())/100,
      'Supplied ETH should be worth the total batch amount after slippage is applied');

    batch.amountRecovered += availableAmount;
    soup.unfreeze(address(this), availableAmount);
    _addLiquidity(availableAmount, address(this));

    IERC20 lpToken = liquidityPot.stakingToken();
    uint256 lpBalance = lpToken.balanceOf(address(this));
    lpToken.approve(address(liquidityPot), lpBalance);
    liquidityPot.stakeFor(msg.sender, lpBalance);

    emit AddedToLiquidityPot(msg.sender, batch.id, lpBalance, availableAmount, msg.value);

    _removeBatch(batch);
    _deleteBatch(batch);
    soup.debase();
  }

  /**
   * @notice Internal function to add liquidity to the Uniswap pool
   * @param soupAmount The amount of soup tokens to add
   * @param recipient The recipient address for LP tokens
   */
  function _addLiquidity(uint256 soupAmount, address recipient) internal {
    // Approve the router to spend the specified amount of soup tokens
    soup.approve(address(router), soupAmount);

    // Add liquidity to the Uniswap pool
    // Approve the router to spend the specified amount of soup tokens
    router.addLiquidityETH{ value: address(this).balance }(
      address(soup),               // Token address
      soupAmount,                 // Amount of tokens to add
      0,                         // Minimum amount of tokens to add (slippage protection)
      0,                        // Minimum amount of ETH to add (slippage protection)
      recipient,               // Recipient address for LP tokens
      block.timestamp + 1800  // Deadline: 30 minutes from the current block time
    );
  }

  /**
   * @notice Reclaim the liquid portion of a batch of soup tokens
   * @param _batchId The ID of the batch to reclaim
   */
  function reclaimLiquid(uint256 _batchId) external nonReentrant {
    Batch storage batch = batches[_batchId];
    require(batch.user == msg.sender, "not the user's batch");

    soup.debase();

    require(isRemoved(batch), "batch not yet withdrawn");

    uint256 availableAmount = _calculateLiquid(batch);

    // Claiming available amount should never be mroe than the unrecovered amount
    // These two lines should not be needed, but protecting for best practice.
    uint256 unrecovered = batch.initialAmount - batch.amountRecovered;
    availableAmount = (availableAmount > unrecovered) ? unrecovered : availableAmount;

    batch.amountRecovered += availableAmount;
    if (block.timestamp < batch.removedAt + batch.defrostDuration) {
      require(availableAmount > 0, "nothing to reclaim");
      batch.reclaimedAt = block.timestamp;
    } else _deleteBatch(batch);

    soup.unfreeze(msg.sender, availableAmount);
    emit ReclaimedLiquid(msg.sender, batch.id, availableAmount);
  }

  /**
   * @notice Internal function to delete a batch
   * @param batch The batch to delete
   */
  function _deleteBatch(Batch storage batch) private {
    UserInfo storage user = userInfo[batch.user];

    soup.accountForDefrostedDeflation(batch.initialAmount - batch.amountRecovered);

    if (batch.usersBatchIdIndex < user.batchIds.length - 1) {
      uint256 replacementBatchId = user.batchIds[user.batchIds.length - 1];
      user.batchIds[batch.usersBatchIdIndex] = replacementBatchId;
      batches[replacementBatchId].usersBatchIdIndex = batch.usersBatchIdIndex;
    } // else, it's the last batch in the user's list, so just pop()

    user.batchIds.pop();
    delete batches[batch.id];
  }

  /**
   * @notice Calculate the liquid portion of a batch of soup tokens
   * @param _batchId The ID of the batch to calculate
   * @return The amount of liquid soup tokens
   */
  function calculateLiquid(uint256 _batchId) public view returns (uint256) {
    Batch storage batch = batches[_batchId];
    return _calculateLiquid(batch);
  }

  /**
   * @notice Internal function to calculate the solid portion of a batch of soup tokens
   * @param batch The batch to calculate
   * @return The amount of solid soup tokens
   */
  function _calculateSolid(Batch memory batch) internal view returns (uint256) {
    if (!isRemoved(batch)) return batch.initialAmount;

    uint256 defrostDuration = batch.defrostDuration;
    uint256 defrostRate = batch.initialAmount / defrostDuration;

    uint256 totalDefrostTime = Math.min(defrostDuration, block.timestamp - batch.removedAt);
    return batch.initialAmount - (defrostRate * totalDefrostTime);
  }

  /**
   * @notice Internal function to calculate the liquid portion of a batch of soup tokens
   * @param batch The batch to calculate
   * @return The amount of liquid soup tokens
   */
  function _calculateLiquid(Batch memory batch) internal view returns (uint256) {
    if (!isRemoved(batch)) return 0;

    uint256 defrostDuration = batch.defrostDuration;
    uint256 remainingDefrostDuration = defrostDuration;
    if (batch.reclaimedAt != 0)
      remainingDefrostDuration = defrostDuration - (batch.reclaimedAt - batch.removedAt);

    uint256 elapsedTime = block.timestamp - Math.max(batch.removedAt, batch.reclaimedAt);
    uint256 defrostTime = Math.min(elapsedTime, remainingDefrostDuration);
    uint256 fullyThawedDelfationTime = elapsedTime - defrostTime;
    uint256 defrostRate = batch.initialAmount / defrostDuration; // Amount that defrosts per second

    int128 one = ABDKMath64x64.fromUInt(1);

    // Since liquid portion subject to deflation, we use this equation:
    // Calculate defrostRate * ((deflationRate^defrostTime - 1) / (deflationRate - 1))
    int128 defrostDeflationFactor = deflationRate.pow(defrostTime);
    int128 numerator = defrostDeflationFactor.sub(one);
    int128 denominator = deflationRate.sub(one);
    int128 fraction = numerator.div(denominator);
    uint256 available = fraction.mulu(defrostRate);

    // after it finishes the process of defrosting, the
    // remaining amount is subject to normal deflation:
    // amount * deflationRate^deflationTime
    int128 fullyThawedDeflation = deflationRate.pow(fullyThawedDelfationTime);
    return fullyThawedDeflation.mulu(available);
  }

  /**
   * @notice Internal function to get the batch size for a given amount of soup tokens
   * @param _amount The amount of soup tokens
   * @return The batch size
   */
  function getBatchSize(uint256 _amount) internal view returns (uint256) {
    uint256 maxBatch = maxBatchSize();
    if (_amount <= maxBatch / 4) return 1;
    if (_amount <= maxBatch / 2) return 2;
    if (_amount <= (3 * maxBatch) / 4) return 3;
    return 4;
  }

  /**
   * @notice Internal function to remove a batch of soup tokens
   * @param batch The batch to remove
   */
  function _removeBatch(Batch storage batch) internal {
    if (isRemoved(batch)) return;
    uint256 prevBatchId = batch.prevBatchId;
    uint256 nextBatchId = batch.nextBatchId;

    batch.removedAt = block.timestamp;
    usedCapacity -= batch.size;

    if (oldestBatchId != batch.id)
      batches[prevBatchId].nextBatchId = nextBatchId;
    else oldestBatchId = nextBatchId;

    if (nextBatchId != 0)
      batches[nextBatchId].prevBatchId = prevBatchId;
    else newestBatchId = prevBatchId;
  }

  /**
   * @notice Internal function to remove the oldest batch of soup tokens
   */
  function removeOldestBatch() internal {
    Batch storage batch = batches[oldestBatchId];
    require(isExpired(batch), 'oldest batch still within grace period');
    _removeBatch(batch);
  }

  /**
   * @notice Get the freezer capacity
   * @return The freezer capacity
   */
  function capacity() public view returns (uint256) {
    return game.get('freezerCapacity');
  }

  /**
   * @notice Get the permitted liquidity slippage
   * @return The permitted liquidity slippage
   */
  function liquiditySlippage() public view returns (uint256) {
    return game.get('liquiditySlippage');
  }

  /**
   * @notice Get information about the freezer
   * @return An Info struct containing information about the freezer
   */
  function getInfo() public view returns (Info memory) {
    uint256 gracePeriod = game.get('freezerGracePeriod');
    uint256 currentCapacity = Math.max(capacity(), usedCapacity);

    uint256 nextSlotAvailableAt;
    if (usedCapacity == currentCapacity) {
      Batch storage oldestBatch = batches[oldestBatchId];
      nextSlotAvailableAt = isExpired(oldestBatch) ? 0 : oldestBatch.frozenAt + gracePeriod;
    }

    Info memory info = Info({
      availableSlots: (currentCapacity - usedCapacity) + calculateExpiredSlots(),
      batchDefrostTime: game.get('batchDefrostTime'),
      nextSlotAvailableAt: nextSlotAvailableAt,
      minBatchSize: minBatchSize(),
      maxBatchSize: maxBatchSize(),
      usedCapacity: usedCapacity,
      gracePeriod: gracePeriod,
      totalSoup: totalSoup(),
      capacity: capacity()
    });

    return info;
  }

  /**
   * @notice Check if a batch of soup tokens has expired
   * @param batch The batch to check
   * @return True if the batch has expired, false otherwise
   */
  function isExpired(Batch memory batch) public view returns (bool) {
    uint256 gracePeriod = game.get('freezerGracePeriod');
    return batch.frozenAt + gracePeriod < block.timestamp;
  }

  /**
   * @notice Calculate the number of expired slots in the freezer
   * @return The number of expired slots
   */
  function calculateExpiredSlots() public view returns (uint256) {
    uint256 currentBatchId = oldestBatchId;
    uint256 freeSlots = 0;

    if (currentBatchId == 0 && batches.length > 0) {
      Batch memory batch = batches[currentBatchId];
      if (isExpired(batch)) freeSlots += batch.size;
      currentBatchId = batch.nextBatchId;
    }

    while (currentBatchId != 0) {
      Batch memory batch = batches[currentBatchId];
      if (!isExpired(batch)) break;

      freeSlots += batch.size;
      currentBatchId = batch.nextBatchId;
    }

    return freeSlots;
  }

  /**
   * @notice Get the batches of a user
   * @param user The address of the user
   * @param page The page number
   * @param pageSize The number of batches per page
   * @return An array of batches
   */
  function getUserBatches(address user, uint256 page, uint256 pageSize) public view returns (Batch[] memory) {
    uint256 gracePeriod = game.get('freezerGracePeriod');
    UserInfo memory info = userInfo[user];

    if (page * pageSize > info.batchIds.length)
      pageSize = 0;
    else if ((page + 1) * pageSize > info.batchIds.length)
      pageSize = info.batchIds.length % pageSize;

    Batch[] memory _batches = new Batch[](pageSize);

    for (uint256 i=0; i < pageSize; i++) {
      Batch memory batch = batches[info.batchIds[(page*pageSize) + i]];
      _batches[i] = batch;
      if (isRemoved(batch))
        batch._amountLiquid = _calculateLiquid(batch);

      batch._canBeRemovedAt = batch.frozenAt + gracePeriod;
      batch._fullyDefrostedAt = batch.removedAt + batch.defrostDuration;
      batch._currentAmount = batch._amountLiquid + _calculateSolid(batch);
    }

    return _batches;
  }

  function getFrozenBatches() public view returns (Batch[] memory) {
    // 1) Count how many batches are frozen
    uint256 length;
    uint256 currentId = oldestBatchId;
    while (currentId != 0) {
      length++;
      currentId = batches[currentId].nextBatchId;
    }

    // 2) Allocate an array of that size
    Batch[] memory allBatches = new Batch[](length);

    // 3) Populate the array by walking the linked list again
    uint256 id = 0;
    currentId = oldestBatchId;
    uint256 gracePeriod = game.get('freezerGracePeriod');
    while (currentId != 0) {
      // Copy from storage into memory
      Batch memory batch = batches[currentId];
      batch._currentAmount = _calculateSolid(batches[currentId]);
      batch._canBeRemovedAt = batch.frozenAt + gracePeriod;

      // Place in our return array
      allBatches[id] = batch;
      id++;

      // Move to the next batch in the linked list
      currentId = batch.nextBatchId;
    }

    return allBatches;
  }


  function totalSoup() public view returns (uint256) {
    // If no batches are active, oldestBatchId will be 0
    // and there's no nextBatchId to follow.
    // This loop exits immediately if currentId == 0.
    uint256 currentId = oldestBatchId;
    uint256 total;

    while (currentId != 0) {
      Batch storage batch = batches[currentId];
      total += _calculateSolid(batch) + _calculateLiquid(batch);
      currentId = batch.nextBatchId;
    }
    return total;
  }


  /**
   * @notice Check if a batch of soup tokens has been removed
   * @param batch The batch to check
   * @return True if the batch has been removed, false otherwise
   */
  function isRemoved(Batch memory batch) public pure returns (bool) {
    return batch.removedAt != 0;
  }

  receive() external payable {}
  fallback() external payable {}
}