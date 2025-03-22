// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract C2Erc20Bep20 {
    using SafeERC20 for IERC20;

    error E1(); // ZeroToken
    error E2(); // PaymentTooLow
    error E3(); // Overpayment

    event T(  // Transfer
        uint256 indexed l,  // l2LinkedId
        uint256 indexed n,  // nonce
        address r,  // recipient
        uint256 a          // amount
    );

    struct PaymentInfo {
        uint96 p;   // paid
        uint32 n;   // nonce
        uint128 u;  // unused
    }
    
    mapping(bytes32 => PaymentInfo) private s; // storage

    IERC20 public immutable t; // token
    uint256 private constant M = 1; // MIN_PAYMENT

    constructor(IERC20 _t) {
        if(address(_t) == address(0)) revert E1();
        t = _t;
    }
    
    function k(address r, uint256 l) internal pure returns(bytes32 o) {
        assembly {
            mstore(0x00, r)
            mstore(0x20, l)
            o := keccak256(0x00, 0x40)
        }
    }

    function transfer(
        uint256 l,    // l2LinkedId
        uint256 m,    // maxAllowedPayment
        address r,    // recipient
        uint256 a     // amount
    ) external {
        if(a < M) revert E2();

        bytes32 x = k(r, l);
        PaymentInfo storage i = s[x];
        
        unchecked {
            uint256 p = uint256(i.p) + a;
            if(p > m) revert E3();
            
            uint256 n = i.n;
            uint256 newNonce = n + 1;
            
            assembly {
                let slot := sload(i.slot)
                slot := 0
                slot := or(slot, p)
                slot := or(slot, shl(96, newNonce))
                sstore(i.slot, slot)
            }
            
            t.safeTransferFrom(msg.sender, r, a);
            
            emit T(l, n, r, a);
        }
    }

    function paidFor(
        uint256 l,
        address r
    ) external view returns (uint256) {
        PaymentInfo memory i = s[k(r, l)];
        return i.p;
    }

    function getNonce(
        uint256 l,
        address r
    ) external view returns (uint256) {
        return uint256(s[k(r, l)].n);
    }
}