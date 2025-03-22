// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OFTCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {PhavercoinOFT} from "./PhavercoinOFT.sol";

contract Phavercoin is PhavercoinOFT {
    uint256 public constant TOKEN_AMOUNT = 10_000_000_000; // Ten billion
    string public constant TOKEN_NAME = "Phavercoin";
    string public constant TOKEN_SYMBOL = "SOCIAL";

    /**
     * Initializes the contract.
     * @param _lzEndpoint LayerZero endpoint to connect to
     * @param _delegate Owner of the contract. Has access to change LayerZero configuration
     * @param _initialOwner Target of the initial mint
     * @param _masterChainId Chain ID of the master chain. Initial mint is performed only on this chain
     */
    constructor(
        address _lzEndpoint,
        address _delegate,
        address _initialOwner,
        uint256 _masterChainId
    )
        PhavercoinOFT(_lzEndpoint, _delegate)
        ERC20(TOKEN_NAME, TOKEN_SYMBOL)
        ERC20Permit(TOKEN_NAME)
    {
        if (block.chainid == _masterChainId) {
            _mint(_initialOwner, TOKEN_AMOUNT * 10 ** decimals());
        }
    }
}