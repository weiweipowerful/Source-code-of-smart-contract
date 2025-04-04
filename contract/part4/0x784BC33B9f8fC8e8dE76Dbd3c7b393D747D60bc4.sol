
# @version 0.3.7

"""
@title Voting Escrow
@author Curve Finance
@license MIT
@notice Votes have a weight depending on time, so that users are
        committed to the future of (whatever they are voting for)
@dev Vote weight decays linearly over time. Lock time cannot be
     more than `MAXTIME` (set by creator).
"""

# Voting escrow to have time-weighted votes
# Votes have a weight depending on time, so that users are committed
# to the future of (whatever they are voting for).
# The weight in this implementation is linear, and lock cannot be more than maxtime:
# w ^
# 1 +        /
#   |      /
#   |    /
#   |  /
#   |/
# 0 +--------+------> time
#       maxtime

struct Point:
    bias: int128
    slope: int128  # - dweight / dt
    ts: uint256
    blk: uint256  # block
# We cannot really do block numbers per se b/c slope is per time, not per block
# and per block could be fairly bad b/c Ethereum changes blocktimes.
# What we can do is to extrapolate ***At functions

struct LockedBalance:
    amount: int128
    end: uint256


interface ERC20:
    def decimals() -> uint256: view
    def name() -> String[64]: view
    def symbol() -> String[32]: view
    def balanceOf(account: address) -> uint256: view
    def transfer(to: address, amount: uint256) -> bool: nonpayable
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def transferFrom(spender: address, to: address, amount: uint256) -> bool: nonpayable


# Interface for checking whether address belongs to a whitelisted
# type of a smart wallet.
# When new types are added - the whole contract is changed
# The check() method is modifying to be able to use caching
# for individual wallet addresses
interface SmartWalletChecker:
    def check(addr: address) -> bool: nonpayable

interface BalancerMinter:
    def mint(gauge: address) -> uint256: nonpayable

interface RewardDistributor:
    def depositToken(token: address, amount: uint256): nonpayable

DEPOSIT_FOR_TYPE: constant(int128) = 0
CREATE_LOCK_TYPE: constant(int128) = 1
INCREASE_LOCK_AMOUNT: constant(int128) = 2
INCREASE_UNLOCK_TIME: constant(int128) = 3


event CommitOwnership:
    admin: address

event ApplyOwnership:
    admin: address

event EarlyUnlock:
    status: bool

event PenaltySpeed:
    penalty_k: uint256

event PenaltyTreasury:
    penalty_treasury: address

event TotalUnlock:
    status: bool

event RewardReceiver:
    newReceiver: address

event Deposit:
    provider: indexed(address)
    value: uint256
    locktime: indexed(uint256)
    type: int128
    ts: uint256

event Withdraw:
    provider: indexed(address)
    value: uint256
    ts: uint256

event WithdrawEarly:
    provider: indexed(address)
    penalty: uint256
    time_left: uint256

event Supply:
    prevSupply: uint256
    supply: uint256


WEEK: constant(uint256) = 7 * 86400  # all future times are rounded by week
MAXTIME: public(uint256)
MULTIPLIER: constant(uint256) = 10**18

TOKEN: public(address)

NAME: String[64]
SYMBOL: String[32]
DECIMALS: uint256

supply: public(uint256)
locked: public(HashMap[address, LockedBalance])

epoch: public(uint256)
point_history: public(Point[100000000000000000000000000000])  # epoch -> unsigned point
user_point_history: public(HashMap[address, Point[1000000000]])  # user -> Point[user_epoch]
user_point_epoch: public(HashMap[address, uint256])
slope_changes: public(HashMap[uint256, int128])  # time -> signed slope change

# Checker for whitelisted (smart contract) wallets which are allowed to deposit
# The goal is to prevent tokenizing the escrow
future_smart_wallet_checker: public(address)
smart_wallet_checker: public(address)

admin: public(address)

# unlock admins can be set only once. Zero-address means unlock is disabled
admin_unlock_all: public(address)
admin_early_unlock: public(address)

future_admin: public(address)

is_initialized: public(bool)

