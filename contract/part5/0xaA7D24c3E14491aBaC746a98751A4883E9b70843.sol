/*

 ██████╗ ██╗   ██╗██████╗ ██╗   ██╗
██╔════╝ ██║   ██║██╔══██╗██║   ██║
██║  ███╗██║   ██║██████╔╝██║   ██║
██║   ██║██║   ██║██╔══██╗██║   ██║
╚██████╔╝╚██████╔╝██║  ██║╚██████╔╝
 ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ 

ERC20 Token

---------------------------------------------
Website    https://guru.fund
Docs       https://guru-fund.gitbook.io
Twitter    https://x.com/thegurufund
Telegram   https://t.me/guruportal
---------------------------------------------

*/

// SPDX-License-Identifier: MIT

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

import 'contracts/helpers/TransferHelper.sol';

pragma solidity =0.8.27;

contract GURU is
    Ownable,
    ERC20,
    TransferHelper,
    ReentrancyGuard,
    AccessControl
{
    IUniswapV2Router02 public constant router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    bytes32 private constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
    uint256 private constant SUPPLY = 100_000_000 * 10 ** 18;

    bool private feeOnTransfer = true;
    uint8 private kArMA = 10;
    uint8 private burnFee = 0;
    uint8 private vaultFee = 4;
    uint8 private teamFee = 1;

    address public uniswapV2Pair;
    address public vault;
    address public team;

    uint256 public maxWallet = SUPPLY;
    uint256 private swapThreshold = 50_000 * 10 ** 18;

    /**
     * @notice Addresses exempt from fees and max wallet size
     */
    mapping(address => bool) public isExempt;

    error Unauthorized();
    error OnlyReducingFeesAllowed();
    error StillMeditating();
    error ChakraOverload(uint256 projectedBalance, uint256 maxWallet);
    error KarmaMinimum();

    constructor(
        address _team,
        address _vault,
        address _governance
    ) Ownable(msg.sender) ERC20('Guru', 'GURU') {
        _grantRole(ADMIN_ROLE, _governance);

        isExempt[address(this)] = true;
        isExempt[owner()] = true;
        isExempt[_vault] = true;

        _mint(_vault, (SUPPLY * 31) / 100);
        _mint(address(this), (SUPPLY * 69) / 100);

        team = _team;
        vault = _vault;
    }

    receive() external payable {}

    /// External functions

    /**
     * @notice [Owner] Creates a new pair, adds liquidity to it, and sets max wallet
     */
    function enterNirvana() external onlyOwner {
        address pair = IUniswapV2Factory(router.factory()).createPair(
            address(this),
            router.WETH()
        );
        _approve(address(this), address(router), balanceOf(address(this)));
        router.addLiquidityETH{ value: address(this).balance }(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            block.timestamp
        );

        uniswapV2Pair = pair;

        maxWallet = SUPPLY / 100;
    }

    /**
     * @notice [Owner] Slashes the karma fee. Only the owner can do this, until the fee is at minimum.
     */
    function slashTheKarma() external onlyOwner {
        require(kArMA > 1, KarmaMinimum());

        unchecked {
            --kArMA;
        }
    }

    /**
     * @notice [Owner] Manually triggers the burn and swap mechanism.
     */
    function unclog() external onlyOwner {
        _burnAndSwap(swapThreshold, getTotalFeeRate());
    }

    /**
     * @notice [Admin] Reduces or rebalances the transfer fee allocations.
     * Reverts if the new fees exceed the current total fees.
     * @param newBurnFee The new burn fee
     * @param newVaultFee The new vault fee
     * @param newTeamFee The new team fee
     */
    function reduceOrRebalanceFees(
        uint8 newBurnFee,
        uint8 newVaultFee,
        uint8 newTeamFee
    ) external onlyRole(ADMIN_ROLE) {
        require(
            newBurnFee + newVaultFee + newTeamFee <= getTotalFeeRate(),
            OnlyReducingFeesAllowed()
        );

        burnFee = newBurnFee;
        vaultFee = newVaultFee;
        teamFee = newTeamFee;
    }

    /**
     * @notice [Admin] Updates the swap threshold amount.
     * Setting it to 0 keeps the fee on transfer enabled, but disables the swap mechanism.
     * @param value The new swap threshold amount
     */
    function updateSwapThreshold(uint256 value) external onlyRole(ADMIN_ROLE) {
        require(value <= SUPPLY / 50);
        swapThreshold = value;
    }

    /**
     * @notice [Admin] Toggles an address's exemption from fees and max wallet size
     * @param account The address to toggle
     */
    function toggleExemption(address account) external onlyRole(ADMIN_ROLE) {
        isExempt[account] = !isExempt[account];
    }

    /**
     * @notice [Admin] Toggles the fee on transfer. This does not affect buy/sell fees.
     */
    function toggleFeeOnTransfer() external onlyRole(ADMIN_ROLE) {
        feeOnTransfer = !feeOnTransfer;
    }

    /**
     * @notice [Admin] Transfers the admin role
     * @param newAdmin The new admin address
     */
    function transferAdmin(address newAdmin) external onlyRole(ADMIN_ROLE) {
        require(newAdmin != address(0));

        _revokeRole(ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, newAdmin);
    }

    /**
     * @notice [Admin] Updates the vault wallet
     * @param newVault The new vault wallet
     */
    function setVaultWallet(address newVault) external onlyRole(ADMIN_ROLE) {
        vault = _applyWalletUpdate(vault, newVault);
    }

    /**
     * @notice [Admin] Updates the team wallet
     * @param newTeam The new team wallet
     */
    function setTeamWallet(address newTeam) external onlyRole(ADMIN_ROLE) {
        team = _applyWalletUpdate(team, newTeam);
    }

    /**
     * @notice Burns tokens from the caller's balance
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // Public functions

    /**
     * @notice [Admin] Updates the max holding percent
     * @param percent The new max holding percent
     */
    function updateMaxHoldingPercent(
        uint8 percent
    ) public onlyRole(ADMIN_ROLE) {
        require(1 <= percent && percent <= 100);
        maxWallet = (SUPPLY * percent) / 100;
    }

    /**
     * @notice The current total transfer fee
     */
    function getTotalFeeRate() public view returns (uint8) {
        return (burnFee + vaultFee + teamFee) * kArMA;
    }

    // Internal functions

    /**
     * @notice Transfers are disabled until liquidity is added to the pair.
     * @dev This function is used to handle fees on transfer.
     * @param from The sender address
     * @param to The recipient address
     * @param amount The amount of tokens to transfer
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // When liquidity not added yet:
        if (uniswapV2Pair == address(0)) {
            require(
                from == address(this) ||
                    from == address(0) ||
                    from == vault ||
                    to == vault,
                StillMeditating()
            );
            super._update(from, to, amount);
            return;
        }

        // No fees or max wallet size check if exempt
        if (isExempt[from] || isExempt[to]) {
            super._update(from, to, amount);
            return;
        }

        // When liquidity has been added, max wallet size check (pair is exempt)
        if (to != uniswapV2Pair) {
            uint256 projectedBalance = super.balanceOf(to) + amount;
            require(
                projectedBalance <= maxWallet,
                ChakraOverload(projectedBalance, maxWallet)
            );
        }

        // Swap threshold check
        uint8 feeRate = getTotalFeeRate();

        if (
            swapThreshold > 0 &&
            balanceOf(address(this)) >= swapThreshold &&
            from != uniswapV2Pair &&
            (feeOnTransfer || to == uniswapV2Pair)
        ) {
            _burnAndSwap(swapThreshold, feeRate);
        }

        if (feeRate > 0) {
            uint256 feeTokens = (amount * feeRate) / 100;
            amount -= feeTokens;

            super._update(from, address(this), feeTokens);
        }

        // Continue with the transfer
        super._update(from, to, amount);
    }

    // Private functions

    /**
     * @dev Internal function to handle wallet updates and credit transfers
     */
    function _applyWalletUpdate(
        address oldWallet,
        address newWallet
    ) private returns (address) {
        creditByAddress[newWallet] = creditByAddress[oldWallet];
        delete creditByAddress[oldWallet];
        return newWallet;
    }

    /**
     * @notice Burns collected tokens and swaps the remaining for ETH
     * @param tokenAmount The amount of tokens to swap
     * @param feeRate The fee rate
     */
    function _burnAndSwap(
        uint256 tokenAmount,
        uint8 feeRate
    ) private nonReentrant {
        uint256 burnAmount = (tokenAmount * burnFee) / feeRate;
        uint256 swapAmount = tokenAmount - burnAmount;

        if (burnAmount > 0) {
            _burn(address(this), burnAmount);
        }

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        _approve(address(this), address(router), swapAmount);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            swapAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 balance = address(this).balance;

        if (balance > 0) {
            uint256 toTeam = (balance * teamFee) / (vaultFee + teamFee);
            uint256 toVault = balance - toTeam;

            _safeTransferETH(team, toTeam);
            _safeTransferETH(vault, toVault);
        }
    }
}