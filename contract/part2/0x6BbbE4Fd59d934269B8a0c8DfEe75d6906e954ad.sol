// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IExpiry} from "../../interfaces/IExpiry.sol";
import {IRates} from "../../interfaces/IRates.sol";
import {CustomERC20Permit} from "../../libraries/ERC/CustomERC20Permit.sol";
/**
 * @title Contract for Adding Exchange Rate functionality
 * @author Cork Team
 * @notice Adds Exchange Rate functionality to Assets contracts
 */

abstract contract ExchangeRate is IRates {
    uint256 internal rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    /**
     * @notice returns the current exchange rate
     */
    function exchangeRate() external view override returns (uint256) {
        return rate;
    }
}

/**
 * @title Contract for Adding Expiry functionality to DS
 * @author Cork Team
 * @notice Adds Expiry functionality to Assets contracts
 * @dev Used for adding Expiry functionality to contracts like DS
 */
abstract contract Expiry is IExpiry {
    uint256 internal immutable EXPIRY;
    uint256 internal immutable ISSUED_AT;

    constructor(uint256 _expiry) {
        if (_expiry != 0 && _expiry < block.timestamp) {
            revert Expired();
        }

        EXPIRY = _expiry;
        ISSUED_AT = block.timestamp;
    }

    /**
     * @notice returns if contract is expired or not(if timestamp==0 then contract not having any expiry)
     */
    function isExpired() external view virtual returns (bool) {
        if (EXPIRY == 0) {
            return false;
        }

        return block.timestamp >= EXPIRY;
    }

    /**
     * @notice returns expiry timestamp of contract
     */
    function expiry() external view virtual returns (uint256) {
        return EXPIRY;
    }

    function issuedAt() external view virtual returns (uint256) {
        return ISSUED_AT;
    }
}

/**
 * @title Assets Contract
 * @author Cork Team
 * @notice Contract for implementing assets like DS/CT etc
 */
contract Asset is ERC20Burnable, CustomERC20Permit, Ownable, Expiry, ExchangeRate {
    uint256 internal immutable DS_ID;

    string public pairName;

    constructor(string memory _pairName, address _owner, uint256 _expiry, uint256 _rate, uint256 _dsId)
        ExchangeRate(_rate)
        ERC20(_pairName, _pairName)
        CustomERC20Permit(_pairName)
        Ownable(_owner)
        Expiry(_expiry)
    {
        pairName = _pairName;
        DS_ID = _dsId;
    }

    /**
     * @notice mints `amount` number of tokens to `to` address
     * @param to address of receiver
     * @param amount number of tokens to be minted
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice returns expiry timestamp of contract
     */
    function dsId() external view virtual returns (uint256) {
        return DS_ID;
    }

    function updateRate(uint256 newRate) external override onlyOwner {
        rate = newRate;
    }
}