early_unlock: public(bool)
penalty_k: public(uint256)
prev_penalty_k: public(uint256)
penalty_upd_ts: public(uint256)
PENALTY_COOLDOWN: constant(uint256) = 60 # cooldown to prevent font-run on penalty change
PENALTY_MULTIPLIER: constant(uint256) = 10

penalty_treasury: public(address)

balMinter: public(address)
balToken: public(address)
rewardReceiver: public(address)
rewardReceiverChangeable: public(bool)

rewardDistributor: public(address)

all_unlock: public(bool)


@external
def initialize(
    _token_addr: address,
    _name: String[64],
    _symbol: String[32],
    _admin_addr: address,
    _admin_unlock_all: address,
    _admin_early_unlock: address,
    _max_time: uint256,
    _balToken: address,
    _balMinter: address,
    _rewardReceiver: address,
    _rewardReceiverChangeable: bool,
    _rewardDistributor: address
):
    """
    @notice Contract constructor
    @param _token_addr 80/20 Token-WETH BPT token address
    @param _name Token name
    @param _symbol Token symbol
    @param _admin_addr Contract admin address
    @param _admin_unlock_all Admin to enable Unlock-All feature (zero-address to disable forever)
    @param _admin_early_unlock Admin to enable Eraly-Unlock feature (zero-address to disable forever)
    @param _max_time Locking max time
    @param _balToken Address of the Balancer token
    @param _balMinter Address of the Balancer minter
    @param _rewardReceiver Address of the reward receiver
    @param _rewardReceiverChangeable Boolean indicating whether the reward receiver is changeable
    @param _rewardDistributor The RewardDistributor contract address
    """

    assert(not self.is_initialized), 'only once'
    self.is_initialized = True

    assert(_admin_addr != empty(address)), '!empty'
    self.admin = _admin_addr

    self.penalty_k = 10
    self.prev_penalty_k = 10
    self.penalty_upd_ts = block.timestamp
    self.penalty_treasury = _admin_addr

    self.TOKEN = _token_addr
    self.point_history[0].blk = block.number
    self.point_history[0].ts = block.timestamp

    _decimals: uint256 = ERC20(_token_addr).decimals()  # also validates token for non-zero
    assert (_decimals >= 6 and _decimals <= 255), '!decimals'

    self.NAME = _name
    self.SYMBOL = _symbol
    self.DECIMALS = _decimals

    assert(_max_time >= WEEK and _max_time <= WEEK * 52 * 5), '!maxlock'
    self.MAXTIME = _max_time

    self.admin_unlock_all = _admin_unlock_all
    self.admin_early_unlock = _admin_early_unlock

    self.balToken = _balToken
    self.balMinter = _balMinter
    self.rewardReceiver = _rewardReceiver
    self.rewardReceiverChangeable = _rewardReceiverChangeable
    self.rewardDistributor = _rewardDistributor


@external
@view
def token() -> address:
    return self.TOKEN

@external
@view
def name() -> String[64]:
    return self.NAME

@external
@view
def symbol() -> String[32]:
    return self.SYMBOL

@external
@view
def decimals() -> uint256:
    return self.DECIMALS

@external
def commit_transfer_ownership(addr: address):
    """
    @notice Transfer ownership of VotingEscrow contract to `addr`
    @param addr Address to have ownership transferred to
    """
    assert msg.sender == self.admin  # dev: admin only
    self.future_admin = addr
    log CommitOwnership(addr)


@external
def apply_transfer_ownership():
    """
    @notice Apply ownership transfer
    """
    assert msg.sender == self.admin  # dev: admin only
    _admin: address = self.future_admin
    assert _admin != empty(address)  # dev: admin not set
    self.admin = _admin
    log ApplyOwnership(_admin)


@external
def commit_smart_wallet_checker(addr: address):
    """
    @notice Set an external contract to check for approved smart contract wallets
    @param addr Address of Smart contract checker
    """
    assert msg.sender == self.admin
    self.future_smart_wallet_checker = addr

@external
def apply_smart_wallet_checker():
    """
    @notice Apply setting external contract to check approved smart contract wallets
    """
    assert msg.sender == self.admin
    self.smart_wallet_checker = self.future_smart_wallet_checker


