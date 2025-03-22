// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _transferOwnership(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "You are not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

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
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
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

contract RunecoinNetworkIdo is Ownable, VerifySignature {
    receive() external payable {}

    event BuyRune(
        address indexed sender,
        address indexed rerecipient,
        uint256 amount,
        uint256 tokenAmount,
        address indexed ref
    );

    address public devAddress = 0x63D8B48a7AfE2E4662994f7ac86B8A9fc2562Bd4;
    uint256 public refRate = 5;

    address public usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    mapping(uint256 => bool) public usedNonce;

    struct Owner {
        uint256 tokenAmount;
        uint256 usdAmount;
        uint256 refTokenAmount;
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

    function buyRune(
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

        usedNonce[_nonce] = true;

        uint256 refBonus = (_amountOut * refRate) / 100;
        
        owners[msg.sender].usdAmount += _usdAmount;
        owners[msg.sender].tokenAmount += _amountOut;

        if (_ref != address(0)) {
            owners[_ref].tokenAmount += refBonus;
            owners[_ref].refTokenAmount += refBonus;
            totalToken += refBonus;
        }

        totalToken += _amountOut;
        totalUsd += _usdAmount;

        safeTransfer(_amount, _payment, msg.sender, devAddress);
        
        emit BuyRune(msg.sender, msg.sender, _usdAmount, _amountOut, _ref);
    }
}