// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

import {DioneBridge} from "./bridge/DioneBridge.sol";

//////////////////////////////////////////////////
///                                            ///
///            Wrapped Dione token             ///
///                                            ///
//////////////////////////////////////////////////

contract WDIONEBridged is ERC20, Ownable2Step{
    /// ERRORS

    error FeeTooBig();
    error ZeroAddress();
    error OnlyBridge();
    error BalanceUnderflow();

    /// EVENTS

    event FeesSentToBridge(address indexed receiver, uint256 amount);
    event FeeUpdated(uint256 newFee);
    event FeeReceiverUpdated(address newFeeReceiver);
    event PayFeeListUpdated(address account, bool isPayFee);
    event FeeThresholdUpdated(uint256 newFeeThreshold);

    /// CONSTANTS

    /// @notice Divisor for computation (1 bps (basis point) precision: 0.001%).
    uint32 constant PCT_DIV = 100_000; 
    /// @notice Minimum amount of accumulated commission to send commission to Odyssey
    uint256 constant MIN_FEE_THRESHOLD = 1 * 10 ** 18;
    /// @notice Dione bridge instance
    DioneBridge immutable public BRIDGE;
    /// @notice Odyssey chain id, used in Wanchain gateway
    uint256 immutable public ODYSSEY_ID;
    
    /// STORAGE

    /// @notice List of addresses of token recipients for which commission is charged
    mapping(address => bool) public isPayFee;
    /// @notice send fees to the Odyssey chain if collected fees are above this threshold
    uint256 public feeThreshold;
    /// @notice collected fees tracker
    uint256 public collectedFees;
    /// @notice transfer fee in bps, [0...100000]
    uint32 public fee;
    /// @notice account that will receive bridged fees in Odyssey
    address public feeReceiver;
    /// @dev Indicator that an attempt was made to send fees during the transfer
    bool private _isTrySendFees;

    modifier onlyBridge() {
        if(msg.sender != address(BRIDGE)) revert OnlyBridge();
        _;
    }
    /// @notice Set initial parameters for the token
    /// @param name Token name
    /// @param symbol Token symbol
    /// @param _bridge Dione bridge address
    /// @param _targetId chain Id of the fee receiver
    /// @param _owner token admin
    /// @param _fee fee amount in bps [0...100000]
    /// @param _feeThreshold send fees to the receiver if collected amount is above the threshold
    /// @param _feeReceiver address of the fee receiver in the target chain
    /// @param _toAdd array of (accounts)token recipients for which commission is charged
    constructor(
        string memory name,
        string memory symbol,
        DioneBridge _bridge,
        uint256 _targetId,
        address _owner,
        uint32 _fee,
        uint256 _feeThreshold,
        address _feeReceiver,
        address[] memory _toAdd
    )
        ERC20(name, symbol)
    {
        if (address(_bridge) == address(0)) revert ZeroAddress();
        if(fee > PCT_DIV) revert FeeTooBig();
        BRIDGE = _bridge;
        ODYSSEY_ID = _targetId;
        fee = _fee;
        feeThreshold = _feeThreshold;
        feeReceiver = _feeReceiver;
        setPayFeeListBatch(_toAdd, true);

        _transferOwnership(_owner);
    }

    /// @notice Send collected fees to the target chain if threshold condition allows
    /// @dev Will not revert in failure
    /// @dev This contract MUST have ETH tokens to pay for the tokens bridging into the target chain
    function checkAndSendFees() public {
        if (!_isTrySendFees) {
            if(collectedFees > feeThreshold) {
                _isTrySendFees = true;
                uint256 _collectedFees = collectedFees;
                collectedFees = 0;

                uint256 toPay = _estimateGas();
                if(address(this).balance < toPay) return;

                _approve(address(this), address(BRIDGE), _collectedFees);
                bool success = _trySendFees(toPay);
                _approve(address(this), address(BRIDGE), 0);
                
                if(!success) {
                    collectedFees = _collectedFees;
                    return;
                }
                emit FeesSentToBridge(feeReceiver, _collectedFees);
            }
        }
    }

    receive() external payable {}

    ///------------------ BRIDGE ------------------///

    /// @notice Mint tokens to the recipient
    /// @param to Minted tokens recipient
    /// @param amount Minted tokens amount
    function mint(address to, uint256 amount) onlyBridge external {
        _mint(to, amount);
    }

    /// @notice Burn tokens from the account
    /// @param amount Burned tokens amount
    function burn(uint256 amount) onlyBridge external {
        if(balanceOf(msg.sender) < amount) revert BalanceUnderflow();
        _burn(msg.sender, amount);
    }

    function _trySendFees(uint256 toPay) internal returns(bool success) {
        (success, ) = address(BRIDGE).call{value: toPay}(abi.encodeWithSelector(
            BRIDGE.redeem.selector,
            feeReceiver,
            ODYSSEY_ID,
            IERC20(address(this)),
            collectedFees
        ));
    } 

    function _estimateGas() internal view returns(uint256 toPay) {
        toPay = BRIDGE.estimateFee(
            ODYSSEY_ID,
            BRIDGE.messageGasLimit()
        );
    }

    ///------------------ ADMIN ------------------///

    /// @notice Set fee 
    /// @param _fee fee amount in bps [0...100000]
    function setFee(uint32 _fee) onlyOwner external {
        if(_fee > PCT_DIV) revert FeeTooBig();
        fee = _fee;

        emit FeeUpdated(_fee);
    }

    /// @notice Set fee receiver
    /// @param _feeReceiver address of the fee receiver in the target chain
    function setFeeReceiver(address _feeReceiver) onlyOwner external {
        if (_feeReceiver == address(0)) revert ZeroAddress();
        feeReceiver = _feeReceiver;

        emit FeeReceiverUpdated(_feeReceiver);
    }

    /// @notice Set fee threshold
    /// @param _feeThreshold send fees to the receiver if collected amount is above the threshold
    function setFeeThreshold(uint256 _feeThreshold) onlyOwner external {
        require(_feeThreshold >= MIN_FEE_THRESHOLD, "WDIONEBridged: Fee threshold too low");
        feeThreshold = _feeThreshold;

        emit FeeThresholdUpdated(_feeThreshold);
    }

    /// @notice Configure the pay fee list
    /// @param account Account to add/remove from the pay fee list
    /// @param add Add=true, Remove=false
    function setPayFeeList(address account, bool add) onlyOwner public {
        if (account == address(0)) revert ZeroAddress();
        isPayFee[account] = add;

        emit PayFeeListUpdated(account, add);
    }

    /// @notice Mass configure the pay fee list
    /// @param accounts Array of accounts
    /// @param add Add=true, Remove=false
    function setPayFeeListBatch(address[] memory accounts, bool add) onlyOwner public {
        for(uint256 i=0; i<accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            isPayFee[accounts[i]] = add;

            emit PayFeeListUpdated(accounts[i], add);
        }
    }

    /// @notice Withdraw native tokens from contract
    /// @param amount Amount of native tokens
    function withdrawNative(uint256 amount) onlyOwner external {
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH_TRANSFER_FAILED");
    }

    ///------------------ ERC20 ------------------///

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        uint256 feeAmount = 0;
        if(isPayFee[to] && to != address(BRIDGE)) {
            feeAmount = amount * fee / PCT_DIV;
        }
        if (spender != from) {
            _spendAllowance(from, spender, amount);
        }
        if (feeAmount > 0) {
            collectedFees += feeAmount;
            _transfer(from, address(this), feeAmount);
        }
        _transfer(from, to, amount - feeAmount);

        _isTrySendFees = false;
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        return transferFrom(owner, to, amount);
    }

    function _afterTokenTransfer(address, address, uint256) internal override {
        checkAndSendFees();
    }
}