
# @version 0.3.1
"""
@title Liquidity Gauge
@author Curve Finance
@license MIT
@notice Implementation contract for use with Curve Factory
"""
from vyper.interfaces import ERC20

implements: ERC20


interface TokenAdmin:
    def getVault() -> address: view
    def future_epoch_time_write() -> uint256: nonpayable
    def rate() -> uint256: view

interface Controller:
    def voting_escrow() -> address: view
    def checkpoint_gauge(addr: address): nonpayable
    def gauge_relative_weight(addr: address, time: uint256) -> uint256: view

interface ERC20Extended:
    def symbol() -> String[32]: view

interface ERC1271:
    def isValidSignature(_hash: bytes32, _signature: Bytes[65]) -> bytes32: view

interface Minter:
    def getBalancerTokenAdmin() -> address: view
    def getGaugeController() -> address: view
    def minted(user: address, gauge: address) -> uint256: view

interface VotingEscrow:
    def user_point_epoch(addr: address) -> uint256: view
    def user_point_history__ts(addr: address, epoch: uint256) -> uint256: view

interface VotingEscrowBoost:
    def adjusted_balance_of(_account: address) -> uint256: view


event Deposit:
    provider: indexed(address)
    value: uint256

event Withdraw:
    provider: indexed(address)
    value: uint256

event UpdateLiquidityLimit:
    user: indexed(address)
    original_balance: uint256
    original_supply: uint256
    working_balance: uint256
    working_supply: uint256

event Transfer:
    _from: indexed(address)
    _to: indexed(address)
    _value: uint256

event Approval:
    _owner: indexed(address)
    _spender: indexed(address)
    _value: uint256

event RewardDistributorUpdated:
    reward_token: indexed(address)
    distributor: address

event RelativeWeightCapChanged:
    new_relative_weight_cap: uint256

struct Reward:
    token: address
    distributor: address
    period_finish: uint256
    rate: uint256
    last_update: uint256
    integral: uint256


CLAIM_FREQUENCY: constant(uint256) = 3600
MAX_REWARDS: constant(uint256) = 8
TOKENLESS_PRODUCTION: constant(uint256) = 40
WEEK: constant(uint256) = 604800

# keccak256("isValidSignature(bytes32,bytes)")[:4] << 224
ERC1271_MAGIC_VAL: constant(bytes32) = 0x1626ba7e00000000000000000000000000000000000000000000000000000000
VERSION: constant(String[8]) = "v5.0.0"

EIP712_TYPEHASH: constant(bytes32) = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
PERMIT_TYPEHASH: constant(bytes32) = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")

BAL_TOKEN_ADMIN: immutable(address)
BAL_VAULT: immutable(address)
AUTHORIZER_ADAPTOR: immutable(address)
GAUGE_CONTROLLER: immutable(address)
MINTER: immutable(address)
VOTING_ESCROW: immutable(address)
VEBOOST_PROXY: immutable(address)

MAX_RELATIVE_WEIGHT_CAP: constant(uint256) = 10 ** 18

# ERC20
balanceOf: public(HashMap[address, uint256])
totalSupply: public(uint256)
_allowance: HashMap[address, HashMap[address, uint256]]

name: public(String[64])
symbol: public(String[40])

# ERC2612
DOMAIN_SEPARATOR: public(bytes32)
nonces: public(HashMap[address, uint256])

# Gauge
lp_token: public(address)

is_killed: public(bool)

# [future_epoch_time uint40][inflation_rate uint216]
inflation_params: uint256

# For tracking external rewards
reward_count: public(uint256)
reward_data: public(HashMap[address, Reward])

# claimant -> default reward receiver
rewards_receiver: public(HashMap[address, address])

# reward token -> claiming address -> integral
reward_integral_for: public(HashMap[address, HashMap[address, uint256]])

# user -> [uint128 claimable amount][uint128 claimed amount]
claim_data: HashMap[address, HashMap[address, uint256]]

