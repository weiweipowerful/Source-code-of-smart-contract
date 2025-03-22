// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/ITITANX.sol";
import "../interfaces/ITitanBurn.sol";
import "../interfaces/ITitanOnBurn.sol";
import "../interfaces/IShogunOnBurn.sol";
import "../interfaces/IShogun.sol";
import "../interfaces/IX28.sol";

import "./GlobalInfo.sol";
import "./BurnInfo.sol";

//custom errors
error Shogun_NotSupportedContract();
error Shogun_NotAllowed();
error Shogun_InvalidBurnRewardPercent();
error Shogun_LPTokensHasMinted();
error Shogun_InvalidAddress();
error Shogun_UnregisteredCA();
error Shogun_NoSupplyToClaim();
error Shogun_NoAllowance();
error Shogun_NotEnoughBalance();
error Shogun_BurnStakeClosed();
error Shogun_CannotZero();

/** @title Shogun */
contract Shogun is ERC20, ReentrancyGuard, GlobalInfo, BurnInfo, Ownable, ITitanOnBurn {
    /** Storage Variables*/
    /** @dev stores genesis wallet address */
    address private s_genesisAddress;

    /** @dev stores LP wallet address */
    address private s_lPAddress;

    /** @dev stores buy and burn contract address */
    address private s_buyAndBurnAddress;

    /** @dev tracks total amount of X28 deposited */
    uint256 s_totalX28Deposited;

    /** @dev tracks total amount of X28 burned */
    uint256 s_totalX28Burned;

    /** @dev tracks total amount of TitanX deposited */
    uint256 s_totalTitanXDeposited;

    /** @dev tracks total amount of TitanX burned */
    uint256 s_totalTitanXBurned;

    /** @dev tracks total amount of Shogun burned from tax */
    uint256 s_totalShogunTaxBurned;

    /** @dev Tracks Shogun buy and burn contract addresses status
     * Specifically used for burning Shogun in registered CA */
    mapping(address => bool) s_buyAndBurnAddressRegistry;

    /** @dev track addresses to exclude from transfer tax */
    mapping(address => bool) private s_taxExclusionList;

    /** @dev tracks if initial LP tokens has minted or not */
    bool private s_initialLPMinted;

    event AuctionEntered(address indexed user, uint256 indexed day, uint256 indexed amount);
    event AuctionSupplyClaimed(address indexed user, uint256 indexed amount);

    constructor(
        address genesisAddress,
        address lPAddress,
        address buyAndBurnAddress
    ) Ownable(msg.sender) ERC20("SHOGUN", "SHOGUN") {
        if (genesisAddress == address(0)) revert Shogun_InvalidAddress();
        if (lPAddress == address(0)) revert Shogun_InvalidAddress();
        if (buyAndBurnAddress == address(0)) revert Shogun_InvalidAddress();
        s_genesisAddress = genesisAddress;
        s_lPAddress = lPAddress;
        s_buyAndBurnAddress = buyAndBurnAddress;
        s_buyAndBurnAddressRegistry[buyAndBurnAddress] = true;
        s_taxExclusionList[buyAndBurnAddress] = true;
        s_taxExclusionList[lPAddress] = true;
        s_taxExclusionList[address(0)] = true;
        _mint(s_lPAddress, LP_WALLET_TOKENS);
    }

    /** @notice add given address to be excluded from transfer tax. Only callable by owner address.
     * @param addr address
     */
    function addTaxExclusionAddress(address addr) external onlyOwner {
        if (addr == address(0)) revert Shogun_InvalidAddress();
        s_taxExclusionList[addr] = true;
    }

    /** @notice remove given address to be excluded from transfer tax. Only callable by owner address.
     * @param addr address
     */
    function removeTaxExclusionAddress(address addr) external onlyOwner {
        if (addr == address(0)) revert Shogun_InvalidAddress();
        s_taxExclusionList[addr] = false;
    }

    /** @notice Set BuyAndBurn Contract Address.
     * Only owner can call this function
     * @param contractAddress BuyAndBurn contract address
     */
    function setBuyAndBurnContractAddress(address contractAddress) external onlyOwner {
        /* Only able to change to supported buyandburn contract address.
         * Also prevents owner from registering EOA address into s_buyAndBurnAddressRegistry and call burnCAShogun to burn user's tokens.
         */
        if (
            !IERC165(contractAddress).supportsInterface(IERC165.supportsInterface.selector) ||
            !IERC165(contractAddress).supportsInterface(type(IShogun).interfaceId)
        ) revert Shogun_NotSupportedContract();
        s_buyAndBurnAddress = contractAddress;
        s_buyAndBurnAddressRegistry[contractAddress] = true;
        s_taxExclusionList[contractAddress] = true;
    }

    /** @notice Set to new genesis wallet. Only genesis wallet can call this function
     * @param newAddress new genesis wallet address
     */
    function setNewGenesisAddress(address newAddress) external {
        if (msg.sender != s_genesisAddress) revert Shogun_NotAllowed();
        if (newAddress == address(0)) revert Shogun_InvalidAddress();
        s_genesisAddress = newAddress;
    }

    /** @notice Set to new LP wallet. Only LP wallet can call this function
     * @param newAddress new LP wallet address
     */
    function setNewLPAddress(address newAddress) external {
        if (msg.sender != s_lPAddress) revert Shogun_NotAllowed();
        if (newAddress == address(0)) revert Shogun_InvalidAddress();
        s_lPAddress = newAddress;
        s_taxExclusionList[newAddress] = true;
    }

    /** @notice mint initial LP tokens. Only BuyAndBurn contract set by owner can call this function
     */
    function mintLPTokens() external {
        if (msg.sender != s_buyAndBurnAddress) revert Shogun_NotAllowed();
        if (s_initialLPMinted) revert Shogun_LPTokensHasMinted();
        s_initialLPMinted = true;
        _mint(s_buyAndBurnAddress, INITAL_LP_TOKENS);
    }

    /** @notice burn Shogun in BuyAndBurn contract.
     * Only burns registered contract address
     * % to LP wallet, % to War Chest supply (stored in variable), burn all tokens except LP tokens
     */
    function burnCAShogun(address contractAddress) external dailyUpdate(s_buyAndBurnAddress) {
        if (!s_buyAndBurnAddressRegistry[contractAddress]) revert Shogun_UnregisteredCA();

        uint256 totalAmount = balanceOf(contractAddress);
        uint256 lPAmount = (totalAmount * SHOGUN_LP_PERCENT) / PERCENT_BPS;
        uint256 warChestAmount = (totalAmount * SHOGUN_WARCHEST_PERCENT) / PERCENT_BPS;
        super._update(contractAddress, address(0), totalAmount - lPAmount); //burn including war chest supply
        super._update(contractAddress, s_lPAddress, lPAmount); //LP supply
        _AddWarChestSupply(warChestAmount);
    }

    /** @notice enter auction using liquid X28
     * % burned, % to LP address, % to genesis address, % to B&B contract
     * @param amount TitanX amount
     */
    function enterAuctionX28Liquid(
        uint256 amount
    ) external dailyUpdate(s_buyAndBurnAddress) nonReentrant {
        if (amount == 0) revert Shogun_CannotZero();

        //transfer burn amount to X28 BNB, call public burnCAX28() to burn X28
        uint256 burnAmount = (amount * BURN_PERCENT) / PERCENT_BPS;
        IX28(X28).transferFrom(msg.sender, X28_BNB, burnAmount);
        IX28(X28).burnCAX28(X28_BNB);

        //transfer LP amount to LP address
        uint256 lPAmount = (amount * LP_PERCENT) / PERCENT_BPS;
        IX28(X28).transferFrom(msg.sender, s_lPAddress, lPAmount);

        //transfer genesis amount to genesis address
        uint256 genesisAmount = (amount * GENESIS_PERCENT) / PERCENT_BPS;
        IX28(X28).transferFrom(msg.sender, s_genesisAddress, genesisAmount);

        //transfer BnB amount to BnB contract
        IX28(X28).transferFrom(
            msg.sender,
            s_buyAndBurnAddress,
            amount - burnAmount - lPAmount - genesisAmount
        );

        _updateCycleAmount(msg.sender, amount);
        s_totalX28Deposited += amount;
        s_totalX28Burned += burnAmount;

        emit AuctionEntered(msg.sender, getCurrentContractDay(), amount);
    }

    /** @notice enter auction using TitanX stakes (up to 28 at once)
     * same amount of staked TitanX as liquid is required to burn stake
     * % burned, % to LP address, % to genesis address, % to B&B contract
     * 8% burn dev reward to BnB contract
     * credit 2x amount in current auction
     * @param stakeId User TitanX stake Ids
     */
    function enterAuctionTitanXStake(
        uint256[] calldata stakeId
    ) external dailyUpdate(s_buyAndBurnAddress) nonReentrant {
        if (getCurrentContractDay() > 28) revert Shogun_BurnStakeClosed();
        if (ITITANX(TITANX_CA).allowanceBurnStakes(msg.sender, address(this)) < stakeId.length)
            revert Shogun_NoAllowance();

        uint256 amount;
        uint256 claimCount;
        for (uint256 i = 0; i < stakeId.length; i++) {
            ITITANX.UserStakeInfo memory info = ITITANX(TITANX_CA).getUserStakeInfo(
                msg.sender,
                stakeId[i]
            );

            if (info.status == ITITANX.StakeStatus.ACTIVE && info.titanAmount != 0) {
                ITitanBurn(TITANX_CA).burnStakeToPayAddress(
                    msg.sender,
                    stakeId[i],
                    0,
                    8,
                    s_buyAndBurnAddress
                );
                amount += info.titanAmount;
                ++claimCount;
            }
            if (claimCount == MAX_BATCH_BURN_COUNT) break;
        }
        if (ITITANX(TITANX_CA).balanceOf(msg.sender) < amount) revert Shogun_NotEnoughBalance();

        //transfer burn amount to TitanX BNBV2, call public burnLPTokens() to burn TitanX
        uint256 burnAmount = (amount * BURN_PERCENT) / PERCENT_BPS;
        ITITANX(TITANX_CA).transferFrom(msg.sender, TITANX_BNBV2, burnAmount);
        ITITANX(TITANX_CA).burnLPTokens();

        //transfer LP amount to LP address
        uint256 lPAmount = (amount * LP_PERCENT) / PERCENT_BPS;
        ITITANX(TITANX_CA).transferFrom(msg.sender, s_lPAddress, lPAmount);

        //transfer genesis amount to genesis address
        uint256 genesisAmount = (amount * GENESIS_PERCENT) / PERCENT_BPS;
        ITITANX(TITANX_CA).transferFrom(msg.sender, s_genesisAddress, genesisAmount);

        //transfer BnB amount to BnB contract
        ITITANX(TITANX_CA).transferFrom(
            msg.sender,
            s_buyAndBurnAddress,
            amount - burnAmount - lPAmount - genesisAmount
        );

        uint256 totalCreditAmount = amount * 2;
        _updateCycleAmount(msg.sender, totalCreditAmount);
        s_totalTitanXDeposited += totalCreditAmount;
        s_totalTitanXBurned += burnAmount + amount; //100% staked amount burned + 20% liquid burned

        emit AuctionEntered(msg.sender, getCurrentContractDay(), totalCreditAmount);
    }

    /** @notice claim available auction supply (accumulate if past auctions was not claimed) */
    function claimUserAuction() external dailyUpdate(s_buyAndBurnAddress) nonReentrant {
        uint256 claimableSupply = getUserClaimableAuctionSupply(msg.sender);
        if (claimableSupply == 0) revert Shogun_NoSupplyToClaim();

        _updateUserAuctionClaimIndex(msg.sender);
        _mint(msg.sender, claimableSupply);

        emit AuctionSupplyClaimed(msg.sender, claimableSupply);
    }

    /** @notice callback function from TitanX contract after burn.
     * do nothing
     * @param user wallet address
     * @param amount burned Titan X amount
     */
    function onBurn(address user, uint256 amount) external {}

    //private functions
    /** @dev override ERC20 update for tax logic
     * add to tax exlusion list to avoid tax logic
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (s_taxExclusionList[from] || s_taxExclusionList[to]) {
            super._update(from, to, value);
            return;
        }

        uint256 taxAmount = (value * TRANSFER_TAX_PERCENT) / PERCENT_BPS;
        uint256 lPAmount = (taxAmount * SHOGUN_LP_PERCENT) / PERCENT_BPS;
        uint256 warChestAmount = (taxAmount * SHOGUN_WARCHEST_PERCENT) / PERCENT_BPS;
        super._update(from, address(0), taxAmount - lPAmount); //burn including war chest supply
        super._update(from, s_lPAddress, lPAmount); //LP supply
        super._update(from, to, value - taxAmount); //transfer taxed amount
        _AddWarChestSupply(warChestAmount);
        s_totalShogunTaxBurned += taxAmount - lPAmount - warChestAmount;
    }

    /** @dev burn liquid Shogun through other project.
     * called by other contracts for proof of burn 2.0 with up to 8% for both builder fee and user rebate
     * @param user user address
     * @param amount liquid Shogun amount
     * @param userRebatePercentage percentage for user rebate in liquid Shogun (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid Shogun (0 - 8)
     * @param rewardPaybackAddress builder can opt to receive fee in another address
     */
    function _burnLiquidShogun(
        address user,
        uint256 amount,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage,
        address rewardPaybackAddress
    ) private {
        _spendAllowance(user, msg.sender, amount);
        _burnbefore(userRebatePercentage, rewardPaybackPercentage);
        _burn(user, amount);
        _burnAfter(
            user,
            amount,
            userRebatePercentage,
            rewardPaybackPercentage,
            rewardPaybackAddress
        );
    }

    /** @dev perform checks before burning starts.
     * check reward percentage and check if called by supported contract
     * @param userRebatePercentage percentage for user rebate
     * @param rewardPaybackPercentage percentage for builder fee
     */
    function _burnbefore(
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage
    ) private view {
        if (rewardPaybackPercentage + userRebatePercentage > MAX_BURN_REWARD_PERCENT)
            revert Shogun_InvalidBurnRewardPercent();

        //Only supported contracts is allowed to call this function
        if (
            !IERC165(msg.sender).supportsInterface(IERC165.supportsInterface.selector) ||
            !IERC165(msg.sender).supportsInterface(type(IShogunOnBurn).interfaceId)
        ) revert Shogun_NotSupportedContract();
    }

    /** @dev update burn stats and mint reward to builder or user if applicable
     * @param user user address
     * @param amount Shogun amount burned
     * @param userRebatePercentage percentage for user rebate in liquid Shogun (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid Shogun (0 - 8)
     * @param rewardPaybackAddress builder can opt to receive fee in another address
     */
    function _burnAfter(
        address user,
        uint256 amount,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage,
        address rewardPaybackAddress
    ) private {
        _updateBurnAmount(user, msg.sender, amount);

        uint256 devFee;
        uint256 userRebate;
        if (rewardPaybackPercentage != 0) devFee = (amount * rewardPaybackPercentage) / 100;
        if (userRebatePercentage != 0) userRebate = (amount * userRebatePercentage) / 100;

        if (devFee != 0) _mint(rewardPaybackAddress, devFee);
        if (userRebate != 0) _mint(user, userRebate);

        IShogunOnBurn(msg.sender).onBurn(user, amount);
    }

    //Views
    /** @notice Returns true/false of the given interfaceId
     * @param interfaceId interface id
     * @return bool true/false
     */
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == IERC165.supportsInterface.selector ||
            interfaceId == type(ITitanOnBurn).interfaceId;
    }

    /** @notice Returns current genesis wallet address
     * @return address current genesis wallet address
     */
    function getGenesisAddress() public view returns (address) {
        return s_genesisAddress;
    }

    /** @notice Returns current LP wallet address
     * @return address current LP wallet address
     */
    function getLPAddress() public view returns (address) {
        return s_lPAddress;
    }

    /** @notice Returns current buy and burn contract address
     * @return address current buy and burn contract address
     */
    function getBuyAndBurnAddress() public view returns (address) {
        return s_buyAndBurnAddress;
    }

    /** @notice Returns status of the given address
     * @return true/false
     */
    function getBuyAndBurnAddressRegistry(address contractAddress) public view returns (bool) {
        return s_buyAndBurnAddressRegistry[contractAddress];
    }

    /** @notice Returns status of the given address if it's excluded from transfer tax
     * @return true/false
     */
    function isAddressTaxExcluded(address user) public view returns (bool) {
        return s_taxExclusionList[user];
    }

    /** @notice Returns total X28 deposited
     * @return amount
     */
    function getTotalX28Deposited() public view returns (uint256) {
        return s_totalX28Deposited;
    }

    /** @notice Returns total TitanX burned from deposit
     * @return amount
     */
    function getTotalX28BurnedFromDeposits() public view returns (uint256) {
        return s_totalX28Burned;
    }

    /** @notice Returns total TitanX deposited
     * @return amount
     */
    function getTotalTitanXDeposited() public view returns (uint256) {
        return s_totalTitanXDeposited;
    }

    /** @notice Returns total TitanX burned from deposit
     * @return amount
     */
    function getTotalTitanXBurnedFromDeposits() public view returns (uint256) {
        return s_totalTitanXBurned;
    }

    /** @notice Returns total Shogun burned from tax
     * @return amount
     */
    function getTotalShogunBurnedFromTax() public view returns (uint256) {
        return s_totalShogunTaxBurned;
    }

    //Public functions for devs to intergrate with Shogun
    /** @notice allow anyone to sync dailyUpdate manually */
    function manualDailyUpdate() public dailyUpdate(s_buyAndBurnAddress) {}

    /** @notice Burn Shogun tokens and creates Proof-Of-Burn record to be used by connected DeFi and fee is paid to specified address
     * @param user user address
     * @param amount Shogun amount
     * @param userRebatePercentage percentage for user rebate in liquid Shogun (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid Shogun (0 - 8)
     * @param rewardPaybackAddress builder can opt to receive fee in another address
     */
    function burnTokensToPayAddress(
        address user,
        uint256 amount,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage,
        address rewardPaybackAddress
    ) public nonReentrant dailyUpdate(s_buyAndBurnAddress) {
        _burnLiquidShogun(
            user,
            amount,
            userRebatePercentage,
            rewardPaybackPercentage,
            rewardPaybackAddress
        );
    }

    /** @notice Burn Shogun tokens and creates Proof-Of-Burn record to be used by connected DeFi and fee is paid to specified address
     * @param user user address
     * @param amount Shogun amount
     * @param userRebatePercentage percentage for user rebate in liquid Shogun (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid Shogun (0 - 8)
     */
    function burnTokens(
        address user,
        uint256 amount,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage
    ) public nonReentrant dailyUpdate(s_buyAndBurnAddress) {
        _burnLiquidShogun(user, amount, userRebatePercentage, rewardPaybackPercentage, msg.sender);
    }

    /** @notice allows user to burn liquid Shogun directly from contract
     * @param amount Shogun amount
     */
    function userBurnTokens(uint256 amount) public nonReentrant dailyUpdate(s_buyAndBurnAddress) {
        _burn(msg.sender, amount);
        _updateBurnAmount(msg.sender, address(0), amount);
    }
}