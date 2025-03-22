// * ————————————————————————————————————————————————————————————————————————————————— *
// |                                                                                   |
// |    SSSSS K    K EEEEEE L      EEEEEE PPPPP  H    H U    U N     N K    K  SSSSS   |
// |   S      K   K  E      L      E      P    P H    H U    U N N   N K   K  S        |
// |    SSSS  KKKK   EEE    L      EEE    PPPPP  HHHHHH U    U N  N  N KKKK    SSSS    |
// |        S K   K  E      L      E      P      H    H U    U N   N N K   K       S   |
// |   SSSSS  K    K EEEEEE LLLLLL EEEEEE P      H    H  UUUU  N     N K    K SSSSS    |
// |                                                                                   |
// | * AN ETHEREUM-BASED INDENTITY PLATFORM BROUGHT TO YOU BY NEUROMANTIC INDUSTRIES * |
// |                                                                                   |
// |                             @@@@@@@@@@@@@@@@@@@@@@@@                              |
// |                             @@@@@@@@@@@@@@@@@@@@@@@@                              |
// |                          @@@,,,,,,,,,,,,,,,,,,,,,,,,@@@                           |
// |                       @@@,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,@@@                        |
// |                       @@@,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,@@@                        |
// |                       @@@,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,@@@                        |
// |                       @@@,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,@@@                        |
// |                       @@@@@@@@@@,,,,,,,,,,@@@@@@,,,,,,,@@@                        |
// |                       @@@@@@@@@@,,,,,,,,,,@@@@@@,,,,,,,@@@                        |
// |                       @@@@@@@@@@,,,,,,,,,,@@@@@@,,,,,,,@@@                        |
// |                       @@@,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,@@@                        |
// |                       @@@,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,@@@                        |
// |                       @@@,,,,,,,@@@@@@,,,,,,,,,,,,,,,,,@@@                        |
// |                       @@@,,,,,,,@@@@@@,,,,,,,,,,,,,,,,,@@@                        |
// |                          @@@,,,,,,,,,,,,,,,,,,,,,,,,@@@                           |
// |                          @@@,,,,,,,,,,,,,,,,,,,,@@@@@@@                           |
// |                             @@@@@@@@@@@@@@@@@@@@@@@@@@@                           |
// |                             @@@@@@@@@@@@@@@@@@@@@@@@@@@                           |
// |                             @@@@,,,,,,,,,,,,,,,,@@@@,,,@@@                        |
// |                                 @@@@@@@@@@@@@@@@,,,,@@@                           |
// |                                           @@@,,,,,,,,,,@@@                        |
// |                                           @@@,,,,,,,,,,@@@                        |
// |                                              @@@,,,,@@@                           |
// |                                           @@@,,,,,,,,,,@@@                        |
// |                                                                                   |
// |                                                                                   |
// |   for more information visit skelephunks.com  |  follow @skelephunks on twitter   |
// |                                                                                   |
// * ————————————————————————————————————————————————————————————————————————————————— *
   
   
////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                           |                                                        //
//  The SkeleDrop Contract                   |  SkeleDrop is a way to manually airdrop crypt mints    //
//  By Autopsyop,for Neuromantic Industries  |  The tokens will be randomly selected from whats left  //
//  Part of the Skelephunks Platform         |  Only the owner of this contract can airdrop tokens    //
//                                           |                                                        //  
//////////////////////////////////////////////////////////////////////////////////////////////////////// 
// CHANGELOG
// V2: Fixes an issue where remaining claims for a wallet could be calculated incorrectly 
// V3: Fixes an issue where disableAllLists breaks everything, removes multiple lists concept


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol"; 
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./MerkleProof.sol";
import {SkelephunksController} from "SkelephunksController.sol";