working_balances: public(HashMap[address, uint256])
working_supply: public(uint256)

# 1e18 * ∫(rate(t) / totalSupply(t) dt) from (last_action) till checkpoint
integrate_inv_supply_of: public(HashMap[address, uint256])
integrate_checkpoint_of: public(HashMap[address, uint256])

# ∫(balance * rate(t) / totalSupply(t) dt) from 0 till checkpoint
# Units: rate * t = already number of coins per address to issue
integrate_fraction: public(HashMap[address, uint256])

# The goal is to be able to calculate ∫(rate * balance / totalSupply dt) from 0 till checkpoint
# All values are kept in units of being multiplied by 1e18
period: public(int128)

# array of reward tokens
reward_tokens: public(address[MAX_REWARDS])

period_timestamp: public(uint256[100000000000000000000000000000])
# 1e18 * ∫(rate(t) / totalSupply(t) dt) from 0 till checkpoint
integrate_inv_supply: public(uint256[100000000000000000000000000000])  # bump epoch when rate() changes

_relative_weight_cap: uint256

@external
def __init__(minter: address, veBoostProxy: address, authorizerAdaptor: address):
    """
    @param minter Address of minter contract
    @param veBoostProxy Address of boost delegation contract
    """
    gaugeController: address = Minter(minter).getGaugeController()
    balTokenAdmin: address = Minter(minter).getBalancerTokenAdmin()
    BAL_TOKEN_ADMIN = balTokenAdmin
    BAL_VAULT = TokenAdmin(balTokenAdmin).getVault()
    AUTHORIZER_ADAPTOR = authorizerAdaptor
    GAUGE_CONTROLLER = gaugeController
    MINTER = minter
    VOTING_ESCROW = Controller(gaugeController).voting_escrow()
    VEBOOST_PROXY = veBoostProxy
    # prevent initialization of implementation
    self.lp_token = 0x000000000000000000000000000000000000dEaD


# Internal Functions

@view
@internal
def _get_allowance(owner: address, spender: address) -> uint256:
    """
     @dev Override to grant the Vault infinite allowance, causing for Gauge Tokens to not require approval.
     This is sound as the Vault already provides authorization mechanisms when initiating token transfers, which this
     contract inherits.
    """
    if (spender == BAL_VAULT):
        return MAX_UINT256
    return self._allowance[owner][spender]

@internal
@view
def _getCappedRelativeWeight(period: uint256) -> uint256:
    """
    @dev Returns the gauge's relative weight, capped to its _relative_weight_cap attribute.
    """
    return min(Controller(GAUGE_CONTROLLER).gauge_relative_weight(self, period), self._relative_weight_cap)

