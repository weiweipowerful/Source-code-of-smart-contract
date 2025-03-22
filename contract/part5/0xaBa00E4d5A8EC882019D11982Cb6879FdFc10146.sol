/**
 *Submitted for verification at Etherscan.io on 2025-03-18
*/

// SPDX-License-Identifier: MIT
pragma solidity = 0.8.28;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256) ;

    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function decreaseAllowance(address spender,uint256 subtractedValue) external returns (bool);
    function increaseAllowance(address spender,uint256 addedValue) external returns (bool);

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract ForwardingContract {

    IERC20 public usdt;
    IERC20 public usdc;
    address payable owner;
 
    constructor (
        address _usdtAddress,
        address _usdcAddress,
        address _owner
    ){
        usdt = IERC20(_usdtAddress);
        usdc = IERC20(_usdcAddress);
        owner = payable(_owner);
    }

    receive() external payable { payable(msg.sender).transfer(msg.value); }

    event TranasctionConfirmed(
        address indexed from,
        uint256 amount,
        string txid,
        string typeOfPayment
    );

    function purchaseWithETH(uint256 _amount, string memory _txid) public  payable {
        require(_amount == msg.value, "Funds are less/greater then desired amount");
        owner.transfer(msg.value);
        emit TranasctionConfirmed(msg.sender, _amount, _txid, "ETH");
    }

    function purchaseWithUSDT(uint256 _amount, string memory _txid) external {
        require(usdt.allowance(msg.sender, address(this)) <= _amount,"Insufficient allowance");
        require(usdt.transferFrom(msg.sender, address(owner), _amount), "Transafer USDT got Failed");
        emit TranasctionConfirmed(msg.sender, _amount, _txid, "USDT");
    }
    
    function purchaseWithUSDC(uint256 _amount, string memory _txid) external {
        require(usdc.allowance(msg.sender, address(this)) <= _amount,"Insufficient allowance");
        require(usdc.transferFrom(msg.sender, address(owner), _amount), "Transafer USDC got Failed");
        emit TranasctionConfirmed(msg.sender, _amount, _txid, "USDC");
    }
}