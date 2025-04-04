/**
 *Submitted for verification at Etherscan.io on 2024-07-05
*/

/**
 * SPDX-License-Identifier: unlicensed
 */

pragma solidity 0.8.17;

interface IRouter {
    function WETH() external pure returns (address);

    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
}

interface IERC20 {
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
}

abstract contract Auth {
    address internal _owner;
    mapping(address => bool) public isAuthorized;

    constructor(address owner) {
        _owner = owner;
    }

    function isOwner(address account) public view returns (bool) {
        return account == _owner;
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender), "Auth: owner only");
        _;
    }

    function setAuthorization(
        address address_,
        bool authorization
    ) external onlyOwner {
        isAuthorized[address_] = authorization;
    }

    modifier authorized() {
        require(isAuthorized[msg.sender], "Auth: authorized only");
        _;
    }

    event OwnershipTransferred(address owner);

    function _transferOwnership(address newOwner) internal {
        _owner = newOwner;
        emit OwnershipTransferred(newOwner);
    }

    function transferOwnership(address payable newOwner) external onlyOwner {
        require(newOwner != address(0), "Auth: owner address cannot be zero");
        _transferOwnership(newOwner);
    }

    function renounceOwnership() external onlyOwner {
        _transferOwnership(address(0));
    }
}

contract VoxRoyaleTreasury is Auth {
    address private constant router =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private weth;
    address private token;

    constructor(address tokenAddress) Auth(msg.sender) {
        require(
            tokenAddress != address(0),
            "Treasury: token address cannot be zero"
        );
        token = tokenAddress;

        bool approved = IERC20(token).approve(router, type(uint).max);
        require(approved == true, "Treasury: approve failed");

        weth = IRouter(router).WETH();
    }

    uint ratelimit = 10000 * 10 ** 18;
    uint ratelimitTimeframe = 1 hours;

    function setRatelimit(uint amount, uint time) external onlyOwner {
        require(
            time >= 15,
            "Treasury: withdraw ratelimit must be more or equal to 15 minutes"
        );

        ratelimitTimeframe = time * 1 minutes;

        require(
            amount >=
                ((1080 * 10 ** 18) / 1 hours) * ratelimitTimeframe,
            "Treasury: withdraw ratelimit amount is too low"
        );

        timeframeTotal = 0;
        ratelimit = amount;
    }

    uint timeframe;
    uint timeframeTotal;

    function withdraw(
        address to,
        uint amount,
        uint minimum,
        uint gas,
        uint deadline
    ) external authorized {
        uint currentTimeframe = block.timestamp / ratelimitTimeframe;

        if (timeframe < currentTimeframe) {
            timeframeTotal = amount;
            timeframe = currentTimeframe;
        } else {
            timeframeTotal += amount;
        }

        require(
            timeframeTotal <= ratelimit,
            "Treasury: global withdraw rate limit reached"
        );

        if (gas == 0) {
            IERC20(token).transfer(to, amount);
        } else {
            address[] memory path = new address[](2);
            path[1] = weth;
            path[0] = token;

            uint[] memory amounts = IRouter(router)
                .swapTokensForExactETH(
                    gas,
                    amount,
                    path,
                    msg.sender,
                    deadline
                );

            uint resultAmount = amount - amounts[0];
            require(
                resultAmount >= minimum,
                "Treasury: insufficient amount"
            );

            bool success = IERC20(token).transfer(to, resultAmount);
            require(success == true, "Treasury: transfer failed");
        }
    }
}