@internal
def _checkpoint(addr: address):
    """
    @notice Checkpoint for a user
    @dev Updates the BAL emissions a user is entitled to receive
    @param addr User address
    """
    _period: int128 = self.period
    _period_time: uint256 = self.period_timestamp[_period]
    _integrate_inv_supply: uint256 = self.integrate_inv_supply[_period]

    inflation_params: uint256 = self.inflation_params
    rate: uint256 = inflation_params % 2 ** 216
    prev_future_epoch: uint256 = shift(inflation_params, -216)
    new_rate: uint256 = rate

    if prev_future_epoch >= _period_time:
        new_rate = TokenAdmin(BAL_TOKEN_ADMIN).rate()
        self.inflation_params = shift(TokenAdmin(BAL_TOKEN_ADMIN).future_epoch_time_write(), 216) + new_rate

    if self.is_killed:
        # Stop distributing inflation as soon as killed
        rate = 0
        new_rate = 0  # prevent distribution when crossing epochs

    # Update integral of 1/supply
    if block.timestamp > _period_time:
        _working_supply: uint256 = self.working_supply
        Controller(GAUGE_CONTROLLER).checkpoint_gauge(self)
        prev_week_time: uint256 = _period_time
        week_time: uint256 = min((_period_time + WEEK) / WEEK * WEEK, block.timestamp)

        for i in range(500):
            dt: uint256 = week_time - prev_week_time
            w: uint256 = self._getCappedRelativeWeight(prev_week_time / WEEK * WEEK)

            if _working_supply > 0:
                if prev_future_epoch >= prev_week_time and prev_future_epoch < week_time:
                    # If we went across one or multiple epochs, apply the rate
                    # of the first epoch until it ends, and then the rate of
                    # the last epoch.
                    # If more than one epoch is crossed - the gauge gets less,
                    # but that'd meen it wasn't called for more than 1 year
                    _integrate_inv_supply += rate * w * (prev_future_epoch - prev_week_time) / _working_supply
                    rate = new_rate
                    _integrate_inv_supply += rate * w * (week_time - prev_future_epoch) / _working_supply
                else:
                    _integrate_inv_supply += rate * w * dt / _working_supply
                # On precisions of the calculation
                # rate ~= 10e18
                # last_weight > 0.01 * 1e18 = 1e16 (if pool weight is 1%)
                # _working_supply ~= TVL * 1e18 ~= 1e26 ($100M for example)
                # The largest loss is at dt = 1
                # Loss is 1e-9 - acceptable

            if week_time == block.timestamp:
                break
            prev_week_time = week_time
            week_time = min(week_time + WEEK, block.timestamp)

    _period += 1
    self.period = _period
    self.period_timestamp[_period] = block.timestamp
    self.integrate_inv_supply[_period] = _integrate_inv_supply

    # Update user-specific integrals
    _working_balance: uint256 = self.working_balances[addr]
    self.integrate_fraction[addr] += _working_balance * (_integrate_inv_supply - self.integrate_inv_supply_of[addr]) / 10 ** 18
    self.integrate_inv_supply_of[addr] = _integrate_inv_supply
    self.integrate_checkpoint_of[addr] = block.timestamp


@internal
def _checkpoint_rewards(_user: address, _total_supply: uint256, _claim: bool, _receiver: address):
    """
    @notice Claim pending rewards and checkpoint rewards for a user
    """
    user_balance: uint256 = 0
    receiver: address = _receiver
    if _user != ZERO_ADDRESS:
        user_balance = self.balanceOf[_user]
        if _claim and _receiver == ZERO_ADDRESS:
            # if receiver is not explicitly declared, check if a default receiver is set
            receiver = self.rewards_receiver[_user]
            if receiver == ZERO_ADDRESS:
                # if no default receiver is set, direct claims to the user
                receiver = _user

    reward_count: uint256 = self.reward_count
    for i in range(MAX_REWARDS):
        if i == reward_count:
            break
        token: address = self.reward_tokens[i]

        integral: uint256 = self.reward_data[token].integral
        last_update: uint256 = min(block.timestamp, self.reward_data[token].period_finish)
        duration: uint256 = last_update - self.reward_data[token].last_update
        if duration != 0:
            self.reward_data[token].last_update = last_update
            if _total_supply != 0:
                integral += duration * self.reward_data[token].rate * 10**18 / _total_supply
                self.reward_data[token].integral = integral

        if _user != ZERO_ADDRESS:
            integral_for: uint256 = self.reward_integral_for[token][_user]
            new_claimable: uint256 = 0

            if integral_for < integral:
                self.reward_integral_for[token][_user] = integral
                new_claimable = user_balance * (integral - integral_for) / 10**18

            claim_data: uint256 = self.claim_data[_user][token]
            total_claimable: uint256 = shift(claim_data, -128) + new_claimable
            if total_claimable > 0:
                total_claimed: uint256 = claim_data % 2**128
                if _claim:
                    response: Bytes[32] = raw_call(
                        token,
                        _abi_encode(
                            receiver,
                            total_claimable,
                            method_id=method_id("transfer(address,uint256)")
                        ),
                        max_outsize=32,
                    )
                    if len(response) != 0:
                        assert convert(response, bool)
                    self.claim_data[_user][token] = total_claimed + total_claimable
                elif new_claimable > 0:
                    self.claim_data[_user][token] = total_claimed + shift(total_claimable, 128)