@internal
def assert_not_contract(addr: address):
    """
    @notice Check if the call is from a whitelisted smart contract, revert if not
    @param addr Address to be checked
    """
    if addr != tx.origin:
        checker: address = self.smart_wallet_checker
        if checker != empty(address):
            if SmartWalletChecker(checker).check(addr):
                return
        raise "Smart contract depositors not allowed"


@external
def set_early_unlock(_early_unlock: bool):
    """
    @notice Sets the availability for users to unlock their locks before lock-end with penalty
    @dev Only the admin_early_unlock can execute this function.
    @param _early_unlock A boolean indicating whether early unlock is allowed or not.
    """
    assert msg.sender == self.admin_early_unlock, '!admin'  # dev: admin_early_unlock only
    assert _early_unlock != self.early_unlock, 'already'
    
    self.early_unlock = _early_unlock
    log EarlyUnlock(_early_unlock)


@external
def set_early_unlock_penalty_speed(_penalty_k: uint256):
    """
    @notice Sets penalty speed for early unlocking
    @dev Only the admin can execute this function. To prevent frontrunning we use PENALTY_COOLDOWN period
    @param _penalty_k Coefficient indicating the penalty speed for early unlock.
                      Must be between 0 and 50, inclusive. Default 10 - means linear speed.
    """
    assert msg.sender == self.admin_early_unlock, '!admin'  # dev: admin_early_unlock only
    assert _penalty_k <= 50, '!k'
    assert block.timestamp > self.penalty_upd_ts + PENALTY_COOLDOWN, 'early' # to avoid frontrun

    self.prev_penalty_k = self.penalty_k
    self.penalty_k = _penalty_k
    self.penalty_upd_ts = block.timestamp

    log PenaltySpeed(_penalty_k)


@external
def set_penalty_treasury(_penalty_treasury: address):
    """
    @notice Sets penalty treasury address
    @dev Only the admin_early_unlock can execute this function.
    @param _penalty_treasury The address to collect early penalty (default admin address)
    """
    assert msg.sender == self.admin_early_unlock, '!admin'  # dev: admin_early_unlock only
    assert _penalty_treasury != empty(address), '!zero'
   
    self.penalty_treasury = _penalty_treasury
    log PenaltyTreasury(_penalty_treasury)


@external
def set_all_unlock():
    """
    @notice Deactivates VotingEscrow and allows users to unlock their locks before lock-end. 
            New deposits will no longer be accepted.
    @dev Only the admin_unlock_all can execute this function. Make sure there are no rewards for distribution in other contracts.
    """
    assert msg.sender == self.admin_unlock_all, '!admin'  # dev: admin_unlock_all only
    self.all_unlock = True
    log TotalUnlock(True)


@external
@view
def get_last_user_slope(addr: address) -> int128:
    """
    @notice Get the most recently recorded rate of voting power decrease for `addr`
    @param addr Address of the user wallet
    @return Value of the slope
    """
    uepoch: uint256 = self.user_point_epoch[addr]
    return self.user_point_history[addr][uepoch].slope


@external
@view
def user_point_history__ts(_addr: address, _idx: uint256) -> uint256:
    """
    @notice Get the timestamp for checkpoint `_idx` for `_addr`
    @param _addr User wallet address
    @param _idx User epoch number
    @return Epoch time of the checkpoint
    """
    return self.user_point_history[_addr][_idx].ts


@external
@view
def locked__end(_addr: address) -> uint256:
    """
    @notice Get timestamp when `_addr`'s lock finishes
    @param _addr User wallet
    @return Epoch time of the lock end
    """
    return self.locked[_addr].end


