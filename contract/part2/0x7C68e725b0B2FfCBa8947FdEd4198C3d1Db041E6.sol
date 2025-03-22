/*
SAFU TEAM VERIFICATION
*/


// SPDX-License-Identifier: No License
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable2Step.sol";
import "./TokenRecover.sol";
import "./Initializable.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router01.sol";
import "./IUniswapV2Router02.sol";

contract Pongo is ERC20, ERC20Burnable, Ownable2Step, TokenRecover, Initializable {
    
    uint16 public swapThresholdRatio;
    
    uint256 private _pongoPending;

    address public pongoAddress;
    uint16[3] public pongoFees;

    mapping (address => bool) public isExcludedFromFees;

    uint16[3] public totalFees;
    bool private _swapping;

    IUniswapV2Router02 public routerV2;
    address public pairV2;
    mapping (address => bool) public AMMPairs;

    bool public tradingEnabled;
    mapping (address => bool) public isExcludedFromTradingRestriction;
 
    event SwapThresholdUpdated(uint16 swapThresholdRatio);

    event pongoAddressUpdated(address pongoAddress);
    event pongoFeesUpdated(uint16 buyFee, uint16 sellFee, uint16 transferFee);
    event pongoFeeSent(address recipient, uint256 amount);

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event RouterV2Updated(address indexed routerV2);
    event AMMPairsUpdated(address indexed AMMPair, bool isPair);

    event TradingEnabled();
    event ExcludeFromTradingRestriction(address indexed account, bool isExcluded);
 
    constructor()
        ERC20(unicode"Pongo", unicode"Pongo") 
    {
        address supplyRecipient = 0x55942589c493012BC3a9A71c7A698007ce7a8fe9;
        
        updateSwapThreshold(30);

        pongoAddressSetup(0x9ff91A8bdbf1271Bb14acF8cF66363323fC2d24B);
        pongoFeesSetup(2500, 2500, 0);

        excludeFromFees(supplyRecipient, true);
        excludeFromFees(address(this), true); 

        excludeFromTradingRestriction(supplyRecipient, true);
        excludeFromTradingRestriction(address(this), true);

        _mint(supplyRecipient, 10101010101010 * (10 ** decimals()) / 10);
        _transferOwnership(0x55942589c493012BC3a9A71c7A698007ce7a8fe9);
    }
    
    /*
        This token is not upgradeable, but uses both the constructor and initializer for post-deployment setup.
    */
    function initialize(address _router) initializer external {
        _updateRouterV2(_router);
    }

    receive() external payable {}

    function decimals() public pure override returns (uint8) {
        return 9;
    }
    
    function _swapTokensForCoin(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = routerV2.WETH();

        _approve(address(this), address(routerV2), tokenAmount);

        routerV2.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    function updateSwapThreshold(uint16 _swapThresholdRatio) public onlyOwner {
        require(_swapThresholdRatio > 0 && _swapThresholdRatio <= 500, "SwapThreshold: Cannot exceed limits from 0.01% to 5% for new swap threshold");
        swapThresholdRatio = _swapThresholdRatio;
        
        emit SwapThresholdUpdated(_swapThresholdRatio);
    }

    function getSwapThresholdAmount() public view returns (uint256) {
        return balanceOf(pairV2) * swapThresholdRatio / 10000;
    }

    function getAllPending() public view returns (uint256) {
        return 0 + _pongoPending;
    }

    function pongoAddressSetup(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "TaxesDefaultRouterWallet: Wallet tax recipient cannot be a 0x0 address");

        pongoAddress = _newAddress;
        excludeFromFees(_newAddress, true);

        emit pongoAddressUpdated(_newAddress);
    }

    function pongoFeesSetup(uint16 _buyFee, uint16 _sellFee, uint16 _transferFee) public onlyOwner {
        totalFees[0] = totalFees[0] - pongoFees[0] + _buyFee;
        totalFees[1] = totalFees[1] - pongoFees[1] + _sellFee;
        totalFees[2] = totalFees[2] - pongoFees[2] + _transferFee;
        require(totalFees[0] <= 2500 && totalFees[1] <= 2500 && totalFees[2] <= 2500, "TaxesDefaultRouter: Cannot exceed max total fee of 25%");

        pongoFees = [_buyFee, _sellFee, _transferFee];

        emit pongoFeesUpdated(_buyFee, _sellFee, _transferFee);
    }

    function excludeFromFees(address account, bool isExcluded) public onlyOwner {
        isExcludedFromFees[account] = isExcluded;
        
        emit ExcludeFromFees(account, isExcluded);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (!_swapping && amount > 0 && to != address(routerV2) && !isExcludedFromFees[from] && !isExcludedFromFees[to]) {
            uint256 fees = 0;
            uint8 txType = 3;
            
            if (AMMPairs[from]) {
                if (totalFees[0] > 0) txType = 0;
            }
            else if (AMMPairs[to]) {
                if (totalFees[1] > 0) txType = 1;
            }
            else if (totalFees[2] > 0) txType = 2;
            
            if (txType < 3) {
                
                fees = amount * totalFees[txType] / 10000;
                amount -= fees;
                
                _pongoPending += fees * pongoFees[txType] / totalFees[txType];

                
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }
        }
        
        bool canSwap = getAllPending() >= getSwapThresholdAmount() && balanceOf(pairV2) > 0;
        
        if (!_swapping && !AMMPairs[from] && from != address(routerV2) && canSwap) {
            _swapping = true;
            
            if (false || _pongoPending > 0) {
                uint256 token2Swap = 0 + _pongoPending;
                bool success = false;

                _swapTokensForCoin(token2Swap);
                uint256 coinsReceived = address(this).balance;
                
                uint256 pongoPortion = coinsReceived * _pongoPending / token2Swap;
                if (pongoPortion > 0) {
                    success = payable(pongoAddress).send(pongoPortion);
                    if (success) {
                        emit pongoFeeSent(pongoAddress, pongoPortion);
                    }
                }
                _pongoPending = 0;

            }

            _swapping = false;
        }

        super._transfer(from, to, amount);
        
    }

    function _updateRouterV2(address router) private {
        routerV2 = IUniswapV2Router02(router);
        pairV2 = IUniswapV2Factory(routerV2.factory()).createPair(address(this), routerV2.WETH());
        
        _setAMMPair(pairV2, true);

        emit RouterV2Updated(router);
    }

    function setAMMPair(address pair, bool isPair) external onlyOwner {
        require(pair != pairV2, "DefaultRouter: Cannot remove initial pair from list");

        _setAMMPair(pair, isPair);
    }

    function _setAMMPair(address pair, bool isPair) private {
        AMMPairs[pair] = isPair;

        if (isPair) { 
        }

        emit AMMPairsUpdated(pair, isPair);
    }

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "EnableTrading: Trading was enabled already");
        tradingEnabled = true;
        
        emit TradingEnabled();
    }

    function excludeFromTradingRestriction(address account, bool isExcluded) public onlyOwner {
        isExcludedFromTradingRestriction[account] = isExcluded;
        
        emit ExcludeFromTradingRestriction(account, isExcluded);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        // Interactions with DEX are disallowed prior to enabling trading by owner
        if ((AMMPairs[from] && !isExcludedFromTradingRestriction[to]) || (AMMPairs[to] && !isExcludedFromTradingRestriction[from])) {
            require(tradingEnabled, "EnableTrading: Trading was not enabled yet");
        }

        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        super._afterTokenTransfer(from, to, amount);
    }
}