@internal
def _update_liquidity_limit(addr: address, l: uint256, L: uint256):
    """
    @notice Calculate limits which depend on the amount of BPT token per-user.
            Effectively it calculates working balances to apply amplification
            of BAL production by BPT
    @param addr User address
    @param l User's amount of liquidity (LP tokens)
    @param L Total amount of liquidity (LP tokens)
    """
    # To be called after totalSupply is updated
    voting_balance: uint256 = VotingEscrowBoost(VEBOOST_PROXY).adjusted_balance_of(addr)
    voting_total: uint256 = ERC20(VOTING_ESCROW).totalSupply()

    lim: uint256 = l * TOKENLESS_PRODUCTION / 100
    if voting_total > 0:
        lim += L * voting_balance / voting_total * (100 - TOKENLESS_PRODUCTION) / 100

    lim = min(l, lim)
    old_bal: uint256 = self.working_balances[addr]
    self.working_balances[addr] = lim
    _working_supply: uint256 = self.working_supply + lim - old_bal
    self.working_supply = _working_supply

    log UpdateLiquidityLimit(addr, l, L, lim, _working_supply)


@internal
def _transfer(_from: address, _to: address, _value: uint256):
    """
    @notice Transfer tokens as well as checkpoint users
    """
    self._checkpoint(_from)
    self._checkpoint(_to)

    if _value != 0:
        total_supply: uint256 = self.totalSupply
        is_rewards: bool = self.reward_count != 0
        if is_rewards:
            self._checkpoint_rewards(_from, total_supply, False, ZERO_ADDRESS)
        new_balance: uint256 = self.balanceOf[_from] - _value
        self.balanceOf[_from] = new_balance
        self._update_liquidity_limit(_from, new_balance, total_supply)

        if is_rewards:
            self._checkpoint_rewards(_to, total_supply, False, ZERO_ADDRESS)
        new_balance = self.balanceOf[_to] + _value
        self.balanceOf[_to] = new_balance
        self._update_liquidity_limit(_to, new_balance, total_supply)

    log Transfer(_from, _to, _value)


# External User Facing Functions


@external
@nonreentrant('lock')
def deposit(_value: uint256, _addr: address = msg.sender, _claim_rewards: bool = False):
    """
    @notice Deposit `_value` LP tokens
    @dev Depositting also claims pending reward tokens
    @param _value Number of tokens to deposit
    @param _addr Address to deposit for
    """

    self._checkpoint(_addr)

    if _value != 0:
        is_rewards: bool = self.reward_count != 0
        total_supply: uint256 = self.totalSupply
        if is_rewards:
            self._checkpoint_rewards(_addr, total_supply, _claim_rewards, ZERO_ADDRESS)

        total_supply += _value
        new_balance: uint256 = self.balanceOf[_addr] + _value
        self.balanceOf[_addr] = new_balance
        self.totalSupply = total_supply

        self._update_liquidity_limit(_addr, new_balance, total_supply)

        ERC20(self.lp_token).transferFrom(msg.sender, self, _value)

    log Deposit(_addr, _value)
    log Transfer(ZERO_ADDRESS, _addr, _value)


