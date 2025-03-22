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
//         MNLTH X Reveal made w/ love by Maximonee

/**
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
**/

pragma solidity ^0.8.17;

import "@openzeppelin/[email protected]/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/[email protected]/access/Ownable.sol";
import "erc721a/contracts/ERC721A.sol";

abstract contract VRF {
    function getVrfSeed() external virtual returns (uint256);
}

interface MNLTHXContract {
    function burn(address owner, uint256 tokenId, uint256 amount) external;
}

contract MNLTHXRevealed is ERC721A, Ownable {
    uint256 constant MNLTHX_TOKEN_ID = 1;
    
    string ipfsHash;

    mapping (address => bool) public walletMinted;

    mapping (uint256 => uint256) public mintedByTokenType;
    mapping (uint256 => uint256) public tokenIdToType;

    event newForge(uint256 tokenType, address owner);

    bool public mintIsOpen;

    uint256 vrfSeed;
    uint256 vrfRequestId;
    address public vrfAddress;
    address public mnlthxAddress;

    VRF vrfContract;
    MNLTHXContract mnlthx;

    constructor (address mnlthxAddress_, address vrfAddress_) ERC721A("MNLTHXREVEALED", "MNLTHXREVEALED") {
        vrfAddress = vrfAddress_;
        mnlthxAddress = mnlthxAddress_;

        vrfContract = VRF(vrfAddress);
        mnlthx = MNLTHXContract(mnlthxAddress);
    }

    function mintTransfer(address owner) public returns (uint256) {
        require(vrfSeed != 0, "VRF not initialized");
        require(mintIsOpen, "Mint is not active");
        require(msg.sender == mnlthxAddress, "Unauthorized");

        uint256 tokenId = _nextTokenId();
        uint256 tokenType = _getTokenType();

        tokenIdToType[tokenId] = 1; // CD
        tokenIdToType[tokenId+1] = 2; // CS
        tokenIdToType[tokenId+2] = 3; // DB
        tokenIdToType[tokenId+3] = tokenType; // RAND
        mintedByTokenType[tokenType] += 1;

        _mint(owner, 4);

        emit newForge(tokenType, owner);

        return tokenType;
    }

    /////////////////////////////
    // GETTER FUNCTIONS       //
    /////////////////////////////

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        uint256 tokenType = tokenIdToType[tokenId];

        return string(abi.encodePacked(ipfsHash, _toString(tokenType)));
    }

    function _getTokenType() internal returns (uint256) {
        bytes32 seed = keccak256(
            abi.encode(
                block.timestamp,
                block.coinbase,
                vrfSeed
            )
        );

        // Update global seed after recalculation
        vrfSeed = uint256(seed);
        return _roll(vrfSeed);
    }

    function _roll(uint256 seed) private view returns (uint256) {
        uint256 rand = seed % 33333;
        
        uint256 tokenType;

        // Do not force any rarity limits.
        // Let RNJesus take the wheel for 33% odds
        if (rand < 11111) {
            tokenType = 4;
        } else if (rand < 22222) {
            tokenType = 5;
        } else {
            tokenType = 6;
        }

        return tokenType;
    }

    /////////////////////////////
    // CONTRACT MANAGEMENT 
    /////////////////////////////

    function toggleMint() public onlyOwner {
        mintIsOpen = !mintIsOpen;
    }

    function withdrawFunds() public onlyOwner {
		payable(msg.sender).transfer(address(this).balance);
	}

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function setIpfsHash(string calldata newUri) public onlyOwner {
        ipfsHash = newUri;
    }

    function setVrfAddress(address vrfAddress_) public onlyOwner {
        vrfAddress = vrfAddress_;
        vrfContract = VRF(vrfAddress_);
    }

    function setMnlthxAddress(address mnlthxAddress_) public onlyOwner {
        mnlthxAddress = mnlthxAddress_;
        mnlthx = MNLTHXContract(mnlthxAddress_);
    }

    function getVrfSeed() public onlyOwner {
        vrfRequestId = vrfContract.getVrfSeed();
    }

    function setVrfSeed(uint256 seed) public {
        require(msg.sender == vrfAddress, "Unauthorized");
        vrfSeed = seed;
    }
}