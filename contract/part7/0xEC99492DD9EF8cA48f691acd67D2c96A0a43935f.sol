// SPDX-License-Identifier: MIT
//
//          .@@@                                                                  
//               ,@@@@@@@&,                  #@@%                                  
//                    @@@@@@@@@@@@@@.          @@@@@@@@@                           
//                        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                      
//                            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                   
//                                @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@.                 
//                                    @@@@@@@    &@@@@@@@@@@@@@@@@@                
//                                        @@@/        &@@@@@@@@@@@@@,              
//                                            @            @@@@@@@@@@@             
//                                                             /@@@@@@@#           
//                                                                  @@@@@          
//                                                                      *@&   
//         RTFKT Studios (https://twitter.com/RTFKT)
//         Animus Contract (made w/ love by @maximonee_ & @cardillosamuel)

/*
    RTFKT Legal Overview [https://rtfkt.com/legaloverview]
    1. RTFKT Platform Terms of Services [Document #1, https://rtfkt.com/tos]
    2. End Use License Terms
    A. Digital Collectible Terms (RTFKT-Owned Content) [Document #2-A, https://rtfkt.com/legal-2A]
    B. Digital Collectible Terms (Third Party Content) [Document #2-B, https://rtfkt.com/legal-2B]
    C. Digital Collectible Limited Commercial Use License Terms (RTFKT-Owned Content) [Document #2-C, https://rtfkt.com/legal-2C]
    D. Digital Collectible Terms [Document #2-D, https://rtfkt.com/legal-2D]
    
    3. Policies or other documentation
    A. RTFKT Privacy Policy [Document #3-A, https://rtfkt.com/privacy]
    B. NFT Issuance and Marketing Policy [Document #3-B, https://rtfkt.com/legal-3B]
    C. Transfer Fees [Document #3C, https://rtfkt.com/legal-3C]
    C. 1. Commercialization Registration [https://rtfkt.typeform.com/to/u671kiRl]
    
    4. General notices
    A. Murakami Short Verbiage – User Experience Notice [Document #X-1, https://rtfkt.com/legal-X1]
*/

pragma solidity ^0.8.17;

import "@limitbreak/creator-token-standards/src/erc721c/ERC721C.sol";
import "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/IEgg.sol";

contract AnimusRevelio is ERC721C, BasicRoyalties, OwnableBasic {
    using Strings for uint256;

    constructor(address eggAddress_, address royaltyRecipient_)
        ERC721OpenZeppelin("Project Animus", "ANIMUS") 
        BasicRoyalties(royaltyRecipient_, 500)
    {
        egg = IEgg(eggAddress_);
    }

    IEgg egg;

    bool public isRevealOpen;
    bool public contractLocked;
    
    string baseURI;

    event EggsRevealed(address holder, uint256[] tokenIds);

    error RevealNotOpen();
    error ContractLocked();
    error NotOwnerOfToken();
    error TokenDoesNotExist();

    function reveal(uint256[] calldata eggIds) public {
        if (!isRevealOpen) revert RevealNotOpen();

        for (uint256 i = 0; i < eggIds.length; ++i) {
            egg.burn(eggIds[i]);
            _mint(msg.sender, eggIds[i]);
        }

        emit EggsRevealed(msg.sender, eggIds);
    }

    //////////////////////////////
    // VIEW FUNCTIONS
    /////////////////////////////

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721C, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    //////////////////////////////
    // ADMIN FUNCTIONS
    /////////////////////////////

    function airdrop(uint256[] calldata tokenIds, address[] calldata wallets) public onlyOwner {
        if (contractLocked) revert ContractLocked();

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            _mint(wallets[i], tokenIds[i]);
        }

        emit EggsRevealed(msg.sender, tokenIds);
    }

    function setEggAddress(address newAddress) public onlyOwner {
        egg = IEgg(newAddress);
    }

    function setBaseUri(string calldata uri) public onlyOwner {
        if (contractLocked) revert ContractLocked();

        baseURI = uri;
    }

    function toggleRevealOpenState() public onlyOwner {
        isRevealOpen = !isRevealOpen;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function withdrawFunds() public onlyOwner {
		payable(msg.sender).transfer(address(this).balance);
	}

    function lockContract() public onlyOwner {
        contractLocked = true;
    }
}