@internal
def _checkpoint(addr: address, old_locked: LockedBalance, new_locked: LockedBalance):
    """
    @notice Record global and per-user data to checkpoint
    @param addr User's wallet address. No user checkpoint if 0x0
    @param old_locked Pevious locked amount / end lock time for the user
    @param new_locked New locked amount / end lock time for the user
    """
    u_old: Point = empty(Point)
    u_new: Point = empty(Point)
    old_dslope: int128 = 0
    new_dslope: int128 = 0
    _epoch: uint256 = self.epoch

    if addr != empty(address):
        # Calculate slopes and biases
        # Kept at zero when they have to
        if old_locked.end > block.timestamp and old_locked.amount > 0:
            u_old.slope = old_locked.amount / convert(self.MAXTIME, int128)
            u_old.bias = u_old.slope * convert(old_locked.end - block.timestamp, int128)
        if new_locked.end > block.timestamp and new_locked.amount > 0:
            u_new.slope = new_locked.amount / convert(self.MAXTIME, int128)
            u_new.bias = u_new.slope * convert(new_locked.end - block.timestamp, int128)


        # Read values of scheduled changes in the slope
        # old_locked.end can be in the past and in the future
        # new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
        old_dslope = self.slope_changes[old_locked.end]
        if new_locked.end != 0:
            if new_locked.end == old_locked.end:
                new_dslope = old_dslope
            else:
                new_dslope = self.slope_changes[new_locked.end]

    last_point: Point = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number})
    if _epoch > 0:
        last_point = self.point_history[_epoch]
    last_checkpoint: uint256 = last_point.ts
    # initial_last_point is used for extrapolation to calculate block number
    # (approximately, for *At methods) and save them
    # as we cannot figure that out exactly from inside the contract
    initial_last_point: Point = last_point
    block_slope: uint256 = 0  # dblock/dt
    if block.timestamp > last_point.ts:
        block_slope = MULTIPLIER * (block.number - last_point.blk) / (block.timestamp - last_point.ts)
    # If last point is already recorded in this block, slope=0
    # But that's ok b/c we know the block in such case

    # Go over weeks to fill history and calculate what the current point is
    t_i: uint256 = (last_checkpoint / WEEK) * WEEK
    for i in range(255):
        # Hopefully it won't happen that this won't get used in 5 years!
        # If it does, users will be able to withdraw but vote weight will be broken
        t_i += WEEK
        d_slope: int128 = 0
        if t_i > block.timestamp:
            t_i = block.timestamp
        else:
            d_slope = self.slope_changes[t_i]
        last_point.bias -= last_point.slope * convert(t_i - last_checkpoint, int128)
        last_point.slope += d_slope
        if last_point.bias < 0:  # This can happen
            last_point.bias = 0
        if last_point.slope < 0:  # This cannot happen - just in case
            last_point.slope = 0
        last_checkpoint = t_i
        last_point.ts = t_i
        last_point.blk = initial_last_point.blk + block_slope * (t_i - initial_last_point.ts) / MULTIPLIER
        _epoch += 1
        if t_i == block.timestamp:
            last_point.blk = block.number
            break
        else:
            self.point_history[_epoch] = last_point

    self.epoch = _epoch
    # Now point_history is filled until t=now

    if addr != empty(address):
        # If last point was in this block, the slope change has been applied already
        # But in such case we have 0 slope(s)
        last_point.slope += (u_new.slope - u_old.slope)
        last_point.bias += (u_new.bias - u_old.bias)
        if last_point.slope < 0:
            last_point.slope = 0
        if last_point.bias < 0:
            last_point.bias = 0

    # Record the changed point into history
    self.point_history[_epoch] = last_point

    if addr != empty(address):
        # Schedule the slope changes (slope is going down)
        # We subtract new_user_slope from [new_locked.end]
        # and add old_user_slope to [old_locked.end]
        if old_locked.end > block.timestamp:
            # old_dslope was <something> - u_old.slope, so we cancel that
            old_dslope += u_old.slope
            if new_locked.end == old_locked.end:
                old_dslope -= u_new.slope  # It was a new deposit, not extension
            self.slope_changes[old_locked.end] = old_dslope

        if new_locked.end > block.timestamp:
            if new_locked.end > old_locked.end:
                new_dslope -= u_new.slope  # old slope disappeared at this point
                self.slope_changes[new_locked.end] = new_dslope
            # else: we recorded it already in old_dslope

        # Now handle user history
        user_epoch: uint256 = self.user_point_epoch[addr] + 1

        self.user_point_epoch[addr] = user_epoch
        u_new.ts = block.timestamp
        u_new.blk = block.number
        self.user_point_history[addr][user_epoch] = u_new


