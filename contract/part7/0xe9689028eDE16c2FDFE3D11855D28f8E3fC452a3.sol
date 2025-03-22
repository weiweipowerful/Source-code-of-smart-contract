// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';

contract Bubble is ERC20Permit, Ownable {
    uint256 private constant TOTAL_SUPPLY = 10_000_000_000 * 10 ** 18;

    mapping(address => bool) public allowedPermitSpenders;

    error SpenderUnauthorized();
    error SpenderStatusUnchanged();

    event AllowedPermitSpendersUpdated(address spender, bool isPermitted);

    /// @notice Mint the total supply to multi-sig treasury for disbursement
    constructor(
        string memory _name,
        string memory _symbol,
        address _treasury
    ) ERC20(_name, _symbol) ERC20Permit(_name) Ownable(msg.sender) {
        _mint(_treasury, TOTAL_SUPPLY);
    }

    /// @dev Provide ERC20Permit benefits to whitelsited addresses (spender) to prevent signature phishing on unauthorized addresses
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public virtual override(ERC20Permit) {
        if (!allowedPermitSpenders[_spender]) revert SpenderUnauthorized();
        super.permit(_owner, _spender, _value, _deadline, _v, _r, _s);
    }

    /// @dev Update permitted spender address
    /// @param _spender Spender address
    /// @param _isPermitted Flag to identify if spender address is permitted
    function updateAllowedPermitSpender(
        address _spender,
        bool _isPermitted
    ) external onlyOwner {
        if (_isPermitted == allowedPermitSpenders[_spender])
            revert SpenderStatusUnchanged();

        allowedPermitSpenders[_spender] = _isPermitted;

        emit AllowedPermitSpendersUpdated(_spender, _isPermitted);
    }
}