/** ---------------------------------------------------------------------------- //
 *                                                                               //
 *                Smart contract generated by https://nfts2me.com                //
 *                                                                               //
 *                                      .::.                                     //
 *                                    ......                                     //
 *                                ....        ::.                                //
 *                             .:..           :: ...                             //
 *                         ..:.               ::     ...                         //
 *                       ::.      ..:--       ::.       ...                      //
 *                      .:    ..:::::-==:     :::::..     :                      //
 *                      .:    :::::::-====:   ::::::::    :                      //
 *                      .:    :::::::-======. ::::::::    :                      //
 *                      .:    :::::::-=======-::::::::    :                      //
 *                      .:    :::::::-========-:::::::    :                      //
 *                      .:    ::::::::========-:::::::    :                      //
 *                      .:    :::::::. .======-:::::::    :                      //
 *                      .:    :::::::.   :====-:::::::    :                      //
 *                      .:     .:::::.     -==-:::::.     :                      //
 *                       .:.       .:.      .--:..      ...                      //
 *                          .:.     :.               ...                         //
 *                             .... :.           ....                            //
 *                                 .:.        .:.                                //
 *                                      .::::.                                   //
 *                                      :--.                                     //
 *                                                                               //
 *                                                                               //
 *   NFTs2Me. Make an NFT Collection.                                            //
 *   With ZERO Coding Skills.                                                    //
 *                                                                               //
 *   NFTs2Me is not associated or affiliated with this project.                  //
 *   NFTs2Me is not liable for any bugs or issues associated with this contract. //
 *   NFTs2Me Terms of Service: https://nfts2me.com/terms-of-service/             //
 *   More info at: https://docs.nfts2me.com/                                     //
 * ----------------------------------------------------------------------------- */

/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {ERC721} from "openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "openzeppelin/contracts/interfaces/IERC721.sol";

import {ECDSA} from "solady/utils/ECDSA.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Ownable} from "solady/auth/Ownable.sol";

import {IERC2981} from "openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol"; 
import {IN2MFactory, IN2MCommon} from "./interfaces/IN2MFactory.sol";
import {N2MVersion, Readme} from "./N2MVersion.sol";
import {IN2MCrossFactory} from "./interfaces/IN2MCrossFactory.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

address constant N2M_TREASURY = 0x6db16927DbC38AA39F0Ee2cB545e15EFd813FB99;
address constant N2M_CONDUIT = 0x88899DC0B84C6E726840e00DFb94ABc6248825eC;
address constant OPENSEA_CONDUIT = 0x1E0049783F008A0085193E00003D00cd54003c71;

bytes4 constant IERC165_INTERFACE_ID = 0x01ffc9a7;
bytes4 constant IERC173_INTERFACE_ID = 0x7f5828d0;
bytes4 constant IERC721_INTERFACE_ID = 0x80ac58cd;
bytes4 constant IERC721METADATA_INTERFACE_ID = 0x5b5e139f;
bytes4 constant IERC2981_INTERFACE_ID = 0x2a55205a;