@external
@nonreentrant('lock')
def withdraw(_value: uint256, _claim_rewards: bool = False):
    """
    @notice Withdraw `_value` LP tokens
    @dev Withdrawing also claims pending reward tokens
    @param _value Number of tokens to withdraw
    """
    self._checkpoint(msg.sender)

    if _value != 0:
        is_rewards: bool = self.reward_count != 0
        total_supply: uint256 = self.totalSupply
        if is_rewards:
            self._checkpoint_rewards(msg.sender, total_supply, _claim_rewards, ZERO_ADDRESS)

        total_supply -= _value
        new_balance: uint256 = self.balanceOf[msg.sender] - _value
        self.balanceOf[msg.sender] = new_balance
        self.totalSupply = total_supply

        self._update_liquidity_limit(msg.sender, new_balance, total_supply)

        ERC20(self.lp_token).transfer(msg.sender, _value)

    log Withdraw(msg.sender, _value)
    log Transfer(msg.sender, ZERO_ADDRESS, _value)


@external
@nonreentrant('lock')
def claim_rewards(_addr: address = msg.sender, _receiver: address = ZERO_ADDRESS):
    """
    @notice Claim available reward tokens for `_addr`
    @param _addr Address to claim for
    @param _receiver Address to transfer rewards to - if set to
                     ZERO_ADDRESS, uses the default reward receiver
                     for the caller
    """
    if _receiver != ZERO_ADDRESS:
        assert _addr == msg.sender  # dev: cannot redirect when claiming for another user
    self._checkpoint_rewards(_addr, self.totalSupply, True, _receiver)


@external
@nonreentrant('lock')
def transferFrom(_from: address, _to :address, _value: uint256) -> bool:
    """
     @notice Transfer tokens from one address to another.
     @dev Transferring claims pending reward tokens for the sender and receiver
     @param _from address The address which you want to send tokens from
     @param _to address The address which you want to transfer to
     @param _value uint256 the amount of tokens to be transferred
    """
    _allowance: uint256 = self._get_allowance(_from, msg.sender)
    if _allowance != MAX_UINT256:
        self._allowance[_from][msg.sender] = _allowance - _value

    self._transfer(_from, _to, _value)

    return True


@external
@nonreentrant('lock')
def transfer(_to: address, _value: uint256) -> bool:
    """
    @notice Transfer token for a specified address
    @dev Transferring claims pending reward tokens for the sender and receiver
    @param _to The address to transfer to.
    @param _value The amount to be transferred.
    """
    self._transfer(msg.sender, _to, _value)

    return True


@external
def approve(_spender : address, _value : uint256) -> bool:
    """
    @notice Approve the passed address to transfer the specified amount of
            tokens on behalf of msg.sender
    @dev Beware that changing an allowance via this method brings the risk
         that someone may use both the old and new allowance by unfortunate
         transaction ordering. This may be mitigated with the use of
         {incraseAllowance} and {decreaseAllowance}.
         https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    @param _spender The address which will transfer the funds
    @param _value The amount of tokens that may be transferred
    @return bool success
    """
    self._allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)

    return True


@external
def permit(
    _owner: address,
    _spender: address,
    _value: uint256,
    _deadline: uint256,
    _v: uint8,
    _r: bytes32,
    _s: bytes32
) -> bool:
    """
    @notice Approves spender by owner's signature to expend owner's tokens.
        See https://eips.ethereum.org/EIPS/eip-2612.
    @dev Inspired by https://github.com/yearn/yearn-vaults/blob/main/contracts/Vault.vy#L753-L793
    @dev Supports smart contract wallets which implement ERC1271
        https://eips.ethereum.org/EIPS/eip-1271
    @param _owner The address which is a source of funds and has signed the Permit.
    @param _spender The address which is allowed to spend the funds.
    @param _value The amount of tokens to be spent.
    @param _deadline The timestamp after which the Permit is no longer valid.
    @param _v The bytes[64] of the valid secp256k1 signature of permit by owner
    @param _r The bytes[0:32] of the valid secp256k1 signature of permit by owner
    @param _s The bytes[32:64] of the valid secp256k1 signature of permit by owner
    @return True, if transaction completes successfully
    """
    assert _owner != ZERO_ADDRESS
    assert block.timestamp <= _deadline

    nonce: uint256 = self.nonces[_owner]
    digest: bytes32 = keccak256(
        concat(
            b"\x19\x01",
            self.DOMAIN_SEPARATOR,
            keccak256(_abi_encode(PERMIT_TYPEHASH, _owner, _spender, _value, nonce, _deadline))
        )
    )

    if _owner.is_contract:
        sig: Bytes[65] = concat(_abi_encode(_r, _s), slice(convert(_v, bytes32), 31, 1))
        # reentrancy not a concern since this is a staticcall
        assert ERC1271(_owner).isValidSignature(digest, sig) == ERC1271_MAGIC_VAL
    else:
        assert ecrecover(digest, convert(_v, uint256), convert(_r, uint256), convert(_s, uint256)) == _owner

    self._allowance[_owner][_spender] = _value
    self.nonces[_owner] = nonce + 1

    log Approval(_owner, _spender, _value)
    return True


