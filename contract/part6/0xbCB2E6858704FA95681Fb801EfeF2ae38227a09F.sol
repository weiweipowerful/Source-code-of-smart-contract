//
// https://cryptopunks.eth.limo/
//
pragma solidity ^0.8.20;

import "./interfaces/INotLarvaLabsMarketplace.sol";
import "./interfaces/IPhunkToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";



contract NotLarvaLabsBulkLister is Ownable, ReentrancyGuard {
    
    address constant notLarvaLabsContractAddress = 0xd6c037bE7FA60587e174db7A6710f7635d2971e7;
    address constant phunksContractAddress = 0xf07468eAd8cf26c752C676E43C814FEe9c8CF402;
    mapping (address => uint[]) public listedPhunks;
    mapping (uint16 => address) public listedBy;
    uint16[] public allListedPhunks;
    mapping (uint16 => uint) public phunksAmount;
    mapping(address => uint256) public balances;
    
    constructor(address initialOwner) Ownable(initialOwner) {
    }

    receive() external payable {
        IPhunksToken phunksContract = IPhunksToken(phunksContractAddress);
        for (uint i = 0; i < allListedPhunks.length; i++) {
            uint16 phunkId = allListedPhunks[i];
            if (phunksContract.ownerOf(phunkId) != address(this)) {
                balances[listedBy[phunkId]] += msg.value; 
                phunkSelled(phunkId);
            }
        }
    }

    function approveLister() public {
        IPhunksToken(phunksContractAddress).setApprovalForAll(notLarvaLabsContractAddress, true);
    }


    function listPhunks(uint16[] memory phunksIndex, uint[] memory amounts) public nonReentrant {
        require(phunksIndex.length > 0, "No phunks provided");
        require(phunksIndex.length == amounts.length, "Mismatch between phunks and amounts");

        INotLarvaLabsMarketplace notLarvaLabsContract = INotLarvaLabsMarketplace(notLarvaLabsContractAddress);
        IPhunksToken phunksContract = IPhunksToken(phunksContractAddress);
        for (uint i = 0; i < phunksIndex.length; i++) {
            uint16 phunkIndex = phunksIndex[i];
            require(phunksContract.ownerOf(phunkIndex) == msg.sender, "Caller is not the owner");

            phunksContract.transferFrom(msg.sender, address(this), phunkIndex);
            notLarvaLabsContract.offerPhunkForSale(phunkIndex, amounts[i]);

            listedPhunks[msg.sender].push(phunkIndex);
            listedBy[phunkIndex] = msg.sender;
            phunksAmount[phunkIndex] = amounts[i];
        }
    }

    function delistPhunks(uint16[] memory phunksIndex) public nonReentrant {
        require(phunksIndex.length > 0, "No phunks provided");

        IPhunksToken phunksContract = IPhunksToken(phunksContractAddress);
        for (uint i = 0; i < phunksIndex.length; i++) {
            uint16 phunkIndex = phunksIndex[i];
            require(listedBy[phunkIndex] == msg.sender, "Caller not owner of the phunk");

            phunksContract.transferFrom(address(this), msg.sender, phunkIndex);
            delete listedBy[phunkIndex];
            delete phunksAmount[phunkIndex];

            // Remove from listedPhunks array
            removePhunkFromListed(msg.sender, phunkIndex);
        }
    }

    function removePhunkFromListed(address owner, uint phunkIndex) private {
        uint length = listedPhunks[owner].length;
        for (uint i = 0; i < length; i++) {
            if (listedPhunks[owner][i] == phunkIndex) {
                listedPhunks[owner][i] = listedPhunks[owner][length - 1];
                listedPhunks[owner].pop();
                break;
            }
        }
    }

    function withdrawFunds() public {
        uint amount = balances[msg.sender];
        require(amount > 0, "No funds available");

        balances[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Failed to send Ether");
    }    


    function withdrawAllFunds() public onlyOwner {
        uint balance = address(this).balance;
        require(balance > 0, "No funds available");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Failed to send Ether");
    }    

    function withdrawExternal() public nonReentrant() {
        INotLarvaLabsMarketplace notLarvaLabsContract = INotLarvaLabsMarketplace(notLarvaLabsContractAddress);
        notLarvaLabsContract.withdraw();
    }

    function phunkSelled(uint16 phunkIndex) public nonReentrant {
        
        IPhunksToken phunksContract = IPhunksToken(phunksContractAddress);

        address currentOwner = phunksContract.ownerOf(phunkIndex);
        require(currentOwner != msg.sender, "Caller is already the owner");

        // Transfer the sale amount to the current owner
        (bool success, ) = payable(currentOwner).call{value: balances[listedBy[phunkIndex]]}("");
        require(success, "Failed to send Ether");

        // Clear the sale listing
        delete listedBy[phunkIndex];
        delete phunksAmount[phunkIndex];
        removePhunkFromListed(currentOwner, phunkIndex);
    }

}