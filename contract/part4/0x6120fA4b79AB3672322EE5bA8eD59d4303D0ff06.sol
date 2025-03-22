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
 * ERC20AntiBot contract
 * This contract is used to control bad actors using bots on trades
 */
/// @title ERC20AntiBot
/// @author Smithii

import {IERC20AntiBot} from "./interfaces/services/IERC20AntiBot.sol";
import {Indexable} from "./utils/Indexable.sol";
import {Payable} from "./utils/Payable.sol";

contract ERC20AntiBot is IERC20AntiBot, Payable, Indexable {
    constructor(
        address _indexer,
        address _payments,
        string memory _serviceId
    ) Indexable(_indexer) Payable(_payments, _serviceId) {}

    /// mappings
    mapping(address => mapping(address => uint256)) private buyBlock;
    mapping(address => Options) private canUseAntiBot;
    mapping(address => mapping(address => bool)) public exempts;

    /// @inheritdoc IERC20AntiBot
    function isBotDetected(address _from) public view returns (bool) {
        if (isExempt(msg.sender, _from)) return false;

        if (isActive(msg.sender)) {
            return (buyBlock[msg.sender][_from] == block.number);
        }
        return false;
    }
    /// @inheritdoc IERC20AntiBot
    function registerBlock(address _to) external {
        if (isActive(msg.sender)) {
            buyBlock[msg.sender][_to] = block.number;
        }
    }
    /// set a token address to be registered in the AntiBot
    /// @param _tokenAddress the address to check
    /// @param _options the options for anti bot
    function _setCanUseAntiBot(
        address _tokenAddress,
        Options memory _options
    ) internal {
        canUseAntiBot[_tokenAddress] = _options;
    }
    /// @inheritdoc IERC20AntiBot
    function setCanUseAntiBot(
        bytes32 projectId,
        address _tokenAddress
    ) external payable onlyProjectOwner(_tokenAddress) {
        if (canUseAntiBot[_tokenAddress].active)
            revert TokenAlreadyActiveOnAntiBot();
        Options memory _options = Options(true, true);
        _setCanUseAntiBot(_tokenAddress, _options);
        payService(projectId, _tokenAddress, 1);
    }
    /// @inheritdoc IERC20AntiBot
    function setActive(
        address _tokenAddress,
        bool _active
    ) external onlyProjectOwner(_tokenAddress) {
        if (!canUseAntiBot[_tokenAddress].active)
            revert TokenNotActiveOnAntiBot();
        canUseAntiBot[_tokenAddress].applied = _active;
    }
    /// @inheritdoc IERC20AntiBot
    function setExempt(
        address _tokenAddress,
        address _traderAddress,
        bool _exempt
    ) external onlyProjectOwner(_tokenAddress) {
        if (!canUseAntiBot[_tokenAddress].active)
            revert TokenNotActiveOnAntiBot();
        exempts[_tokenAddress][_traderAddress] = _exempt;
    }
    /// @inheritdoc IERC20AntiBot
    function isExempt(
        address _tokenAddress,
        address _traderAddress
    ) public view returns (bool) {
        return exempts[_tokenAddress][_traderAddress];
    }
    /// @inheritdoc IERC20AntiBot
    function isActive(address _tokenAddress) public view returns (bool) {
        if (!canUseAntiBot[_tokenAddress].active) return false;
        return canUseAntiBot[_tokenAddress].applied;
    }
    /// @inheritdoc IERC20AntiBot
    function canUse(address _tokenAddress) public view returns (bool) {
        return canUseAntiBot[_tokenAddress].active;
    }
}