/**
 *Submitted for verification at Etherscan.io on 2025-03-09
*/

/**
 *Submitted for verification at Etherscan.io on 2025-02-03
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


contract Context {

    function _msgSender() internal view returns (address) {
        return payable(msg.sender);
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() {
        _transferOwnership(_msgSender());
    }
    function owner() public view virtual returns (address) {
        return _owner;
    }
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {

        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

        assembly {
            codehash := extcodehash(account)
        }
        return (codehash != accountHash && codehash != 0x0);
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }

    function functionCall(address target, bytes memory data)
        internal
        returns (bytes memory)
    {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return
            functionCallWithValue(
                target,
                data,
                value,
                "Address: low-level call with value failed"
            );
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(
            address(this).balance >= value,
            "Address: insufficient balance for call"
        );
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(
        address target,
        bytes memory data,
        uint256 weiValue,
        string memory errorMessage
    ) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: weiValue}(
            data
        );
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

interface IERC20 {
    function decimals() external view returns (uint256);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner,address spender) external view returns (uint256);

    function approve(address _spender, uint _value) external;

    function transferFrom(address _from, address _to, uint _value) external ;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract ATHTools is Ownable{



    event Pledge(address indexed account,uint value,uint price,uint payToken,uint day);

    using SafeMath for uint256;
    using Address for address;

    mapping(uint => uint) private pledgeMin;

    mapping(uint => uint) private pledgeMax;

    IERC20 private Ath;
    IERC20 private Weth;
    IERC20 private Usdt;

    address private ath_weth_pair;

    address private usdt_weth_pair;

    uint256 private constant ATH_RATIO = 10 ** 18; 

    uint256 private constant PRICE_RATIO = 10 ** 10; 

    uint256 private price;

    address private Master;


    constructor() {
        Ath = IERC20(0xbe0Ed4138121EcFC5c0E56B40517da27E6c5226B);
        Weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        Usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        Master = 0xa0392f91C125B9a8f97dbb9c55a4171D11c18F84;
        ath_weth_pair = 0xd31d41DfFa3589bB0c0183e46a1eed983a5E5978;
        usdt_weth_pair = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
        pledgeMin[7 days] = 100;
        pledgeMax[7 days] = 1000;
        pledgeMin[15 days] = 1000;
        pledgeMax[15 days] = 3000;
        pledgeMin[33 days] = 3000;
        pledgeMax[33 days] = 10000;
        pledgeMin[10000 days] = 10000;
        price = 342900000;
    }

    function getMaster() public view returns(address){
        return Master;
    }

    function setMaster(address _master) public onlyOwner(){
        Master = _master;
    }

    function getPledgeMin(uint _day) public view returns(uint){
        return pledgeMin[_day];
    }

    function setPledgeMin(uint _day,uint amount) public onlyOwner(){
        pledgeMin[_day] = amount;
    }

    function removePledgeMin(uint _day) public onlyOwner(){
        delete pledgeMin[_day];
    }

    function setPledgeMax(uint _day,uint amount) public onlyOwner(){
        pledgeMax[_day] = amount;
    }

    function removePledgeMax(uint _day) public onlyOwner(){
        delete pledgeMax[_day];
    }

    function getPledgeMax(uint _day) public view returns(uint){
        return pledgeMax[_day];
    }

    function getPrice() public view returns(uint){
        return price;
    }

    function updatePrice(uint _price) public onlyOwner(){
        price = _price;
    }

    function pledge(uint _value,uint _day) public {
        uint min = pledgeMin[_day];
        require(min > 0,"Days does not exist");
        require(_value >= min,"Pledged Minimum amount");
        uint max = pledgeMax[_day];
        if(max > 0) {
            require(_value <= max,"Pledged amount has reached");
        }

        uint balance = Ath.balanceOf(msg.sender);
        uint approved = Ath.allowance(msg.sender,address(this));
        uint payToken =  _value * ATH_RATIO * PRICE_RATIO / price;
        require(balance >= payToken,"Balance not enough");
        require(approved >=  payToken,"Insufficient authorized amount");
        require(price > 0,"Price error");

        Ath.transferFrom(msg.sender,Master,payToken);
    
        emit Pledge(msg.sender,_value,price,payToken,_day);
    }
   
}