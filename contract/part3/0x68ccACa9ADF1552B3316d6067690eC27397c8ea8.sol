// SPDX-License-Identifier: ISC
pragma solidity 0.8.22;

import "../CryptosOFT.sol";

/// @title Cryptopia Token 
/// @notice Game currency used in Cryptopia
/// @dev Implements the ERC20 and OFT standard
/// @author Frank Bonnet - <[email protected]>
contract CryptosToken is CryptosOFT {

    /// @dev Contract constructor
    /// @param _layerZeroEndpoint Local endpoint address
    /// @param _initialOwner Token owner used as a delegate in LayerZero Endpoint
    constructor(address _layerZeroEndpoint, address _initialOwner ) 
        CryptosOFT("Cryptos", "TOS", _layerZeroEndpoint, _initialOwner) 
    {
        _mint(msg.sender, 10_000_000_000 * 10 ** decimals());
    }
}