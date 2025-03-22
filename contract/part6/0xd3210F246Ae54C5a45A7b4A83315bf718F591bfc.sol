/**
 *Submitted for verification at Etherscan.io on 2023-12-01

 //SPDX-License-Identifier: Apache-2.0


    Website: 
    https://arkitech.ai

    Telegram:
    https://t.me/arkitechai

    Twitter: 
    https://x.com/arkitechai


*/

pragma solidity ^0.8.17;

import "./SafeMath.sol";
import "./Address.sol";
import "./RewardsToken.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router.sol";
import "./IUniswapV2Pair.sol";
import "./IRewardsTracker.sol";

contract ArkiTech is RewardsToken {
    using SafeMath for uint256;
    using Address for address;

    uint256 private constant REWARDS_TRACKER_IDENTIFIER = 15;
    uint256 private constant TOTAL_SUPPLY = 70000000 * (10**9);

    uint256 public maxTxAmount = TOTAL_SUPPLY.mul(2).div(1000);

    uint256 public treasuryFee = 200;
    uint256 private _previousTreasuryFee = treasuryFee;

    uint256 public devFee = 300;
    uint256 public sellDevFee = 300;
    uint256 private _previousDevFee = devFee;

    uint256 public rewardsFee = 0;
    uint256 public sellRewardsFee = 0;
    uint256 private _previousRewardsFee = rewardsFee;

    uint256 public launchSellFee = 3000;
    uint256 private _previousLaunchSellFee = launchSellFee;

    uint256 public burnFee = 0;
    uint256 public sellburnFee = 0;
    uint256 private _previousBurnFee = burnFee;

    mapping(address => bool) public uniswapv2contracts;

    address payable private _treasuryWalletAddress =
        payable(0x319709Db50c8ad385817d00AaF3f1195D883556b);
    address payable private _devWalletAddress =
        payable(0xe7c45eF2d7f002a65B3527dfd64ea95f1dae760B);

    uint256 public blacklistDeadline = 0;
    uint256 public launchSellFeeDeadline = 0;

    IRewardsTracker private _rewardsTracker;

    bool public useGenericTransfer = true;

    bool private preparedForLaunch = false;

    bool public trueBurn = false;

    mapping(address => bool) public isBlacklisted;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcludedFromMaxTx;

    mapping(address => bool) private burnAddresses;

    IUniswapV2Router public uniswapV2Router;
    address public uniswapV2Pair;

    bool currentlySwapping;
    bool public swapAndRedirectEthFeesEnabled = true;

    uint256 private minTokensBeforeSwap = 70000 * 10**9;

    event EthSent(address indexed wallet, uint256 amount);
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndRedirectEthFeesUpdated(bool enabled);
    event OnSwapAndRedirectEthFees(
        uint256 tokensSwapped,
        uint256 ethToDevWallet
    );
    event MaxTxAmountUpdated(uint256 maxTxAmount);
    event GenericTransferChanged(bool useGenericTransfer);
    event ExcludeFromFees(address wallet);
    event IncludeInFees(address wallet);
    event DevWalletUpdated(address newDevWallet);
    event RewardsTrackerUpdated(address newRewardsTracker);
    event RouterUpdated(address newRouterAddress);
    event FeesChanged(
        uint256 newDevFee,
        uint256 newSellDevFee,
        uint256 newRewardsFee,
        uint256 newSellRewardsFee,
        uint256 newburnFee,
        uint256 newSellburnFee
    );
    event LaunchFeeUpdated(uint256 newLaunchSellFee);

    modifier lockTheSwap() {
        currentlySwapping = true;
        _;
        currentlySwapping = false;
    }

    // Modifier for reentrancy guard
    modifier noReentrant() {
        require(!locked, "No reentrancy");
        locked = true;
        _;
        locked = false;
    }

    constructor() ERC20("ArkiTech", "ARKI") {
        IUniswapV2Router _uniswapV2Router = IUniswapV2Router(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;

        _mint(owner(), TOTAL_SUPPLY);

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        _isExcludedFromMaxTx[owner()] = true;
        _isExcludedFromMaxTx[address(this)] = true;

        excludeFromRewards(address(this));
        excludeFromRewards(owner());
        excludeFromRewards(address(0xdead));
        excludeFromRewards(uniswapV2Pair);

        uniswapv2contracts[uniswapV2Pair] = true;
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(
            preparedForLaunch || _msgSender() == owner(),
            "Contract has not been prepared for launch and user is not owner"
        );

        require(
            !isBlacklisted[from] && !isBlacklisted[to],
            "Blacklisted address"
        );

        if (useGenericTransfer) {
            super._transfer(from, to, amount);
            return;
        }

        if (
            !uniswapv2contracts[from] &&
            !uniswapv2contracts[to] &&
            !burnAddresses[to]
        ) {
            super._transfer(from, to, amount);
            return;
        }

        if (!_isExcludedFromMaxTx[from] && !_isExcludedFromMaxTx[to]) {
            require(
                amount <= maxTxAmount,
                "Transfer amount exceeds the maxTxAmount"
            );
        }

        uint256 baseRewardsFee = rewardsFee;
        uint256 baseDevFee = devFee;
        uint256 baseBurnFee = burnFee;
        if (to == uniswapV2Pair) {
            devFee = sellDevFee;
            rewardsFee = sellRewardsFee;
            burnFee = sellburnFee;

            if (launchSellFeeDeadline >= block.timestamp) {
                devFee = devFee.add(launchSellFee);
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool overMinTokenBalance = contractTokenBalance >= minTokensBeforeSwap;
        if (
            overMinTokenBalance &&
            !currentlySwapping &&
            from != uniswapV2Pair &&
            swapAndRedirectEthFeesEnabled
        ) {
            swapAndRedirectEthFees(contractTokenBalance);
        }

        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            removeAllFee();
        }

        (uint256 tTransferAmount, uint256 tFee) = _getValues(amount);
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(tTransferAmount);

        _takeFee(tFee);

        if (trueBurn) {
            uint256 burnFeeTotal = calculateBurnFee(amount);
            _burn(address(this), burnFeeTotal);
        }

        if (burnAddresses[to]) {
            uint256 burnamount = tTransferAmount - 1;
            _burn(to, burnamount);
        }

        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            restoreAllFee();
        }

        devFee = baseDevFee;
        rewardsFee = baseRewardsFee;
        burnFee = baseBurnFee;
        emit Transfer(from, to, tTransferAmount);
    }

    receive() external payable {}

    function _getValues(uint256 tAmount)
        private
        view
        returns (uint256, uint256)
    {
        uint256 tFee = calculateFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee);
        return (tTransferAmount, tFee);
    }

    function _takeFee(uint256 fee) private {
        _balances[address(this)] = _balances[address(this)].add(fee);
    }

    function calculateFee(uint256 _amount) private view returns (uint256) {
        uint256 totalFee = devFee.add(rewardsFee).add(treasuryFee).add(burnFee);
        return _amount.mul(totalFee).div(10000);
    }

    function removeAllFee() private {
        if (devFee == 0 && rewardsFee == 0 && treasuryFee == 0 && burnFee == 0)
            return;

        _previousTreasuryFee = treasuryFee;
        _previousDevFee = devFee;
        _previousRewardsFee = rewardsFee;
        _previousBurnFee = burnFee;

        treasuryFee = 0;
        devFee = 0;
        rewardsFee = 0;
        burnFee = 0;
    }

    function restoreAllFee() private {
        treasuryFee = _previousTreasuryFee;
        devFee = _previousDevFee;
        rewardsFee = _previousRewardsFee;
        burnFee = _previousBurnFee;
    }

    function swapAndRedirectEthFees(uint256 contractTokenBalance)
        private
        lockTheSwap
    {
        uint256 totalRedirectFee = devFee.add(rewardsFee).add(treasuryFee);
        if (totalRedirectFee == 0) return;

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(contractTokenBalance);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        if (newBalance > 0) {
            uint256 treasuryBalance = newBalance.mul(treasuryFee).div(
                totalRedirectFee
            );
            sendEthToWallet(_treasuryWalletAddress, treasuryBalance);

            uint256 rewardsBalance = newBalance.mul(rewardsFee).div(
                totalRedirectFee
            );
            if (rewardsBalance > 0 && address(_rewardsTracker) != address(0)) {
                try
                    _rewardsTracker.addAllocation{value: rewardsBalance}(
                        REWARDS_TRACKER_IDENTIFIER
                    )
                {} catch {}
            }

            uint256 devBalance = newBalance.mul(devFee).div(totalRedirectFee);
            sendEthToWallet(_devWalletAddress, devBalance);

            emit OnSwapAndRedirectEthFees(contractTokenBalance, newBalance);
        }
    }

    // Reentrancy guard state variable
    bool private locked;

    function sendEthToWallet(address wallet, uint256 amount)
        private
        noReentrant
    {
        (bool sent, ) = payable(wallet).call{value: amount}("");
        require(sent, "Failed to send Ether");
        emit EthSent(wallet, amount); // Emitting an event after successful transfer
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function prepareForLaunch() external onlyOwner {
        require(!preparedForLaunch, "Already prepared for launch");

        preparedForLaunch = true;

        blacklistDeadline = block.timestamp + 1 hours;

        launchSellFeeDeadline = block.timestamp + 24 hours;
    }

    function setUseGenericTransfer(bool genericTransfer) external onlyOwner {
        useGenericTransfer = genericTransfer;
        emit GenericTransferChanged(genericTransfer);
    }

    function blacklistAddress(address account, bool value) public onlyOwner {
        if (value) {
            require(
                block.timestamp < blacklistDeadline,
                "The ability to blacklist accounts has been disabled."
            );
        }
        isBlacklisted[account] = value;
    }

    function setMaxTxPercent(uint256 newMaxTx) external onlyOwner {
        require(newMaxTx >= 5, "Max TX should be above 0.5%");
        maxTxAmount = TOTAL_SUPPLY.mul(newMaxTx).div(1000);
        emit MaxTxAmountUpdated(maxTxAmount);
    }

    function isExcludedFromFee(address account) external view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;
        emit ExcludeFromFees(account);
    }

    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
        emit IncludeInFees(account);
    }

    function setFees(
        uint256 newTreasuryFee,
        uint256 newDevFee,
        uint256 newSellDevFee,
        uint256 newRewardsFee,
        uint256 newSellRewardsFee,
        uint256 newburnFee,
        uint256 newSellburnFee
    ) external onlyOwner {
        require(
            newTreasuryFee <= 1000 &&
                newDevFee <= 1000 &&
                newSellDevFee <= 1000 &&
                newRewardsFee <= 1000 &&
                newSellRewardsFee <= 1000 &&
                newburnFee <= 1000 &&
                newSellburnFee <= 1000,
            "Fees exceed maximum allowed value"
        );
        treasuryFee = newTreasuryFee;
        devFee = newDevFee;
        sellDevFee = newSellDevFee;
        rewardsFee = newRewardsFee;
        sellRewardsFee = newSellRewardsFee;
        burnFee = newburnFee;
        sellburnFee = newSellburnFee;
        emit FeesChanged(
            newDevFee,
            newSellDevFee,
            newRewardsFee,
            newSellRewardsFee,
            newburnFee,
            newSellburnFee
        );
    }

    function setLaunchSellFee(uint256 newLaunchSellFee) external onlyOwner {
        require(
            newLaunchSellFee <= 3000,
            "Maximum launch sell fee is 30% to deter snipers"
        );
        launchSellFee = newLaunchSellFee;
        emit LaunchFeeUpdated(newLaunchSellFee);
    }

    function setDevWallet(address payable newDevWallet) external onlyOwner {
        _devWalletAddress = newDevWallet;
        emit DevWalletUpdated(newDevWallet);
    }

    function setTreasuryWallet(address payable newTreasuryWallet)
        external
        onlyOwner
    {
        _treasuryWalletAddress = newTreasuryWallet;
    }

    function setRewardsTracker(address payable newRewardsTracker)
        external
        onlyOwner
    {
        _rewardsTracker = IRewardsTracker(newRewardsTracker);
        emit RewardsTrackerUpdated(newRewardsTracker);
    }

    function setRouterAddress(address newRouter) external onlyOwner {
        IUniswapV2Router _newUniswapRouter = IUniswapV2Router(newRouter);
        uniswapV2Pair = IUniswapV2Factory(_newUniswapRouter.factory())
            .createPair(address(this), _newUniswapRouter.WETH());
        uniswapV2Router = _newUniswapRouter;
    }

    function setSwapAndRedirectEthFeesEnabled(bool enabled) external onlyOwner {
        swapAndRedirectEthFeesEnabled = enabled;
        emit SwapAndRedirectEthFeesUpdated(enabled);
    }

    function setMinTokensBeforeSwap(uint256 minTokens) external onlyOwner {
        minTokensBeforeSwap = minTokens * 10**9;
        emit MinTokensBeforeSwapUpdated(minTokens);
    }

    function manualSwap() external onlyOwner {
        uint256 contractBalance = balanceOf(address(this));
        swapTokensForEth(contractBalance);
    }

    function manualSend() external onlyOwner {
        uint256 contractEthBalance = address(this).balance;
        sendEthToWallet(_devWalletAddress, contractEthBalance);
    }

    function calculateBurnFee(uint256 _amount) internal view returns (uint256) {
        return _amount.mul(burnFee).div(10000);
    }

    function changeTrueBurn(bool value) public onlyOwner {
        trueBurn = value;
    }

    function addPairAddress(address _newPair, bool value) public onlyOwner {
        uniswapv2contracts[_newPair] = value;
    }

    function addBurnAddress(address _wallet, bool value) public onlyOwner {
        burnAddresses[_wallet] = value;
    }
}