@internal
def _deposit_for(_addr: address, _value: uint256, unlock_time: uint256, locked_balance: LockedBalance, type: int128):
    """
    @notice Deposit and lock tokens for a user
    @param _addr User's wallet address
    @param _value Amount to deposit
    @param unlock_time New time when to unlock the tokens, or 0 if unchanged
    @param locked_balance Previous locked amount / timestamp
    """
    # block all new deposits (and extensions) in case of unlocked contract
    assert (not self.all_unlock), "all unlocked,no sense"

    _locked: LockedBalance = locked_balance
    supply_before: uint256 = self.supply

    self.supply = supply_before + _value
    old_locked: LockedBalance = _locked
    # Adding to existing lock, or if a lock is expired - creating a new one
    _locked.amount += convert(_value, int128)
    if unlock_time != 0:
        _locked.end = unlock_time
    self.locked[_addr] = _locked

    # Possibilities:
    # Both old_locked.end could be current or expired (>/< block.timestamp)
    # value == 0 (extend lock) or value > 0 (add to lock or extend lock)
    # _locked.end > block.timestamp (always)
    self._checkpoint(_addr, old_locked, _locked)

    if _value != 0:
        assert ERC20(self.TOKEN).transferFrom(_addr, self, _value, default_return_value=True)

    log Deposit(_addr, _value, _locked.end, type, block.timestamp)
    log Supply(supply_before, supply_before + _value)


@external
def checkpoint():
    """
    @notice Record global data to checkpoint
    """
    self._checkpoint(empty(address), empty(LockedBalance), empty(LockedBalance))


@external
@nonreentrant("lock")
def deposit_for(_addr: address, _value: uint256):
    """
    @notice Deposit `_value` tokens for `_addr` and add to the lock
    @dev Anyone (even a smart contract) can deposit for someone else, but
         cannot extend their locktime and deposit for a brand new user
    @param _addr User's wallet address
    @param _value Amount to add to user's lock
    """
    _locked: LockedBalance = self.locked[_addr]

    assert _value > 0  # dev: need non-zero value
    assert _locked.amount > 0, "No existing lock found"
    assert _locked.end > block.timestamp, "Cannot add to expired lock. Withdraw"

    self._deposit_for(_addr, _value, 0, self.locked[_addr], DEPOSIT_FOR_TYPE)


@external
@nonreentrant("lock")
def create_lock(_value: uint256, _unlock_time: uint256):
    """
    @notice Deposit `_value` tokens for `msg.sender` and lock until `_unlock_time`
    @param _value Amount to deposit
    @param _unlock_time Epoch time when tokens unlock, rounded down to whole weeks
    """
    self.assert_not_contract(msg.sender)
    unlock_time: uint256 = (_unlock_time / WEEK) * WEEK  # Locktime is rounded down to weeks
    _locked: LockedBalance = self.locked[msg.sender]

    assert _value > 0  # dev: need non-zero value
    assert _locked.amount == 0, "Withdraw old tokens first"
    assert (unlock_time > block.timestamp), "Can only lock until time in the future"
    assert (unlock_time <= block.timestamp + self.MAXTIME), "Voting lock too long"

    self._deposit_for(msg.sender, _value, unlock_time, _locked, CREATE_LOCK_TYPE)


@external
@nonreentrant("lock")
def increase_amount(_value: uint256):
    """
    @notice Deposit `_value` additional tokens for `msg.sender`
            without modifying the unlock time
    @param _value Amount of tokens to deposit and add to the lock
    """
    self.assert_not_contract(msg.sender)
    _locked: LockedBalance = self.locked[msg.sender]

    assert _value > 0  # dev: need non-zero value
    assert _locked.amount > 0, "No existing lock found"
    assert _locked.end > block.timestamp, "Cannot add to expired lock. Withdraw"

    self._deposit_for(msg.sender, _value, 0, _locked, INCREASE_LOCK_AMOUNT)


