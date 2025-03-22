//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title The token Contract for the Apollo Ecosystem
contract ApolloFTW is ERC20, Ownable {
    /// @notice whether a wallet excludes fees
    mapping(address => bool) public isExcludedFromFee;
    /// @notice The owner of the contract can still change whitelist addresses
    bool public ownerCanChangeWhitelist = true;
    /// @notice Addresses that will be used to determine B/S/T
    mapping(address => bool) private _markets;
    /// @notice The DAO address
    address public DAO;

    /// @notice The types of transactions
    enum TypeOfTransaction {
        BUY,
        SELL,
        TRANSFER
    }
    /// @notice The % of the transaction to be taxed in a buy.
    /// e.g. if this value is 1 that is .1%
    uint256 public buyTaxPerMille = 0;
    /// @notice The % of the transaction to be taxed in a sell.
    /// e.g. if this value is 1 that is .1%
    uint256 public sellTaxPerMille = 100;
    /// @notice The % of the transaction to be taxed in a transfer.
    /// e.g. if this value is 1 that is .1%
    uint256 public transferTaxPerMille = 0;

    /// @notice The owner of the contract can still change tax rates
    bool public ownerCanAdjustTaxes = true;

    constructor(address _devWallet) ERC20("Apollo FTW", "FTW") Ownable() {
        _mint(_devWallet, 2000000000000000000000000000);
        transferOwnership(_devWallet);
        DAO = _devWallet;
    }

    // Public ERC20 Functions

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        address owner = _msgSender();
        _transferWithTax(owner, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transferWithTax(from, to, amount);
        return true;
    }

    /// @notice Burn some tokens
    /// @param  value The amount of tokens to burn
    function burn(uint256 value) public virtual {
        _burn(_msgSender(), value);
    }

    // Public View Functions

    /// @notice Specifies what type of transaction this is
    /// @param _sender The address sending tokens
    /// @param _recipient The address receiving tokens
    function getTypeOfTransaction(
        address _sender,
        address _recipient
    ) public view returns (TypeOfTransaction) {
        if (isMarketAddress(_sender)) {
            return TypeOfTransaction.BUY;
        } else if (isMarketAddress(_recipient)) {
            return TypeOfTransaction.SELL;
        } else {
            return TypeOfTransaction.TRANSFER;
        }
    }

    /// @notice Shows whether or not an address is being treated as a market
    /// @param _potentialMarket The address to investigate
    function isMarketAddress(
        address _potentialMarket
    ) public view returns (bool) {
        return _markets[_potentialMarket];
    }

    /// @notice Shows how many tokens will be taxed for a transaction
    /// @param _amount The amount of tokens to be sent for a transaction
    /// @param _transactionType The type of transaction 0=Buy, 1=Sell, 2=Transfer
    function getTaxedAmount(
        uint256 _amount,
        TypeOfTransaction _transactionType
    ) public view returns (uint256) {
        if (_transactionType == TypeOfTransaction.BUY) {
            return (_amount * buyTaxPerMille) / 1000;
        } else if (_transactionType == TypeOfTransaction.SELL) {
            return (_amount * sellTaxPerMille) / 1000;
        } else {
            return (_amount * transferTaxPerMille) / 1000;
        }
    }

    //Owner Functions
    /// @notice Set an address to be or not be a market
    /// @param _potentialMarket The address to be changed
    /// @param _isMarket Is the address to be a market or not
    function setMarket(
        address _potentialMarket,
        bool _isMarket
    ) public onlyOwner {
        _markets[_potentialMarket] = _isMarket;
    }

    /// @notice Set a new buy tax
    /// @param _newBuyTaxPerMille New tax perMille (if this value is 1 that is .1%)
    function setBuyTax(
        uint256 _newBuyTaxPerMille
    ) public onlyOwner canRevokeTaxControl {
        require(
            _newBuyTaxPerMille <= 1000,
            "Tax can not be more than 1000 permille"
        );
        buyTaxPerMille = _newBuyTaxPerMille;
    }

    /// @notice Set a new sell tax
    /// @param _newSellTaxPerMille New tax perMille (if this value is 1 that is .1%)
    function setSellTax(
        uint256 _newSellTaxPerMille
    ) public onlyOwner canRevokeTaxControl {
        require(
            _newSellTaxPerMille <= 1000,
            "Tax can not be more than 1000 permille"
        );
        sellTaxPerMille = _newSellTaxPerMille;
    }

    /// @notice Set a new transfer tax
    /// @param _newTransferTaxPerMille New tax perMille (if this value is 1 that is .1%)
    function setTransferTax(
        uint256 _newTransferTaxPerMille
    ) public onlyOwner canRevokeTaxControl {
        require(
            _newTransferTaxPerMille <= 1000,
            "Tax can not be more than 1000 permille"
        );
        transferTaxPerMille = _newTransferTaxPerMille;
    }

    /// @notice Revoke ability to change taxes
    function revokeTaxControl() public onlyOwner {
        ownerCanAdjustTaxes = false;
    }

    /// @notice Whitelist an address
    /// @param account The address to be whitelisted
    function excludeFromFee(
        address account
    ) external onlyOwner canModifyWhitelist {
        isExcludedFromFee[account] = true;
    }

    /// @notice Un-whitelist an address
    /// @param account The address to be un-whitelisted
    function includeFromFee(
        address account
    ) external onlyOwner canModifyWhitelist {
        isExcludedFromFee[account] = false;
    }

    /// @notice Revoke ability to control whitelist
    function revokeWhiteListControl() public onlyOwner {
        ownerCanChangeWhitelist = false;
    }

    // Internal Functions

    function _transferWithTax(
        address from,
        address to,
        uint256 amount
    ) internal {
        uint256 taxedAmount = getTaxedAmount(
            amount,
            getTypeOfTransaction(from, to)
        );

        if (
            taxedAmount > 0 &&
            !isExcludedFromFee[from] &&
            !isExcludedFromFee[to]
        ) {
            amount -= taxedAmount;
            _transfer(from, DAO, taxedAmount);
        }

        _transfer(from, to, amount);
    }

    // Modifiers

    modifier canRevokeTaxControl() {
        require(ownerCanAdjustTaxes, "Owner has revoked control over taxes");
        _;
    }

    modifier canModifyWhitelist() {
        require(
            ownerCanChangeWhitelist,
            "Owner has revoked control over whitelist"
        );
        _;
    }

    //DAO Functions

    /// @notice Update the DAO contract
    /// @param _newDAO The address of the new dao
    function updateDAO(address _newDAO) public {
        require(_msgSender() == DAO, "Only current DAO can change the address");
        isExcludedFromFee[_newDAO] = true;
        _transfer(DAO, _newDAO, balanceOf(DAO));
        DAO = _newDAO;
    }
}