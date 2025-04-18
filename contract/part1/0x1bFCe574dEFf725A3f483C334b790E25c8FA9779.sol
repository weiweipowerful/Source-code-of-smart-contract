// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;
/*********************************************************************************************************************|
|                                                                                                                     |
|              τττττττττττττττττττ       ττττττττττττττττττττττττττττττττττττττττττττττττττττττττττττ     τττττ       |
|           ττττττττττττττττττττ      τττττττττττττττττττττττττττττττττττττττττττττττττττττττττττττττ     τττττ       |
|         τττττττ                   τττττττ                                τττττ                          τττττ       |
|         τττττ                    ττττττ                                  τττττ                          τττ         |
|        ττττττ                    ττττττ                                  τττττ                                      |
|        ττττττ                    τττττττττττττττττττττττττττ             τττττ                              τ       |
|        ττττττ                    τττττττττττττττττττττττττττ             τττττ                            τττ       |
|        ττττττ                    ττττττ                                  τττττ                          τττττ       |
|        ττττττ                    ττττττ                                  τττττ                          τττττ       |
|         ττττττ                    ττττττ                                 ττττττ         τττττττττ       τττττ       |
|          ττττττττττττττττττττ      τττττττττττττττττττττττττττττττττ      ττττττττττττττττττττ          τττττ       |
|            ττττττττττττττττττττ      τττττττττττττττττττττττττττττττ        τττττττττττττττ             τττττ       |       
|                 ττττττττττττττττ          ττττττττττττττττττττττττττ             τττττ                  τττττ       |
|                                                                                                                     |
**********************************************************************************************************************|
|                                                                                                                     |
|                     PER MARE                         PER TERRAS                        PER CONSTELLATUM             |
|                                                                                                                     |
**********************************************************************************************************************|
|                                                                                                                     |
|        @notice Modern and gas efficient ERC20 + EIP-2612 implementation with ownership and a tax.                   |
|        @author Ceτɩ https://taoceti.ai                                                                              |
|        @author Modified from Solmate                                                                                |
|                                                                                                                     |
**********************************************************************************************************************/
contract CETI {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    error NOT_OWNER();
    error PERMIT_DEADLINE_EXPIRED();
    error INVALID_SIGNER();
    error MAX_BUY_AMOUNT_EXCEEDED();
    error MAX_WALLET_AMOUNT_EXCEEDED();
    error FEE_WILLY_HIGH();
    error DO_LITTLE();
    error GAMES_OVER();

    string public name = "Tao Ce\u03C4i";
    string public symbol = "CETI";
    uint8 public immutable decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    uint256 public sellFee = 5;
    uint256 public buyAndTransferFee = 5;
    uint256 public maxBuyAmount = totalSupply / 300;
    address public feeReceiver;

    mapping(address => bool) internal _isExcludedFromFee;
    
    address public owner;

    bool public whackAMole = true;

    modifier onlyOwner() {
        if(msg.sender != owner)
            revert NOT_OWNER();
        _;
    }

    constructor() {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
        owner = msg.sender;
        feeReceiver = owner;
        _isExcludedFromFee[owner] = true;
        _mint(owner, 21_000_000 ether);
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;
        unchecked {
            if(!_isExcludedFromFee[to] && !_isExcludedFromFee[msg.sender]){
                    uint fee = (amount * buyAndTransferFee) / 100;
                    if(whackAMole) {
                        if(amount > maxBuyAmount)
                            revert MAX_BUY_AMOUNT_EXCEEDED();
                        if(balanceOf[to] + amount > maxBuyAmount * 3)
                            revert MAX_WALLET_AMOUNT_EXCEEDED();
                    }
                    amount -= fee;
                    balanceOf[to] += amount;
                    balanceOf[feeReceiver] += fee;
                    emit Transfer(msg.sender, feeReceiver, fee);
            }
            else
                balanceOf[to] += amount;
        }
        if (to == address(0)) {
            unchecked {
                totalSupply -= amount;
            }
        }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;
        unchecked {
            uint fee;
            if(!_isExcludedFromFee[to] && !_isExcludedFromFee[from]){
                fee = (amount * sellFee) / 100;            
                amount -= fee;
                balanceOf[to] += amount;
                balanceOf[feeReceiver] += fee;
                emit Transfer(from, feeReceiver, fee);
            }
            else
                balanceOf[to] += amount;
        }
        if (to == address(0)) {
            unchecked {
                totalSupply -= amount;
            }
        }
        emit Transfer(from, to, amount);
        return true;
    }

    function permit(
        address owner_,
        address spender_,
        uint256 value_,
        uint256 deadline_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) public virtual {
        if(deadline_ < block.timestamp)
            revert PERMIT_DEADLINE_EXPIRED();
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                   "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner_,
                                spender_,
                                value_,
                                nonces[owner]++,
                                deadline_
                            )
                        )
                    )
                ),
                v_,
                r_,
                s_
            );
            if(recoveredAddress == address(0) || recoveredAddress != owner_)
                revert INVALID_SIGNER();
            allowance[recoveredAddress][spender_] = value_;
        }
        emit Approval(owner_, spender_, value_);
    }

    function setFeeReceiver(address feeReceiver_) public onlyOwner {
        _isExcludedFromFee[feeReceiver_] = true;
        feeReceiver = feeReceiver_;
    }

    function renounceOwnership() public onlyOwner {
        owner = address(0);
        _isExcludedFromFee[msg.sender] = false;
        emit OwnershipTransferred(owner, address(0));
    }

    function transferOwnership(address newOwner_) public onlyOwner {
        address oldOwner = owner;
        _isExcludedFromFee[oldOwner] = false;
        owner = newOwner_;
        _isExcludedFromFee[owner] = true;
        emit OwnershipTransferred(oldOwner, newOwner_);
    }

    function setFees(uint256 _buyAndTransferFee, uint256 _sellFee) public onlyOwner {
        if( buyAndTransferFee > 35 || sellFee > 35)
            revert FEE_WILLY_HIGH();
        buyAndTransferFee = _buyAndTransferFee;
        sellFee = _sellFee;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFee[account] = excluded;
    }

    function setMaxBuyAmount(uint256 _maxBuyAmount) public onlyOwner {
        if(_maxBuyAmount < totalSupply / 300)
            revert DO_LITTLE();
        maxBuyAmount = _maxBuyAmount;
        maxBuyAmount = totalSupply;
    }

    function turnOffMaxBuyAmount() public onlyOwner {
        if(!whackAMole)
            revert GAMES_OVER();
        whackAMole = false;
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID
                ? INITIAL_DOMAIN_SEPARATOR
                : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}
//                                    0xCE71cd1CeA29f9849844462bE12b9bC3E62F5AF1                                     \\