// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/*

                                                                                                    
                    &&&&&& &&&&&                                        &%                          
                     &&&&&&&&&&&&&&&                               && &&&&&&&&&&%                   
                     &&&&&&&      &&&&&                          #&&&&&&&&&&&&&                     
                     &&&&&  &&&&&&&   &&                      &&&&    &%  &&&&&&&                   
                        &&. &&&&&&&&&&                        &  %&&&&&&&  &&&&                     
                        &&&&  *&&&&&&&&&                       &&&&&&&&&  &&&&                      
                           .&&&   &&&&&&&&                   &&&&&&&&   &&&                         
                                    .&&&&&&&               &&&&&&&   &&&%                           
                                       &&&&&&             &&&&&&                                    
                                         &&&&&          /&&&&.                                      
                                           &&&&  %&&&  #&&&,                                        
                                   &&&&(     &&&&&&&&&&&&&                                          
                               &&&&&&&&&&&&&&&&&&&&&&&&&&&&   &&&&&&&&&&                            
                             &&&%        &&&&&&&&&&&&&&&&&&&&&&&&&     &&&                          
                            &&&    &&&*    &&&&&&&&&&&&&&&&&&&&&         &&*                        
                           &&&   .&&&&&&   &&&&&&&&&&&&&&&&&&&&   &&&&&   &&                        
                           &&&   #&&&&&&   &&&&&&&&&&&&&&&&&&&&&  &&&&&   &&                        
                            &&&    &&&&    &&&&&&&&&&&&&&&&&&&&&&  #&&   &&&                        
                             &&&         &&&&&&&&&&&&&&&&&&&&&&&&,     *&&&                         
                              (&&&&&&&&&&&&&&&&&&&&          &&&&&&&&&&&%                           
                                  &&&&&&&&&&&&&&&&&          &&&&&                                  
                                    &&&&&&&&&&&&&&&&&&    %&&&&&&&                                  
                                    &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&#                                 
                                      &&&&&&&&&&&&&&&&&&&&&&&&&&&&                                  
                                           &&&&&&&&&&&&&&&&&&&&                                     

*/
/*
 * Factory contract
 * This contract is used to deploy smart contracts and register them in the Indexer contract
 */
/// @title ERC20TokenFactory
/// @author Smithii

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Indexable} from "./utils/Indexable.sol";
import {Payable} from "./utils/Payable.sol";

contract ERC20TokenFactory is Payable, Indexable {
    constructor(
        address _indexer,
        address _payments,
        string memory _serviceId
    ) Payable(_payments, _serviceId) Indexable(_indexer) {}

    /// Deploys a contract and pays the service creating fee
    /// @param _projectId bytes32 projectId
    /// @param _byteCode the contract bytecode
    /// @param _type the contract type
    function deployContract(
        bytes32 _projectId,
        bytes calldata _byteCode,
        string memory _type,
        string memory _name,
        string memory _symbol
    ) external payable {
        address resultedAddress = Create2.computeAddress(
            _projectId,
            keccak256(_byteCode)
        );
        registerProject(_projectId, msg.sender, resultedAddress, _type, _name, _symbol);
        address _contract = Create2.deploy(0, _projectId, _byteCode);
        require(_contract == resultedAddress, "Contract address mismatch");
        /// @notice Pay the total of 1 token creation fee
        payService(_projectId, _contract, 1);
    }
}