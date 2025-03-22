// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

import "./BurnInfo.sol";

import "../libs/constant.sol";

import "../interfaces/ITITANX.sol";
import "../interfaces/IX28.sol";
import "../interfaces/IX28OnBurn.sol";

error X28_InvalidCaller();
error X28_InvalidAddress();
error X28_InsufficientBurnAllowance();
error X28_NotSupportedContract();
error X28_UnregisteredCA();
error X28_LPTokensHasMinted();
error X28_InvalidBurnRewardPercent();
error X28_OnlyOnEthereum();

contract X28 is OFT, BurnInfo, ReentrancyGuard, IX28 {
    /** @dev stores genesis wallet address */
    address private s_genesisAddress;
    /** @dev stores buy and burn contract address */
    address private s_buyAndBurnAddress;

    /** @dev track if initial LP token has minted */
    bool private s_initialLPMinted;

    /** @dev tracks total amount of TitanX deposited */
    uint256 s_titanXDeposited;

    /** @dev Tracks X28 buy and burn contract addresses status
     * Specifically used for burning X28 in registered CA */
    mapping(address => bool) s_buyAndBurnAddressRegistry;

    //events
    event X28Minted(address indexed user, uint256 indexed amount);

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _owner,
        address _genesis,
        address _buyAndBurnAddress
    ) OFT(_name, _symbol, _lzEndpoint, _owner) Ownable(_owner) {
        s_genesisAddress = _genesis;
        s_buyAndBurnAddress = _buyAndBurnAddress;
        s_buyAndBurnAddressRegistry[_buyAndBurnAddress] = true;
    }

    /** @notice Set to new genesis wallet. Only genesis wallet can call this function
     * @param newAddress new genesis wallet address
     */
    function setNewGenesisAddress(address newAddress) external {
        if (msg.sender != s_genesisAddress) revert X28_InvalidCaller();
        if (newAddress == address(0)) revert X28_InvalidAddress();
        s_genesisAddress = newAddress;
    }

    /** @notice Set BuyAndBurn Contract Address.
     * Only owner can call this function
     * @param contractAddress BuyAndBurn contract address
     */
    function setBuyAndBurnContractAddress(address contractAddress) external onlyOwner {
        /* Only able to change to supported buyandburn contract address.
         * Also prevents owner from registering EOA address into s_buyAndBurnAddressRegistry and call burnCAX28 to burn user's tokens.
         */
        if (
            !IERC165(contractAddress).supportsInterface(IERC165.supportsInterface.selector) ||
            !IERC165(contractAddress).supportsInterface(type(IX28).interfaceId)
        ) revert X28_NotSupportedContract();
        s_buyAndBurnAddress = contractAddress;
        s_buyAndBurnAddressRegistry[contractAddress] = true;
    }

    /** @notice mint initial LP tokens. Only BuyAndBurn contract set by owner can call this function
     */
    function mintLPTokens() external {
        if (msg.sender != s_buyAndBurnAddress) revert X28_InvalidCaller();
        if (s_initialLPMinted) revert X28_LPTokensHasMinted();
        s_initialLPMinted = true;
        _mint(s_buyAndBurnAddress, INITAL_LP_TOKENS);
    }

    /** @notice burn X28 in BuyAndBurn contract.
     * Only burns registered contract address
     * @param contractAddress contract address
     */
    function burnCAX28(address contractAddress) external {
        if (!s_buyAndBurnAddressRegistry[contractAddress]) revert X28_UnregisteredCA();
        _burn(contractAddress, balanceOf(contractAddress));
    }

    /** @notice Use TitanX to mint X28, 50% burn, and 50% for buy and burn
     * Forever 1:1 mint ratio
     * Only on Ethereum chain
     * @param amount TitanX amount
     */
    function mintX28withTitanX(uint256 amount) external nonReentrant {
        if (block.chainid != 1) revert X28_OnlyOnEthereum();

        //transfer burn amount to TitanX BNBV2, call public burnLPTokens() to burn TitanX
        uint256 burnAmount = (amount * TITANX_BURN_PERCENT) / PERCENT_BPS;
        ITITANX(TITANX_CA).transferFrom(msg.sender, TITANX_BNBV2, burnAmount);
        ITITANX(TITANX_CA).burnLPTokens();

        //transfer remaining to BNB contract
        ITITANX(TITANX_CA).transferFrom(msg.sender, s_buyAndBurnAddress, amount - burnAmount);

        //mint X28
        _mintX28(msg.sender, amount);
        s_titanXDeposited += amount;

        emit X28Minted(msg.sender, amount);
    }

    //Private functions
    /** @dev mint X28 to user, a % to genesis
     * @param user user address
     * @param amount mint amount
     */
    function _mintX28(address user, uint256 amount) private {
        _mint(user, amount);
        _mint(s_genesisAddress, (amount * GENESIS_MINT_PERCENT) / PERCENT_BPS);
    }

    /** @dev burn liquid X28 through other project.
     * called by other contracts for proof of burn 2.0 with up to 8% for both builder fee and user rebate
     * @param user user address
     * @param amount liquid X28 amount
     * @param userRebatePercentage percentage for user rebate in liquid X28 (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid X28 (0 - 8)
     * @param rewardPaybackAddress builder can opt to receive fee in another address
     */
    function _burnLiquidX28(
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
            revert X28_InvalidBurnRewardPercent();

        //Only supported contracts is allowed to call this function
        if (
            !IERC165(msg.sender).supportsInterface(IERC165.supportsInterface.selector) ||
            !IERC165(msg.sender).supportsInterface(type(IX28OnBurn).interfaceId)
        ) revert X28_NotSupportedContract();
    }

    /** @dev update burn stats and mint reward to builder or user if applicable
     * @param user user address
     * @param amount X28 amount burned
     * @param userRebatePercentage percentage for user rebate in liquid X28 (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid X28 (0 - 8)
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
        if (rewardPaybackPercentage != 0)
            devFee = (amount * rewardPaybackPercentage * PERCENT_BPS) / (100 * PERCENT_BPS);
        if (userRebatePercentage != 0)
            userRebate = (amount * userRebatePercentage * PERCENT_BPS) / (100 * PERCENT_BPS);

        if (devFee != 0) _mint(rewardPaybackAddress, devFee);
        if (userRebate != 0) _mint(user, userRebate);

        IX28OnBurn(msg.sender).onBurn(user, amount);
    }

    //views
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

    /** @notice Returns total TitanX deposited
     * @return amount
     */
    function getTotalTitanXDeposited() public view returns (uint256) {
        return s_titanXDeposited;
    }

    /** @notice Returns total TitanX burned from deposit
     * @return amount
     */
    function getTotalTitanXBurnedFromDeposits() public view returns (uint256) {
        return (s_titanXDeposited * TITANX_BURN_PERCENT) / PERCENT_BPS;
    }

    //Public functions for devs to intergrate with X28
    /** @notice Burn X28 tokens and creates Proof-Of-Burn record to be used by connected DeFi and fee is paid to specified address
     * @param user user address
     * @param amount X28 amount
     * @param userRebatePercentage percentage for user rebate in liquid X28 (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid X28 (0 - 8)
     * @param rewardPaybackAddress builder can opt to receive fee in another address
     */
    function burnTokensToPayAddress(
        address user,
        uint256 amount,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage,
        address rewardPaybackAddress
    ) public nonReentrant {
        _burnLiquidX28(
            user,
            amount,
            userRebatePercentage,
            rewardPaybackPercentage,
            rewardPaybackAddress
        );
    }

    /** @notice Burn X28 tokens and creates Proof-Of-Burn record to be used by connected DeFi and fee is paid to specified address
     * @param user user address
     * @param amount X28 amount
     * @param userRebatePercentage percentage for user rebate in liquid X28 (0 - 8)
     * @param rewardPaybackPercentage percentage for builder fee in liquid X28 (0 - 8)
     */
    function burnTokens(
        address user,
        uint256 amount,
        uint256 userRebatePercentage,
        uint256 rewardPaybackPercentage
    ) public nonReentrant {
        _burnLiquidX28(user, amount, userRebatePercentage, rewardPaybackPercentage, msg.sender);
    }

    /** @notice allows user to burn liquid X28 directly from contract
     * @param amount X28 amount
     */
    function userBurnTokens(uint256 amount) public nonReentrant {
        _burn(msg.sender, amount);
        _updateBurnAmount(msg.sender, address(0), amount);
    }
}