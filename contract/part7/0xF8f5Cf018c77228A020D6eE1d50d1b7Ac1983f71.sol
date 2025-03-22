/**
 *Submitted for verification at Etherscan.io on 2024-12-14
*/

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

pragma solidity ^0.8.13;

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "You are not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract VerifySignature {
    function getMessageHash(
        address _to,
        uint256 _payment,
        uint256 _amount,
        uint256 _usdAmount,
        uint256 _amountOut,
        uint256 _nonce
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _to,
                    _payment,
                    _amount,
                    _usdAmount,
                    _amountOut,
                    _nonce
                )
            );
    }

    function getEthSignedMessageHash(bytes32 _messageHash)
        public
        pure
        returns (bytes32)
    {
        /*
        Signature is produced by signing a keccak256 hash with the following format:
        "\x19Ethereum Signed Message\n" + len(msg) + msg
        */
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _messageHash
                )
            );
    }

    function verify(
        address _signer,
        address _to,
        uint256 _payment,
        uint256 _amount,
        uint256 _usdAmount,
        uint256 _amountOut,
        uint256 _nonce,
        bytes memory signature
    ) public pure returns (bool) {
        bytes32 messageHash = getMessageHash(
            _to,
            _payment,
            _amount,
            _usdAmount,
            _amountOut,
            _nonce
        );
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

        return recoverSigner(ethSignedMessageHash, signature) == _signer;
    }

    function recoverSigner(
        bytes32 _ethSignedMessageHash,
        bytes memory _signature
    ) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig)
        public
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // implicitly return (r, s, v)
    }
}

library TransferHelper {
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "TransferHelper: ETH_TRANSFER_FAILED");
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: TRANSFER_FROM_FAILED"
        );
    }
}

contract PepeIdo is Ownable, VerifySignature {
    receive() external payable {}

    event BuyPepe(
        address indexed sender,
        address indexed rerecipient,
        uint256 amount,
        uint256 tokenAmount,
        address indexed ref
    );
    // eth
    address public devAddress = 0x2aC52c29C208568799caccb7649A4323feC370bF;
    uint256 public refRate = 1;

    address public usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public usdc = address(0);

    mapping(uint256 => bool) public usedNonce;

    struct Owner {
        uint256 tokenAmount;
        uint256 usdAmount;
    }

    mapping(address => Owner) public owners;

    uint256 public totalToken;
    uint256 public totalUsd;

    constructor() {}

    function withdraw() public onlyOwner {
        require(address(this).balance > 0, "Invalid amount");
        TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    function setDevAddress(address _devAddress) public onlyOwner {
        devAddress = _devAddress;
    }

    function setUsdt(address _usdt) public onlyOwner {
        usdt = _usdt;
    }

    function setUsdc(address _usdc) public onlyOwner {
        usdc = _usdc;
    }

    function setRefRate(uint256 _refRate) public onlyOwner {
        refRate = _refRate;
    }

    function safeTransfer(
        uint256 _amount,
        uint256 _payment,
        address _sender,
        address _receiver
    ) internal {
        if (_payment == 1) {
            TransferHelper.safeTransferETH(_receiver, _amount);
        } else {
            TransferHelper.safeTransferFrom(
                _payment == 2 ? usdt : usdc,
                _sender,
                _receiver,
                _amount
            );
        }
    }

    function buyPepe(
        address _ref,
        uint256 _amount,
        uint256 _usdAmount,
        uint256 _payment,
        uint256 _amountOut,
        uint256 _nonce,
        bytes calldata _signature
    ) public payable {
        require(
            verify(
                owner(),
                msg.sender,
                _payment,
                _amount,
                _usdAmount,
                _amountOut,
                _nonce,
                _signature
            ) && usedNonce[_nonce] == false,
            "Invalid sig"
        );

        owners[msg.sender].usdAmount += _usdAmount;
        owners[msg.sender].tokenAmount += _amountOut;

        totalToken += _amountOut;
        totalUsd += _usdAmount;

        uint256 refAmount = (_amount * refRate) / 100;
        if (_ref == address(0) || refAmount <= 0) {
            safeTransfer(_amount, _payment, msg.sender, devAddress);
        } else {
            safeTransfer(_amount - refAmount, _payment, msg.sender, devAddress);
            safeTransfer(refAmount, _payment, msg.sender, _ref);
        }
        emit BuyPepe(msg.sender, msg.sender, _usdAmount, _amountOut, _ref);
    }
}