@external
@nonreentrant("lock")
def increase_unlock_time(_unlock_time: uint256):
    """
    @notice Extend the unlock time for `msg.sender` to `_unlock_time`
    @param _unlock_time New epoch time for unlocking
    """
    self.assert_not_contract(msg.sender)
    _locked: LockedBalance = self.locked[msg.sender]
    unlock_time: uint256 = (_unlock_time / WEEK) * WEEK  # Locktime is rounded down to weeks

    assert _locked.end > block.timestamp, "Lock expired"
    assert _locked.amount > 0, "Nothing is locked"
    assert unlock_time > _locked.end, "Can only increase lock duration"
    assert (unlock_time <= block.timestamp + self.MAXTIME), "Voting lock too long"

    self._deposit_for(msg.sender, 0, unlock_time, _locked, INCREASE_UNLOCK_TIME)


@external
@nonreentrant("lock")
def withdraw():
    """
    @notice Withdraw all tokens for `msg.sender`
    @dev Only possible if the lock has expired
    """
    _locked: LockedBalance = self.locked[msg.sender]
    assert block.timestamp >= _locked.end or self.all_unlock, "lock !expire or !unlock"
    value: uint256 = convert(_locked.amount, uint256)

    old_locked: LockedBalance = _locked
    _locked.end = 0
    _locked.amount = 0
    self.locked[msg.sender] = _locked
    supply_before: uint256 = self.supply
    self.supply = supply_before - value

    # old_locked can have either expired <= timestamp or zero end
    # _locked has only 0 end
    # Both can have >= 0 amount
    self._checkpoint(msg.sender, old_locked, _locked)

    assert ERC20(self.TOKEN).transfer(msg.sender, value, default_return_value=True)

    log Withdraw(msg.sender, value, block.timestamp)
    log Supply(supply_before, supply_before - value)


@external
@nonreentrant("lock")
def withdraw_early():
    """
    @notice Withdraws locked tokens for `msg.sender` before lock-end with penalty
    @dev Only possible if `early_unlock` is enabled (true)
    By defualt there is linear formula for calculating penalty. 
    In some cases an admin can configure penalty speed using `set_early_unlock_penalty_speed()`
    
    L - lock amount
    k - penalty coefficient, defined by admin (default 1)
    Tleft - left time to unlock
    Tmax - MAXLOCK time
    Penalty amount = L * k * (Tlast / Tmax)
    """
    assert(self.early_unlock == True), "!early unlock"

    _locked: LockedBalance = self.locked[msg.sender]
    assert block.timestamp < _locked.end, "lock expired"

    value: uint256 = convert(_locked.amount, uint256)

    time_left: uint256 = _locked.end - block.timestamp
    
    # to avoid front-run with penalty_k
    penalty_k_: uint256 = 0
    if block.timestamp > self.penalty_upd_ts + PENALTY_COOLDOWN:
        penalty_k_ = self.penalty_k
    else:
        penalty_k_ = self.prev_penalty_k

    penalty_ratio: uint256 = (time_left * MULTIPLIER / self.MAXTIME) * penalty_k_
    penalty: uint256 = (value * penalty_ratio / MULTIPLIER) / PENALTY_MULTIPLIER    
    if penalty > value:
        penalty = value
    user_amount: uint256 = value - penalty

    old_locked: LockedBalance = _locked
    _locked.end = 0
    _locked.amount = 0
    self.locked[msg.sender] = _locked
    supply_before: uint256 = self.supply
    self.supply = supply_before - value

    # old_locked can have either expired <= timestamp or zero end
    # _locked has only 0 end
    # Both can have >= 0 amount
    self._checkpoint(msg.sender, old_locked, _locked)

    if penalty > 0:
        assert ERC20(self.TOKEN).transfer(self.penalty_treasury, penalty, default_return_value=True)
    if user_amount > 0:
        assert ERC20(self.TOKEN).transfer(msg.sender, user_amount, default_return_value=True)

    log Withdraw(msg.sender, value, block.timestamp)
    log Supply(supply_before, supply_before - value)
    log WithdrawEarly(msg.sender, penalty, time_left)


# The following ERC20/minime-compatible methods are not real balanceOf and supply!
# They measure the weights for the purpose of voting, so they don't represent
# real coins.