contract SkeleDropV3 is Ownable, SkelephunksController {   
    constructor () {
        //ENSURE SKELEPHUNKSCONTROLLER.SOL IS SET UP FOR THE RIGHT ENVIRONMENT
        transferOwnership(skelephunks.owner());
    }
    bytes32 listRoot;
    uint16 public maxDrops = 666;//limit to the number of drops that can be served from this contract
    uint16 public totalDrops;//number of drops allocated
    uint16 public totalClaims;//number of drops that have been claimed (from any source)
    uint16 listRemaining;
    uint16 listMaxPer;
    bool claimsPaused;
    mapping( address=>uint16) walletDrops;    
    mapping( address=>uint16 ) claims;
    mapping( address=>mapping( bytes32=>uint16 ) ) claimedFromList;
    mapping( address=>uint16 ) totalListClaims;

    /** 
        Math
    **/
    function max(
        uint16 a,
        uint16 b
    ) private pure returns (uint16){
        if(a > b)return a;
        return b;
    }
    function min(
        uint16 a,
        uint16 b
    ) private pure returns (uint16){
        if(a < b)return a;
        return b;
    }
// SUPPLY INFO
    function remainingDropSupply(
    ) public view returns (uint16) {
        if (!cryptHasMints() ){
            return 0;
        }
        return maxDrops - totalDrops;
    }
    modifier needsDropSupply{
        require(0 < remainingDropSupply());
        _;
    }
// SUPPLY COMMANDS
  function setMaxDropSupply( 
            uint16 maximum 
    ) public onlyOwner {
        require(totalDrops <= maximum , "Already dropped more than that" );
        require(maximum - totalDrops < maxCryptMints() , "Not enough mints in crypt" );//new max cant be supported by crypt
        maxDrops = maximum;
    }

// CRYPT INFO
    /**
        SkeleDrop requires the Crypt to have supply
    **/
    function maxCryptMints(
    ) private view returns (uint){
        return  skelephunks.maxReserveSupply() - skelephunks.numMintedReserve() - 666;//after mint-out there must be SOME tokens left in crypt.
    }
    function cryptHasMints(
    ) private view returns (bool){
        return 0 < maxCryptMints() ;
    }   
// UNCLAIMED DROPS INFO
    
    function unclaimedDrops(
    ) public view returns (uint16){
        return totalDrops - totalClaims;
    }
    function unclaimedListDrops(
    ) public view returns (uint16){
        return listRemaining;
    }

// DROP INFO FOR WALLET
    function walletDropsForWallet(
        address wallet
    ) public view returns (uint16){
        return walletDrops[wallet];
    }    
    function isMember(
        address wallet, 
        bytes32 root,
        bytes32[] calldata proof
    )private pure returns (bool){
        return MerkleProof.verifyCalldata(proof,root,keccak256(abi.encodePacked(wallet)));
    }
    function listDropsForWallet(
        address wallet, 
        bytes32[] calldata proof
    ) private view returns (uint16){
        uint16 count;
        if(listRemaining > 0 && isMember(wallet,listRoot,proof)){
            count=remainingListDropsForWallet(wallet);
        }
        return count;
    }
    function remainingListDropsForWallet(
        address wallet
    )private view returns(uint16){
        return min(listMaxPer - claimedFromList[wallet][listRoot],listRemaining);
    }

    function totalDropsForWallet(
        address wallet,
        bytes32[] calldata proof
    )public view returns (uint16){
        return totalListClaimsForWallet(wallet) + listDropsForWallet(wallet,proof) + walletDropsForWallet(wallet);
    }    
    function unclaimedDropsForWallet(
        address wallet,
        bytes32[] calldata proof
    )public view returns (uint16){
        return totalDropsForWallet(wallet,proof) - totalClaimsForWallet(wallet);
    }
    function claimableDropsForWallet(
        address wallet,
        bytes32[] calldata proof
    ) public view returns (uint16){
        return claimsPaused ? 0 : unclaimedDropsForWallet(wallet,proof);
    }

// CLAIMS INFO FOR WALLET
    function totalClaimsForWallet(
        address wallet
    ) public view returns (uint16){
        return claims[wallet];
    }
    function walletClaimsForWallet(
        address wallet
    ) public view returns (uint){
        return totalClaimsForWallet(wallet) - totalListClaimsForWallet(wallet);
    }

    function totalListClaimsForWallet(address wallet) private view returns (uint16){
        return totalListClaims[wallet];
    }
    function currentListClaimsForWallet(
        address wallet
    ) private view returns (uint16){
        return claimedFromList[wallet][listRoot];
    }
    function priorListClaimsForWallet(
        address wallet
    )public view returns (uint16){
        return totalListClaimsForWallet(wallet) - currentListClaimsForWallet(wallet);
    }


// CONTROLS
    /**
        drops can be capped instantly using maxDrops to prevent future allocations 
    **/
    function capDropSupply(
    ) public onlyOwner {
        setMaxDropSupply(totalDrops);
    }
    /**
       claims can be paused
    **/  
    function pauseClaims() public onlyOwner{ require(!claimsPaused,"claims already paused");claimsPaused = true;}
    function unpauseClaims() public onlyOwner{ require(claimsPaused,"claims not paused");claimsPaused = false;}
    modifier pauseable { require (!claimsPaused,"claimes are paused");_;}

// LIST COMMANDS

    /**
       skeledrop enables an operator to allocate create a list with access to an allocation of mints
    **/  
    function setList(
        bytes32 root,
        uint16 amount,
        uint16 maxPer
    )public onlyOwner{
        require(amount <= remainingDropSupply(),"cannot supply this many drops, please lower the amount");
        if(listRemaining > 0){
            disableList();
        }
        totalDrops+=amount;
        listRoot = root;
        listRemaining = amount;
        listMaxPer = maxPer;
    }

    function quickSetList(
        bytes32 root,
        uint16 amount
    )public onlyOwner{
        setList(root,amount,1);
    }

    function disableList(
    )public onlyOwner{
        totalDrops -= listRemaining;
        listRemaining= 0;
    }

// DROP COMMANDS
    function bulkDrop(
        address[] calldata tos,
        uint16 amount
    ) public onlyOwner needsDropSupply {
        require(remainingDropSupply() >= tos.length ,"not enuff walletDrops for all that");
        for( uint16 i = 0; i < tos.length; i++){
            drop(tos[i],amount);
        }
    }
    function quickDrop(
        address to
    ) public onlyOwner needsDropSupply {
        drop(to,1);
    }
    function drop(
        address to,
        uint16 amount
    ) public onlyOwner needsDropSupply {
        require(to != owner(), "WTF scammer");
        walletDrops[to]+=amount;
        totalDrops+=amount;
    }

// CLAIM COMMANDS
    function mintFromCrypt(
        address to, 
        uint16 num, 
        uint16 gad
    ) private requiresSkelephunks {
        skelephunks.mintReserve(to, num, gad);
    }

    function claimMyDrops (
        uint16 gad
    ) public requiresSkelephunks pauseable {
        require(gad >= 0 && gad < 4, "invalid gender and direction");
        uint16 numDrops = walletDrops[msg.sender];
        uint16 numClaims = claims[msg.sender];
        uint16 dropsLeft = numDrops-numClaims ;// walletDrops left for wallet
        uint16 claimsRequested = dropsLeft;
        mintFromCrypt(msg.sender,claimsRequested,gad);// do the mint
        claims[msg.sender] += claimsRequested;//register the claims for wallet
        totalClaims += claimsRequested;//register claims to total
    }

    function claim (
        uint16 quantity,
        uint16 gad,
        bytes32[] calldata proof
    ) public requiresSkelephunks pauseable {
        require(gad >= 0 && gad < 4, "invalid gender and direction");
        uint16 unclaimed = unclaimedDropsForWallet(msg.sender,proof);// all drops left for wallet
        require(quantity <= unclaimed, "not enough drops for this wallet to claim this quantity");
        uint16 requested = quantity == 0 ? unclaimed : quantity; //amount claiming - 0  = claim all
        uint16 requests = requested;

        // claim from list first, then walletDrops 
            if( listRemaining > 0 && requests > 0 && claimedFromList[msg.sender][listRoot] < listMaxPer ){//claims remain, was list i max claimed by wallet?
                uint16 listRemains = remainingListDropsForWallet(msg.sender);//dont claim more than max ever
                uint16 listClaims = min(requests,listRemains);//we will claim no more than we're requesting from what remains
                listRemaining-=listClaims;//list remains minus claiming amount
                claimedFromList[msg.sender][listRoot] += listClaims;// account for wallet claims from list
                totalListClaims[msg.sender]+=listClaims;//add to wallet lifetime list total
                require(claimedFromList[msg.sender][listRoot]<=listMaxPer,"attempted to claim more than maxPer from list");//this shouln't be possible
                requests-=listClaims;// requests less claiming amount
            }
        claims[msg.sender] += requested;//register the claims for wallet
        totalClaims += requested;//register claims to total
        mintFromCrypt(msg.sender,requested,gad);// do the mint
    }
}