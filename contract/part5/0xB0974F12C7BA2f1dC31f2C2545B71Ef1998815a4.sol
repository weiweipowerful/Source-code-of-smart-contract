// SPDX-License-Identifier: MIT
/**
   ____    _    ____  _____ ____       _    ___ 
  | __ )  / \  / ___|| ____|  _ \     / \  |_ _|
  |  _ \ / _ \ \___ \|  _| | | | |   / _ \  | | 
  | |_) / ___ \ ___) | |___| |_| |  / ___ \ | | 
  |____/_/___\_\____/|_____|____/ _/_/   \_\___|
  | __ )|  _ \    / \  |_ _| \ | / ___|         
  |  _ \| |_) |  / _ \  | ||  \| \___ \         
  | |_) |  _ <  / ___ \ | || |\  |___) |        
  |____/|_| \_\/_/   \_\___|_| \_|____/         
*/
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./BrainERC20.sol"; 

interface IBrainCredits {
    function decreaseTotalSupply() external;
    function increaseTotalSupply() external;
}

contract Brains is ERC721, Ownable, IERC721Receiver, ReentrancyGuard {
    using SafeMath for uint256;

    struct MetadataProposal {
        string name;
        string ticker;
        string metadataUrl;
        string imageUrl;
        uint256 votesLocked;
        mapping(address => uint256) voterLocks;
        bool executed;
    }

    struct BrainMetadata {
        string name;
        string ticker;
        string metadataUrl;
        string imageUrl;
    }
    
    address public brainCreditAddress;
    address public pepecoinAddress;

    mapping(uint256 => address) public brainToERC20; 
    mapping(uint256 => BrainMetadata) public brainMetadata;
    mapping(uint256 => string) public brainERC20Names;
    mapping(uint256 => string) public brainERC20Symbols;
    mapping(address => uint256) public contributions;
    mapping(uint256 => mapping(uint256 => MetadataProposal)) public metadataProposals;
    mapping(uint256 => uint256) public proposalCounter;
    mapping(address => uint256) public stakes;
    mapping(uint256 => uint256) public tokenStakeTime;
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => bool) private _blockedTokenIds;

    uint256 public tokenCounter;
    uint256 private constant TOKENS_PER_NFT = 1000 * 10**18; 
    uint256 private constant STAKE_AMOUNT = 100000 * 10**18;
    uint256 private constant STAKE_DURATION = 90 days;
    uint256[] private availableTokenIds;
    uint256 public constant MAX_SUPPLY = 1024;
    uint256 public constant PROPOSAL_THRESHOLD = 250000 * 10**18; // 250,000 tokens

    // Add new state variables
    uint256 public currentBatchId;
    mapping(uint256 => mapping(address => uint256)) public batchContributions; // Contributions per batch per contributor
    mapping(uint256 => uint256) public batchTotalContributions;               // Total contributions per batch
    mapping(uint256 => bool) public batchMinted;                              // Whether the batch has been minted
    mapping(uint256 => address) public batchERC20Address;                     // The ERC20 token address associated with a batch
    mapping(uint256 => uint256) public batchTokenId;                          // The NFT tokenId associated with a batch
    mapping(uint256 => mapping(address => bool)) public tokensClaimed;         

    event BrainMinted(uint256 nftId, address brainFather);
    event BrainTokenActivated(uint256 nftId, address brainTokenAddress);
    event ContributionReceived(address contributor, uint256 amount);
    event BrainMetadataUpdated(uint256 tokenId, string name, string ticker, string metadataUrl, string imageUrl);
    event BrainTransferred(uint256 indexed tokenId, address indexed from, address indexed to, uint256 timestamp);
    event MetadataChangeProposed(uint256 indexed tokenId, uint256 proposalId, string name, string ticker, string metadataUrl, string imageUrl);
    event VoteCast(uint256 indexed tokenId, uint256 proposalId, address voter, uint256 amount);

    // Update the constructor to initialize `currentBatchId`
    constructor() ERC721("BasedAI Brains", "BRAIN") Ownable(msg.sender) {
        tokenCounter = 0;
        currentBatchId = 0; // Start with batch ID 0
    }

    function setBrainCredits(address _brainCreditAddress) public onlyOwner {
        brainCreditAddress = _brainCreditAddress;
    }

    function setPepecoin(address _pepecoinAddress) public onlyOwner {
        pepecoinAddress = _pepecoinAddress;
    }

    function redeemBrain(uint256 amount) public {
        require(brainCreditAddress != address(0), "Specific Brain Credit address not set");
        require(amount >= TOKENS_PER_NFT, "Minimum amount not met");
        require(amount % TOKENS_PER_NFT == 0, "Amount must be in increments of 1000 credits");
        uint256 numNFTs = amount / TOKENS_PER_NFT;
        require(tokenCounter + numNFTs - 1 <= MAX_SUPPLY, "Exceeds maximum supply of Brains");

        IERC20(brainCreditAddress).transferFrom(msg.sender, address(this), amount);

        for (uint256 i = 0; i < numNFTs; i++) {
            uint256 tokenId;
            if (availableTokenIds.length > 0) {
                tokenId = availableTokenIds[availableTokenIds.length - 1];
                availableTokenIds.pop();
            } else {
                unchecked {
                    tokenId = tokenCounter;
                    tokenCounter++;
                }
                
            }
            emit BrainMinted(tokenId, msg.sender);
            _safeMint(msg.sender, tokenId);
        }
    }

    function stakePepecoin(uint256 amount) public {
        require(pepecoinAddress != address(0), "Specific Pepecoin address not set");
        require(amount % STAKE_AMOUNT == 0, "Stake amount must be in increments of 100,000 tokens");
        uint256 numNFTs = amount.div(STAKE_AMOUNT);
        require(tokenCounter + numNFTs - 1 <= MAX_SUPPLY, "Exceeds maximum supply of Brains");

        IERC20(pepecoinAddress).transferFrom(msg.sender, address(this), amount);
        stakes[msg.sender] = stakes[msg.sender].add(amount);

        IBrainCredits(brainCreditAddress).decreaseTotalSupply();

        for (uint256 i = 0; i < numNFTs; i++) {
            uint256 tokenId;
            if (availableTokenIds.length > 0) {
                tokenId = availableTokenIds[availableTokenIds.length - 1];
                availableTokenIds.pop();
            } else {
                unchecked {
                    tokenId = tokenCounter;
                    tokenCounter++;
                    if (tokenCounter == 47) tokenCounter++; // reserved for Based Labs
                }
                
            }
            emit BrainMinted(tokenId, msg.sender);
            _safeMint(msg.sender, tokenId);
            tokenStakeTime[tokenId] = block.timestamp;
        }
    }

    function unstakePepecoin(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "Only Brain owner can unstake");
        require(block.timestamp >= tokenStakeTime[tokenId] + STAKE_DURATION, "Stake period not yet completed");
        require(stakes[msg.sender] >= STAKE_AMOUNT, "Not enough tokens staked");

        stakes[msg.sender] = stakes[msg.sender].sub(STAKE_AMOUNT);
        IERC20(pepecoinAddress).transfer(msg.sender, STAKE_AMOUNT);
        _burn(tokenId);
        availableTokenIds.push(tokenId);

        IBrainCredits(brainCreditAddress).increaseTotalSupply();
    }

    function activateBrain(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "Only Brain owner can link a ERC20");
        require(brainToERC20[tokenId] == address(0), "Brain token has been activated.");
        address erc20Contract = _deployERC20(msg.sender, tokenId); 
        brainToERC20[tokenId] = erc20Contract;
        emit BrainTokenActivated(tokenId, erc20Contract);
    }

    function _deployERC20(address tokenOwner, uint256 tokenId) internal returns (address) {
        string memory name;
        string memory symbol;
    
        // Check if name and symbol are defined in metadata
        if (bytes(brainMetadata[tokenId].name).length > 0 && bytes(brainMetadata[tokenId].ticker).length > 0) {
            name = brainMetadata[tokenId].name;
            symbol = brainMetadata[tokenId].ticker;
        } else {
            name = string(abi.encodePacked("BRAIN TOKEN #", Strings.toString(tokenId)));
            symbol = string(abi.encodePacked("B#", Strings.toString(tokenId)));
        }
    
        uint256 initialSupply = 1000000 * 10**18; 
        BrainERC20 newERC20 = new BrainERC20(name, symbol, initialSupply, tokenOwner);
        brainERC20Names[tokenId] = name;
        brainERC20Symbols[tokenId] = symbol;
        return address(newERC20);
    }

    function contributeBrainCredits(uint256 amount) public {
        require(brainCreditAddress != address(0), "Brain Credit address not set");
        require(amount > 0, "Amount must be greater than zero");
        IERC20(brainCreditAddress).transferFrom(msg.sender, address(this), amount);

        uint256 remainingAmount = amount;

        while (remainingAmount > 0) {
            uint256 availableContribution = TOKENS_PER_NFT.sub(batchTotalContributions[currentBatchId]);

            uint256 contributionAmount = remainingAmount;
            if (contributionAmount > availableContribution) {
                contributionAmount = availableContribution;
            }

            batchContributions[currentBatchId][msg.sender] = batchContributions[currentBatchId][msg.sender].add(contributionAmount);
            batchTotalContributions[currentBatchId] = batchTotalContributions[currentBatchId].add(contributionAmount);

            remainingAmount = remainingAmount.sub(contributionAmount);

            emit ContributionReceived(msg.sender, contributionAmount);

            if (batchTotalContributions[currentBatchId] >= TOKENS_PER_NFT) {
                // Move to the next batch
                currentBatchId++;
            }
        }
    }

    function getBrainERC20Address(uint256 tokenId) public view returns (address) {
        return brainToERC20[tokenId];
    }

    function collectiveMint(uint256 batchId) public {
        require(batchTotalContributions[batchId] >= TOKENS_PER_NFT, "Not enough BrainCredits contributed in this batch");
        require(!batchMinted[batchId], "Batch already minted");
        require(tokenCounter < MAX_SUPPLY, "Exceeds maximum supply of Brains");

        uint256 tokenId;
        if (availableTokenIds.length > 0) {
            tokenId = availableTokenIds[availableTokenIds.length - 1];
            availableTokenIds.pop();
        } else {
            unchecked {
                tokenId = tokenCounter;
                tokenCounter++;
                if (tokenCounter == 47) tokenCounter++; // reserved for Based Labs
            }
        }
        emit BrainMinted(tokenId, address(this));
        _safeMint(address(this), tokenId);
        address erc20Contract = _deployERC20(address(this), tokenId);
        brainToERC20[tokenId] = erc20Contract;

    
        batchERC20Address[batchId] = erc20Contract;
        batchTokenId[batchId] = tokenId;
        batchMinted[batchId] = true;

        emit BrainTokenActivated(tokenId, erc20Contract);
    }

    function claimTokens(uint256 batchId) public {
        require(batchMinted[batchId], "Tokens not minted for this batch yet");
        require(!tokensClaimed[batchId][msg.sender], "Tokens already claimed for this batch");
        uint256 contribution = batchContributions[batchId][msg.sender];
        require(contribution > 0, "No contributions for this batch");

        // Calculate the share based on contributions
        uint256 share = contribution.mul(1000000 * 10**18).div(TOKENS_PER_NFT);

        tokensClaimed[batchId][msg.sender] = true;

        BrainERC20(batchERC20Address[batchId]).transfer(msg.sender, share);
    }

    function getStakedAmount(address staker) public view returns (uint256) {
        return stakes[staker];
    }

    function mintLabsBrain(uint256 tokenId) public onlyOwner {
        require(tokenId < MAX_SUPPLY, "Token ID exceeds maximum supply");
        require(pepecoinAddress == address(0), "Cannot run after mint start");
        emit BrainMinted(tokenId, msg.sender);
        IBrainCredits(brainCreditAddress).decreaseTotalSupply();
        _safeMint(msg.sender, tokenId);
        if (tokenId != 47) tokenCounter++;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        string memory _tokenURI = _tokenURIs[tokenId];

        if (bytes(_tokenURI).length > 0) {
            return _tokenURI;
        }

        if (bytes(brainMetadata[tokenId].metadataUrl).length > 0) {
            return brainMetadata[tokenId].metadataUrl;
        }

        return "https://ordinals.com/content/f4be79518ebb0283ed37012b42152dedc2bdfe2e7a89267c7448ab36e02bf99ci0";
    }

    function proposeMetadataChange(uint256 tokenId, string memory name, string memory ticker, string memory metadataUrl, string memory imageUrl) public {
        require(brainToERC20[tokenId] != address(0), "Brain token not activated");
        require(IERC20(brainToERC20[tokenId]).balanceOf(msg.sender) > 100, "Must own at least 100 brain tokens to propose");
        require(!_blockedTokenIds[tokenId], "Metadata updates disabled on Brain");
        
        uint256 proposalId = proposalCounter[tokenId];
        MetadataProposal storage proposal = metadataProposals[tokenId][proposalId];
        
        proposal.name = name;
        proposal.ticker = ticker;
        proposal.metadataUrl = metadataUrl;
        proposal.imageUrl = imageUrl;
        proposal.votesLocked = 0;
        proposal.executed = false;
        
        proposalCounter[tokenId]++;
        
        emit MetadataChangeProposed(tokenId, proposalId, name, ticker, metadataUrl, imageUrl);
    }

    function voteOnProposal(uint256 tokenId, uint256 proposalId, uint256 amount) public nonReentrant {
        require(brainToERC20[tokenId] != address(0), "Brain token not activated");
        require(!_blockedTokenIds[tokenId], "Metadata updates disabled on Brain");
        MetadataProposal storage proposal = metadataProposals[tokenId][proposalId];
        require(!proposal.executed, "Proposal already executed");
        
        IERC20 brainToken = IERC20(brainToERC20[tokenId]);
        require(brainToken.balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        brainToken.transferFrom(msg.sender, address(this), amount);
        
        proposal.votesLocked = proposal.votesLocked.add(amount);
        proposal.voterLocks[msg.sender] = proposal.voterLocks[msg.sender].add(amount);
        
        emit VoteCast(tokenId, proposalId, msg.sender, amount);
        
        if (proposal.votesLocked >= PROPOSAL_THRESHOLD) {
            executeProposal(tokenId, proposalId);
        }
    }

    function executeProposal(uint256 tokenId, uint256 proposalId) internal {
        require(!_blockedTokenIds[tokenId], "Metadata updates disabled on Brain");
        MetadataProposal storage proposal = metadataProposals[tokenId][proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(proposal.votesLocked >= PROPOSAL_THRESHOLD, "Voting threshold not met");
        
        brainMetadata[tokenId] = BrainMetadata(proposal.name, proposal.ticker, proposal.metadataUrl, proposal.imageUrl);
        
        // Update ERC20 token name and symbol
        address erc20Address = brainToERC20[tokenId];
        if (erc20Address != address(0)) {
            string memory newERC20Name = string(abi.encodePacked("BRAIN TOKEN #", Strings.toString(tokenId), " - ", proposal.name));
            string memory newERC20Symbol = string(abi.encodePacked("B#", Strings.toString(tokenId), "-", proposal.ticker));
            BrainERC20(erc20Address).updateTokenInfo(newERC20Name, newERC20Symbol);
            brainERC20Names[tokenId] = newERC20Name;
            brainERC20Symbols[tokenId] = newERC20Symbol;
        }
        
        proposal.executed = true;
        
        emit BrainMetadataUpdated(tokenId, proposal.name, proposal.ticker, proposal.metadataUrl, proposal.imageUrl);
    }

    function updateBrainMetadata(uint256 tokenId, string memory name, string memory ticker, string memory metadataUrl, string memory imageUrl) public {
        require(ownerOf(tokenId) == msg.sender, "Only Brain owner can update metadata");
        require(!_blockedTokenIds[tokenId], "Metadata updates disabled on Brain");
    
        brainMetadata[tokenId] = BrainMetadata(name, ticker, metadataUrl, imageUrl);
    
        // Update ERC20 token name and symbol
        address erc20Address = brainToERC20[tokenId];
        if (erc20Address != address(0)) {
            BrainERC20(erc20Address).updateTokenInfo(name, ticker);
            brainERC20Names[tokenId] = name;
            brainERC20Symbols[tokenId] = ticker;
        }
    
        emit BrainMetadataUpdated(tokenId, name, ticker, metadataUrl, imageUrl);
    }

    function toggleBlockBrainUri(uint256 tokenId) public onlyOwner {
        _blockedTokenIds[tokenId] = !_blockedTokenIds[tokenId];
    }

    function totalSupply() public pure returns (uint256) {
        return MAX_SUPPLY;
    }
    function _afterBrainTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        emit BrainTransferred(tokenId, from, to, block.timestamp);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        super.transferFrom(from, to, tokenId);
        _afterBrainTransfer(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override {
        super.safeTransferFrom(from, to, tokenId, data);
        _afterBrainTransfer(from, to, tokenId);
    }

    // Stub functionality for self-storage of ERC721s 
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        // Handle the receipt of an ERC721 token
        return this.onERC721Received.selector;
    }

}