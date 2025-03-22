// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
/*
████████╗██╗░░██╗███████╗
╚══██╔══╝██║░░██║██╔════╝
░░░██║░░░███████║█████╗░░
░░░██║░░░██╔══██║██╔══╝░░
░░░██║░░░██║░░██║███████╗
░░░╚═╝░░░╚═╝░░╚═╝╚══════╝

░██████╗░░█████╗░███╗░░░███╗███████╗
██╔════╝░██╔══██╗████╗░████║██╔════╝
██║░░██╗░███████║██╔████╔██║█████╗░░
██║░░╚██╗██╔══██║██║╚██╔╝██║██╔══╝░░
╚██████╔╝██║░░██║██║░╚═╝░██║███████╗
░╚═════╝░╚═╝░░╚═╝╚═╝░░░░░╚═╝╚══════╝

░█████╗░░█████╗░███╗░░░███╗██████╗░░█████╗░███╗░░██╗██╗░░░██╗
██╔══██╗██╔══██╗████╗░████║██╔══██╗██╔══██╗████╗░██║╚██╗░██╔╝
██║░░╚═╝██║░░██║██╔████╔██║██████╔╝███████║██╔██╗██║░╚████╔╝░
██║░░██╗██║░░██║██║╚██╔╝██║██╔═══╝░██╔══██║██║╚████║░░╚██╔╝░░
╚█████╔╝╚█████╔╝██║░╚═╝░██║██║░░░░░██║░░██║██║░╚███║░░░██║░░░
░╚════╝░░╚════╝░╚═╝░░░░░╚═╝╚═╝░░░░░╚═╝░░╚═╝╚═╝░░╚══╝░░░╚═╝░░░
*/

import {OApp, Origin, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {OAppSender} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import {OAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PeriodStakingL1Deposit is OAppSender {
    using SafeERC20 for IERC20;
    IERC20 public immutable baseToken;
    uint32 public immutable dstEid;

    constructor(address _endpoint, address _owner, address _baseToken, uint32 _dstEid) OAppCore(_endpoint, _owner) {
        baseToken = IERC20(_baseToken);
        dstEid = _dstEid;
    }

    function depositTokens(uint256 _amount, bool _isStake, bytes calldata _options) external payable {
        bytes memory _payload = abi.encode(msg.sender, _amount, _isStake);
        baseToken.safeTransferFrom(msg.sender, address(this), _amount);
        _lzSend(
            dstEid,
            _payload,
            _options,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
    }

    function estimateFee(uint256 _amount, bool _isStake, bytes calldata _options)
        public
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        bytes memory payload = abi.encode(msg.sender, _amount, _isStake);
        MessagingFee memory fee = _quote(dstEid, payload, _options, false);
        return (fee.nativeFee, fee.lzTokenFee);
    }
}