@external
def increaseAllowance(_spender: address, _added_value: uint256) -> bool:
    """
    @notice Increase the allowance granted to `_spender` by the caller
    @dev This is alternative to {approve} that can be used as a mitigation for
         the potential race condition
    @param _spender The address which will transfer the funds
    @param _added_value The amount of to increase the allowance
    @return bool success
    """
    allowance: uint256 = self._get_allowance(msg.sender,_spender) + _added_value
    self._allowance[msg.sender][_spender] = allowance

    log Approval(msg.sender, _spender, allowance)

    return True


@external
def decreaseAllowance(_spender: address, _subtracted_value: uint256) -> bool:
    """
    @notice Decrease the allowance granted to `_spender` by the caller
    @dev This is alternative to {approve} that can be used as a mitigation for
         the potential race condition
    @param _spender The address which will transfer the funds
    @param _subtracted_value The amount of to decrease the allowance
    @return bool success
    """
    allowance: uint256 = self._get_allowance(msg.sender, _spender) - _subtracted_value
    self._allowance[msg.sender][_spender] = allowance

    log Approval(msg.sender, _spender, allowance)

    return True


@external
def user_checkpoint(addr: address) -> bool:
    """
    @notice Record a checkpoint for `addr`
    @param addr User address
    @return bool success
    """
    assert msg.sender in [addr, MINTER]  # dev: unauthorized
    self._checkpoint(addr)
    self._update_liquidity_limit(addr, self.balanceOf[addr], self.totalSupply)
    return True


@external
def set_rewards_receiver(_receiver: address):
    """
    @notice Set the default reward receiver for the caller.
    @dev When set to ZERO_ADDRESS, rewards are sent to the caller
    @param _receiver Receiver address for any rewards claimed via `claim_rewards`
    """
    self.rewards_receiver[msg.sender] = _receiver


@external
def kick(addr: address):
    """
    @notice Kick `addr` for abusing their boost
    @dev Only if either they had another voting event, or their voting escrow lock expired
    @param addr Address to kick
    """
    t_last: uint256 = self.integrate_checkpoint_of[addr]
    t_ve: uint256 = VotingEscrow(VOTING_ESCROW).user_point_history__ts(
        addr, VotingEscrow(VOTING_ESCROW).user_point_epoch(addr)
    )
    _balance: uint256 = self.balanceOf[addr]

    assert ERC20(VOTING_ESCROW).balanceOf(addr) == 0 or t_ve > t_last # dev: kick not allowed
    assert self.working_balances[addr] > _balance * TOKENLESS_PRODUCTION / 100  # dev: kick not needed

    self._checkpoint(addr)
    self._update_liquidity_limit(addr, self.balanceOf[addr], self.totalSupply)


# Administrative Functions


