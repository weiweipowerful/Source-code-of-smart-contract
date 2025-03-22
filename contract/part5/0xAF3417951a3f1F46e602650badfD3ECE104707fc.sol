//               @@@@@@@@@@@@@
//           @@@@@@          @@@@@
//        @@@@                   @@@@
//      @@@@                       @@@@          @@@@@@@     @@@@@@@@     @@@@@       @@@@@      @@      @@    @@@@@@@@         @@@
//     @@@@ @@@@@@@@@@@ @@@@@@@@@@@ @@@@         @@    @@    @@          @@   @@@   @@@   @@     @@@    @@@    @@               @ @
//    @@@@  @@       @@ @@       @@  @@@@        @@    @@    @@         @@          @@     @@    @@@@  @@@@    @@              @@ @@
//   @@ @@  @@   @@  @@ @@   @@  @@  @@ @@       @@@@@@@     @@@@@@@    @@         @@@     @@    @@ @@@@ @@    @@@@@@@         @   @@
//  @@  @@  @@   @@  @@ @@   @@  @@  @@  @@      @@     @@   @@         @@          @@     @@    @@  @@  @@    @@             @@@@@@@
// @@@  @@       @@  @@ @@   @@      @@  @@@     @@     @@   @@         @@     @@   @@     @@    @@      @@    @@            @@     @@
// @@   @@@@@@@@@@@ @@@ @@@  @@@@@@@@@@   @@     @@@@@@@@    @@@@@@@@    @@@@@@@     @@@@@@@     @@      @@    @@@@@@@@      @@     @@
// @@                                     @@
// @@   @@@@@@@@@@@ @@@ @@@  @@@@@@@@@@   @@
// @@   @@       @@  @@ @@   @@      @@   @@     @@@@@@@@     @@@     @@@@@@@@@   @@@@@@@      @@@@@@     @@@    @@
// @@@  @@  @@   @@  @@ @@   @@  @@  @@  @@@     @@     @@    @@@@       @@       @@    @@    @@    @@    @@@@   @@
//  @@  @@  @@   @@  @@ @@   @@  @@  @@  @@      @@     @@   @@  @@      @@       @@    @@   @@      @@   @@ @@  @@
//   @@ @@  @@   @@  @@ @@   @@  @@  @@ @@       @@@@@@@@    @@  @@      @@       @@@@@@@    @@      @@   @@  @@ @@
//    @@@@  @@       @@ @@       @@  @@@@        @@         @@@@@@@@     @@       @@  @@     @@      @@   @@   @@@@
//     @@@@ @@@@@@@@@@@ @@@@@@@@@@@ @@@@         @@         @     @@     @@       @@   @@     @@    @@    @@    @@@
//      @@@@                       @@@@          @@        @@      @@    @@       @@    @@      @@@@      @@     @@
//        @@@@                   @@@@
//           @@@@@@          @@@@@
//               @@@@@@@@@@@@@
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { ERC721ABatchTransferable } from "ERC721A/extensions/ERC721ABatchTransferable.sol";
import { ERC721A } from "ERC721A/ERC721A.sol";
import { IERC721A } from "ERC721A/ERC721A.sol";
import { ERC2981 } from "@openzeppelin/contracts/token/common/ERC2981.sol";
import { IERC2981 } from "@openzeppelin/contracts/token/common/ERC2981.sol";

contract PatronNFT is ERC2981, ERC721ABatchTransferable {
    uint256 public constant TOTAL_SUPPLY = 100_000;
    // as per https://github.com/chiru-labs/ERC721A/blob/c5bd8e1b1d845e321f35b69872597f308f455019/contracts/ERC721A.sol#L89
    uint256 public constant MAX_MINT_ERC2309_QUANTITY_LIMIT = 5000;

    string private baseTokenURI;

    constructor(
        string memory name_,
        string memory symbol_,
        address _mintDestination,
        address _royaltyReceiver,
        uint96 _feeNumerator,
        string memory _baseTokenURI
    ) ERC721A(name_, symbol_) {
        _setDefaultRoyalty(_royaltyReceiver, _feeNumerator);
        baseTokenURI = _baseTokenURI;
        for (uint256 i = 0; i < TOTAL_SUPPLY; i += MAX_MINT_ERC2309_QUANTITY_LIMIT) {
            _mintERC2309(_mintDestination, MAX_MINT_ERC2309_QUANTITY_LIMIT);
        }
    }

    /**
     * @notice Returns whether `tokenId` exists.
     * @param tokenId The ID of the token to check.
     * @return bool True if the token exists, false otherwise.
     * @dev Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     * @dev Tokens start existing when they are minted. See {_mint}.
     */
    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    /**
     * @dev Returns the total amount of tokens minted in the contract.
     */
    function totalMinted() public view returns (uint256) {
        return _totalMinted();
    }

    /*///////////////////////////////////////////////////////////////
    //                                 Metadata
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Overriding the baseURI function as per ERC721A instructions.
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     *      token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     *      by default, it can be overridden in child contracts.
     */
    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    /*///////////////////////////////////////////////////////////////
    //                      Mandatory Overrides
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns true if this contract implements the interface defined by `interfaceId`.
     * @param interfaceId The interface identifier, as specified in ERC-165.
     * @return bool True if the contract implements `interfaceId` and false otherwise.
     * @dev See the corresponding [EIP section](https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified) to learn more about how these ids are created.
     * @dev This function call must use less than 30000 gas.
     * @dev Natspec and code copied from ERC721A, with the addition of ERC2981 interface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC2981, ERC721A, IERC721A) returns (bool) {
        // The interface IDs are constants representing the first 4 bytes
        // of the XOR of all function selectors in the interface.
        // See: [ERC165](https://eips.ethereum.org/EIPS/eip-165)
        // (e.g. `bytes4(i.functionA.selector ^ i.functionB.selector ^ ...)`)
        return interfaceId == 0x01ffc9a7 // ERC165 interface ID for ERC165.
            || interfaceId == 0x80ac58cd // ERC165 interface ID for ERC721.
            || interfaceId == 0x5b5e139f // ERC165 interface ID for ERC721Metadata.
            || interfaceId == type(IERC2981).interfaceId; // ERC165 interface ID for ERC2981.
    }
}