/**
 *Submitted for verification at Etherscan.io on 2018-01-18
*/

pragma solidity ^0.4.18;

// ----------------------------------------------------------------------------
// Owned - Ownership model with 2 phase transfers
// Enuma Blockchain Platform
//
// Copyright (c) 2017 Enuma Technologies.
// https://www.enuma.io/
// ----------------------------------------------------------------------------


// Implements a simple ownership model with 2-phase transfer.
contract Owned {

   address public owner;
   address public proposedOwner;

   event OwnershipTransferInitiated(address indexed _proposedOwner);
   event OwnershipTransferCompleted(address indexed _newOwner);
   event OwnershipTransferCanceled();


   function Owned() public
   {
      owner = msg.sender;
   }


   modifier onlyOwner() {
      require(isOwner(msg.sender) == true);
      _;
   }


   function isOwner(address _address) public view returns (bool) {
      return (_address == owner);
   }


   function initiateOwnershipTransfer(address _proposedOwner) public onlyOwner returns (bool) {
      require(_proposedOwner != address(0));
      require(_proposedOwner != address(this));
      require(_proposedOwner != owner);

      proposedOwner = _proposedOwner;

      OwnershipTransferInitiated(proposedOwner);

      return true;
   }


   function cancelOwnershipTransfer() public onlyOwner returns (bool) {
      if (proposedOwner == address(0)) {
         return true;
      }

      proposedOwner = address(0);

      OwnershipTransferCanceled();

      return true;
   }


   function completeOwnershipTransfer() public returns (bool) {
      require(msg.sender == proposedOwner);

      owner = msg.sender;
      proposedOwner = address(0);

      OwnershipTransferCompleted(owner);

      return true;
   }
}

// ----------------------------------------------------------------------------
// OpsManaged - Implements an Owner and Ops Permission Model
// Enuma Blockchain Platform
//
// Copyright (c) 2017 Enuma Technologies.
// https://www.enuma.io/
// ----------------------------------------------------------------------------



//
// Implements a security model with owner and ops.
//
contract OpsManaged is Owned {

   address public opsAddress;

   event OpsAddressUpdated(address indexed _newAddress);


   function OpsManaged() public
      Owned()
   {
   }


   modifier onlyOwnerOrOps() {
      require(isOwnerOrOps(msg.sender));
      _;
   }


   function isOps(address _address) public view returns (bool) {
      return (opsAddress != address(0) && _address == opsAddress);
   }


   function isOwnerOrOps(address _address) public view returns (bool) {
      return (isOwner(_address) || isOps(_address));
   }


   function setOpsAddress(address _newOpsAddress) public onlyOwner returns (bool) {
      require(_newOpsAddress != owner);
      require(_newOpsAddress != address(this));

      opsAddress = _newOpsAddress;

      OpsAddressUpdated(opsAddress);

      return true;
   }
}

// ----------------------------------------------------------------------------
// Math - General Math Utility Library
// Enuma Blockchain Platform
//
// Copyright (c) 2017 Enuma Technologies.
// https://www.enuma.io/
// ----------------------------------------------------------------------------


library Math {

   function add(uint256 a, uint256 b) internal pure returns (uint256) {
      uint256 r = a + b;

      require(r >= a);

      return r;
   }


   function sub(uint256 a, uint256 b) internal pure returns (uint256) {
      require(a >= b);

      return a - b;
   }


   function mul(uint256 a, uint256 b) internal pure returns (uint256) {
      uint256 r = a * b;

      require(a == 0 || r / a == b);

      return r;
   }


   function div(uint256 a, uint256 b) internal pure returns (uint256) {
      return a / b;
   }
}

// ----------------------------------------------------------------------------
// ERC20Interface - Standard ERC20 Interface Definition
// Enuma Blockchain Platform
//
// Copyright (c) 2017 Enuma Technologies.
// https://www.enuma.io/
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Based on the final ERC20 specification at:
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
// ----------------------------------------------------------------------------
contract ERC20Interface {

   event Transfer(address indexed _from, address indexed _to, uint256 _value);
   event Approval(address indexed _owner, address indexed _spender, uint256 _value);

   function name() public view returns (string);
   function symbol() public view returns (string);
   function decimals() public view returns (uint8);
   function totalSupply() public view returns (uint256);

   function balanceOf(address _owner) public view returns (uint256 balance);
   function allowance(address _owner, address _spender) public view returns (uint256 remaining);

   function transfer(address _to, uint256 _value) public returns (bool success);
   function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);
   function approve(address _spender, uint256 _value) public returns (bool success);
}

// ----------------------------------------------------------------------------
// ERC20Token - Standard ERC20 Implementation
// Enuma Blockchain Platform
//
// Copyright (c) 2017 Enuma Technologies.
// https://www.enuma.io/
// ----------------------------------------------------------------------------


