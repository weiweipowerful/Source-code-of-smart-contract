// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import "./AddressUtils.sol";

contract EpicToken is ERC20, ERC20Burnable, Ownable2Step {
    using SafeERC20 for IERC20;
    using AddressUtils for address;

    address public governor;  // Address of the governor contract
    uint256 public lastMint;  // Epoch in seconds of last mint event
    uint256 public waitPeriod;  // Wait period in between mints, in seconds
    uint256 public constant initialSupply = 30000000;

    event Minted(address indexed to, uint256 amount);
    event GovernorSet(address indexed governor);

    /** @dev Modifier to restrict access to the governor contract. */
    modifier onlyGovernor() {
        require(msg.sender == governor, "Not the governor");
        _;
    }

    /**
     * @dev Constructor initializes the EpicToken contract and distribute tokens
     * @param _name Token full name
     * @param _symbol Token symbol
     * @param _swap The swap smart contract address
     * @param _initialOwner The address of the initial owner - must be a multisig wallet
     * @param _waitPeriod Wait period in between mints, in seconds
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _swap,
        address _initialOwner,
        uint256 _waitPeriod
    ) ERC20(_name, _symbol) Ownable(_initialOwner) {
        require(_initialOwner.isContract(), "Initial owner can't be an EOA");
        waitPeriod = _waitPeriod;
        // Mint to the Swap contract
        _mint(_swap, initialSupply * (10 ** 18));
        lastMint = block.timestamp;
    }

    /** 
     * @dev Mint new tokens (can only be called by the governor contract)
     *      Can only mint every year, and up to 12% of the initial supply
     * @param _to Mint to this address
     * @param _amount Mint this amount (without decimals)
     */ 
    function mint(address _to, uint256 _amount) external onlyGovernor {
        require(block.timestamp > lastMint + waitPeriod, "Must wait period before minting again");
        require(
            _amount <= (initialSupply * 12 / 100) * (10 ** 18),
            "Amount to mint exceeds 12% of the initial supply"
        );
        _mint(_to, _amount);
        emit Minted(_to, _amount); // Emit the Minted event
        lastMint = block.timestamp;
    }

    /** 
     * @dev Set the governor contract address (can only be set by the owner).
     * @param _governor The address of the governor contract.
     */
    function setGovernor(address _governor) external onlyOwner {
        require(_governor != address(0), "Invalid address");
        require(_governor.isContract(), "Governor can't be an EOA");
        governor = _governor;
        emit GovernorSet(_governor);
    }

    /**
     * @dev Withdraw tokens that were sent to the contract by mistake
     * @param _tokenAddress The ERC20 token address sent to this contract
     * @param _amount The amount to be withdrawn
     */
    function adminTokenWithdraw(address _tokenAddress, uint256 _amount) public onlyOwner {
        IERC20 _token = IERC20(_tokenAddress);
        _token.safeTransfer(owner(), _amount);
    }

}