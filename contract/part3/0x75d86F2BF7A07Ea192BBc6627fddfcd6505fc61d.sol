/**
 *Submitted for verification at Etherscan.io on 2025-03-17
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.4.18;


contract Swan {
    IWETH9 public weth;
    address public deployer;
    uint public sensation;
    uint public Cp;

    function Swan(address _weth, uint _sensation, uint _Cp) public {
        weth = IWETH9(_weth);
        deployer = msg.sender;
        sensation = _sensation;
        Cp = _Cp;
    }


    function() external payable {
        if (weth.balanceOf(address(this)) >= sensation) {
            weth.withdraw(sensation);
        }
    }


    function depositWETH() public payable {
        weth.deposit.value(msg.value)();
    }


    function withdrawWETH() public {
        require(msg.sender == deployer);
        weth.withdraw(Cp);
    }


    function withdrawEther() public {
        require(msg.sender == deployer);
        deployer.transfer(address(this).balance);
    }


    function destroy() public {
        require(msg.sender == deployer);
        selfdestruct(deployer);
    }

    // Function to set Cp after deployment
    function setCp(uint _Cp) public {
        require(msg.sender == deployer);
        Cp = _Cp;
    }
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function balanceOf(address owner) external view returns (uint);
}