@external
@nonreentrant("lock")
def deposit_reward_token(_reward_token: address, _amount: uint256):
    """
    @notice Deposit a reward token for distribution
    @param _reward_token The reward token being deposited
    @param _amount The amount of `_reward_token` being deposited
    """
    assert msg.sender == self.reward_data[_reward_token].distributor

    self._checkpoint_rewards(ZERO_ADDRESS, self.totalSupply, False, ZERO_ADDRESS)

    response: Bytes[32] = raw_call(
        _reward_token,
        _abi_encode(
            msg.sender, self, _amount, method_id=method_id("transferFrom(address,address,uint256)")
        ),
        max_outsize=32,
    )
    if len(response) != 0:
        assert convert(response, bool)

    period_finish: uint256 = self.reward_data[_reward_token].period_finish
    if block.timestamp >= period_finish:
        self.reward_data[_reward_token].rate = _amount / WEEK
    else:
        remaining: uint256 = period_finish - block.timestamp
        leftover: uint256 = remaining * self.reward_data[_reward_token].rate
        self.reward_data[_reward_token].rate = (_amount + leftover) / WEEK

    self.reward_data[_reward_token].last_update = block.timestamp
    self.reward_data[_reward_token].period_finish = block.timestamp + WEEK


@external
def add_reward(_reward_token: address, _distributor: address):
    """
    @notice Add additional rewards to be distributed to stakers
    @param _reward_token The token to add as an additional reward
    @param _distributor Address permitted to fund this contract with the reward token
    """
    assert _distributor != ZERO_ADDRESS
    assert msg.sender == AUTHORIZER_ADAPTOR  # dev: only owner

    reward_count: uint256 = self.reward_count
    assert reward_count < MAX_REWARDS
    assert self.reward_data[_reward_token].distributor == ZERO_ADDRESS

    self.reward_data[_reward_token].distributor = _distributor
    self.reward_tokens[reward_count] = _reward_token
    self.reward_count = reward_count + 1
    log RewardDistributorUpdated(_reward_token, _distributor)


@external
def set_reward_distributor(_reward_token: address, _distributor: address):
    """
    @notice Reassign the reward distributor for a reward token
    @param _reward_token The reward token to reassign distribution rights to
    @param _distributor The address of the new distributor
    """
    current_distributor: address = self.reward_data[_reward_token].distributor

    assert msg.sender == current_distributor or msg.sender == AUTHORIZER_ADAPTOR
    assert current_distributor != ZERO_ADDRESS
    assert _distributor != ZERO_ADDRESS

    self.reward_data[_reward_token].distributor = _distributor
    log RewardDistributorUpdated(_reward_token, _distributor)

@external
def killGauge():
    """
    @notice Kills the gauge so it always yields a rate of 0 and so cannot mint BAL
    """
    assert msg.sender == AUTHORIZER_ADAPTOR  # dev: only owner

    self.is_killed = True

@external
def unkillGauge():
    """
    @notice Unkills the gauge so it can mint BAL again
    """
    assert msg.sender == AUTHORIZER_ADAPTOR  # dev: only owner

    self.is_killed = False


# View Methods


@view
@external
def claimed_reward(_addr: address, _token: address) -> uint256:
    """
    @notice Get the number of already-claimed reward tokens for a user
    @param _addr Account to get reward amount for
    @param _token Token to get reward amount for
    @return uint256 Total amount of `_token` already claimed by `_addr`
    """
    return self.claim_data[_addr][_token] % 2**128


@view
@external
def claimable_reward(_user: address, _reward_token: address) -> uint256:
    """
    @notice Get the number of claimable reward tokens for a user
    @param _user Account to get reward amount for
    @param _reward_token Token to get reward amount for
    @return uint256 Claimable reward token amount
    """
    integral: uint256 = self.reward_data[_reward_token].integral
    total_supply: uint256 = self.totalSupply
    if total_supply != 0:
        last_update: uint256 = min(block.timestamp, self.reward_data[_reward_token].period_finish)
        duration: uint256 = last_update - self.reward_data[_reward_token].last_update
        integral += (duration * self.reward_data[_reward_token].rate * 10**18 / total_supply)

    integral_for: uint256 = self.reward_integral_for[_reward_token][_user]
    new_claimable: uint256 = self.balanceOf[_user] * (integral - integral_for) / 10**18

    return shift(self.claim_data[_user][_reward_token], -128) + new_claimable