/// @title NFTs2Me.com Factory
/// @author The NFTs2Me Team
/// @notice Read our terms of service
/// @custom:security-contact [email protected]
/// @custom:terms-of-service https://nfts2me.com/terms-of-service/
/// @custom:website https://nfts2me.com/
contract N2MFactory is
    ERC721,
    Ownable,
    IN2MFactory,
    IN2MCrossFactory,
    N2MVersion
{
    mapping(bytes32 => address) private _implementationAddresses;
    address private _delegatedCreationSigner;
    string private _ownerTokenURI = "https://metadata.nfts2me.com/api/ownerTokenURI/";

    constructor(
        address owner,
        address delegatedCreationSigner,
        bytes32 type1,
        bytes32 type2,
        address type1Address,
        address type2Address)
        ERC721("", "") payable { 
        _initializeOwner(owner);
        _delegatedCreationSigner = delegatedCreationSigner;
        _implementationAddresses[type1] = type1Address;
        _implementationAddresses[type2] = type2Address;
    }

    /**
     * @dev Returns the name of the NFT Collection for the Ownership NFTs.
     * @return The name of the NFT Collection for the Ownership NFTs.
     */
    function name() public pure override(ERC721) returns (string memory) {
        return "NFTs2Me Owners";
    }

    /***
     * @dev Returns the symbol of the NFT Collection for the Ownership NFTs.
     * @return The symbol of the NFT Collection for the Ownership NFTs.
     */
    function symbol() public pure override(ERC721) returns (string memory) {
        return "N2MOwners";
    }

    /***
     * @dev Returns the implementation address for the given implementation type.
     * @param implementationType The type of implementation. Only 96 bits are considered.
     * @return The address of the implementation.
     */
    function getImplementation(bytes32 implementationType) external view override returns (address) {
        return _implementationAddresses[implementationType];
    }

    function _newContractImplementationsAndSigner(
        bytes32[] calldata implementationTypesAndAddresses,
        address delegatedCreationSigner_,
        string calldata ownerTokenURI
    ) private {
        for (uint256 i; i<implementationTypesAndAddresses.length; i++) {
            address implementationAddress = address(uint160(uint256(implementationTypesAndAddresses[i])));
            bytes32 implementationType = implementationTypesAndAddresses[i] >> 160;
            _implementationAddresses[implementationType] = implementationAddress;
        }
        if (delegatedCreationSigner_ != address(0)) {
            _delegatedCreationSigner = delegatedCreationSigner_;
        }
        if (bytes(ownerTokenURI).length > 0) {
            _ownerTokenURI = ownerTokenURI;
        }        
    }

    /**
     * @dev Sets new contract implementations and signer.
     * @param implementationTypesAndAddresses The array of implementation types and addresses.
     * @param delegatedCreationSigner_ The address of the signer for delegatedCreation.
     */
    function newContractImplementationsAndSigner(
        bytes32[] calldata implementationTypesAndAddresses,
        address delegatedCreationSigner_,
        string calldata ownerTokenURI
    ) external payable onlyOwner {
        _newContractImplementationsAndSigner(implementationTypesAndAddresses, delegatedCreationSigner_, ownerTokenURI);
    }

    /**
     * @dev Creates a new NFT collection.
     * @param collectionInformation The information to create the collection.
     * @param collectionId The unique identifier for the collection and deployment. Must contain the msg.sender.
     * @param implementationType The type of implementation for the collection. Only 96 bits are considered.
     */
    function createCollection(
        bytes calldata collectionInformation,
        bytes32 collectionId,
        bytes32 implementationType
    ) external payable containsCaller(collectionId) {
        address collection = LibClone.cloneDeterministic(
            _implementationAddresses[implementationType],
            collectionId
        );

        (bool success, bytes memory returnData) = collection.call(collectionInformation);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }                
        }

        _mint(msg.sender, uint256(uint160((collection))));
    }

    /**
     * @dev Creates a new NFT collection.
     * @param collectionInformation The information to create the collection.
     * @param collectionId The unique identifier for the collection and deployment. Must contain the msg.sender.
     * @param implementationType The type of implementation for the collection. Only 96 bits are considered.
     */
    function createCollectionN2M_000oEFvt(
        bytes calldata collectionInformation,
        bytes32 collectionId,
        bytes32 implementationType
    ) external payable containsCaller(collectionId) {
        address collection = LibClone.cloneDeterministic(
            _implementationAddresses[implementationType],
            collectionId
        );

        (bool success, bytes memory returnData) = collection.call(collectionInformation);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }                
        }

        _mint(msg.sender, uint256(uint160((collection))));
    }

    /**
     * @dev Creates a new NFT collection.
     * @param collectionInformation The information to create the collection.
     * @param collectionId The unique identifier for the collection and deployment. Must contain the msg.sender.
     * @param implementationType The type of implementation for the collection. Only 96 bits are considered.
     */
    function createCrossCollection(
        bytes calldata collectionInformation,
        bytes32 collectionId,
        bytes32 implementationType
    ) external payable containsCaller(collectionId) {
        bytes memory initCode = LibClone.initCode(_implementationAddresses[implementationType]);
        address collection = CREATE3.deploy(collectionId, initCode, 0);

        (bool success, bytes memory returnData) = collection.call(collectionInformation);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }                
        }

        _mint(msg.sender, uint256(uint160((collection))));
    }

    /**
     * @dev Performs a delegated creation of a new NFT collection.
     * @param owner The owner of the NFT collection.
     * @param collectionInformation The collection information to create the collection.
     * @param collectionId The ID of the NFT collection and deployment. Must contain the owner address.
     * @param implementationType The type of implementation for the NFT collection. Only 96 bits are considered.
     * @param signature The signature to validate the creation operation.
     */
    function delegatedCreation(
        bytes calldata collectionInformation,
        address owner,
        bytes32 collectionId,
        bytes32 implementationType,
        bytes calldata signature
    ) external payable override {
        LibClone.checkStartsWith(collectionId, owner);
        address signer = ECDSA.recoverCalldata(
            ECDSA.toEthSignedMessageHash(
                keccak256(
                    abi.encodePacked(
                        this.delegatedCreation.selector,
                        block.chainid,
                        collectionInformation,
                        owner,
                        collectionId,
                        implementationType
                    )
                )
            ),
            signature
        );

        if (signer != _delegatedCreationSigner && signer != owner) revert InvalidSignature();

        address collection = LibClone.cloneDeterministic(
            _implementationAddresses[implementationType],
            collectionId
        );

        (bool success, bytes memory returnData) = collection.call(collectionInformation);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }                
        }

        _mint(owner, uint256(uint160((collection))));
    }

    /**
     * @dev Creates a new dynamic contract instance using the provided dynamic address, salt, and initialization data.
     * The caller must be the contract containing the `salt`.
     * @param dynamicAddress The address of the dynamic contract to clone.
     * @param salt The salt value used for deterministic cloning.
     * @param initData The initialization data to be passed to the cloned contract.
     */
    function createNewDynamic(
        address dynamicAddress,
        bytes32 salt,
        bytes calldata initData
    ) external payable override containsCaller(salt) {
        address dynamic = LibClone.cloneDeterministic(
            dynamicAddress,
            salt
        );

        if (initData.length > 0) {
            (bool success, bytes memory returnData) = dynamic.call{value: msg.value}(initData);
            if (!success) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }     
            }
        }
    }

    /**
     * @dev Create a contract using CREATE3 by submitting a given salt or nonce
     * along with the initialization code for the contract. Note that the first 20
     * bytes of the salt must match those of the calling address, which prevents
     * contract creation events from being submitted by unintended parties.
     * @param salt bytes32 The nonce that will be passed into the CREATE3 call.
     * Salts cannot be reused with the same initialization code.
     * @param initCode bytes The initialization code that will be passed
     * into the CREATE3 call. Note that initCode doesn't influence the generated address
     */
    function create3(bytes32 salt, bytes memory initCode) external payable containsCaller(salt) {
        CREATE3.deploy(salt, initCode, msg.value);
    }

    /**
     * @dev Executes multiple calls in a single transaction, including calls to the factory and to a given collection.
     * @param collectionAndSelfcalls The first 160 bits represent the address of the collection contract, and the remaining bits represent the number of self-calls to be made to the factory.
     * @param data The array of calldata for each call. The length of the array must match the number of calls.
     */
    function multicallN2M_001Taw5z(uint256 collectionAndSelfcalls, bytes[] calldata data) external payable override {
        address collection = address(uint160(collectionAndSelfcalls));
        uint256 selfcalls = collectionAndSelfcalls >> 160;
        /// Delegate calls to factory (selfcalls)
        uint256 i;
        for (; i < selfcalls; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }                
            }
        }

        /// Calls to collection with owner permission
        if (collection != address(0)) {
            /// Check if msg.sender is the owner of the collection
            if (msg.sender != _ownerOf(uint256(uint160(collection)))) revert Unauthorized();

            /// Regular call to collection
            for (; i < data.length; i++) {
                (bool success, bytes memory returnData) = collection.call(data[i]);
                if (!success) {
                    assembly {
                        revert(add(returnData, 32), mload(returnData))
                    }                
                }
            }
        }
    }

    /**
     * @dev Executes multiple calls in a single transaction, including calls to the factory and to a given collection.
     * @param collectionAndSelfcalls The first 160 bits represent the address of the collection contract, and the remaining bits represent the number of self-calls to be made to the factory.
     * @param data The array of calldata for each call. The length of the array must match the number of calls.
     */
    function multicall(uint256 collectionAndSelfcalls, bytes[] calldata data) external payable override {
        address collection = address(uint160(collectionAndSelfcalls));
        uint256 selfcalls = collectionAndSelfcalls >> 160;
        /// Delegate calls to factory (selfcalls)
        uint256 i;
        for (; i < selfcalls; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }                
            }
        }

        /// Calls to collection with owner permission
        if (collection != address(0)) {
            /// Check if msg.sender is the owner of the collection
            if (msg.sender != _ownerOf(uint256(uint160(collection)))) revert Unauthorized();

            /// Regular call to collection
            for (; i < data.length; i++) {
                (bool success, bytes memory returnData) = collection.call(data[i]);
                if (!success) {
                    assembly {
                        revert(add(returnData, 32), mload(returnData))
                    }                
                }
            }
        }
    }

    /**
     * @dev Executes multiple calls in a single transaction, including calls to the factory and to multiple collections.
     * @param collectionsAndCalls Array of collection addresses and call amounts. address(0) is used for selfcalls. The first 160 bits represent the address of the collection contract, and the remaining bits represent the number of calls to be made to the collection.
     * @param collectionsValues Optional. Array of values to be sent with each call. If the array is shorter than the number of calls, the remaining calls will be sent with 0 value.
     * @param data Array of call data for each collection. The length of the array must match the number of calls.
     */
    function multicallMulticollection(uint256[] calldata collectionsAndCalls, uint256[] calldata collectionsValues, bytes[] calldata data) external payable override {
        uint256 collectionsValuesLength = collectionsValues.length;

        /// If there are msg.value transfers, transfer current native contract balance to treasury.
        if (collectionsValuesLength > 0) {
            uint256 previousBalance = address(this).balance - msg.value;
            if ((previousBalance) > 0) {
                assembly {
                    pop(call(gas(), N2M_TREASURY, previousBalance, 0, 0, 0, 0))
                }
            }
        }

        uint256 dataIndex;
        uint256 valueIndex;
        for (uint256 i; i < collectionsAndCalls.length; i++) {
            uint256 currentCollectionAndAmount = collectionsAndCalls[i];
            address collection = address(uint160(currentCollectionAndAmount));
            uint256 callAmount = currentCollectionAndAmount >> 160;
            if (collection == address(0)) {
                /// Delegate calls to factory (selfcalls)
                for (uint256 j; j < callAmount; j++) {
                    (bool success, bytes memory returnData) = address(this).delegatecall(data[dataIndex++]);
                    if (!success) {
                        assembly {
                            revert(add(returnData, 32), mload(returnData))
                        }                
                    }
                }
            } else {
                /// Check if msg.sender is the owner of the collection
                if (msg.sender != _ownerOf(uint256(uint160(collection)))) revert Unauthorized();
                for (uint256 j; j < callAmount; j++) {
                    uint256 currentValue;
                    if (valueIndex < collectionsValuesLength) {
                        currentValue = collectionsValues[valueIndex++];
                    }
                    (bool success, bytes memory returnData) = collection.call{value: currentValue}(data[dataIndex++]);
                    if (!success) {
                        assembly {
                            revert(add(returnData, 32), mload(returnData))
                        }                
                    }
                }
            }
        }

        /// Final additional checks
        if (dataIndex != data.length) revert InvalidLengths();
        if (valueIndex != collectionsValuesLength) revert InvalidLengths();
    }

    /**
     * @dev Predicts the deterministic address for a contract deployment based on the implementation type and collection and deploy ID.
     * @param implementationType The type of implementation for the contract.
     * @param collectionId The collection and deploy ID for the contract.
     * @return The deterministic address for the contract deployment.
     */
    function predictDeterministicAddress(
        bytes32 implementationType,
        bytes32 collectionId
    ) external view returns (address) {
        return
            LibClone.predictDeterministicAddress(
                _implementationAddresses[implementationType],
                collectionId,
                address(this)
            );
    }

    /**
     * @dev Withdraws ETH and ERC20 tokens from the contract to a specified address.
     * @param to The address to which the funds will be transferred.
     * @param erc20 Optional. The address of the ERC20 token.
     */
    function withdrawTo(address to, address erc20) onlyOwner external payable {
        assembly {
            pop(call(gas(), to, selfbalance(), 0, 0, 0, 0))
        }
        if (erc20 != address(0)) {
            IERC20(erc20).transfer(to, SafeTransferLib.balanceOf(erc20, address(this)));
        }
    }

    function _update(
        address to, 
        uint256 tokenId, 
        address auth
    ) internal virtual override returns (address previousOwner) {
        previousOwner = super._update(to, tokenId, auth);

        if (previousOwner != address(0)) {
            address collection = address(uint160(tokenId));
            IN2MCommon(collection).ownershipTransferred(previousOwner, to);
        }
    }

    /**
     * @dev Returns the token URI for a given token ID of the Ownership NFTs.
     * @param tokenId The ID of the Ownership NFT.
     * @return The token URI.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        address collection = address(uint160(tokenId));
        uint256 ownerRevenue = IN2MCommon(collection).ownerMaxRevenue();

        return string(abi.encodePacked(_ownerTokenURI, LibString.toString(block.chainid), "/", LibString.toString(tokenId), "/", LibString.toString(uint256(uint160(ownerOf(tokenId)))), "/", LibString.toString(ownerRevenue), "/"));
    }

    /// @notice Returns how much royalty is owed and to whom, based on a sale price that may be denominated in any unit of exchange. The royalty amount is denominated and should be paid in that same unit of exchange.
    /// @param salePrice The sale price
    /// @return receiver the receiver of the royalties.
    /// @return royaltyAmount the amount of the royalties for the given input.
    function royaltyInfo(
        uint256, 
        uint256 salePrice
    ) external view virtual returns (address receiver, uint256 royaltyAmount) {
        return (address(N2M_TREASURY), uint256((salePrice * 5_00) / 100_00));
    }

    /// @notice Query if a contract implements an interface
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceId` and `interfaceId` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override(ERC721)
        returns (bool)
    {
        if (interfaceId == IERC165_INTERFACE_ID) return true;
        if (interfaceId == IERC173_INTERFACE_ID) return true;
        if (interfaceId == IERC721_INTERFACE_ID) return true;
        if (interfaceId == IERC721METADATA_INTERFACE_ID) return true;
        return (interfaceId == IERC2981_INTERFACE_ID);
    }    

    /// @notice Query if an address is an authorized operator for another address
    /// @param owner The address that owns the NFTs
    /// @param operator The address that acts on behalf of the owner
    /// @return True if `operator` is an approved operator for `owner`, false otherwise
    function isApprovedForAll(address owner, address operator)
    public
    view
    virtual
    override
    returns (bool)
    {
        if (operator == N2M_CONDUIT) return true;
        if (operator == OPENSEA_CONDUIT) return true;

        return super.isApprovedForAll(owner, operator);
    }

    function ownerOf(uint256 tokenId)
        public
        view
        override(ERC721, IN2MCrossFactory)
        returns (address)
    {
        return super.ownerOf(tokenId);
    }

    /**
     * @dev Transfers the ownership of a collection to the specified address.
     * @param to The address to transfer the ownership to.
     * @notice The caller must be the collection itself, being the call initiated by the current owner of the collection.
     * @notice If the collection does not exist, the function reverts.
     */
    function transferCollectionOwnership(address to) external payable {
        uint256 tokenId = uint256(uint160(msg.sender));
        address previousOwner = _update(to, tokenId, address(0));
        if (previousOwner == address(0)) revert ERC721NonexistentToken(tokenId);
    }

    /**
     * @dev Retrieves the IPFS URI for a given CID hash.
     * @param CIDHash The CID hash to retrieve the IPFS URI for.
     * @return The IPFS URI in base32 v1 using DAG-PB codec for root.
     */
    function getIPFSURI(bytes32 CIDHash) external pure override returns (string memory) {
        bytes memory decodedInput = abi.encodePacked(bytes4(0x01701220), CIDHash, bytes1(0x00));
        bytes memory outputString = new bytes(58);
        for(uint256 i = 0; i < 58; i++){
            uint8 base32Value = _getBase32Value(decodedInput, i);
            outputString[i] = _base32ToChar(base32Value);
        }

        return string.concat("ipfs://b", string(outputString));
    }

    function _getBase32Value(bytes memory decodedInput, uint256 position) private pure returns (uint8){
        position *= 5;

        uint256 inputPosition = (position) / 8;
        bytes32 temp = bytes32(decodedInput[inputPosition]) | bytes32(decodedInput[inputPosition + 1]) >> 8;
        uint256 positionRemainder = (position) % 8;
        temp <<= positionRemainder;
        bytes32 mask = 0xf800000000000000000000000000000000000000000000000000000000000000;
        temp &= mask;
        return uint8(uint256((temp >> 251)));
    }

    function _base32ToChar(uint8 base32Value) private pure returns (bytes1){
        if (base32Value < 26){
            return bytes1(base32Value + 97);
        } else {
            return bytes1(base32Value + 24);
        }

    }

    modifier containsCaller(bytes32 salt) {
        /// prevent contract addresses from being stolen by requiring
        /// that the first 20 bytes of the submitted salt match msg.sender.
        LibClone.checkStartsWith(salt, msg.sender);
        /// if (
        /// (address(bytes20(salt)) != msg.sender) &&
        /// (bytes20(salt) != bytes20(0)))
        ///     revert InvalidSalt();
        _;
    }

}