@internal
@view
def find_block_epoch(_block: uint256, max_epoch: uint256) -> uint256:
    """
    @notice Binary search to find epoch containing block number
    @param _block Block to find
    @param max_epoch Don't go beyond this epoch
    @return Epoch which contains _block
    """
    # Binary search
    _min: uint256 = 0
    _max: uint256 = max_epoch
    for i in range(128):  # Will be always enough for 128-bit numbers
        if _min >= _max:
            break
        _mid: uint256 = (_min + _max + 1) / 2
        if self.point_history[_mid].blk <= _block:
            _min = _mid
        else:
            _max = _mid - 1
    return _min

@internal
@view
def find_timestamp_epoch(_timestamp: uint256, max_epoch: uint256) -> uint256:
    """
    @notice Binary search to find epoch for timestamp
    @param _timestamp timestamp to find
    @param max_epoch Don't go beyond this epoch
    @return Epoch which contains _timestamp
    """
    # Binary search
    _min: uint256 = 0
    _max: uint256 = max_epoch
    for i in range(128):  # Will be always enough for 128-bit numbers
        if _min >= _max:
            break
        _mid: uint256 = (_min + _max + 1) / 2
        if self.point_history[_mid].ts <= _timestamp:
            _min = _mid
        else:
            _max = _mid - 1
    return _min


@internal
@view
def find_block_user_epoch(_addr: address, _block: uint256, max_epoch: uint256) -> uint256:
    """
    @notice Binary search to find epoch for block number
    @param _addr User for which to find user epoch for
    @param _block Block to find
    @param max_epoch Don't go beyond this epoch
    @return Epoch which contains _block
    """
    # Binary search
    _min: uint256 = 0
    _max: uint256 = max_epoch
    for i in range(128):  # Will be always enough for 128-bit numbers
        if _min >= _max:
            break
        _mid: uint256 = (_min + _max + 1) / 2
        if self.user_point_history[_addr][_mid].blk <= _block:
            _min = _mid
        else:
            _max = _mid - 1
    return _min


@internal
@view
def find_timestamp_user_epoch(_addr: address, _timestamp: uint256, max_epoch: uint256) -> uint256:
    """
    @notice Binary search to find user epoch for timestamp
    @param _addr User for which to find user epoch for
    @param _timestamp timestamp to find
    @param max_epoch Don't go beyond this epoch
    @return Epoch which contains _timestamp
    """
    # Binary search
    _min: uint256 = 0
    _max: uint256 = max_epoch
    for i in range(128):  # Will be always enough for 128-bit numbers
        if _min >= _max:
            break
        _mid: uint256 = (_min + _max + 1) / 2
        if self.user_point_history[_addr][_mid].ts <= _timestamp:
            _min = _mid
        else:
            _max = _mid - 1
    return _min

@external
@view
def balanceOf(addr: address, _t: uint256 = block.timestamp) -> uint256:
    """
    @notice Get the current voting power for `msg.sender`
    @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
    @param addr User wallet address
    @param _t Epoch time to return voting power at
    @return User voting power
    """
    _epoch: uint256 = 0
    if _t == block.timestamp:
        # No need to do binary search, will always live in current epoch
        _epoch = self.user_point_epoch[addr]
    else:
        _epoch = self.find_timestamp_user_epoch(addr, _t, self.user_point_epoch[addr])

    if _epoch == 0:
        return 0
    else:
        last_point: Point = self.user_point_history[addr][_epoch]
        last_point.bias -= last_point.slope * convert(_t - last_point.ts, int128)
        if last_point.bias < 0:
            last_point.bias = 0
        return convert(last_point.bias, uint256)


@external
@view
def balanceOfAt(addr: address, _block: uint256) -> uint256:
    """
    @notice Measure voting power of `addr` at block height `_block`
    @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
    @param addr User's wallet address
    @param _block Block to calculate the voting power at
    @return Voting power
    """
    # Copying and pasting totalSupply code because Vyper cannot pass by
    # reference yet
    assert _block <= block.number

    _user_epoch: uint256 = self.find_block_user_epoch(addr, _block, self.user_point_epoch[addr])
    upoint: Point = self.user_point_history[addr][_user_epoch]

    max_epoch: uint256 = self.epoch
    _epoch: uint256 = self.find_block_epoch(_block, max_epoch)
    point_0: Point = self.point_history[_epoch]
    d_block: uint256 = 0
    d_t: uint256 = 0
    if _epoch < max_epoch:
        point_1: Point = self.point_history[_epoch + 1]
        d_block = point_1.blk - point_0.blk
        d_t = point_1.ts - point_0.ts
    else:
        d_block = block.number - point_0.blk
        d_t = block.timestamp - point_0.ts
    block_time: uint256 = point_0.ts
    if d_block != 0:
        block_time += d_t * (_block - point_0.blk) / d_block

    upoint.bias -= upoint.slope * convert(block_time - upoint.ts, int128)
    if upoint.bias >= 0:
        return convert(upoint.bias, uint256)
    else:
        return 0


