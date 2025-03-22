// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IFee } from "./Fee.sol";

// Mirada AI & LightLink 2024

contract MiradaToken is Ownable, ERC20 {
  using SafeERC20 for IERC20;

  address public feeContract = 0x87f9327BA01E169391EDF91177210539FdDeCFB4;

  constructor() ERC20("Mirada AI", "$MIRX") {
    _mint(0xc8cB6871694a429991873688641e7A627e8Db73f, 1_000_000_000 * (10 ** decimals()));
  }

  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    if (feeContract == address(0) || IFee(feeContract).masterAccount() == address(0)) {
      return super.transfer(to, amount);
    }

    address owner = _msgSender();
    address master = IFee(feeContract).masterAccount();
    (uint256 fee, uint256 receipts) = IFee(feeContract).extractFee(owner, amount);
    _transfer(owner, master, fee);
    _transfer(owner, to, receipts);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
    if (feeContract == address(0) || IFee(feeContract).masterAccount() == address(0)) {
      return super.transferFrom(from, to, amount);
    }

    address spender = _msgSender();
    _spendAllowance(from, spender, amount);
    address master = IFee(feeContract).masterAccount();
    (uint256 fee, uint256 receipts) = IFee(feeContract).extractFee(spender, amount);
    _transfer(from, master, fee);
    _transfer(from, to, receipts);
    return true;
  }

  /* Admin */
  function setFeeContract(address _contract) public onlyOwner {
    feeContract = _contract;
  }

  // support in case of accidental user transfers of Token to the contract
  function withdrawToken(address _token, uint256 _amount) public onlyOwner {
    IERC20(_token).safeTransfer(msg.sender, _amount);
  }
}