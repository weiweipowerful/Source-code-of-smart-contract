// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ERC20, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title GEMS token contract
/// @notice An ERC20 token
contract GEMS is Ownable2Step, ERC20Burnable, ERC20Permit {
    /// @member lastMinted The timestamp when last time tokens were minted
    /// @member nextMintTime The next mint time for the tokens
    /// @member amountToMint The token amount that will be minted in next year
    struct EmissionDetails {
        uint256 lastMinted;
        uint256 nextMintTime;
        uint256 amountToMint;
    }

    /// @notice The one year time in seconds
    uint256 private constant ONE_YEAR_TIME = 365 days;

    /// @notice The constant value helps in calculating upcoming year mint amount
    uint256 private constant EMISSION_RATE_PPH = 5;

    /// @notice The constant value helps in calculating upcoming year mint amount
    uint256 private constant PPH = 100;

    /// @notice The address of vesting wallet
    address public vestingWallet;

    /// @notice Stores the token amount, previous mint time and next mint time info
    EmissionDetails public emissionDetails;

    /// @dev Emitted when address of vesting wallet is updated
    event VestingWalletUpdated(address oldAddress, address newAddress);

    /// @notice Thrown when updating an address with zero address
    error ZeroAddress();

    /// @notice Thrown when updating with the same value as previously stored
    error IdenticalValue();

    /// @notice Thrown when function is called before one year time
    error NotAllowed();

    /// @dev Constructor
    /// @param initialHolder The address of account in which tokens will be minted to
    /// @param vestingWalletAddress The address of vesting wallet
    constructor(
        address initialHolder,
        address vestingWalletAddress
    ) Ownable(vestingWalletAddress) ERC20("GEMS", "GEMS") ERC20Permit("GEMS") {
        if (vestingWalletAddress == address(0) || initialHolder == address(0)) {
            revert ZeroAddress();
        }

        _mint(initialHolder, 843_303_980 * 10 ** decimals());
        vestingWallet = vestingWalletAddress;
        emissionDetails = EmissionDetails({
            lastMinted: block.timestamp,
            nextMintTime: block.timestamp + ONE_YEAR_TIME,
            amountToMint: (totalSupply() * EMISSION_RATE_PPH) / PPH
        });
    }

    /// @notice Mints token to vesting wallet after every year
    function tokenEmission() external {
        EmissionDetails memory details = emissionDetails;

        if (block.timestamp < details.nextMintTime) {
            revert NotAllowed();
        }

        _mint(vestingWallet, details.amountToMint);

        emissionDetails = EmissionDetails({
            lastMinted: details.nextMintTime,
            nextMintTime: details.nextMintTime + ONE_YEAR_TIME,
            amountToMint: (totalSupply() * EMISSION_RATE_PPH) / PPH
        });
    }

    /// @notice Changes vesting wallet to a new address only callable by owner
    /// @param newVestingWallet The address of the new vesting wallet
    function changeVestingWallet(address newVestingWallet) external onlyOwner {
        if (newVestingWallet == address(0)) {
            revert ZeroAddress();
        }

        address oldWallet = vestingWallet;

        if (oldWallet == newVestingWallet) {
            revert IdenticalValue();
        }

        emit VestingWalletUpdated({ oldAddress: oldWallet, newAddress: newVestingWallet });

        vestingWallet = newVestingWallet;
    }
}