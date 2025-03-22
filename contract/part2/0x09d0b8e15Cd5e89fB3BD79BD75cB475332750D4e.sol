// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title  Civ Vault
 * @author Ren / Frank
 */

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/ICivFund.sol";
import "./CIV-VaultGetter.sol";
import "./CIV-VaultFactory.sol";
import "./dependencies/Ownable.sol";

contract CIVVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for ICivFundRT;
    using Strings for uint;

    /// @notice All Fees Base Amount
    uint public constant feeBase = 10_000;
    /// @notice Max entry Fee Amount
    uint public constant maxEntryFee = 1_000;
    /// @notice Max users for shares distribution
    uint public maxUsersToDistribute;
    /// @notice Number of strategies
    uint public strategiesCounter;
    /// @notice vault getter contract
    ICivVaultGetter public vaultGetter;
    /// @notice share factory contract
    CIVFundShareFactory public fundShareFactory;
    /// @notice mapping with info on each strategy
    mapping(uint => StrategyInfo) private _strategyInfo;
    /// @notice structure with epoch info
    mapping(uint => mapping(uint => EpochInfo)) private _epochInfo;
    /// @notice Info of each user that enters the fund
    mapping(uint => mapping(address => UserInfo)) private _userInfo;
    /// @notice Counter for the epochs of each strategy
    mapping(uint => uint) private _epochCounter;
    /// @notice Each Strategies epoch informations per address
    mapping(uint => mapping(address => mapping(uint => UserInfoEpoch)))
        private _userInfoEpoch;
    /// @notice Mapping of depositors on a particular epoch
    mapping(uint => mapping(uint => mapping(uint => address)))
        private _depositors;

    ////////////////// EVENTS //////////////////

    /// @notice Event emitted when user deposit fund to our vault or vault deposit fund to strategy
    event Deposit(
        address indexed user,
        address receiver,
        uint indexed id,
        uint amount
    );
    /// @notice Event emitted when user request withdraw fund from our vault or vault withdraw fund to user
    event Withdraw(address indexed user, uint indexed id, uint amount);
    /// @notice Event emitted when owner sets new fee
    event SetFee(
        uint indexed id,
        uint oldFee,
        uint newFee,
        uint oldDuration,
        uint newDuration
    );
    /// @notice Event emitted when owner sets new entry fee
    event SetEntryFee(uint indexed id, uint oldEntryFee, uint newEntryFee);
    /// @notice Event emitted when owner sets new deposit duration
    event SetEpochDuration(uint indexed id, uint oldDuration, uint newDuration);
    /// @notice Event emitted when owner sets new treasury addresses
    event SetWithdrawAddress(
        uint indexed id,
        address[] oldAddress,
        address[] newAddress
    );
    /// @notice Event emitted when owner sets new invest address
    event SetInvestAddress(
        uint indexed id,
        address oldAddress,
        address newAddress
    );
    /// @notice Event emitted when send fee to our treasury
    event SendFeeWithOwner(
        uint indexed id,
        address treasuryAddress,
        uint feeAmount
    );
    /// @notice Event emitted when owner update new VPS
    event UpdateVPS(uint indexed id, uint lastEpoch, uint VPS, uint netVPS);
    /// @notice Event emitted when owner paused deposit
    event SetPaused(uint indexed id, bool paused);
    /// @notice Event emitted when owner set new Max & Min Deposit Amount
    event SetLimits(
        uint indexed id,
        uint oldMaxAmount,
        uint newMaxAmount,
        uint oldMinAmount,
        uint newMinAmount,
        uint oldMaxUsers,
        uint newMaxUsers
    );
    /// @notice Event emitted when user cancel pending deposit from vault
    event CancelDeposit(address indexed user, uint indexed id, uint amount);
    /// @notice Event emitted when user cancel withdraw request from vault
    event CancelWithdraw(address indexed user, uint indexed id, uint amount);
    /// @notice Event emitted when user claim Asset token for each epoch
    event ClaimWithdrawedToken(
        uint indexed id,
        address user,
        uint epoch,
        uint assetAmount
    );
    event SharesDistributed(
        uint indexed id,
        uint epoch,
        address indexed investor,
        uint dueShares
    );
    event TransferFailed(
        uint indexed strategyId,
        uint indexed epoch,
        address indexed investor,
        uint dueShares
    );
    /// @notice Event emitted when user claim Asset token
    event WithdrawedToken(
        uint indexed id,
        address indexed user,
        uint assetAmount
    );
    /// @notice Event emitted when owner adds new strategy
    event AddStrategy(
        uint indexed id,
        uint fee,
        uint entryFee,
        uint maxDeposit,
        uint minDeposit,
        bool paused,
        address[] withdrawAddress,
        address assetToken,
        uint feeDuration
    );
    /// @notice Event emitted when strategy is initialized
    event InitializeStrategy(uint indexed id);

    ////////////////// ERROR CODES //////////////////
    /*
    ERR_V.1 = "Strategy does not exist";
    ERR_V.2 = "Deposit paused";
    ERR_V.3 = "Treasury Address Length must be 2";
    ERR_V.4 = "Burn failed";
    ERR_V.5 = "Wait for rebalancing to complete";
    ERR_V.6 = "First Treasury address cannot be null address";
    ERR_V.7 = "Second Treasury address cannot be null address";
    ERR_V.8 = "Minting failed";
    ERR_V.9 = "Strategy already initialized";
    ERR_V.10 = "No epochs exist";
    ERR_V.11 = "Nothing to claim";
    ERR_V.12 = "Insufficient contract balance";
    ERR_V.13 = "Not enough amount to withdraw";
    ERR_V.14 = "Strategy address cannot be null address";
    ERR_V.15 = "No pending Fees to distribute";
    ERR_V.16 = "Distribute all shares for previous epoch";
    ERR_V.17 = "Epoch does not exist";
    ERR_V.18 = "Epoch not yet expired";
    ERR_V.19 = "Vault balance is not enough to pay fees";
    ERR_V.20 = "Amount can't be 0";
    ERR_V.21 = "Insufficient User balance";
    ERR_V.22 = "No more users are allowed";
    ERR_V.23 = "Deposit amount exceeds epoch limit";
    ERR_V.24 = "Epoch expired";
    ERR_V.25 = "Current balance not enough";
    ERR_V.26 = "Not enough total withdrawals";
    ERR_V.27 = "VPS not yet updated";
    ERR_V.28 = "Already started distribution";
    ERR_V.29 = "Not yet distributed";
    ERR_V.30 = "Already distributed";
    ERR_V.31 = "Fee duration not yet passed";
    ERR_V.32 = "Withdraw Token cannot be deposit token";
    ERR_V.33 = "Entry fee too high!";
    */

    ////////////////// MODIFIER //////////////////

    modifier checkStrategyExistence(uint _id) {
        require(strategiesCounter > _id, "ERR_V.1");
        _;
    }

    modifier checkEpochExistence(uint _id) {
        require(_epochCounter[_id] > 0, "ERR_V.10");
        _;
    }

    ////////////////// CONSTRUCTOR //////////////////

    constructor() {
        CivVaultGetter getterContract = new CivVaultGetter(address(this));
        fundShareFactory = new CIVFundShareFactory();
        vaultGetter = ICivVaultGetter(address(getterContract));
    }

    ////////////////// INITIALIZATION //////////////////

    /// @notice Add new strategy to our vault
    /// @dev Only Owner can call this function
    /// @param addStrategyParam Parameters for new strategy
    function addStrategy(
        AddStrategyParam memory addStrategyParam
    ) external virtual nonReentrant onlyOwner {
        require(addStrategyParam._withdrawAddresses.length == 2, "ERR_V.3");
        require(
            addStrategyParam._withdrawAddresses[0] != address(0),
            "ERR_V.6"
        );
        require(
            addStrategyParam._withdrawAddresses[1] != address(0),
            "ERR_V.7"
        );

        /// deploy new CIVFundShare contract
        uint id = strategiesCounter;

        // Generate unique name and symbol
        string memory name = string(abi.encodePacked("CIVFundShare ", Strings.toString(id)));
        string memory symbol = string(abi.encodePacked("CIVS", Strings.toString(id)));

        // deploy new CIVFundShare contract with dynamic name and symbol
        CIVFundShare fundRepresentToken = fundShareFactory.createCIVFundShare(
            name,
            symbol
        );

        _strategyInfo[id] = StrategyInfo({
            assetToken: addStrategyParam._assetToken,
            fundRepresentToken: ICivFundRT(address(fundRepresentToken)),
            fee: addStrategyParam._fee,
            entryFee: addStrategyParam._entryFee,
            withdrawAddress: addStrategyParam._withdrawAddresses,
            investAddress: addStrategyParam._investAddress,
            initialized: false,
            pendingFees: 0,
            maxDeposit: addStrategyParam._maxDeposit,
            maxUsers: addStrategyParam._maxUsers,
            minDeposit: addStrategyParam._minAmount,
            paused: addStrategyParam._paused,
            epochDuration: addStrategyParam._epochDuration,
            feeDuration: addStrategyParam._feeDuration,
            lastFeeDistribution: 0,
            lastProcessedEpoch: 0,
            watermark: 0
        });

        strategiesCounter++;

        emit AddStrategy(
            id,
            addStrategyParam._fee,
            addStrategyParam._entryFee,
            addStrategyParam._maxDeposit,
            addStrategyParam._minAmount,
            addStrategyParam._paused,
            addStrategyParam._withdrawAddresses,
            address(addStrategyParam._assetToken),
            addStrategyParam._feeDuration
        );
    }

    /// @notice Internal strategy initialization
    /// @dev Internal function
    /// @param _id strategy id
    function _initializeStrategy(uint _id) internal {
        _strategyInfo[_id].initialized = true;
        vaultGetter.addTimeOracle(_id, _strategyInfo[_id].epochDuration);

        _epochInfo[_id][_epochCounter[_id]] = EpochInfo({
            totDepositors: 0,
            totDepositedAssets: 0,
            totWithdrawnShares: 0,
            VPS: 0,
            netVPS: 0,
            newShares: 0,
            currentWithdrawAssets: 0,
            epochStartTime: block.timestamp,
            entryFee: _strategyInfo[_id].entryFee,
            totalFee: 0,
            lastDepositorProcessed: 0,
            duration: _strategyInfo[_id].epochDuration
        });

        _epochCounter[_id]++;
    }

    /// @notice Delayed strategy start
    /// @dev Only Owner can call this function
    /// @param _id strategy id
    function initializeStrategy(
        uint _id
    ) external onlyOwner checkStrategyExistence(_id) {
        require(!_strategyInfo[_id].initialized, "ERR_V.9");

        _initializeStrategy(_id);
        emit InitializeStrategy(_id);
    }

    ////////////////// SETTER //////////////////

    /// @notice Sets new fee and new collecting fee duration
    /// @dev Only Owner can call this function
    /// @param _id Strategy Id
    /// @param _newFee New Fee Percent
    /// @param _newDuration New Collecting Fee Duration
    function setFee(
        uint _id,
        uint _newFee,
        uint _newDuration
    ) external onlyOwner checkStrategyExistence(_id) {
        emit SetFee(
            _id,
            _strategyInfo[_id].fee,
            _newFee,
            _strategyInfo[_id].feeDuration,
            _newDuration
        );
        _strategyInfo[_id].fee = _newFee;
        _strategyInfo[_id].feeDuration = _newDuration;
    }

    /// @notice Sets new entry fee
    /// @dev Only Owner can call this function
    /// @param _id Strategy Id
    /// @param _newEntryFee New Fee Percent
    function setEntryFee(
        uint _id,
        uint _newEntryFee
    ) external onlyOwner checkStrategyExistence(_id) {
        emit SetEntryFee(_id, _strategyInfo[_id].entryFee, _newEntryFee);
        require(_newEntryFee <= maxEntryFee, "ERR_V.33");
        _strategyInfo[_id].entryFee = _newEntryFee;
    }

    /// @notice Sets new deposit fund from vault to strategy duration
    /// @dev Only Owner can call this function
    /// @param _id Strategy Id
    /// @param _newDuration New Duration for Deposit fund from vault to strategy
    function setEpochDuration(
        uint _id,
        uint _newDuration
    ) external onlyOwner checkStrategyExistence(_id) {
        emit SetEpochDuration(
            _id,
            _strategyInfo[_id].epochDuration,
            _newDuration
        );
        vaultGetter.setEpochDuration(_id, _newDuration);
        _strategyInfo[_id].epochDuration = _newDuration;
    }

    /// @notice Sets new treasury addresses to keep fee
    /// @dev Only Owner can call this function
    /// @param _id Strategy Id
    /// @param _newAddress Address list to keep fee
    function setWithdrawAddress(
        uint _id,
        address[] memory _newAddress
    ) external onlyOwner checkStrategyExistence(_id) {
        require(_newAddress.length == 2, "ERR_V.3");
        require(_newAddress[0] != address(0), "ERR_V.6");
        require(_newAddress[1] != address(0), "ERR_V.7");
        emit SetWithdrawAddress(
            _id,
            _strategyInfo[_id].withdrawAddress,
            _newAddress
        );
        _strategyInfo[_id].withdrawAddress = _newAddress;
    }

    /// @notice Sets new invest address
    /// @dev Only Owner can call this function
    /// @param _id Strategy Id
    /// @param _newAddress Address to invest funds into
    function setInvestAddress(
        uint _id,
        address _newAddress
    ) external onlyOwner checkStrategyExistence(_id) {
        require(_newAddress != address(0), "ERR_V.14");
        emit SetInvestAddress(
            _id,
            _strategyInfo[_id].investAddress,
            _newAddress
        );
        _strategyInfo[_id].investAddress = _newAddress;
    }

    /// @notice Set Pause or Unpause for deposit to vault
    /// @dev Only Owner can change this status
    /// @param _id Strategy Id
    /// @param _paused paused or unpaused for deposit
    function setPaused(
        uint _id,
        bool _paused
    ) external onlyOwner checkStrategyExistence(_id) {
        emit SetPaused(_id, _paused);
        _strategyInfo[_id].paused = _paused;
    }

    /// @notice Set limits on a given strategy
    /// @dev Only Owner can change this status
    /// @param _id Strategy Id
    /// @param _newMaxDeposit New Max Deposit Amount
    /// @param _newMinDeposit New Min Deposit Amount
    /// @param _newMaxUsers New Max User Count
    function setEpochLimits(
        uint _id,
        uint _newMaxDeposit,
        uint _newMinDeposit,
        uint _newMaxUsers
    ) external onlyOwner checkStrategyExistence(_id) {
        emit SetLimits(
            _id,
            _strategyInfo[_id].maxDeposit,
            _newMaxDeposit,
            _strategyInfo[_id].minDeposit,
            _newMinDeposit,
            _strategyInfo[_id].maxUsers,
            _newMaxUsers
        );
        _strategyInfo[_id].maxDeposit = _newMaxDeposit;
        _strategyInfo[_id].minDeposit = _newMinDeposit;
        _strategyInfo[_id].maxUsers = _newMaxUsers;
    }

    /// @notice Set the max number of users per distribution
    /// @param _maxUsersToDistribute Max number of users to distribute shares to
    function setMaxUsersToDistribute(
        uint _maxUsersToDistribute
    ) external onlyOwner {
        require(
            _maxUsersToDistribute > 0 &&
                _maxUsersToDistribute != maxUsersToDistribute,
            "Invalid number of users"
        );
        maxUsersToDistribute = _maxUsersToDistribute;
    }

    ////////////////// GETTER //////////////////

    /**
     * @dev Fetches the strategy information for a given strategy _id.
     * @param _id The ID of the strategy to fetch the information for.
     * @return strategy The StrategyInfo struct associated with the provided _id.
     */
    function getStrategyInfo(
        uint _id
    )
        external
        view
        checkStrategyExistence(_id)
        returns (StrategyInfo memory strategy)
    {
        strategy = _strategyInfo[_id];
    }

    /**
     * @dev Fetches the epoch information for a given strategy _id.
     * @param _id The ID of the strategy to fetch the information for.
     * @param _index The index of the epoch to fetch the information for.
     * @return epoch The EpochInfo struct associated with the provided _id and _index.
     */
    function getEpochInfo(
        uint _id,
        uint _index
    )
        external
        view
        checkStrategyExistence(_id)
        checkEpochExistence(_id)
        returns (EpochInfo memory epoch)
    {
        epoch = _epochInfo[_id][_index];
    }

    /**
     * @dev Fetches the current epoch number for a given strategy _id.
     * The current epoch is determined as the last index of the epochInfo mapping for the strategy.
     * @param _id The _id of the strategy to fetch the current epoch for.
     * @return The current epoch number for the given strategy _id.
     */
    function getCurrentEpoch(
        uint _id
    )
        public
        view
        checkStrategyExistence(_id)
        checkEpochExistence(_id)
        returns (uint)
    {
        return _epochCounter[_id] - 1;
    }

    /**
     * @dev Fetches the user information for a given strategy _id.
     * @param _id The _id of the strategy to fetch the information for.
     * @param _user The address of the user to fetch the information for.
     * @return user The UserInfo struct associated with the provided _id and _user.
     */
    function getUserInfo(
        uint _id,
        address _user
    ) external view checkStrategyExistence(_id) returns (UserInfo memory user) {
        user = _userInfo[_id][_user];
    }

    /**
     * @dev Fetches the user information for a given strategy _id.
     * @param _id The _id of the strategy to fetch the information for.
     * @param _epoch The starting index to fetch the information for.
     * @return users An array of addresses of unique depositors.
     */
    function getDepositors(
        uint _id,
        uint _epoch
    )
        external
        view
        checkStrategyExistence(_id)
        returns (address[] memory users)
    {
        // Initialize the return array with the size equal to the range between the start and end indices
        users = new address[](_epochInfo[_id][_epoch].totDepositors);

        // Loop through the mapping to populate the return array
        for (uint i = 0; i < _epochInfo[_id][_epoch].totDepositors; i++) {
            users[i] = _depositors[_id][_epoch][i];
        }
    }

    /**
     * @dev Fetches the deposit parameters for a given strategy _id.
     * @param _id The _id of the strategy to fetch the information for.
     * @param _user The address of the user to fetch the information for.
     * @param _index The index of the deposit to fetch the information for.
     * @return userEpochStruct The UserInfoEpoch struct associated with the provided _id, _user and _index.
     */
    function getUserInfoEpoch(
        uint _id,
        address _user,
        uint _index
    )
        external
        view
        checkStrategyExistence(_id)
        returns (UserInfoEpoch memory userEpochStruct)
    {
        userEpochStruct = _userInfoEpoch[_id][_user][_index];
    }

    ////////////////// UPDATE //////////////////

    /**
     * @dev Updates the current epoch information for the specified strategy
     * @param _id The Strategy _id
     *
     * This function checks if the current epoch's duration has been met or exceeded.
     * If true, it initializes a new epoch with its starting time as the current block timestamp.
     * If false, no action is taken.
     *
     * Requirements:
     * - The strategy must be initialized.
     * - The current block timestamp must be equal to or greater than the start
     *   time of the current epoch plus the epoch's duration.
     */
    function updateEpoch(uint _id) private checkEpochExistence(_id) {
        uint currentEpoch = getCurrentEpoch(_id);

        if (
            block.timestamp >=
            _epochInfo[_id][currentEpoch].epochStartTime +
                _epochInfo[_id][currentEpoch].duration
        ) {
            require(_epochInfo[_id][currentEpoch].VPS > 0, "ERR_V.5");

            _epochInfo[_id][_epochCounter[_id]] = EpochInfo({
                totDepositors: 0,
                totDepositedAssets: 0,
                totWithdrawnShares: 0,
                VPS: 0,
                netVPS: 0,
                newShares: 0,
                currentWithdrawAssets: 0,
                epochStartTime: vaultGetter.getCurrentPeriod(_id),
                entryFee: _strategyInfo[_id].entryFee,
                totalFee: 0,
                lastDepositorProcessed: 0,
                duration: _strategyInfo[_id].epochDuration
            });

            _epochCounter[_id]++;
        }
    }

    /// @notice Calculate fees to the treasury address and save it in the strategy mapping and returns net VPS
    /**
     * @dev Internal function
     */
    /// @param _id Strategy _id
    /// @param _newVPS new Net Asset Value
    /// @return netVPS The new VPS after fees have been deducted
    function takePerformanceFees(
        uint _id,
        uint _newVPS
    ) private returns (uint netVPS, uint actualFee) {
        StrategyInfo storage strategy = _strategyInfo[_id];

        uint sharesMultiplier = 10 ** strategy.fundRepresentToken.decimals();
        uint totalSupplyShares = strategy.fundRepresentToken.totalSupply();
        actualFee = 0;
        netVPS = _newVPS;

        if (strategy.watermark < _newVPS) {
            if (strategy.fee > 0) {
                actualFee =
                    ((_newVPS - strategy.watermark) *
                        strategy.fee *
                        totalSupplyShares) /
                    feeBase /
                    sharesMultiplier;
                if (actualFee > 0) {
                    strategy.pendingFees += actualFee;
                    // Calculate net VPS based on the actual fee
                    uint adjustedTotalValue = (_newVPS * totalSupplyShares) /
                        sharesMultiplier -
                        actualFee;
                    netVPS =
                        (adjustedTotalValue * sharesMultiplier) /
                        totalSupplyShares;
                }
            }
            strategy.watermark = netVPS;
        }
    }

    /**
     * @dev Processes the fund associated with a particular strategy, handling deposits,
     * minting, and burning of shares.
     * @param _id The Strategy _id
     * @param _newVPS New value per share (VPS) expressed in decimals (same as assetToken)
     * - must be greater than 0
     *
     * This function performs the following actions:
     * 1. Retrieves the current epoch and strategy info, as well as net VPS and performance Fees;
     * 2. Calculate the new shares and current withdrawal based on new VPS;
     * 3. Mints or burns shares depending on the new shares and total withdrawals.
     * 4. Handles deposits, withdrawals and performance fees by transferring the Asset tokens.
     *
     * Requirements:
     * - `_newVPS` must be greater than 0.
     * - The necessary amount of Asset tokens must be present in the contract for deposits if required.
     * - The necessary amount of Asset tokens must be present in the investAddress for withdrawals if required.
     */
    function processFund(uint _id, uint _newVPS) private {
        require(_newVPS > 0, "ERR_V.15");

        uint performanceFees;
        uint netVPS;
        (netVPS, performanceFees) = takePerformanceFees(_id, _newVPS);

        // Step 1
        EpochInfo storage epoch = _epochInfo[_id][
            _strategyInfo[_id].lastProcessedEpoch
        ];
        StrategyInfo memory strategy = _strategyInfo[_id];

        epoch.netVPS = netVPS;
        uint sharesMultiplier = 10 ** strategy.fundRepresentToken.decimals();

        // Step 2
        uint newShares = (epoch.totDepositedAssets * sharesMultiplier) / netVPS;
        uint currentWithdrawAssets = (netVPS * epoch.totWithdrawnShares) /
            sharesMultiplier;

        epoch.newShares = newShares;
        epoch.currentWithdrawAssets = currentWithdrawAssets;

        // Step 3
        if (newShares > epoch.totWithdrawnShares) {
            uint sharesToMint = newShares - epoch.totWithdrawnShares;
            bool success = strategy.fundRepresentToken.mint(sharesToMint);
            require(success, "ERR_V.8");
        } else {
            uint offSetShares = epoch.totWithdrawnShares - newShares;
            if (offSetShares > 0) {
                bool success = strategy.fundRepresentToken.burn(offSetShares);
                require(success, "ERR_V.4");
            }
        }

        // Step 4
        if (
            epoch.totDepositedAssets >= currentWithdrawAssets + performanceFees
        ) {
            uint netDeposits = epoch.totDepositedAssets -
                currentWithdrawAssets -
                performanceFees;
            if (netDeposits > 0) {
                require(
                    strategy.assetToken.balanceOf(address(this)) >= netDeposits,
                    "ERR_V.12"
                );
                strategy.assetToken.safeTransfer(
                    strategy.investAddress,
                    netDeposits
                );
                emit Deposit(
                    address(this),
                    strategy.investAddress,
                    _id,
                    netDeposits
                );
            }
        } else {
            uint offSet = currentWithdrawAssets +
                performanceFees -
                epoch.totDepositedAssets;
            require(
                strategy.assetToken.balanceOf(strategy.investAddress) >= offSet,
                "ERR_V.13"
            );
            require(
                strategy.assetToken.allowance(strategy.investAddress, address(this)) >=
                    offSet,
                "Insufficient allowance for withdraw"
            );
            strategy.assetToken.safeTransferFrom(
                strategy.investAddress,
                address(this),
                offSet
            );
        }

        // Transfer totalEntryFee to withdraw Addresses
        if (epoch.totalFee > 0) {
            require(
                strategy.assetToken.balanceOf(address(this)) >= epoch.totalFee,
                "ERR_V.19"
            );
            strategy.assetToken.safeTransfer(
                strategy.withdrawAddress[0],
                epoch.totalFee / 2
            );
            strategy.assetToken.safeTransfer(
                strategy.withdrawAddress[1],
                epoch.totalFee / 2
            );
        }

        updateEpoch(_id);
        emit UpdateVPS(_id, strategy.lastProcessedEpoch, _newVPS, netVPS);
    }

    /// @notice Sets new VPS of the strategy.
    /**
     * @dev Only Owner can call this function.
     *      Owner must transfer fund to our vault before calling this function
     */
    /// @param _id Strategy _id
    /// @param _newVPS New VPS value
    function rebalancing(
        uint _id,
        uint _newVPS
    ) external nonReentrant onlyOwner checkStrategyExistence(_id) {
        StrategyInfo storage strategy = _strategyInfo[_id];
        require(strategy.investAddress != address(0), "ERR_V.14");

        if (strategy.lastProcessedEpoch == 0) {
            EpochInfo storage initEpoch = _epochInfo[_id][0];
            if (initEpoch.VPS > 0) {
                require(
                    initEpoch.lastDepositorProcessed == initEpoch.totDepositors,
                    "ERR_V.16"
                );
                require(_epochCounter[_id] > 1, "ERR_V.17");
                strategy.lastProcessedEpoch++;
                EpochInfo storage newEpoch = _epochInfo[_id][1];
                require(
                    block.timestamp >=
                        newEpoch.epochStartTime + newEpoch.duration,
                    "ERR_V.18"
                );
                newEpoch.VPS = _newVPS;
            } else {
                require(
                    block.timestamp >=
                        initEpoch.epochStartTime + initEpoch.duration,
                    "ERR_V.18"
                );
                strategy.watermark = _newVPS;
                initEpoch.VPS = _newVPS;
            }
        } else {
            require(
                _epochInfo[_id][strategy.lastProcessedEpoch]
                    .lastDepositorProcessed ==
                    _epochInfo[_id][strategy.lastProcessedEpoch].totDepositors,
                "ERR_V.16"
            );
            strategy.lastProcessedEpoch++;
            require(
                _epochCounter[_id] > strategy.lastProcessedEpoch,
                "ERR_V.17"
            );
            EpochInfo storage subsequentEpoch = _epochInfo[_id][
                strategy.lastProcessedEpoch
            ];
            require(
                block.timestamp >=
                    subsequentEpoch.epochStartTime + subsequentEpoch.duration,
                "ERR_V.18"
            );
            subsequentEpoch.VPS = _newVPS;
        }

        processFund(_id, _newVPS);
    }

    ////////////////// MAIN //////////////////

    /// @notice Users Deposit tokens to our vault
    /**
     * @dev Anyone can call this function if strategy is not paused.
     *      Users must approve deposit token before calling this function
     *      We mint represent token to users so that we can calculate each users deposit amount outside
     */
    /// @param _id Strategy _id
    /// @param _amount Token Amount to deposit
    function deposit(
        uint _id,
        uint _amount
    ) external nonReentrant checkStrategyExistence(_id) {
        require(_strategyInfo[_id].paused == false, "ERR_V.2");
        StrategyInfo storage strategy = _strategyInfo[_id];
        require(_amount > strategy.minDeposit, "ERR_V.20");
        require(
            strategy.assetToken.balanceOf(_msgSender()) >= _amount,
            "ERR_V.21"
        );
        uint curEpoch = getCurrentEpoch(_id);
        EpochInfo storage epoch = _epochInfo[_id][curEpoch];
        require(
            block.timestamp <= epoch.epochStartTime + epoch.duration,
            "ERR_V.5"
        );
        UserInfoEpoch storage userEpoch = _userInfoEpoch[_id][_msgSender()][
            curEpoch
        ];

        require(
            epoch.totDepositedAssets + _amount <= strategy.maxDeposit,
            "ERR_V.23"
        );

        if (!userEpoch.hasDeposited) {
            require(epoch.totDepositors + 1 <= strategy.maxUsers, "ERR_V.22");
            _depositors[_id][curEpoch][epoch.totDepositors] = _msgSender();
            userEpoch.depositIndex = epoch.totDepositors;
            epoch.totDepositors++;
            userEpoch.hasDeposited = true;
        }

        uint feeAmount = strategy.entryFee > 0 ? (_amount * strategy.entryFee) / feeBase : 0;
        epoch.totalFee += feeAmount;
        epoch.totDepositedAssets += (_amount - feeAmount);
        require(
            strategy.assetToken.allowance(_msgSender(), address(this)) >=
                _amount,
            "Insufficient allowance for deposit"
        );
        strategy.assetToken.safeTransferFrom(
            _msgSender(),
            address(this),
            _amount
        );
        userEpoch.depositInfo += (_amount - feeAmount);
        userEpoch.feePaid += feeAmount;
        emit Deposit(_msgSender(), address(this), _id, _amount);
    }

    /// @notice Immediately withdraw current pending deposit amount
    /// @param _id Strategy _id
    function cancelDeposit(
        uint _id
    )
        external
        nonReentrant
        checkStrategyExistence(_id)
        checkEpochExistence(_id)
    {
        StrategyInfo storage strategy = _strategyInfo[_id];
        uint curEpoch = getCurrentEpoch(_id);
        EpochInfo storage epoch = _epochInfo[_id][curEpoch];
        require(
            block.timestamp < epoch.epochStartTime + epoch.duration,
            "ERR_V.24"
        );
        UserInfoEpoch storage userEpoch = _userInfoEpoch[_id][_msgSender()][
            curEpoch
        ];
        uint amount = userEpoch.depositInfo + userEpoch.feePaid;
        require(amount > 0, "ERR_V.20");

        // Update state variables first
        epoch.totDepositedAssets -= userEpoch.depositInfo;
        epoch.totalFee -= userEpoch.feePaid;
    
        // Reset user's deposit info
        userEpoch.depositInfo = 0;
        userEpoch.feePaid = 0;

        // Handle depositors array update
        if (epoch.totDepositors > 1) {
            // Get the last depositor's address
            address lastDepositor = _depositors[_id][curEpoch][
                epoch.totDepositors - 1
            ];

            // Replace the current user with the last depositor if they are not the last one
            if (userEpoch.depositIndex != epoch.totDepositors - 1) {
                _depositors[_id][curEpoch][
                    userEpoch.depositIndex
                ] = lastDepositor;
                _userInfoEpoch[_id][lastDepositor][curEpoch]
                    .depositIndex = userEpoch.depositIndex;
            }

            // Clear the last depositor's slot
            _depositors[_id][curEpoch][epoch.totDepositors - 1] = address(0);
        } else {
            // Clear the only depositor's slot if there's only one depositor
            _depositors[_id][curEpoch][0] = address(0);
        }

        userEpoch.depositIndex = 0;
        userEpoch.hasDeposited = false;
        epoch.totDepositors--;

        // Transfer the assets back to the user
        strategy.assetToken.safeTransfer(_msgSender(), amount);

        emit CancelDeposit(_msgSender(), _id, amount);
    }

    /// @notice Sends Withdraw Request to vault
    /**
     * @dev Withdraw amount user shares from vault
     */
    /// @param _id Strategy _id
    function withdraw(
        uint _id,
        uint _amount
    )
        external
        nonReentrant
        checkStrategyExistence(_id)
        checkEpochExistence(_id)
    {
        require(_amount > 0, "ERR_V.20");
        uint sharesBalance = _strategyInfo[_id].fundRepresentToken.balanceOf(
            _msgSender()
        );
        require(sharesBalance >= _amount, "ERR_V.25");
        uint curEpoch = getCurrentEpoch(_id);
        require(
            block.timestamp <=
                _epochInfo[_id][curEpoch].epochStartTime +
                    _epochInfo[_id][curEpoch].duration,
            "ERR_V.5"
        );
        UserInfoEpoch storage userEpoch = _userInfoEpoch[_id][_msgSender()][
            curEpoch
        ];
        UserInfo storage user = _userInfo[_id][_msgSender()];
        if (user.lastEpoch > 0 && userEpoch.withdrawInfo == 0)
            _claimWithdrawedTokens(_id, user.lastEpoch, _msgSender());

        _epochInfo[_id][curEpoch].totWithdrawnShares += _amount;
        userEpoch.withdrawInfo += _amount;
        if (user.lastEpoch != curEpoch) user.lastEpoch = curEpoch;
        require(
            _strategyInfo[_id].fundRepresentToken.allowance(
                _msgSender(),
                address(this)
            ) >= _amount,
            "Insufficient allowance for withdraw"
        );
        _strategyInfo[_id].fundRepresentToken.safeTransferFrom(
            _msgSender(),
            address(this),
            _amount
        );
        emit Withdraw(_msgSender(), _id, _amount);
    }

    /// @notice Immediately claim current pending shares amount
    /// @param _id Strategy _id
    function cancelWithdraw(
        uint _id
    )
        external
        nonReentrant
        checkStrategyExistence(_id)
        checkEpochExistence(_id)
    {
        StrategyInfo storage strategy = _strategyInfo[_id];
        uint curEpoch = getCurrentEpoch(_id);
        EpochInfo storage epoch = _epochInfo[_id][curEpoch];
        require(
            block.timestamp < epoch.epochStartTime + epoch.duration,
            "ERR_V.24"
        );
        UserInfoEpoch storage userEpoch = _userInfoEpoch[_id][_msgSender()][
            curEpoch
        ];
        UserInfo storage user = _userInfo[_id][_msgSender()];
        uint amount = userEpoch.withdrawInfo;
        require(amount > 0, "ERR_V.20");
        userEpoch.withdrawInfo = 0;
        user.lastEpoch = 0;
        require(epoch.totWithdrawnShares >= amount, "ERR_V.26");
        epoch.totWithdrawnShares -= amount;
        strategy.fundRepresentToken.safeTransfer(
            _msgSender(),
            amount
        );

        emit CancelWithdraw(_msgSender(), _id, amount);
    }

    /// @notice Internal get withdraw tokens from vault for user
    /**
     * @dev Withdraw user funds from vault
     */
    /// @param _id Strategy _id
    /// @param _user Strategy _id
    function _claimWithdrawedTokens(
        uint _id,
        uint _lastEpoch,
        address _user
    ) internal {
        EpochInfo storage epoch = _epochInfo[_id][_lastEpoch];
        require(epoch.VPS > 0, "ERR_V.27");

        uint withdrawInfo = _userInfoEpoch[_id][_user][_lastEpoch].withdrawInfo;
        uint availableToClaim;
        if (withdrawInfo > 0) {
            uint dueWithdraw = (withdrawInfo * epoch.currentWithdrawAssets) /
                epoch.totWithdrawnShares;

            availableToClaim += dueWithdraw;
            emit ClaimWithdrawedToken(_id, _user, _lastEpoch, dueWithdraw);
        }
        if (availableToClaim > 0) {
            _strategyInfo[_id].assetToken.safeTransfer(
                _user,
                availableToClaim
            );
        }

        emit WithdrawedToken(_id, _user, availableToClaim);
    }

    /// @notice Get withdraw tokens from vault
    /**
     * @dev Withdraw my fund from vault
     */
    /// @param _id Strategy _id
    function claimWithdrawedTokens(
        uint _id
    ) external nonReentrant checkStrategyExistence(_id) {
        UserInfo storage user = _userInfo[_id][_msgSender()];
        require(user.lastEpoch > 0, "ERR_V.11");
        _claimWithdrawedTokens(_id, user.lastEpoch, _msgSender());
        user.lastEpoch = 0;
    }

    /// @notice Distribute shares to the epoch depositors
    /// @dev Only Owner can call this function if deposit duration is passed.
    /// @param _id Strategy _id
    function processDeposits(
        uint _id
    ) external nonReentrant onlyOwner checkStrategyExistence(_id) {
        StrategyInfo memory strategy = _strategyInfo[_id];
        EpochInfo memory epoch = _epochInfo[_id][strategy.lastProcessedEpoch];
        require(epoch.VPS > 0, "ERR_V.27");
        require(epoch.lastDepositorProcessed == 0, "ERR_V.28");
        if (epoch.totDepositedAssets == 0) {
            return;
        }

        _distributeShares(_id);
    }

    /**
     * @dev Continues the process of distributing shares for a specific strategy, if possible.
     * This function is only callable by the contract owner.
     * @param _id The _id of the strategy for which to continue distributing shares.
     */
    function continueDistributingShares(
        uint _id
    ) external nonReentrant onlyOwner checkStrategyExistence(_id) {
        // Check if there's anything to distribute
        EpochInfo memory epoch = _epochInfo[_id][
            _strategyInfo[_id].lastProcessedEpoch
        ];
        require(epoch.VPS > 0, "ERR_V.27");
        require(epoch.lastDepositorProcessed != 0, "ERR_V.29");
        require(epoch.lastDepositorProcessed < epoch.totDepositors, "ERR_V.30");
        _distributeShares(_id);
    }

    /**
     * @dev Distributes the newly minted shares among the depositors of a specific strategy.
     * The function processes depositors until maxUsersToDistribute is rechead if it is greater than 0.
     * @param _id The _id of the strategy for which to distribute shares.
     */
    function _distributeShares(uint _id) internal {
        uint lastProcessedEpoch = _strategyInfo[_id].lastProcessedEpoch;
        EpochInfo storage epoch = _epochInfo[_id][lastProcessedEpoch];
        uint sharesToDistribute = epoch.newShares;

        // Calculate loop limit
        uint loopLimit = maxUsersToDistribute > 0
            ? maxUsersToDistribute + epoch.lastDepositorProcessed
            : epoch.totDepositors;

        if (loopLimit > epoch.totDepositors) {
            loopLimit = epoch.totDepositors;
        }

        // Initialize a local counter for last processed index
        uint lastProcessedIndex = epoch.lastDepositorProcessed;

        // Process depositors and distribute shares proportionally
        for (uint i = lastProcessedIndex; i < loopLimit; i++) {
            address investor = _depositors[_id][lastProcessedEpoch][i];
            uint depositInfo = _userInfoEpoch[_id][investor][lastProcessedEpoch]
                .depositInfo;
            uint dueShares = (sharesToDistribute * depositInfo) /
                epoch.totDepositedAssets;

            // Transfer shares if dueShares is greater than 0
            if (dueShares > 0) {
                require(
                    _strategyInfo[_id].fundRepresentToken.balanceOf(
                        address(this)
                    ) >= dueShares,
                    "ERR_V.10"
                );
                _strategyInfo[_id].fundRepresentToken.safeTransfer(
                    investor,
                    dueShares
                );
                emit SharesDistributed(
                    _id,
                    lastProcessedEpoch,
                    investor,
                    dueShares
                );
            }

            lastProcessedIndex = i + 1;
        }

        // Update the epoch's last depositor processed after the loop
        epoch.lastDepositorProcessed = lastProcessedIndex;
    }

    /**
     * @notice Distribute pending fees to the treasury addresses
     * @dev Internal function
     */
    /// @param _id Strategy _id
    function sendPendingFees(
        uint _id
    ) external nonReentrant onlyOwner checkStrategyExistence(_id) {
        StrategyInfo storage strategy = _strategyInfo[_id];

        require(
            block.timestamp >=
                strategy.lastFeeDistribution + strategy.feeDuration,
            "ERR_V.31"
        );
        strategy.lastFeeDistribution = block.timestamp;

        uint pendingFees = strategy.pendingFees;
        require(pendingFees > 0, "ERR_V.15");
        require(
            strategy.assetToken.balanceOf(address(this)) >= pendingFees,
            "ERR_V.19"
        );
        strategy.pendingFees = 0;

        address addr0 = strategy.withdrawAddress[0];
        address addr1 = strategy.withdrawAddress[1];
        emit SendFeeWithOwner(_id, addr0, pendingFees / 2);
        emit SendFeeWithOwner(_id, addr1, pendingFees / 2);
        strategy.assetToken.safeTransfer(addr0, pendingFees / 2);
        strategy.assetToken.safeTransfer(addr1, pendingFees / 2);
    }

    /// @notice Withdraw ERC-20 Token to the owner
    /**
     * @dev Only Owner can call this function
     */
    /// @param _tokenContract ERC-20 Token address
    function withdrawERC20(IERC20 _tokenContract) external onlyOwner {
        for (uint i = 0; i < strategiesCounter; i++) {
            require(_strategyInfo[i].assetToken != _tokenContract, "ERR_V.32");
        }

        _tokenContract.safeTransfer(
            _msgSender(),
            _tokenContract.balanceOf(address(this))
        );
    }
}