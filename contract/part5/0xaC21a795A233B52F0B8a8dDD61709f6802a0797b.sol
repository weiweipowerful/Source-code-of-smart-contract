// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IAggregationRouterV5.sol";
import "../interfaces/IZkSyncL1Gateway.sol";
import "hardhat/console.sol";

contract TokenSwapAndDeposit is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address immutable public AGGREGATION_ROUTER_V5_ADDRESS; // 1inch Router contract address
    address immutable public ZK_SYNC_L1_GATEWAY_ADDRESS;    // zkLink contract address
    address[] public signers;                               // The addresses that can co-sign transactions on the wallet
    mapping(uint256 => order) orders;                       // history orders
    IERC20 private constant ETH_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    IERC20 private constant ZERO_ADDRESS = IERC20(address(0));
    
    event Deposit(
        address from,
        address token,
        uint256 spentAmount,
        uint256 swapReturnAmount
    );

    event Withdraw(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event WithdrawERC20(uint256 orderId, address token, address to, uint256 amount);
    event WithdrawETH(uint256 orderId, address to, uint256 amount);

    struct order{
        address to;     // The address the transaction was sent to
        uint256 amount; // Amount of Wei sent to the address
        address token;  // The address of the ERC20 token contract, 0 means ETH
        bool executed;  // If the order was executed
    }

    constructor(address aggregationRouterV5, address zkSyncL1Gateway, address[] memory allowedSigners) {
        require(allowedSigners.length == 3, "invalid allSigners length");
        require(allowedSigners[0] != allowedSigners[1], "must be different signers");
        require(allowedSigners[0] != allowedSigners[2], "must be different signers");
        require(allowedSigners[1] != allowedSigners[2], "must be different signers");

        signers = allowedSigners;
        AGGREGATION_ROUTER_V5_ADDRESS = aggregationRouterV5;
        ZK_SYNC_L1_GATEWAY_ADDRESS = zkSyncL1Gateway;
        
    }

    /**
    * Gets called when a transaction is received without calling a method
    */
    receive() external payable { }

    uint256 beforeSwapSrcTokenBalance;
    uint256 beforeSwapDstTokenBalance;
    uint256 afterDepositSrcTokenBalance;
    uint256 afterDepositDstTokenBalance;
    uint256 afterSwapSrcTokenBalance;
    uint256 afterSwapDstTokenBalance;

    /**
    * @notice This function handles deposits where both the `from` and `to` assets are ERC20 tokens.
    *         If the `from` and `to` tokens are the same, it directly deposits into zkSync without using 1inch.
    *         If they are different, it swaps using 1inch before depositing the converted token into zkSync.
    * 
    * @param _token The address of the `from` token (ERC20 token being deposited).
    * @param _amount The amount of the `from` token to deposit.
    * @param _zkLinkAddress The zkLink address to deposit the converted tokens to.
    * @param _exchangeData Data required for the 1inch swap, including swap description and min return amount.
    * 
    * @return The amount of tokens deposited to zkSync after the swap.
    */
    function deposit(
        address _token,
        uint256 _amount,
        bytes32 _zkLinkAddress,
        bytes calldata _exchangeData
    ) external payable nonReentrant returns (uint256) {
        uint256 returnAmount;

        (, IAggregationRouterV5.SwapDescription memory desc,) = abi.decode(_exchangeData[4:], (address, IAggregationRouterV5.SwapDescription, bytes));
        require(_token == address(desc.srcToken), 'mismatch token and desc.srcToken');
        require(_amount == desc.amount, 'mismatch amount and desc.amount');
        require(address(this) == address(desc.dstReceiver), 'invalid desc.dstReceiver');

        IERC20 tokenERC20 = IERC20(_token);
        tokenERC20.safeTransferFrom(msg.sender, address(this), _amount);

        if (_token == address(desc.dstToken)) {
            // If ERC20 tokens are deposited directly
            returnAmount = _amount;
        } else {
            // Use 1inch for token exchange
            tokenERC20.safeApprove(AGGREGATION_ROUTER_V5_ADDRESS, 0);
            tokenERC20.safeApprove(AGGREGATION_ROUTER_V5_ADDRESS, desc.amount);
            (bool success, bytes memory returndata)= AGGREGATION_ROUTER_V5_ADDRESS.call{value:msg.value}(_exchangeData);
            require(success, "exchange failed");
            (returnAmount, ) = abi.decode(returndata, (uint256, uint256));
            require(returnAmount >= desc.minReturnAmount, "received less than minReturnAmount");
        }

        // // Assets deposited after exchange
        IERC20 assetERC20 = IERC20(address(desc.dstToken));
        assetERC20.safeApprove(ZK_SYNC_L1_GATEWAY_ADDRESS, 0);
        assetERC20.safeApprove(ZK_SYNC_L1_GATEWAY_ADDRESS, returnAmount);

        uint104 smallAmount = uint104(returnAmount);
        IZkSyncL1Gateway(ZK_SYNC_L1_GATEWAY_ADDRESS).depositERC20(address(desc.dstToken), smallAmount, _zkLinkAddress, 0, false);

        emit Deposit(
            msg.sender,
            _token,
            _amount,
            returnAmount
        );

        return returnAmount;
    }


    /**
    * @notice This function handles deposits where either the `from` or `to` token is a native token (ETH).
    *         It supports the following cases:
    *         - Case 1: From and to are the same native token (ETH -> ETH)
    *         - Case 2: From is native token (ETH) and to is an ERC20 token (ETH -> ERC20)
    *         - Case 3: From is ERC20 token and to is native token (ERC20 -> ETH)
    * 
    * @param _token The address of the source token (either native token or ERC20 token).
    * @param _amount The amount of the source token to deposit.
    * @param _zkLinkAddress The zkLink address to deposit the converted tokens to.
    * @param _exchangeData Data required for the 1inch swap, including swap description and min return amount.
    * 
    * @return The amount of tokens deposited to zkSync after the swap or direct deposit.
    */
    function depositETH(
        address _token,
        uint256 _amount,
        bytes32 _zkLinkAddress,
        bytes calldata _exchangeData
    ) external payable nonReentrant returns (uint256) {
        uint256 returnAmount;

        // Decode the swap description from the exchange data
        (, IAggregationRouterV5.SwapDescription memory desc,) = abi.decode(_exchangeData[4:], (address, IAggregationRouterV5.SwapDescription, bytes));

        // Ensure either `from` or `to` token is native (ETH)
        require(isNative(IERC20(desc.srcToken)) || isNative(IERC20(desc.dstToken)), "Either srcToken or dstToken must be native");

        // Default subAccountId to 0
        uint8 _subAccountId = 0;

        // Case 1: From and to are the same native token (ETH -> ETH)
        if (isNative(IERC20(desc.srcToken)) && isNative(IERC20(desc.dstToken)) && desc.srcToken == desc.dstToken) {
            require(msg.value == _amount, "msg.value must equal amount");

            // Deposit ETH directly to zkSync using the updated method
            IZkSyncL1Gateway(ZK_SYNC_L1_GATEWAY_ADDRESS).depositETH{value: msg.value}(_zkLinkAddress, _subAccountId);

            emit Deposit(msg.sender, address(desc.srcToken), _amount, _amount);
            return _amount;

        } 
        // Case 2: From is native token (ETH) and to is ERC20 token (ETH -> ERC20)
        else if (isNative(IERC20(desc.srcToken)) && !isNative(IERC20(desc.dstToken))) {
            require(msg.value == _amount, "msg.value must equal amount");

            // Swap ETH to ERC20 using 1inch
            (bool success, bytes memory returndata) = AGGREGATION_ROUTER_V5_ADDRESS.call{value: msg.value}(_exchangeData);
            require(success, "exchange failed");

            // Decode the return amount from the swap
            (returnAmount, ) = abi.decode(returndata, (uint256, uint256));
            require(returnAmount >= desc.minReturnAmount, "received less than minReturnAmount");

            // Approve zkSync to pull the swapped ERC20 tokens
            IERC20 tokenERC20 = IERC20(desc.dstToken);
            tokenERC20.safeApprove(ZK_SYNC_L1_GATEWAY_ADDRESS, 0);
            tokenERC20.safeApprove(ZK_SYNC_L1_GATEWAY_ADDRESS, returnAmount);

            // Deposit the swapped ERC20 token into zkSync
            IZkSyncL1Gateway(ZK_SYNC_L1_GATEWAY_ADDRESS).depositERC20(address(desc.dstToken), uint104(returnAmount), _zkLinkAddress, _subAccountId, false);

            emit Deposit(msg.sender, address(desc.srcToken), _amount, returnAmount);
            return returnAmount;

        }
        // Case 3: From is ERC20 token and to is native token (ETH) (ERC20 -> ETH)
        else if (!isNative(IERC20(desc.srcToken)) && isNative(IERC20(desc.dstToken))) {
            IERC20 tokenERC20 = IERC20(desc.srcToken);
            tokenERC20.safeTransferFrom(msg.sender, address(this), _amount);
            tokenERC20.safeApprove(AGGREGATION_ROUTER_V5_ADDRESS, 0);
            tokenERC20.safeApprove(AGGREGATION_ROUTER_V5_ADDRESS, _amount);

            // Swap ERC20 to native token using 1inch
            (bool success, bytes memory returndata)= AGGREGATION_ROUTER_V5_ADDRESS.call{value:msg.value}(_exchangeData);
            require(success, "exchange failed");

            // Decode the return amount from the swap
            (returnAmount, ) = abi.decode(returndata, (uint256, uint256));
            require(returnAmount >= desc.minReturnAmount, "received less than minReturnAmount");

            // Deposit the swapped native token (ETH) into zkSync
            IZkSyncL1Gateway(ZK_SYNC_L1_GATEWAY_ADDRESS).depositETH{value: returnAmount}(_zkLinkAddress, _subAccountId);

            emit Deposit(msg.sender, address(desc.srcToken), _amount, returnAmount);
            return returnAmount;
        } else {
            revert("Invalid token combination for depositETH");
        }
    }



    /**
    * Withdraw ETHER from this wallet using 2 signers.
    *
    * @param  to         the destination address to send an outgoing transaction
    * @param  amount     the amount in Wei to be sent
    * @param  expireTime the number of seconds since 1970 for which this transaction is valid
    * @param  orderId    the unique order id 
    * @param  allSigners all signers who sign the tx
    * @param  signatures the signatures of tx
    */
    function withdrawETH(
        address payable to,
        uint256 amount,
        uint256 expireTime,
        uint256 orderId,
        address[] memory allSigners,
        bytes[] memory signatures
    ) public nonReentrant {
        require(allSigners.length >= 2, "invalid allSigners length");
        require(allSigners.length == signatures.length, "invalid signatures length");
        require(allSigners[0] != allSigners[1],"can not be same signer"); // must be different signer
        require(expireTime >= block.timestamp,"expired transaction");

        bytes32 operationHash = keccak256(abi.encodePacked("ETHER", to, amount, expireTime, orderId, address(this)));
        operationHash = ECDSA.toEthSignedMessageHash(operationHash);
        
        for (uint8 index = 0; index < allSigners.length; index++) {
        address signer = ECDSA.recover(operationHash, signatures[index]);
        require(signer == allSigners[index], "invalid signer");
        require(isAllowedSigner(signer), "not allowed signer");
        }

        // Try to insert the order ID. Will revert if the order id was invalid
        tryInsertOrderId(orderId, to, amount, address(0));

        // send ETHER
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");

        emit WithdrawETH(orderId, to, amount);
    }

    /**
    * Withdraw ERC20 from this wallet using 2 signers.
    *
    * @param  to         the destination address to send an outgoing transactioni
    * @param  amount     the amount in Wei to be sent
    * @param  token      the address of the erc20 token contract
    * @param  expireTime the number of seconds since 1970 for which this transaction is valid
    * @param  orderId    the unique order id 
    * @param  allSigners all signer who sign the tx
    * @param  signatures the signatures of tx
    */


    function withdrawErc20(
        address to,
        uint256 amount,
        address token,
        uint256 expireTime,
        uint256 orderId,
        address[] memory allSigners,
        bytes[] memory signatures
    ) public nonReentrant {
        require(allSigners.length >=2, "invalid allSigners length");
        require(allSigners.length == signatures.length, "invalid signatures length");
        require(allSigners[0] != allSigners[1],"can not be same signer"); // must be different signer
        require(expireTime >= block.timestamp,"expired transaction");

        bytes32 operationHash = keccak256(abi.encodePacked("ERC20", to, amount, token, expireTime, orderId, address(this)));
        operationHash = ECDSA.toEthSignedMessageHash(operationHash);

        for (uint8 index = 0; index < allSigners.length; index++) {
        address signer = ECDSA.recover(operationHash, signatures[index]);
        require(signer == allSigners[index], "invalid signer");
        require(isAllowedSigner(signer),"not allowed signer");
        }

        // Try to insert the order ID. Will revert if the order id was invalid
        tryInsertOrderId(orderId, to, amount, token);

        // Success, send ERC20 token
        IERC20(token).safeTransfer(to, amount);
        emit WithdrawERC20(orderId, token, to, amount);
    }

    /**
    * Determine if an address is a signer on this wallet
    *
    * @param signer address to check
    */
    function isAllowedSigner(address signer) public view returns (bool) {
    // Iterate through all signers on the wallet and
    for (uint i = 0; i < signers.length; i++) {
        if (signers[i] == signer) {
        return true;
        }
    }
    return false;
    }

    /**
    * Verify that the order id has not been used before and inserts it. Throws if the order ID was not accepted.
    *
    * @param orderId   the unique order id 
    * @param to        the destination address to send an outgoing transaction
    * @param amount     the amount in Wei to be sent
    * @param token     the address of the ERC20 contract
    */
    function tryInsertOrderId(
        uint256 orderId, 
        address to,
        uint256 amount, 
        address token
    ) internal {
    if (orders[orderId].executed) {
        // This order ID has been excuted before. Disallow!
        revert("repeated order");
    }

    orders[orderId].executed = true;
    orders[orderId].to = to;
    orders[orderId].amount = amount;
    orders[orderId].token = token;
    }

    function isNative(IERC20 token_) internal pure returns (bool) {
        return (token_ == ZERO_ADDRESS || token_ == ETH_ADDRESS);
    }
  
    function updateSigners(address[] memory newSigners) public onlyOwner {
        require(newSigners.length == 3, "newSigners must have exactly 3 signers");
        require(newSigners[0] != newSigners[1], "newSigners[0] and newSigners[1] must be different");
        require(newSigners[0] != newSigners[2], "newSigners[0] and newSigners[2] must be different");
        require(newSigners[1] != newSigners[2], "newSigners[1] and newSigners[2] must be different");

        signers = newSigners;
    }
      
}