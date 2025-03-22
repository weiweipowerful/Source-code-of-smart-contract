// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20Permit, ERC20 } from "@openzeppelin/[email protected]/token/ERC20/extensions/ERC20Permit.sol";
import { Base64 } from "@openzeppelin/[email protected]/utils/Base64.sol";
import { Helpers } from "./Helpers.sol";

contract WrapCoin is ERC20Permit {
    // storage
    /// @notice agency NFT contract address who is only allowed to mint;
    address public immutable dotAgencyContract;

    // errors
    error WrapCoinOnlyDotAgencyContractCanMint();

    constructor() ERC20("Wrap Coin", "WRAP") ERC20Permit("Wrap") {
        dotAgencyContract = _msgSender();
    }

    /**
     * @dev Mint new tokens.
     * Requirements:
     * - the caller must be the dotAgency contract.
     * @param account The address of the account to mint to.
     * @param amount The amount to mint.
     */
    function mint(address account, uint256 amount) external {
        uint256 beforetotalSupply = totalSupply();
        if (_msgSender() != dotAgencyContract) revert WrapCoinOnlyDotAgencyContractCanMint();
        _mint(account, amount);
        // reentrancy guard
        assert(totalSupply() == beforetotalSupply + amount);
    }

    function tokenURI() public view returns (string memory) {
        string[5] memory parts;
        parts[0] = "data:image/svg+xml;base64,";
        parts[1] =
            '<svg width="700" height="700" viewBox="0 0 1854 1854" fill="none" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><g transform="translate(1830, 210)"><path id="logoPath" d="M-211.538 274.007C-95.0241 274.007 -66 383.159 -66 508.067C-66 686.06 -106.717 883.641 -196.365 1024.8C-259.981 1124.94 -342.46 1186.12 -433.221 1186.12C-531.36 1186.12 -610.288 1110.67 -699.031 976.115C-746.221 904.648 -794.664 817.496 -849.024 719.203L-908.881 611.044C-1029.15 393.592 -1059.64 344.126 -1119.71 262.368C-1225.08 119.292 -1315.08 65 -1433.54 65C-1574.07 65 -1662.95 127.028 -1718.01 220.567 M-1717.97 220.171C-1762.94 296.393 -1785 396.39 -1785 510.368C-1785 717.53 -1729.25 933.492 -1623.18 1100.27C-1529.07 1248.17 -1393.28 1351.58 -1237.51 1351.58 M-1237.62 1351.83C-1147.41 1351.83 -1057.76 1324.57 -964.149 1246.65C-861.695 1161.41 -752.559 1021.11 -616.348 789.744L-567.487 706.709C-449.581 506.431 -382.554 403.453 -343.299 354.839C-292.837 292.456 -257.479 273.862 -211.542 273.862"/><text text-rendering="optimizeSpeed" font-size="80" fill="url(#paint0)"><textPath font-family="Courier New, monospace" startOffset="-100%" xlink:href="#logoPath">';
        parts[2] = _bytesToHex(address(this).code);
        parts[3] =
            '<animate additive="sum" attributeName="startOffset" from="100%" to="0%" begin="0s" dur="30s" repeatCount="indefinite" /></textPath></text>';
        parts[4] = string(
            abi.encodePacked(
                '<defs><linearGradient id="paint0" x1="-460" y1="707" x2="-1600" y2="637" gradientUnits="userSpaceOnUse"><stop stop-color="',
                Helpers.uintToHex(Helpers.getRandMod("linear_logo_0", totalSupply(), 16_777_200)),
                '"/><stop offset="0.3" stop-color="',
                Helpers.uintToHex(Helpers.getRandMod("linear_logo_1", totalSupply(), 16_777_200)),
                '"/><stop offset="0.5" stop-color="',
                Helpers.uintToHex(Helpers.getRandMod("linear_logo_2", totalSupply(), 16_777_200)),
                '"/><stop offset="0.7" stop-color="',
                Helpers.uintToHex(Helpers.getRandMod("linear_logo_3", totalSupply(), 16_777_200)),
                '"/></linearGradient></defs></g></svg>'
            )
        );
        return
            string(abi.encodePacked(parts[0], Base64.encode(abi.encodePacked(parts[1], parts[2], parts[3], parts[4]))));
    }

    function _bytesToHex(bytes memory buffer) internal pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }
}