// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/Registry.sol";

/**
 * @title Bean Token Contract
 */
contract Bean is Ownable(msg.sender), ERC20, ERC20Burnable {
    
    /// @notice Tracks total rewards given to each address.
    mapping(address => uint256) public totalRewarded;
    /// @notice Indicates whether an address is authorized to perform restricted operations.
    mapping(address => bool) public isRegistered;

    /// @notice Maximum supply of the Bean tokens.
    uint256 public immutable MAX_SUPPLY = 21000000000 ether;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(uint256 _initSupply) ERC20("BloomBeans", "BEAN") {
        _mint(msg.sender, _initSupply);
    }

    // =============================================================
    //                          MAIN FUNCTIONS
    // =============================================================

    /**
     * @notice Mints new tokens to a specified user.
     * @dev Can only be called by registered contracts.
     * @param _user The address receiving the newly minted tokens.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _user, uint256 _amount) public {
        require(isRegistered[msg.sender], "Bean:: Not authorized");
        require(
            totalSupply() + _amount <= MAX_SUPPLY,
            "Bean:: Max supply reached"
        );
        _mint(_user, _amount);
    }

    /**
     * @notice Adds reward amount to the total rewarded for a specific address.
     * @dev Can only be called by registered contracts.
     * @param _amount The reward amount to add.
     * @param _address The recipient's address for tracking rewards.
     */
    function addTotalRewarded(uint256 _amount, address _address) external {
        require(isRegistered[msg.sender], "Bean:: Not authorized");
        totalRewarded[_address] += _amount;
    }

    // =============================================================
    //                            SETTERS
    // =============================================================

    /**
     * @notice Registers a contract as authorized to perform restricted operations.
     * @param _contract The contract address to authorize.
     */
    function setRegisteredContracts(address _contract) external onlyOwner {
        isRegistered[_contract] = true;
    }

    // =============================================================
    //                            GETTER
    // =============================================================

    /**
     * @notice Checks whether the maximum supply of tokens has been reached.
     * @return True if the total supply is equal to or exceeds the maximum supply.
     */
    function isMaxSupplyReached() external view returns (bool) {
        return totalSupply() >= MAX_SUPPLY;
    }
}