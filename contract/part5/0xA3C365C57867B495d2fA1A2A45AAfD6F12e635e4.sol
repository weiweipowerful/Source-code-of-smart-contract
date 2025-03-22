// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

contract C2Evm {
    error E1(); // InvalidRecipient
    error E2(); // PaymentTooLow
    error E3(); // Overpayment
    error E4(); // TransferFailed

    event T(  // Transfer event with shortened name
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
    
    mapping(bytes32 => PaymentInfo) private s; // alreadyPaid with shortened name

    uint256 private constant M = 1; // MIN_PAYMENT

    /// @dev createAlreadyPaidKey optimized
    function k(address r, uint256 l) internal pure returns(bytes32 o) {
        assembly {
            mstore(0x00, r)
            mstore(0x20, l)
            o := keccak256(0x00, 0x40)
        }
    }

    function transfer(
        uint256 l,        // l2LinkedId
        uint256 m,        // maxAllowedPayment
        address payable r // recipient
    ) external payable {
        if (r == address(0) || r == address(this)) revert E1();
        if (msg.value < M) revert E2();

        bytes32 x = k(r, l);
        PaymentInfo storage i = s[x];
        
        unchecked {
            uint256 p = uint256(i.p) + msg.value;
            if (p > m) revert E3();
            
            uint256 n = i.n;
            uint256 newNonce = n + 1;
            
            assembly {
                let slot := sload(i.slot)
                slot := 0
                slot := or(slot, p)
                slot := or(slot, shl(96, newNonce))
                sstore(i.slot, slot)
            }
            
            assembly {
                if iszero(call(gas(), r, callvalue(), 0, 0, 0, 0)) {
                    mstore(0x00, 0xf67db1ed) // E4 selector
                    revert(0x00, 0x04)
                }
            }
            
            emit T(l, n, r, msg.value);
        }
    }

    function paidFor(
        uint256 l,
        address r
    ) external view returns (uint256) {
        return uint256(s[k(r, l)].p);
    }

    function getNonce(
        uint256 l,
        address r
    ) external view returns (uint256) {
        return uint256(s[k(r, l)].n);
    }
}