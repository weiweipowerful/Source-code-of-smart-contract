// SPDX-License-Identifier: MIT
// Factory: CreateMyToken (https://www.createmytoken.com)
pragma solidity 0.8.28;

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20TokenMetadata } from "@src/tokens/extensions/ERC20TokenMetadata.sol";
import { ERC20Capped } from "@vendor/oz/token/ERC20/extensions/ERC20Capped.sol";
import { ERC20Base } from "@vendor/oz/token/ERC20/ERC20.sol";
import { Pausable } from "@vendor/oz/utils/Pausable.sol";
import { Ownable } from "@vendor/oz/access/Ownable.sol";

contract UltimateTokenOwnable is Initializable, ERC20TokenMetadata, ERC20Base, ERC20Capped, Pausable, Ownable {
    function initialize(
        address _owner,
        address _mintTarget,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply,
        uint256 _maxSupply,
        string calldata tokenUri_
    ) external initializer {
        ERC20Base.__ERC20_init(_name, _symbol, _decimals);
        ERC20Capped.__ERC20Capped_init(_maxSupply);

        _transferOwnership(_owner);
        _mint(_mintTarget, _initialSupply);
        _setTokenUri(tokenUri_);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 value) public {
        _burn(_msgSender(), value);
    }

    function setTokenURI(string calldata tokenUri_) public onlyOwner {
        _setTokenUri(tokenUri_);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20Base, ERC20Capped) whenNotPaused {
        super._update(from, to, value);
    }
}