pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: GPL-3.0





import "./interfaces/IZkSync.sol";

contract PendingBalanceWithdrawer {
    IZkSync constant zkSync = IZkSync(0xaBEA9132b05A70803a4E85094fD0e1800777fBEF);

    struct RequestWithdrawFT {
        address payable owner;
        address token;
        uint256 gas;
    }

    struct RequestWithdrawNFT {
        uint32 tokenId;
        uint256 gas;
    }

    function withdrawPendingBalances(RequestWithdrawFT[] calldata _FTRequests, RequestWithdrawNFT[] calldata _NFTRequests)
        external
    {
        for (uint256 i = 0; i < _FTRequests.length; ++i) {
            try
                zkSync.withdrawPendingBalance{gas: _FTRequests[i].gas}(
                    _FTRequests[i].owner,
                    _FTRequests[i].token,
                    type(uint128).max
                )
            {} catch {}
        }

        for (uint256 i = 0; i < _NFTRequests.length; ++i) {
            try
                zkSync.withdrawPendingNFTBalance{gas: _NFTRequests[i].gas}(
                    _NFTRequests[i].tokenId
                )
            {} catch {}
        }
    }
}