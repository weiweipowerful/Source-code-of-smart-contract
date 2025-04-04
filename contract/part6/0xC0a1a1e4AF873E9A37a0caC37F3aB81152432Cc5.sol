// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../interfaces/IAggregationRouterV5.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IStarkEx.sol";
import "../interfaces/IFactRegister.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


contract MultiSigPoolV5WithPermit is ReentrancyGuard {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;


  // Events
  event Deposit(address from, address token, uint256 spentAmount, uint256 swapReturnAmount, uint256 starkKey, uint256 positionId);
  event WithdrawETH(uint256 orderId, address to, uint256 amount);
  event WithdrawERC20(uint256 orderId, address token, address to, uint256 amount);
  event WithdrawERC20ForMPC(uint256 orderId, address from, address token, address to, uint256 amount);

  // Public fields
  address immutable public USDT_ADDRESS;                  // USDT contract address
  address immutable public STARKEX_ADDRESS;               // stark exchange adress
  address immutable public FACT_ADDRESS;                  // stark external fact contract address
  address immutable public AGGREGATION_ROUTER_V5_ADDRESS; // 1inch AggregationRouterV5  address
  address[] public signers;                               // The addresses that can co-sign transactions on the wallet
  mapping(uint256 => order) orders;                       // history orders
  uint256 public ASSET_TYPE;                              // stark exchange defined USDT

  IERC20 private constant ETH_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
  IERC20 private constant ZERO_ADDRESS = IERC20(address(0));

  struct order{
    address to;     // The address the transaction was sent to
    uint256 amount; // Amount of Wei sent to the address
    address token;  // The address of the ERC20 token contract, 0 means ETH
    bool executed;  // If the order was executed
  }

  /**
   *
   * @param allowedSigners      An array of signers on the wallet
   * @param usdt                The USDT contract address
   * @param aggregationRouterV5 The 1inch exchange router address
   * @param starkex             The stark exchange address
   * @param fact                The stark fact address
   */
  constructor(address[] memory allowedSigners, address usdt,address aggregationRouterV5,address starkex, address fact, uint256 assetType) {
    require(allowedSigners.length == 3, "invalid allSigners length");
    require(allowedSigners[0] != allowedSigners[1], "must be different signers");
    require(allowedSigners[0] != allowedSigners[2], "must be different signers");
    require(allowedSigners[1] != allowedSigners[2], "must be different signers");
    require(usdt != address(0), "invalid usdt address");
    require(aggregationRouterV5 != address(0), "invalid 1inch address");

    signers = allowedSigners;
    USDT_ADDRESS = usdt;
    AGGREGATION_ROUTER_V5_ADDRESS = aggregationRouterV5;
    STARKEX_ADDRESS = starkex;
    FACT_ADDRESS = fact;
    ASSET_TYPE = assetType;
  }

  /**
   * Gets called when a transaction is received without calling a method
   */
  receive() external payable { }

  /**
    * @notice Make a deposit to the Starkware Layer2, after converting funds to USDT.
    *  Funds will be transferred from the sender and USDT will be deposited into this wallet, and 
    *  generate a deposit event specified by the starkKey and positionId.
    *
    * @param  token          The ERC20 token to convert from
    * @param  amount         The amount in Wei to deposit.
    * @param  starkKey       The starkKey of the L2 account to deposit into.
    * @param  positionId     The positionId of the L2 account to deposit into.
    * @param  exchangeData   Trade parameters for the exchange.
    */
  function deposit(
    IERC20 token,
    uint256 amount,
    uint256 starkKey,
    uint256 positionId,
    bytes calldata exchangeData
  ) public payable nonReentrant returns (uint256) {
    uint256 returnAmount;
    uint256 beforeSwapBalance = IERC20(USDT_ADDRESS).balanceOf(address(this));

    if (address(token) == USDT_ADDRESS){   // deposit USDT 
      token.safeTransferFrom(msg.sender, address(this), amount);
      returnAmount = amount;
    } else {
      (, IAggregationRouterV5.SwapDescription memory desc, ,) = abi.decode(exchangeData[4:], (address, IAggregationRouterV5.SwapDescription, bytes, bytes));
      require(token == desc.srcToken, "mismatch token and desc.srcToken");
      require(USDT_ADDRESS == address(desc.dstToken), "invalid desc.dstToken");
      require(amount == desc.amount, "mismatch amount and desc.amount");
      require(address(this) == desc.dstReceiver, "invalid desc.dstReceiver");

      bool isNativeToken = isNative(desc.srcToken);
      if (!isNativeToken) {  // deposit other ERC20 tokens 
        desc.srcToken.safeTransferFrom(msg.sender, address(this), desc.amount);

        // safeApprove requires unsetting the allowance first.
        desc.srcToken.safeApprove(AGGREGATION_ROUTER_V5_ADDRESS, 0);
        desc.srcToken.safeApprove(AGGREGATION_ROUTER_V5_ADDRESS, desc.amount);
      }

      // Swap token
      (bool success, bytes memory returndata)= AGGREGATION_ROUTER_V5_ADDRESS.call{value:msg.value}(exchangeData);
      require(success, "exchange failed");

      (returnAmount, ) = abi.decode(returndata, (uint256, uint256));
      require(returnAmount >= desc.minReturnAmount, "received USDT less than minReturnAmount");
    }

    uint256 afterSwapBalance = IERC20(USDT_ADDRESS).balanceOf(address(this));
    require (afterSwapBalance == beforeSwapBalance.add(returnAmount),"swap incorrect");

    emit Deposit(
      msg.sender,
      address(token),
      amount,
      returnAmount,
      starkKey,
      positionId
    );

    // ethereum deposit to starkex directly
    if (block.chainid == 1 || block.chainid == 5 || block.chainid == 11155111){
      // safeApprove requires unsetting the allowance first.
      IERC20(USDT_ADDRESS).safeApprove(STARKEX_ADDRESS, 0);
      IERC20(USDT_ADDRESS).safeApprove(STARKEX_ADDRESS, returnAmount);

      // deposit to starkex
      IStarkEx starkEx = IStarkEx(STARKEX_ADDRESS);
      starkEx.depositERC20(starkKey, ASSET_TYPE, positionId, returnAmount);
      return returnAmount;
    }

    return returnAmount;
  }


  /**
    * @param  token          The ERC20 token to convert from
    * @param  amount         The amount in Wei to deposit.
    * @param  starkKey       The starkKey of the L2 account to deposit into.
    * @param  positionId     The positionId of the L2 account to deposit into.
    * @param  owner          The address of permit owner
    * @param  deadline       The deadline time for permit
    * @param  v              The v value for permit
    * @param  r              The r value for permit
    * @param  s              The s value for permit
    * @param  mpcSignature   The signature verify mpc user
    */


  function depositWithPermit(
    address token,
    uint256 amount,
    uint256 starkKey,
    uint256 positionId,
    address owner,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s,
    bytes memory mpcSignature
  ) public nonReentrant returns (uint256) {
    require(address(token) == USDT_ADDRESS, "not support token");

    // check MPC signature
    require(ECDSA.recover(ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(amount, starkKey, positionId, block.chainid))), mpcSignature)  == owner,"invalid mpc signature");

    // permit call
    IERC20Permit(USDT_ADDRESS).permit(owner,address(this),amount,deadline,v,r,s);

    // transfer USDT 
    IERC20(USDT_ADDRESS).safeTransferFrom(owner, address(this), amount);

    emit Deposit(
      owner,
      USDT_ADDRESS,
      amount,
      amount,
      starkKey,
      positionId
    );

    // ethereum deposit to starkex directly
    if (block.chainid == 1 || block.chainid == 5 || block.chainid == 11155111){
      // safeApprove requires unsetting the allowance first.
      IERC20(USDT_ADDRESS).safeApprove(STARKEX_ADDRESS, 0);
      IERC20(USDT_ADDRESS).safeApprove(STARKEX_ADDRESS, amount);

      // deposit to starkex
      IStarkEx(STARKEX_ADDRESS).depositERC20(starkKey, ASSET_TYPE, positionId, amount);
      return amount;
    }
    return amount;
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

    bytes32 operationHash = keccak256(abi.encodePacked("ETHER", to, amount, expireTime, orderId, address(this), block.chainid));
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

    bytes32 operationHash = keccak256(abi.encodePacked("ERC20", to, amount, token, expireTime, orderId, address(this), block.chainid));
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
   * Withdraw ERC20 from this wallet using 2 signers.
   *
   * @param  to         the destination address to send an outgoing transactioni
   * @param  amount     the amount in Wei to be sent
   * @param  token      the address of the erc20 token contract
   * @param  expireTime the number of seconds since 1970 for which this transaction is valid
   * @param  orderId    the unique order id 
   * @param  allSigners all signer who sign the tx
   * @param  signatures the signatures of tx
   * @param  fromUser   the from address who apply a withdraw
   * @param  fromUserSignature the signature of fromUser
   * @param  userSignTime the timestamp foo mpc sign
   */
  function withdrawErc20ForMPC(
    address to,
    uint256 amount,
    address token,
    uint256 expireTime,
    uint256 orderId,
    address[] memory allSigners,
    bytes[] memory signatures,
    address fromUser,
    bytes memory fromUserSignature,
    uint256 userSignTime
  ) public nonReentrant {
    require(allSigners.length >=2, "invalid allSigners length");
    require(allSigners.length == signatures.length, "invalid signatures length");
    require(allSigners[0] != allSigners[1],"can not be same signer"); // must be different signer
    require(expireTime >= block.timestamp,"expired transaction");

    // check MPC user signature
    bytes32 userOperationHash = keccak256(abi.encodePacked(to, amount, token, userSignTime, block.chainid));
    userOperationHash = ECDSA.toEthSignedMessageHash(userOperationHash);
    require(ECDSA.recover(userOperationHash, fromUserSignature)  == fromUser,"invalid from user signature");

    // check withdraw signature
    bytes32 operationHash = keccak256(abi.encodePacked("ERC20", to, amount, token, expireTime, orderId, address(this), block.chainid,fromUser));
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
    emit WithdrawERC20ForMPC(orderId,fromUser, token, to, amount);
  }

  /**
   * Withdraw ERC20 from this wallet using 2 signers.
   * The function only can be called when user make a fast withdraw.
   *
   * @param  to         the destination address to send an outgoing transaction
   * @param  amount     the amount in wei to be sent
   * @param  token      the address of the erc20 token contract
   * @param  salt       salt amount to generate fact
   * @param  expireTime the number of seconds since 1970 for which this transaction is valid
   * @param  orderId    the unique order id 
   * @param  allSigners all signer who sign the tx
   * @param  signatures the signatures of tx
   */
  function factTransferErc20(
    address to,
    address token,
    uint256 amount,
    uint256 salt,
    uint256 expireTime,
    uint256 orderId,
    address[] memory allSigners,
    bytes[] memory signatures
  ) public nonReentrant {
    require(token == USDT_ADDRESS,"invalid token");
    require(allSigners.length >=2, "invalid allSigners length");
    require(allSigners.length == signatures.length, "invalid signatures length");
    require(allSigners[0] != allSigners[1],"can not be same signer"); // must be different signer
    require(expireTime >= block.timestamp,"expired transaction");

    bytes32 operationHash = keccak256(abi.encodePacked("FAST",to, amount, token, expireTime, salt, orderId, address(this), block.chainid));
    operationHash = ECDSA.toEthSignedMessageHash(operationHash);

    for (uint8 index = 0; index < allSigners.length; index++) {
      address signer = ECDSA.recover(operationHash, signatures[index]);
      require(signer == allSigners[index], "invalid signer");
      require(isAllowedSigner(signer),"not allowed signer");
    }

    // Try to insert the order ID. Will revert if the order id was invalid
    tryInsertOrderId(orderId, to, amount, token);

    // check fact 
    bytes32 transferFact =  keccak256(abi.encodePacked(to, amount, token, salt));
    IFactRegister factAddress = IFactRegister(FACT_ADDRESS);
    require(!factAddress.isValid(transferFact),"fact already isValid");

    // safeApprove requires unsetting the allowance first.
    IERC20(token).safeApprove(FACT_ADDRESS, 0);
    IERC20(token).safeApprove(FACT_ADDRESS, amount);
  
    factAddress.transferERC20(to, token, amount, salt);
    emit WithdrawERC20(orderId, token, to, amount);
  }

  function isNative(IERC20 token_) internal pure returns (bool) {
    return (token_ == ZERO_ADDRESS || token_ == ETH_ADDRESS);
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

   /**
   * calcSigHash is a helper function that to help you generate the sighash needed for withdrawal.
   *
   * @param to          The destination address
   * @param amount      The amount in Wei to be sent
   * @param token       The address of the ERC20 contract
   * @param expireTime  the number of seconds since 1970 for which this transaction is valid
   * @param orderId     The unique order id 
   * @param isFact      If fact withdraw calc sighash
   * @param salt        The salt amount to generate fact
   * @param chainId     The chain id
   * 
   */

  function calcSigHash(
    address to,
    uint256 amount,
    address token,
    uint256 expireTime,
    uint256 orderId,
    bool isFact,
    uint256 salt,
    uint256 chainId) public view returns (bytes32) {
    bytes32 operationHash;

    if (isFact) {
      operationHash = keccak256(abi.encodePacked("FAST", to, amount, token, expireTime, salt, orderId, address(this), chainId));
    } else if (token == address(0)) {
      operationHash = keccak256(abi.encodePacked("ETHER", to, amount, expireTime, orderId, address(this), chainId));
    } else {
      operationHash = keccak256(abi.encodePacked("ERC20", to, amount, token, expireTime, orderId, address(this), chainId));
    }
    return operationHash;
  }
}