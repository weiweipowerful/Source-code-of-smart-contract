// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AddressUtils.sol";

contract TokenSwap is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using AddressUtils for address;

    IERC20 public immutable incomingToken;
    IERC20 public outgoingToken;
    address public immutable burnAddress;

    /**
     * @dev Constructor sets token swap configuration
     * @param _incomingToken The address of the incoming token
     * @param _burnAddress The address where to burn the incoming tokens
     * @param _initialOwner Address of contract owner
     */
    constructor(
        address _incomingToken,
        address _burnAddress,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_initialOwner.isContract(), "Initial owner can't be an EOA");
        incomingToken = IERC20(_incomingToken);
        burnAddress = _burnAddress;
    }

    /**
     * @dev Sets the outgoing token address, only one time allowed
     * @param _outgoingToken The address of the outgoing token
     */
    function setOutgoingToken(address _outgoingToken) public onlyOwner {
        require(address(outgoingToken) == address(0), "Outgoing token already set");
        require(_outgoingToken != address(0), "Invalid token address");
        outgoingToken = IERC20(_outgoingToken);
    }

    /**
     * @dev Swap function
     * @param _amount Incoming tokens to be swapped to outgoing token
     */
    function swap(uint256 _amount) public nonReentrant {
        // burn incoming tokens
        incomingToken.safeTransferFrom(msg.sender, burnAddress, _amount);
        // send new token
        outgoingToken.safeTransfer(msg.sender, _amount);
    }

    /**
     * @dev Withdraw tokens that were sent to the contract by mistake, or unclaimed
     * @param _tokenAddress The ERC20 token address sent to this contract
     * @param _amount The amount to be withdrawn
     */
    function adminTokenWithdraw(address _tokenAddress, uint256 _amount) public onlyOwner nonReentrant {
        IERC20 _token = IERC20(_tokenAddress);
        _token.safeTransfer(owner(), _amount);
    }

}