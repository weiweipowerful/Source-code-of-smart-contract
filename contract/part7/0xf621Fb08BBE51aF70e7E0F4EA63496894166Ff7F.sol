// SPDX-License-Identifier: GPL-3.0
// uni -> stable -> uni scheme

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "./MetaRouteStructs.sol";
import "./MetaRouterGateway.sol";
import "../../utils/RevertMessageParser.sol";

/**
 * @title MetaRouterV3
 * @notice Users must give approve on their tokens to `MetaRoutetGateway` contract,
 * not to `MetaRouter` contract.
 */
contract MetaRouter is Context {
    MetaRouterGateway public immutable metaRouterGateway;

    event TransitTokenSent(
        address to,
        uint256 amount,
        address token
    );

    constructor() {
        metaRouterGateway = new MetaRouterGateway(address(this));
    }

    /**
     * @notice Method that starts the Meta Routing
     * @dev external + internal swap for burn scheme, only external for synth scheme
     * @dev calls the next method on the other side
     * @param _metarouteTransaction metaRoute offchain transaction data
     */
    function metaRoute(
        MetaRouteStructs.MetaRouteTransaction calldata _metarouteTransaction
    ) external payable {
        uint256 approvedTokensLength = _metarouteTransaction.approvedTokens.length;

        if (!_metarouteTransaction.nativeIn) {
            metaRouterGateway.claimTokens(
                _metarouteTransaction.approvedTokens[0],
                _msgSender(),
                _metarouteTransaction.amount
            );
        }

        uint256 secondSwapAmountIn = _metarouteTransaction.amount;
        if (_metarouteTransaction.firstSwapCalldata.length != 0) {
            if (!_metarouteTransaction.nativeIn) {
                _lazyApprove(
                    _metarouteTransaction.approvedTokens[0],
                    _metarouteTransaction.firstDexRouter,
                    _metarouteTransaction.amount
                );
            }

            require(
                _metarouteTransaction.firstDexRouter != address(metaRouterGateway),
                "MetaRouter: invalid first router"
            );

            {
                uint256 size;
                address toCheck = _metarouteTransaction.firstDexRouter;

                assembly {
                    size := extcodesize(toCheck)
                }

                require(size != 0, "MetaRouter: call for a non-contract account");
            }

            (bool firstSwapSuccess, bytes memory swapData) = _metarouteTransaction.firstDexRouter.call{value: msg.value}(
                _metarouteTransaction.firstSwapCalldata
            );

            if (!firstSwapSuccess) {
                revert(RevertMessageParser.getRevertMessage(swapData, "MetaRouter: first swap failed"));
            }

            secondSwapAmountIn = IERC20(_metarouteTransaction.approvedTokens[1]).balanceOf(address(this));
        }

        uint256 finalSwapAmountIn = secondSwapAmountIn;
        if (_metarouteTransaction.secondSwapCalldata.length != 0) {
            bytes memory secondSwapCalldata = _metarouteTransaction.secondSwapCalldata;

            assembly {
                mstore(add(secondSwapCalldata, 36), secondSwapAmountIn)
            }

            _lazyApprove(
                _metarouteTransaction.approvedTokens[approvedTokensLength - 2],
                _metarouteTransaction.secondDexRouter,
                secondSwapAmountIn
            );

            require(
                _metarouteTransaction.secondDexRouter != address(metaRouterGateway),
                "MetaRouter: invalid second router"
            );

            {
                uint256 size;
                address toCheck = _metarouteTransaction.secondDexRouter;

                assembly {
                    size := extcodesize(toCheck)
                }

                require(size != 0, "MetaRouter: call for a non-contract account");
            }

            (bool secondSwapSuccess, bytes memory swapData) = _metarouteTransaction.secondDexRouter.call(secondSwapCalldata);

            if (!secondSwapSuccess) {
                revert(RevertMessageParser.getRevertMessage(swapData, "MetaRouter: second swap failed"));
            }

            finalSwapAmountIn = IERC20(
                _metarouteTransaction.approvedTokens[approvedTokensLength - 1]
            ).balanceOf(address(this));
        }

        _lazyApprove(
            _metarouteTransaction.approvedTokens[approvedTokensLength - 1],
            _metarouteTransaction.relayRecipient,
            finalSwapAmountIn
        );

        bytes memory otherSideCalldata = _metarouteTransaction.otherSideCalldata;
        assembly {
            mstore(add(otherSideCalldata, 100), finalSwapAmountIn)
        }

        require(
            _metarouteTransaction.relayRecipient != address(metaRouterGateway),
            "MetaRouter: invalid recipient"
        );

        {
            uint256 size;
            address toCheck = _metarouteTransaction.relayRecipient;

            assembly {
                size := extcodesize(toCheck)
            }

            require(size != 0, "MetaRouter: call for a non-contract account");
        }

        (bool otherSideCallSuccess, bytes memory data) = _metarouteTransaction.relayRecipient.call(otherSideCalldata);

        if (!otherSideCallSuccess) {
            revert(RevertMessageParser.getRevertMessage(data, "MetaRouter: other side call failed"));
        }
    }

    /**
     * @notice Implements an external call on some contract
     * @dev called by Portal in metaUnsynthesize() method
     * @param _token address of token
     * @param _amount amount of _token
     * @param _receiveSide contract on which call will take place
     * @param _calldata encoded method to call
     * @param _offset shift to patch the amount to calldata
     */
    function externalCall(
        address _token,
        uint256 _amount,
        address _receiveSide,
        bytes calldata _calldata,
        uint256 _offset,
        address _to
    ) external {
        (bool success,) = _externalCall(_token, _amount, _receiveSide, _calldata, _offset);

        if (!success) {
            TransferHelper.safeTransfer(
                _token,
                _to,
                _amount
            );
            emit TransitTokenSent(_to, _amount, _token);
        }
    }

    function returnSwap(
        address _token,
        uint256 _amount,
        address _router,
        bytes calldata _swapCalldata,
        address _burnToken,
        address _synthesis,
        bytes calldata _burnCalldata
    ) external {
        (bool success, bytes memory data) = _externalCall(_token, _amount, _router, _swapCalldata, 36);

        if (!success) {
            revert(RevertMessageParser.getRevertMessage(data, "MetaRouterV2: internal swap failed"));
        }

        uint256 internalSwapAmountOut = IERC20(_burnToken).balanceOf(address(this));

        bytes memory burnCalldata = _burnCalldata;
        assembly {
            mstore(add(burnCalldata, 100), internalSwapAmountOut)
        }

        require(
            _synthesis != address(metaRouterGateway),
            "MetaRouterV2: invalid recipient"
        );

        {
            uint256 size;
            address toCheck = _synthesis;

            assembly {
                size := extcodesize(toCheck)
            }

            require(size != 0, "MetaRouter: call for a non-contract account");
        }

        (bool otherSideCallSuccess, bytes memory burnData) = _synthesis.call(burnCalldata);

        if (!otherSideCallSuccess) {
            revert(RevertMessageParser.getRevertMessage(burnData, "MetaRouterV2: revertSynthesizeRequest call failed"));
        }
    }

    /**
     * @notice Implements an internal swap on stable router and final method call
     * @dev called by Synthesis in metaMint() method
     * @param _metaMintTransaction metaMint offchain transaction data
     */
    function metaMintSwap(
        MetaRouteStructs.MetaMintTransaction calldata _metaMintTransaction
    ) external {
        address finalCallToken = _metaMintTransaction.swapTokens[0];
        if (_metaMintTransaction.secondSwapCalldata.length != 0) {
            // internal swap
            (bool internalSwapSuccess, bytes memory internalSwapData) = _externalCall(
                _metaMintTransaction.swapTokens[0],
                _metaMintTransaction.amount,
                _metaMintTransaction.secondDexRouter,
                _metaMintTransaction.secondSwapCalldata,
                36
            );

            if (!internalSwapSuccess) {
                revert(RevertMessageParser.getRevertMessage(internalSwapData, "MetaRouter: internal swap failed"));
            }
            finalCallToken = _metaMintTransaction.swapTokens[1];
        }
        if (_metaMintTransaction.finalCalldata.length != 0) {
            // patch crossChainID
            bytes32 crossChainID = _metaMintTransaction.crossChainID;
            bytes memory calldata_ = _metaMintTransaction.finalCalldata;
            assembly {
                mstore(add(calldata_, 132), crossChainID)
            }

            uint256 finalAmountIn = IERC20(finalCallToken).balanceOf(address(this));
            // external call
            (bool finalSuccess, bytes memory finalData) = _externalCall(
                finalCallToken,
                finalAmountIn,
                _metaMintTransaction.finalReceiveSide,
                calldata_,
                _metaMintTransaction.finalOffset
            );

            if (!finalSuccess) {
                revert(RevertMessageParser.getRevertMessage(finalData, "MetaRouter: final call failed"));
            }
        }

        uint256 amountOut = IERC20(_metaMintTransaction.swapTokens[_metaMintTransaction.swapTokens.length - 1]).balanceOf(address(this));

        if (amountOut != 0) {
            TransferHelper.safeTransfer(
                _metaMintTransaction.swapTokens[_metaMintTransaction.swapTokens.length - 1],
                _metaMintTransaction.to,
                amountOut
            );
        }
    }

    /**
     * @notice Implements call of some operation with token
     * @dev Internal function used in metaMintSwap() and externalCall()
     * @param _token token address
     * @param _amount amount of _token
     * @param _receiveSide address of contract on which method will be called
     * @param _calldata encoded method call
     * @param _offset shift to patch the _amount to calldata
     */
    function _externalCall(
        address _token,
        uint256 _amount,
        address _receiveSide,
        bytes memory _calldata,
        uint256 _offset
    ) internal returns (bool success, bytes memory data) {
        require(_receiveSide != address(metaRouterGateway), "MetaRouter: invalid receiveSide");

        _lazyApprove(_token, _receiveSide, _amount);

        assembly {
            mstore(add(_calldata, _offset), _amount)
        }

        {
            uint256 size;
            address toCheck = _receiveSide;

            assembly {
                size := extcodesize(toCheck)
            }

            require(size != 0, "MetaRouter: call for a non-contract account");
        }

        (success, data) = _receiveSide.call(_calldata);
    }

    /**
     * @notice Implements approve
     * @dev Internal function used to approve the token spending
     * @param _token token address
     * @param _to address to approve
     * @param _amount amount for which approve will be given
     */
    function _lazyApprove(address _token, address _to, uint256 _amount) internal {
        if (IERC20(_token).allowance(address(this), _to) < _amount) {
            TransferHelper.safeApprove(_token, _to, type(uint256).max);
        }
    }
}