@internal
@view
def supply_at(point: Point, t: uint256) -> uint256:
    """
    @notice Calculate total voting power at some point in the past
    @param point The point (bias/slope) to start search from
    @param t Time to calculate the total voting power at
    @return Total voting power at that time
    """
    last_point: Point = point
    t_i: uint256 = (last_point.ts / WEEK) * WEEK
    for i in range(255):
        t_i += WEEK
        d_slope: int128 = 0
        if t_i > t:
            t_i = t
        else:
            d_slope = self.slope_changes[t_i]
        last_point.bias -= last_point.slope * convert(t_i - last_point.ts, int128)
        if t_i == t:
            break
        last_point.slope += d_slope
        last_point.ts = t_i

    if last_point.bias < 0:
        last_point.bias = 0
    return convert(last_point.bias, uint256)


@external
@view
def totalSupply(t: uint256 = block.timestamp) -> uint256:
    """
    @notice Calculate total voting power
    @dev Adheres to the ERC20 `totalSupply` interface for Aragon compatibility
    @return Total voting power
    """
    _epoch: uint256 = 0
    if t == block.timestamp:
        # No need to do binary search, will always live in current epoch
        _epoch = self.epoch
    else:
        _epoch = self.find_timestamp_epoch(t, self.epoch)

    if _epoch == 0:
        return 0
    else:
        last_point: Point = self.point_history[_epoch]
        return self.supply_at(last_point, t)


@external
@view
def totalSupplyAt(_block: uint256) -> uint256:
    """
    @notice Calculate total voting power at some point in the past
    @param _block Block to calculate the total voting power at
    @return Total voting power at `_block`
    """
    assert _block <= block.number
    _epoch: uint256 = self.epoch
    target_epoch: uint256 = self.find_block_epoch(_block, _epoch)

    point: Point = self.point_history[target_epoch]
    dt: uint256 = 0
    if target_epoch < _epoch:
        point_next: Point = self.point_history[target_epoch + 1]
        if point.blk != point_next.blk:
            dt = (_block - point.blk) * (point_next.ts - point.ts) / (point_next.blk - point.blk)
    else:
        if point.blk != block.number:
            dt = (_block - point.blk) * (block.timestamp - point.ts) / (block.number - point.blk)
    # Now dt contains info on how far are we beyond point

    return self.supply_at(point, point.ts + dt)

@external
@nonreentrant("lock")
def claimExternalRewards():
    """
    @notice Claims BAL rewards
    @dev Only possible if the TOKEN is Guage contract
    """
    BalancerMinter(self.balMinter).mint(self.TOKEN)
    balBalance: uint256 = ERC20(self.balToken).balanceOf(self)
    if balBalance > 0:
        # distributes rewards using rewardDistributor into current week
        if self.rewardReceiver == self.rewardDistributor:
            assert ERC20(self.balToken).approve(self.rewardDistributor, balBalance, default_return_value=True)
            RewardDistributor(self.rewardDistributor).depositToken(self.balToken, balBalance)
        else:
            assert ERC20(self.balToken).transfer(self.rewardReceiver, balBalance, default_return_value=True)


@external
def changeRewardReceiver(newReceiver: address):
    """
    @notice Changes the reward receiver address
    @param newReceiver New address to set as the reward receiver
    """
    assert msg.sender == self.admin, '!admin'
    assert (self.rewardReceiverChangeable), '!available'
    assert newReceiver != empty(address), '!empty'

    self.rewardReceiver = newReceiver
    log RewardReceiver(newReceiver)