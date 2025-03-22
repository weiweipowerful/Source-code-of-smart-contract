// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "openzeppelin/contracts/access/Ownable.sol";
import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "openzeppelin/contracts/token/ERC721/ERC721.sol";
import "openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "openzeppelin/contracts/utils/Counters.sol";
import "openzeppelin/contracts/utils/Strings.sol";

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

/**
 * @title SafeERC20
 * @dev Wrappers around ERC-20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    /**
     * @dev An operation with an ERC-20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeCall(token.transferFrom, (from, to, value))
        );
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturnBool} that reverts if call fails to meet the requirements.
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(
                gas(),
                token,
                0,
                add(data, 0x20),
                mload(data),
                0,
                0x20
            )
            // bubble errors
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (
            returnSize == 0 ? address(token).code.length == 0 : returnValue != 1
        ) {
            revert SafeERC20FailedOperation(address(token));
        }
    }
}

contract KenduChad is Ownable, ERC721Enumerable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using Strings for uint256;
    using SafeERC20 for IERC20;

    IERC20 public kenduTokenAddress;
    address public treasuryWallet;

    constructor() ERC721("KenduChad", "KenduChad") {
        kenduTokenAddress = IERC20(0xaa95f26e30001251fb905d264Aa7b00eE9dF6C18); // replace your ERC20 Token address
        treasuryWallet = address(0x9c1BB5F5954fDC36561e50a4A6AcbF634BCcc5E5); // replace your wallet address, where you will receive fees
    }

    bool public isSaleOn = false;
    bool public saleHasBeenStarted = false;

    uint256 public maxMintableAtOnce = 10; // max 10 mint at once

    uint256[10000] private _availableTokens;
    uint256 private _numAvailableTokens = 10000;
    uint256 private _numFreeRollsGiven = 0;

    mapping(address => uint256) public freeRollkenduChads;

    uint256 private _lastTokenIdMintedInInitialSet = 10000;

    function numTotalkenduChads() public view virtual returns (uint256) {
        return 10000;
    }

    function mintWithFreeRoll() public nonReentrant {
        uint256 toMint = freeRollkenduChads[msg.sender];
        freeRollkenduChads[msg.sender] = 0;
        uint256 remaining = numTotalkenduChads() - totalSupply();
        if (toMint > remaining) {
            toMint = remaining;
        }
        _mint(toMint);
    }

    function getNumFreeRollkenduChads(
        address owner
    ) public view returns (uint256) {
        return freeRollkenduChads[owner];
    }

    function mint(uint256 _numToMint) public nonReentrant {
        require(isSaleOn, "Sale hasn't started.");
        uint256 totalSupply = totalSupply();
        require(
            totalSupply + _numToMint <= numTotalkenduChads(),
            "There aren't this many kenduChads left."
        );
        uint256 costForMintingkenduChads = getCostForMintingkenduChads(
            _numToMint
        );

        // not necessary to check allownace or balance
        // Transfer the cost to this contract
        kenduTokenAddress.safeTransferFrom(
            msg.sender,
            address(this),
            costForMintingkenduChads
        );

        // Transfer the costForMintingkenduChads amount to the fee recipient from contract
        kenduTokenAddress.safeTransfer(
            treasuryWallet,
            costForMintingkenduChads
        );

        // Proceed with minting the kenduChads
        _mint(_numToMint);
    }

    // internal minting function
    function _mint(uint256 _numToMint) internal {
        require(_numToMint <= maxMintableAtOnce, "Minting too many at once.");

        uint256 updatedNumAvailableTokens = _numAvailableTokens;
        for (uint256 i = 0; i < _numToMint; i++) {
            uint256 newTokenId = useRandomAvailableToken(_numToMint, i);
            _safeMint(msg.sender, newTokenId);
            updatedNumAvailableTokens--;
        }
        _numAvailableTokens = updatedNumAvailableTokens;
    }

    function useRandomAvailableToken(
        uint256 _numToFetch,
        uint256 _i
    ) internal returns (uint256) {
        uint256 randomNum = uint256(
            keccak256(
                abi.encode(
                    msg.sender,
                    tx.gasprice,
                    block.number,
                    block.timestamp,
                    blockhash(block.number - 1),
                    _numToFetch,
                    _i
                )
            )
        );
        uint256 randomIndex = randomNum % _numAvailableTokens;
        return useAvailableTokenAtIndex(randomIndex);
    }

    function useAvailableTokenAtIndex(
        uint256 indexToUse
    ) internal returns (uint256) {
        uint256 valAtIndex = _availableTokens[indexToUse];
        uint256 result;
        if (valAtIndex == 0) {
            // This means the index itself is still an available token
            result = indexToUse;
        } else {
            // This means the index itself is not an available token, but the val at that index is.
            result = valAtIndex;
        }

        uint256 lastIndex = _numAvailableTokens - 1;
        if (indexToUse != lastIndex) {
            // Replace the value at indexToUse, now that it's been used.
            // Replace it with the data from the last index in the array, since we are going to decrease the array size afterwards.
            uint256 lastValInArray = _availableTokens[lastIndex];
            if (lastValInArray == 0) {
                // This means the index itself is still an available token
                _availableTokens[indexToUse] = lastIndex;
            } else {
                // This means the index itself is not an available token, but the val at that index is.
                _availableTokens[indexToUse] = lastValInArray;
            }
        }

        _numAvailableTokens--;
        return result;
    }

    function getCostForMintingkenduChads(
        uint256 _numToMint
    ) public view returns (uint256) {
        require(
            totalSupply() + _numToMint <= numTotalkenduChads(),
            "There aren't this many kenduChads left."
        );
        if (_numToMint >= 1 && _numToMint <= maxMintableAtOnce) {
            return 5_000_000 * _numToMint * 10 ** 18; // 5M Kendu Tokens equivalent in tokens per nft upto 10 nfts, adjust based on token decimals
        } else {
            revert("Unsupported mint amount");
        }
    }

    function getkenduChadsBelongingToOwner(
        address _owner
    ) external view returns (uint256[] memory) {
        uint256 numkenduChads = balanceOf(_owner);
        if (numkenduChads == 0) {
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](numkenduChads);
            for (uint256 i = 0; i < numkenduChads; i++) {
                result[i] = tokenOfOwnerByIndex(_owner, i);
            }
            return result;
        }
    }

    /*
     * Dev stuff.
     */

    // metadata URI
    string private _baseTokenURI;

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        string memory base = _baseURI();
        string memory _tokenURI = string(
            abi.encodePacked(Strings.toString(_tokenId), ".png")
        );

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }

        return string(abi.encodePacked(base, _tokenURI));
    }

    // contract metadata URI for opensea
    string public contractURI;

    /*
     * Owner stuff
     */

    function startSale() public onlyOwner {
        isSaleOn = true;
        saleHasBeenStarted = true;
    }

    function endSale() public onlyOwner {
        isSaleOn = false;
    }

    function updateTreasuryWallet(address _treasuryWallet) public onlyOwner {
        treasuryWallet = _treasuryWallet;
    }

    function updateMaxMintableOnce(
        uint256 _maxMintableAtOnce
    ) public onlyOwner {
        maxMintableAtOnce = _maxMintableAtOnce;
    }

    function giveFreeRoll(address receiver) public onlyOwner {
        // max number of free mints we can give to the community for promotions/marketing
        require(
            _numFreeRollsGiven < 200,
            "already given max number of free rolls"
        );
        uint256 freeRolls = freeRollkenduChads[receiver];
        freeRollkenduChads[receiver] = freeRolls + 1;
        _numFreeRollsGiven = _numFreeRollsGiven + 1;
    }

    // for handing out free rolls to v1 chad owners
    // details on seeding info here: https://gist.github.com/cryptopmens/7f542feaee510e12464da3bb2a922713
    function seedFreeRolls(
        address[] calldata tokenOwners,
        uint256[] calldata numOfFreeRolls
    ) public onlyOwner {
        require(
            !saleHasBeenStarted,
            "cannot seed free rolls after sale has started"
        );
        require(
            tokenOwners.length == numOfFreeRolls.length,
            "tokenOwners does not match numOfFreeRolls length"
        );

        for (uint256 i = 0; i < tokenOwners.length; i++) {
            // check to make sure the proper values are being passed
            require(
                numOfFreeRolls[i] <= 3,
                "cannot give more than 3 free rolls"
            );

            freeRollkenduChads[tokenOwners[i]] = numOfFreeRolls[i];
        }
    }

    // for seeding the v2 contract with v1 state
    // details on seeding info here: https://gist.github.com/cryptopmens/7f542feaee510e12464da3bb2a922713
    function seedInitialContractState(
        address[] calldata tokenOwners,
        uint256[] calldata tokens
    ) public onlyOwner {
        require(
            !saleHasBeenStarted,
            "cannot initial chad mint if sale has started"
        );
        require(
            tokenOwners.length == tokens.length,
            "tokenOwners does not match tokens length"
        );

        uint256 lastTokenIdMintedInInitialSetCopy = _lastTokenIdMintedInInitialSet;
        for (uint256 i = 0; i < tokenOwners.length; i++) {
            uint256 token = tokens[i];
            require(
                lastTokenIdMintedInInitialSetCopy > token,
                "initial chad mints must be in decreasing order for our availableToken index to work"
            );
            lastTokenIdMintedInInitialSetCopy = token;

            useAvailableTokenAtIndex(token);
            _safeMint(tokenOwners[i], token);
        }
        _lastTokenIdMintedInInitialSet = lastTokenIdMintedInInitialSetCopy;
    }

    // URIs, uri should end with trailing slash for ex. https://example.com/images/
    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function setContractURI(string calldata _contractURI) external onlyOwner {
        contractURI = _contractURI;
    }

    function withdrawMoney() public payable onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}