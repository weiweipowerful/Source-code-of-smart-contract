// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./IFlashLoanRecipient.sol";
import "./IBalancerVault.sol";
import "hardhat/console.sol";

interface IPunksToken {

    function enterBidForPunk(uint punkIndex) payable external;
    function withdrawBidForPunk(uint punkIndex) external;

}
interface IWETH {
    function deposit() external payable;
    function withdraw(uint amount) external;
    function transfer(address to, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint);
}

contract BalancerFlashLoan is IFlashLoanRecipient {
    using Math for uint256;
    IWETH public weth;
    address public immutable vault;
    address private owner;
    address constant WETH_CONTRACT_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant PUNK_CONTRACT_ADDRESS = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
    
    constructor(address _vault) {
        vault = _vault;
        owner = msg.sender;
        weth = IWETH(WETH_CONTRACT_ADDRESS);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the contract owner can call this function");
        _;
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory data
    ) external override {
        

        (uint[] memory punksIndex, uint[] memory punksAmounts) = abi.decode(data, (uint[], uint[]));

        for (uint256 i = 0; i < tokens.length; ++i) {
            
            IERC20 token = tokens[i];
            uint256 amount = amounts[i];

            weth.withdraw(amount);

            console.log("borrowed amount:", amount);
            uint256 feeAmount = feeAmounts[i];
            console.log("flashloan fee: ", feeAmount);
            
            //add logic
            IPunksToken punk = IPunksToken(PUNK_CONTRACT_ADDRESS);
            
            for (uint j = 0; j < punksIndex.length; j++) {
                uint punkIndex = punksIndex[j];
                punk.enterBidForPunk{value: punksAmounts[j]}(punkIndex);
                punk.withdrawBidForPunk(punkIndex);
            }


            weth.deposit{value:amount}();
            // Return loan
            token.transfer(vault, amount);
        }
    }

    function initiateFlashLoan(uint[] memory punksIndexParameter, uint[] memory amounts) external {
        uint maxAmount = 0;
        for (uint i = 0; i < amounts.length; i++) {
            if (amounts[i] > maxAmount) {
                maxAmount = amounts[i];
            }
        }
        
        bytes memory data = abi.encode(punksIndexParameter, amounts);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH_CONTRACT_ADDRESS);
        uint[] memory loanAmounts = new uint[](1);
        loanAmounts[0] = maxAmount;

        IBalancerVault(vault).flashLoan(
            IFlashLoanRecipient(address(this)),
            tokens,
            loanAmounts,
            data
        );
    }

    function withdrawTokens(IERC20[] memory tokens, uint256[] memory amounts) external onlyOwner {
        require(tokens.length == amounts.length, "Token and amount arrays must have the same length");

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = tokens[i].balanceOf(address(this));
            require(balance >= amounts[i], "Insufficient token balance");

            tokens[i].transfer(msg.sender, amounts[i]);
        }
    }

    function withdrawEther(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient Ether balance");
        payable(msg.sender).transfer(amount);
    }

    function transferTokens(IERC20 token, address to, uint256 amount) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Insufficient token balance");

        token.transfer(to, amount);
    }

    function transferEther(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient Ether balance");
        to.transfer(amount);
    }

    receive() external payable {
        // Esta función permite que el contrato reciba Ether cuando se le envía directamente.
    }
}