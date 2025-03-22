// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

interface ISwapRouter {
    function WETH9() external pure returns (address);

    function factory() external pure returns (address);
}

interface ISwapPool {
    function factory() external pure returns (address);
}

contract HoudiniSwapToken is ERC20, Ownable2Step {
    using Address for address;
    using SafeERC20 for IERC20;

    ISwapRouter public immutable swapRouter;

    address public constant ZERO_ADDRESS = address(0);
    address public constant DEAD_ADDRESS = address(0xdead);

    bool private _ammProtectionEnabled;
    bool public launched;

    mapping(address => bool) private _isExcludedFromLimits;
    mapping(address => bool) private _automatedMarketMakerPair;
    mapping(address => bool) private _isBot;

    event Airdrop(address account, uint256 amount);
    event Launch(uint256 blockNumber, uint256 timestamp);
    event WithdrawStuckTokens(address token, uint256 amount);
    event ExcludeFromLimits(address indexed account, bool value);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SetBots(address indexed account, bool value);

    modifier onlyContract(address account) {
        require(
            account.isContract(),
            "HoudiniSwapToken: The address does not contain a contract"
        );
        _;
    }

    constructor() ERC20("Houdini Swap", "LOCK") {
        uint256 tSupply = 100_000_000 ether;

        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

        _excludeFromLimits(_msgSender(), true);
        _excludeFromLimits(address(this), true);
        _excludeFromLimits(DEAD_ADDRESS, true);
        _excludeFromLimits(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6, true); // Uniswap V3 Quoter
        _excludeFromLimits(0x61fFE014bA17989E743c5F6cB21bF9697530B21e, true); // Uniswap V3 QuoterV2

        _mint(_msgSender(), tSupply);
    }

    receive() external payable {}

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    function airdrop(
        address[] memory accounts,
        uint256[] memory amounts
    ) public onlyOwner {
        require(
            accounts.length == amounts.length,
            "HoudiniSwapToken: Arrays must be the same length"
        );
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            uint256 amount = amounts[i];
            _transfer(_msgSender(), account, amount);
            emit Airdrop(account, amount);
        }
    }

    function launch() public onlyOwner {
        require(!launched, "HoudiniSwapToken: Already launched.");
        IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(
            swapRouter.factory()
        );
        address WETH9 = swapRouter.WETH9();
        address uniswapV3Pool = uniswapV3Factory.getPool(
            address(this),
            WETH9,
            10000
        );
        if (uniswapV3Pool == ZERO_ADDRESS) {
            uniswapV3Pool = uniswapV3Factory.createPool(
                address(this),
                WETH9,
                10000
            );
        }

        _setAutomatedMarketMakerPair(address(uniswapV3Pool), true);

        _ammProtectionEnabled = true;
        launched = true;
        emit Launch(block.number, block.timestamp);
    }

    function withdrawStuckTokens(address tkn) public onlyOwner {
        uint256 amount;
        if (tkn == ZERO_ADDRESS) {
            bool success;
            amount = address(this).balance;
            (success, ) = address(_msgSender()).call{value: amount}("");
        } else {
            amount = IERC20(tkn).balanceOf(address(this));
            require(amount > 0, "HoudiniSwapToken: No tokens");
            IERC20(tkn).safeTransfer(_msgSender(), amount);
        }
        emit WithdrawStuckTokens(tkn, amount);
    }

    function excludeFromLimits(
        address[] calldata accounts,
        bool value
    ) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _excludeFromLimits(accounts[i], value);
        }
    }

    function setAutomatedMarketMakerPair(
        address account,
        bool value
    ) public onlyOwner onlyContract(account) {
        require(
            !_automatedMarketMakerPair[account],
            "HoudiniSwapToken: AMM Pair already set."
        );
        _setAutomatedMarketMakerPair(account, value);
    }

    function setBots(address[] calldata accounts, bool value) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (
                (!_automatedMarketMakerPair[accounts[i]]) &&
                (accounts[i] != address(swapRouter)) &&
                (accounts[i] != address(this)) &&
                (!_isExcludedFromLimits[accounts[i]])
            ) _setBots(accounts[i], value);
        }
    }

    function isExcludedFromLimits(address account) public view returns (bool) {
        return _isExcludedFromLimits[account];
    }

    function automatedMarketMakerPairs(
        address account
    ) public view returns (bool) {
        return _automatedMarketMakerPair[account];
    }

    function isBot(address account) public view returns (bool) {
        return _isBot[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(
            from != ZERO_ADDRESS,
            "HoudiniSwapToken: transfer from the zero address"
        );
        require(
            to != ZERO_ADDRESS,
            "HoudiniSwapToken: transfer to the zero address"
        );

        if (_isExcludedFromLimits[from] || _isExcludedFromLimits[to]) {
            super._transfer(from, to, amount);
            return;
        }

        require(!_isBot[from], "HoudiniSwapToken: bot detected");
        require(
            _msgSender() == from || !_isBot[_msgSender()],
            "HoudiniSwapToken: bot detected"
        );
        require(
            tx.origin == from ||
                tx.origin == _msgSender() ||
                !_isBot[tx.origin],
            "HoudiniSwapToken: bot detected"
        );

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        address ownr = owner();

        require(
            launched || from == ownr || to == ownr || to == DEAD_ADDRESS,
            "HoudiniSwapToken: Not launched."
        );

        _validateAddresses(from, to);

        super._transfer(from, to, amount);
    }

    function _validateAddresses(address from, address to) internal virtual {
        if (_ammProtectionEnabled) {
            if (
                !_automatedMarketMakerPair[from] &&
                !_automatedMarketMakerPair[to]
            ) {
                if (to.isContract()) {
                    try ISwapPool(to).factory() returns (address factory) {
                        require(
                            factory == ZERO_ADDRESS,
                            "HoudiniSwapToken: AMM not supported."
                        );
                    } catch {}
                }

                if (from.isContract()) {
                    try ISwapPool(from).factory() returns (address factory) {
                        require(
                            factory == ZERO_ADDRESS,
                            "HoudiniSwapToken: AMM not supported."
                        );
                    } catch {}
                }
            }
        }
    }

    function _excludeFromLimits(address account, bool value) internal virtual {
        _isExcludedFromLimits[account] = value;
        emit ExcludeFromLimits(account, value);
    }

    function _setBots(address account, bool value) internal virtual {
        _isBot[account] = value;
        emit SetBots(account, value);
    }

    function _setAutomatedMarketMakerPair(
        address account,
        bool value
    ) internal virtual {
        _automatedMarketMakerPair[account] = value;
        emit SetAutomatedMarketMakerPair(account, value);
    }
}