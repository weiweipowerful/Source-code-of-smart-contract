// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "../interfaces/ICirculatingSupply.sol";
import "../interfaces/ISignedTokenFeeTransfer.sol";

contract ERC20PausableBurnableOwnableToken is
    ERC20,
    ERC20Burnable,
    ERC20Pausable,
    ERC20Permit,
    Ownable,
    ICirculatingSupply,
    ISignedTokenFeeTransfer
{
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    )
        ERC20(name, symbol)
        ERC20Permit(name)
        Ownable(msg.sender)
    {
        if(initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    function destroy() public onlyOwner {
        selfdestruct(payable(owner()));
    }

    /**
     * Returns the circulating supply (total supply minus tokens held by owner)
     */
    function circulatingSupply() public view virtual override returns (uint256) {
        return totalSupply() - balanceOf(owner());
    }
/*
    function snapshot() public onlyOwner {
        _snapshot();
    }
*/
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * Owner can withdraw any ERC20 token received by the contract
     */
    function transferAnyERC20Token(address token, uint256 amount) public onlyOwner returns (bool success) {
        return ERC20(token).transfer(owner(), amount);
    }

    mapping(bytes32 => bool) invalidHashes;

    /**
     * Transfer tokens as the owner on his behalf for signer of signature.
     *
     * @param to address The address which you want to transfer to.
     * @param value uint256 The amount of tokens to be transferred.
     * @param gasPrice uint256 The price in tokens that will be paid per unit of gas.
     * @param nonce uint256 The unique transaction number per user.
     * @param signature bytes The signature of the signer.
     */
    function transferPreSigned(
        address to,
        uint256 value,
        uint256 gasPrice,
        uint256 nonce,
        bytes memory signature
    )
        public
        virtual
        override
        returns (bool)
    {
        uint256 gas = gasleft();

        require(to != address(0));

        bytes32 payloadHash = transferPreSignedPayloadHash(address(this), to, value, gasPrice, nonce);

        // Recover signer address from signature
        address from = payloadHash.toEthSignedMessageHash().recover(signature);
        require(from != address(0), "Invalid signature provided.");

        // Generate transaction hash
        bytes32 txHash = keccak256(abi.encodePacked(from, payloadHash));

        // Make sure this transfer didn't happen yet
        require(!invalidHashes[txHash], "Transaction has already been executed.");

        // Mark hash as used
        invalidHashes[txHash] = true;

        // Initiate token transfer
        _transfer(from, to, value);

        // If a gas price is set, pay the sender of this transaction in tokens
        uint256 fee = 0;
        if (gasPrice > 0) {
            // 21000 base + ~14000 transfer + ~10000 event
            gas = 21000 + 14000 + 10000 + gas - gasleft();
            fee = gasPrice * gas;
            _transfer(from, tx.origin, fee);
        }

        emit HashRedeemed(txHash, from);

        return true;
    }

    /**
     * Calculates the hash for the payload used by transferPreSigned
     *
     * @param token address The address of this token.
     * @param to address The address which you want to transfer to.
     * @param value uint256 The amount of tokens to be transferred.
     * @param gasPrice uint256 The price in tokens that will be paid per unit of gas.
     * @param nonce uint256 The unique transaction number per user.
     */
    function transferPreSignedPayloadHash(
        address token,
        address to,
        uint256 value,
        uint256 gasPrice,
        uint256 nonce
    )
        public
        pure
        virtual
        override
        returns (bytes32)
    {
        /* "452d3c59": transferPreSignedPayloadHash(address,address,uint256,uint256,uint256) */
        return keccak256(abi.encodePacked(bytes4(0x452d3c59), token, to, value, gasPrice, nonce));
    }
/*
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        virtual
        whenNotPaused
        override(ERC20, ERC20Pausable)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        virtual
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }
*/
/*
    function _mint(address to, uint256 amount)
        internal
        virtual
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        virtual
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
*/

    function _update(address from, address to, uint256 value)
        internal
        virtual
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}