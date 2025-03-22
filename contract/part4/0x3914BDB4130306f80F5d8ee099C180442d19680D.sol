// SPDX-License-Identifier: MIT
/*********************************************************************************************\
* Deployyyyer: https://deployyyyer.io
* Twitter: https://x.com/deployyyyer
* Telegram: https://t.me/Deployyyyer
/*********************************************************************************************/
pragma solidity ^0.8.23;


import { LibDiamond } from "./libraries/LibDiamond.sol";
import { IDiamondCut } from "./interfaces/IDiamondCut.sol";

import "./libraries/LibDiamond.sol";
import "./interfaces/IDiamondLoupe.sol";
import "./interfaces/IDiamondCut.sol";
import "./interfaces/IERC173.sol";
import "./interfaces/IERC165.sol";
import "./interfaces/IERC20.sol";
import { INewToken, IUniswapV2Router02 } from "./interfaces/INewToken.sol";
import "./libraries/LibAppStorage.sol";
//import "hardhat/console.sol";

/// @title Deployyyyer 
/// @notice Diamond Proxy for Deployyyyer
/// @dev 
contract Deployyyyer { 
    AppStorage internal s;
    event Transfer(address indexed from, address indexed to, uint256 value);
    //event Approval(address indexed owner, address indexed spender, uint256 value);
    event FactoryBuilt(string name, string symbol, uint256 supply);
    event TeamSet(INewToken.TeamParams tparams);
    event LaunchCostChanged(uint256 ethCost, uint256 deployyyyerCost);
    event PromoCostChanged(uint256 ethCost, uint256 deployyyyerCost);
    event MinLiquidityChanged(uint256 minLiq);
    event IncreasedLimits(uint256 maxWallet, uint256 maxTx);

    struct ConstructorArgs {
        bool createToken;
        address taxwallet;
        address stakingFacet;
        address presaleFacet;
        address tokenFacet;
        address v2router;
        address team1;
        address team2;
        address team3;
        address marketing;
        address treasury;
        uint256 ethCost;
        uint256 deployyyyerCost;
        uint256 promoCostEth;
        uint256 promoCostDeployyyyer;
        uint256 minLiq;
        address uniswapRouter;
        address sushiswapRouter;
        address pancakeswapRouter;

    }

    /// @notice Constructor of Diamond Proxy for Deployyyyer
    constructor(IDiamondCut.FacetCut[] memory _diamondCut, ConstructorArgs memory _args) {
        if(_args.createToken) {
            emit FactoryBuilt("Deployyyyer", "DEPLOY", 1000000000);
        } else {
            emit FactoryBuilt("Deployyyyer", "DEPLOY", 0);
        }
        LibDiamond.diamondCut(_diamondCut, address(0), new bytes(0));
        //console.log(msg.sender);
        LibDiamond.setContractOwner(msg.sender);

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // adding ERC165 data
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        //ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;
        ds.supportedInterfaces[type(IERC20).interfaceId] = true;

        //init appStorage 
        s.stakingFacet = _args.stakingFacet;
        s.presaleFacet = _args.presaleFacet;
        //s.deployyyyer = address(this);

        s.isParent = true;
        s.decimals = 18;
        s.ethCost = _args.ethCost; //2 * 10**s.decimals / 10; //0.2eth
        s.deployyyyerCost = _args.deployyyyerCost; //100000 * 10**s.decimals;
        s.promoCostEth = _args.promoCostEth; //5 * 10**s.decimals / 100; //0.05 eth per hour
        s.promoCostDeployyyyer = _args.promoCostDeployyyyer; //50000 * 10**s.decimals;
        s.minLiq = _args.minLiq; //1 * 10**s.decimals / 10; //0.1eth min
        //s.bridge = address(0);
        emit LaunchCostChanged(s.ethCost, s.deployyyyerCost);
        emit PromoCostChanged(s.promoCostEth, s.promoCostDeployyyyer);
        emit MinLiquidityChanged(s.minLiq);

        s.isFreeTier = false;

        s.taxWallet = payable(_args.taxwallet);
        s.deployyyyerCa = payable(address(this));
        s.tokenFacet = _args.tokenFacet;
        
        s.validRouters[_args.v2router] = true;
        s.validRouters[_args.uniswapRouter] = true;
        s.validRouters[_args.sushiswapRouter] = true;
        s.validRouters[_args.pancakeswapRouter] = true;
        
        if(_args.createToken) {
            
            s.maxBuyTax = 10;
            s.minBuyTax = 2;
            s.taxBuy = s.maxBuyTax; //20%

            
            s.maxSellTax = 10;
            s.minSellTax = 2;
            s.taxSell = s.maxSellTax; //20%
            
            s.initTaxType = 1;
            s.initInterval = 0;
            s.countInterval = 20;

            // Reduction Rules
            s.buyCount = 0; 
            s.name = "Deployyyyer";
            s.symbol = "DEPLOY";
            s.tTotal = 1000000000 * 10**s.decimals; //1b tokens in wei

            // Contract Swap Rules            
            s.taxSwapThreshold = s.tTotal * 1 / 1000; //0.1%
            s.maxTaxSwap = s.tTotal * 1 / 100; //1%
            s.preventSwap = 20;

            s.maxWallet = s.tTotal * 2 / 100;  //2% 
            s.maxTx = s.tTotal * 2 / 100;  //2% 
            s.walletLimited = true;
            s.balances[address(this)] = s.tTotal;

            emit IncreasedLimits(2, 2);

            emit Transfer(address(0), address(this), s.tTotal);

            s.cliffPeriod = 0;
            s.vestingPeriod = 0;

            s.teamShare[_args.team1] = s.tTotal * 4 / 100;
            s.teamShare[_args.team2] = s.tTotal * 3 / 100;
            s.teamShare[_args.team3] = s.tTotal * 3 / 100;
            s.teamShare[_args.marketing] = s.tTotal * 5 / 100; 
            s.teamShare[_args.treasury] = s.tTotal * 5 / 100; 
            s.isExTxLimit[_args.marketing] = true;
            s.isExWaLimit[_args.marketing] = true;
            s.isExTxLimit[_args.treasury] = true;
            s.isExWaLimit[_args.treasury] = true;
            s.isExTxLimit[_args.team1] = true;
            s.isExWaLimit[_args.team1] = true;
            s.isExTxLimit[_args.team2] = true;
            s.isExWaLimit[_args.team2] = true;
            s.isExTxLimit[_args.team3] = true;
            s.isExWaLimit[_args.team3] = true;

            emit TeamSet(INewToken.TeamParams(_args.team1, 4, s.cliffPeriod, s.vestingPeriod, true)); 
            emit TeamSet(INewToken.TeamParams(_args.team2, 3, s.cliffPeriod, s.vestingPeriod, true)); 
            emit TeamSet(INewToken.TeamParams(_args.team3, 3, s.cliffPeriod, s.vestingPeriod, true)); 
            emit TeamSet(INewToken.TeamParams(_args.marketing, 5, s.cliffPeriod, s.vestingPeriod, true));
            emit TeamSet(INewToken.TeamParams(_args.treasury, 5, s.cliffPeriod, s.vestingPeriod, true)); 

            s.teamBalance = s.tTotal * 20 / 100;
            s.uniswapV2Router = IUniswapV2Router02(_args.v2router);
            s.allowances[address(this)][address(s.uniswapV2Router)] = s.tTotal;
            //emit Approval(address(this), address(s.uniswapV2Router), s.tTotal);
            s.launchedTokens[address(this)] = msg.sender; 
        }
        

    }   

    /// @notice fallback
    // Find facet for function that is called and execute the
    // function if a facet is found and return any value.
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        // get diamond storage
        assembly {
            ds.slot := position
        }
        // get facet from function selector
        address facet = address(bytes20(ds.facets[msg.sig]));
        require(facet != address(0), "S1");
        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
                case 0 {
                    revert(0, returndatasize())
                }
                default {
                    return(0, returndatasize())
                }
        }
    }

    /// @notice receive
    receive() external payable {}
}