contract ERC20Token is ERC20Interface {

   using Math for uint256;

   string  private tokenName;
   string  private tokenSymbol;
   uint8   private tokenDecimals;
   uint256 internal tokenTotalSupply;

   mapping(address => uint256) internal balances;
   mapping(address => mapping (address => uint256)) allowed;


   function ERC20Token(string _name, string _symbol, uint8 _decimals, uint256 _totalSupply, address _initialTokenHolder) public {
      tokenName = _name;
      tokenSymbol = _symbol;
      tokenDecimals = _decimals;
      tokenTotalSupply = _totalSupply;

      // The initial balance of tokens is assigned to the given token holder address.
      balances[_initialTokenHolder] = _totalSupply;

      // Per EIP20, the constructor should fire a Transfer event if tokens are assigned to an account.
      Transfer(0x0, _initialTokenHolder, _totalSupply);
   }


   function name() public view returns (string) {
      return tokenName;
   }


   function symbol() public view returns (string) {
      return tokenSymbol;
   }


   function decimals() public view returns (uint8) {
      return tokenDecimals;
   }


   function totalSupply() public view returns (uint256) {
      return tokenTotalSupply;
   }


   function balanceOf(address _owner) public view returns (uint256 balance) {
      return balances[_owner];
   }


   function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
      return allowed[_owner][_spender];
   }


   function transfer(address _to, uint256 _value) public returns (bool success) {
      balances[msg.sender] = balances[msg.sender].sub(_value);
      balances[_to] = balances[_to].add(_value);

      Transfer(msg.sender, _to, _value);

      return true;
   }


   function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
      balances[_from] = balances[_from].sub(_value);
      allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
      balances[_to] = balances[_to].add(_value);

      Transfer(_from, _to, _value);

      return true;
   }


   function approve(address _spender, uint256 _value) public returns (bool success) {
      allowed[msg.sender][_spender] = _value;

      Approval(msg.sender, _spender, _value);

      return true;
   }
}

// ----------------------------------------------------------------------------
// Finalizable - Basic implementation of the finalization pattern
// Enuma Blockchain Platform
//
// Copyright (c) 2017 Enuma Technologies.
// https://www.enuma.io/
// ----------------------------------------------------------------------------



contract Finalizable is Owned {

   bool public finalized;

   event Finalized();


   function Finalizable() public
      Owned()
   {
      finalized = false;
   }


   function finalize() public onlyOwner returns (bool) {
      require(!finalized);

      finalized = true;

      Finalized();

      return true;
   }
}

// ----------------------------------------------------------------------------
// FinalizableToken - Extension to ERC20Token with ops and finalization
// Enuma Blockchain Platform
//
// Copyright (c) 2017 Enuma Technologies.
// https://www.enuma.io/
// ----------------------------------------------------------------------------



//
// ERC20 token with the following additions:
//    1. Owner/Ops Ownership
//    2. Finalization
//
contract FinalizableToken is ERC20Token, OpsManaged, Finalizable {

   using Math for uint256;


   // The constructor will assign the initial token supply to the owner (msg.sender).
   function FinalizableToken(string _name, string _symbol, uint8 _decimals, uint256 _totalSupply) public
      ERC20Token(_name, _symbol, _decimals, _totalSupply, msg.sender)
      OpsManaged()
      Finalizable()
   {
   }


   function transfer(address _to, uint256 _value) public returns (bool success) {
      validateTransfer(msg.sender, _to);

      return super.transfer(_to, _value);
   }


   function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
      validateTransfer(msg.sender, _to);

      return super.transferFrom(_from, _to, _value);
   }


   function validateTransfer(address _sender, address _to) private view {
      require(_to != address(0));

      // Once the token is finalized, everybody can transfer tokens.
      if (finalized) {
         return;
      }

      if (isOwner(_to)) {
         return;
      }

      // Before the token is finalized, only owner and ops are allowed to initiate transfers.
      // This allows them to move tokens while the sale is still ongoing for example.
      require(isOwnerOrOps(_sender));
   }
}


// ----------------------------------------------------------------------------
// BluzelleTokenConfig - Token Contract Configuration
//
// Copyright (c) 2017 Bluzelle Networks Pte Ltd.
// http://www.bluzelle.com/
//
// The MIT Licence.
// ----------------------------------------------------------------------------


contract BluzelleTokenConfig {

    string  public constant TOKEN_SYMBOL      = "BLZ";
    string  public constant TOKEN_NAME        = "Bluzelle Token";
    uint8   public constant TOKEN_DECIMALS    = 18;

    uint256 public constant DECIMALSFACTOR    = 10**uint256(TOKEN_DECIMALS);
    uint256 public constant TOKEN_TOTALSUPPLY = 500000000 * DECIMALSFACTOR;
}



// ----------------------------------------------------------------------------
// BluzelleToken - ERC20 Compatible Token
//
// Copyright (c) 2017 Bluzelle Networks Pte Ltd.
// http://www.bluzelle.com/
//
// The MIT Licence.
// ----------------------------------------------------------------------------



// ----------------------------------------------------------------------------
// The Bluzelle token is a standard ERC20 token with the addition of a few
// concepts such as:
//
// 1. Finalization
// Tokens can only be transfered by contributors after the contract has
// been finalized.
//
// 2. Ops Managed Model
// In addition to owner, there is a ops role which is used during the sale,
// by the sale contract, in order to transfer tokens.
// ----------------------------------------------------------------------------
contract BluzelleToken is FinalizableToken, BluzelleTokenConfig {


   event TokensReclaimed(uint256 _amount);


   function BluzelleToken() public
      FinalizableToken(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, TOKEN_TOTALSUPPLY)
   {
   }


   // Allows the owner to reclaim tokens that have been sent to the token address itself.
   function reclaimTokens() public onlyOwner returns (bool) {

      address account = address(this);
      uint256 amount  = balanceOf(account);

      if (amount == 0) {
         return false;
      }

      balances[account] = balances[account].sub(amount);
      balances[owner] = balances[owner].add(amount);

      Transfer(account, owner, amount);

      TokensReclaimed(amount);

      return true;
   }
}