import "lib/forge-std/src/mocks/MockERC20.sol";
import "contracts/external/openzeppelin/contracts/access/Ownable.sol";

contract TestPYUSD is MockERC20, Ownable {
  constructor() Ownable() {
    initialize("Test PayPal USD", "t-PYUSD", 6);
  }

  function mint(address to, uint256 value) public onlyOwner {
    _mint(to, value);
  }

  function burn(address from, uint256 value) public onlyOwner {
    _burn(from, value);
  }
}