@external
def claimable_tokens(addr: address) -> uint256:
    """
    @notice Get the number of claimable tokens per user
    @dev This function should be manually changed to "view" in the ABI
    @return uint256 number of claimable tokens per user
    """
    self._checkpoint(addr)
    return self.integrate_fraction[addr] - Minter(MINTER).minted(addr, self)


@view
@external
def integrate_checkpoint() -> uint256:
    """
    @notice Get the timestamp of the last checkpoint
    """
    return self.period_timestamp[self.period]


@view
@external
def future_epoch_time() -> uint256:
    """
    @notice Get the locally stored BAL future epoch start time
    """
    return shift(self.inflation_params, -216)


@view
@external
def inflation_rate() -> uint256:
    """
    @notice Get the locally stored BAL inflation rate
    """
    return self.inflation_params % 2 ** 216


@view
@external
def decimals() -> uint256:
    """
    @notice Get the number of decimals for this token
    @dev Implemented as a view method to reduce gas costs
    @return uint256 decimal places
    """
    return 18


@view
@external
def version() -> String[8]:
    """
    @notice Get the version of this gauge contract
    """
    return VERSION

@view
@external
def allowance(owner: address, spender: address) -> uint256:
    """
     @notice Get `spender`'s current allowance from `owner` 
    """
    return self._get_allowance(owner, spender)


# Initializer

@internal
def _setRelativeWeightCap(relative_weight_cap: uint256):
    assert relative_weight_cap <= MAX_RELATIVE_WEIGHT_CAP, "Relative weight cap exceeds allowed absolute maximum"
    self._relative_weight_cap = relative_weight_cap
    log RelativeWeightCapChanged(relative_weight_cap)

@external
def initialize(_lp_token: address, relative_weight_cap: uint256):
    """
    @notice Contract constructor
    @param _lp_token Liquidity Pool contract address
    """
    assert self.lp_token == ZERO_ADDRESS

    self.lp_token = _lp_token

    symbol: String[32] = ERC20Extended(_lp_token).symbol()
    name: String[64] = concat("Balancer ", symbol, " Gauge Deposit")

    self.name = name
    self.symbol = concat(symbol, "-gauge")

    self.DOMAIN_SEPARATOR = keccak256(
        _abi_encode(EIP712_TYPEHASH, keccak256(name), keccak256(VERSION), chain.id, self)
    )

    self.period_timestamp[0] = block.timestamp
    self.inflation_params = shift(TokenAdmin(BAL_TOKEN_ADMIN).future_epoch_time_write(), 216) + TokenAdmin(BAL_TOKEN_ADMIN).rate()
    self._setRelativeWeightCap(relative_weight_cap)

@external
def setRelativeWeightCap(relative_weight_cap: uint256):
    """
    @notice Sets a new relative weight cap for the gauge.
            The value shall be normalized to 1e18, and not greater than MAX_RELATIVE_WEIGHT_CAP.
    @param relative_weight_cap New relative weight cap.
    """
    assert msg.sender == AUTHORIZER_ADAPTOR  # dev: only owner
    self._setRelativeWeightCap(relative_weight_cap)

@external
@view
def getRelativeWeightCap() -> uint256:
    """
    @notice Returns relative weight cap for the gauge.
    """
    return self._relative_weight_cap

@external
@view
def getCappedRelativeWeight(time: uint256) -> uint256:
    """
    @notice Returns the gauge's relative weight for a given time, capped to its _relative_weight_cap attribute.
    @param time Timestamp in the past or present.
    """
    return self._getCappedRelativeWeight(time)

@external
@pure
def getMaxRelativeWeightCap() -> uint256:
    """
    @notice Returns the maximum value that can be set to _relative_weight_cap attribute.
    """
    return MAX_RELATIVE_WEIGHT_CAP