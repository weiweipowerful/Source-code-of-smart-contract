// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract TestToken is ERC20, ERC20Burnable, AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant TAX_MANAGER_ROLE = keccak256("TAX_MANAGER_ROLE");
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");

    string private tokenName;
    string private tokenSymbol;

    address public treasuryHandler;
    address public taxHandler;

    uint256 public defaultTaxRate;
    uint256 public constant MAX_TAX_RATE = 100 * 1e18; // 100% maximum tax rate
    uint256 public constant MIN_TAXABLE_AMOUNT = 100; // Minimum amount for tax calculation

    event TreasuryHandlerChanged(address indexed oldAddress, address indexed newAddress);
    event TaxHandlerChanged(address indexed oldAddress, address indexed newAddress);
    event DefaultTaxRateChanged(uint256 oldRate, uint256 newRate);
    event TokenNameChanged(string oldName, string newName);
    event TokenSymbolChanged(string oldSymbol, string newSymbol);
    event TaxCollected(address indexed from, address indexed to, uint256 indexed amount);
    event TokensBurned(address indexed burner, uint256 amount);

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply)
        ERC20(_name, _symbol)
    {
        tokenName = _name;
        tokenSymbol = _symbol;
        defaultTaxRate = 0;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(ADMIN_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _msgSender());
        _grantRole(BURNER_ROLE, _msgSender());
        _grantRole(TAX_MANAGER_ROLE, _msgSender());
        _grantRole(TREASURY_MANAGER_ROLE, _msgSender());

        _mint(_msgSender(), _initialSupply);

        emit TokenNameChanged("", _name);
        emit TokenSymbolChanged("", _symbol);
    }

    function name() public view virtual override returns (string memory) {
        return tokenName;
    }

    function symbol() public view virtual override returns (string memory) {
        return tokenSymbol;
    }

    function changeTokenName(string memory newName) external onlyRole(ADMIN_ROLE) {
        require(bytes(newName).length > 0, "Name cannot be empty");
        string memory oldName = tokenName;
        tokenName = newName;
        emit TokenNameChanged(oldName, newName);
    }

    function changeTokenSymbol(string memory newSymbol) external onlyRole(ADMIN_ROLE) {
        require(bytes(newSymbol).length > 0, "Symbol cannot be empty");
        string memory oldSymbol = tokenSymbol;
        tokenSymbol = newSymbol;
        emit TokenSymbolChanged(oldSymbol, newSymbol);
    }

    function setTreasuryHandler(address _treasuryHandler) external onlyRole(TREASURY_MANAGER_ROLE) {
        require(_treasuryHandler != address(0), "Invalid treasury handler address");
        address oldTreasuryHandler = treasuryHandler;
        treasuryHandler = _treasuryHandler;
        emit TreasuryHandlerChanged(oldTreasuryHandler, _treasuryHandler);
    }

    function setTaxHandler(address _taxHandler) external onlyRole(TAX_MANAGER_ROLE) {
        require(_taxHandler != address(0), "Invalid tax handler address");
        address oldTaxHandler = taxHandler;
        taxHandler = _taxHandler;
        emit TaxHandlerChanged(oldTaxHandler, _taxHandler);
    }

    function setDefaultTaxRate(uint256 _defaultTaxRate) external onlyRole(TAX_MANAGER_ROLE) {
        require(_defaultTaxRate <= MAX_TAX_RATE, "Tax rate exceeds maximum allowed");
        uint256 oldDefaultTaxRate = defaultTaxRate;
        defaultTaxRate = _defaultTaxRate;
        emit DefaultTaxRateChanged(oldDefaultTaxRate, _defaultTaxRate);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(uint256 amount) public virtual override onlyRole(BURNER_ROLE) {
        _burn(_msgSender(), amount);
        emit TokensBurned(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public virtual override onlyRole(BURNER_ROLE) {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        unchecked {
            _approve(account, _msgSender(), currentAllowance - amount);
        }
        _burn(account, amount);
        emit TokensBurned(account, amount);
    }

    function calculateTax(address from, address to, uint256 amount) internal returns (uint256) {
        if (amount < MIN_TAXABLE_AMOUNT) return 0;  
        
        uint256 taxAmount;
        if (taxHandler != address(0)) {
            try ITaxHandler(taxHandler).getTax(from, to, amount) returns (uint256 _taxAmount) {
                taxAmount = _taxAmount;
                if (taxAmount > amount) {
                    taxAmount = amount.sub(1);  
                }
            } catch {
                taxAmount = amount.mul(defaultTaxRate).div(1e18);
            }
        } else {
            taxAmount = amount.mul(defaultTaxRate).div(1e18);
        }
        return taxAmount;
    }

    function transferWithTax(address sender, address recipient, uint256 amount) internal nonReentrant {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "ERC20: transfer amount must be greater than zero");

        uint256 taxAmount = calculateTax(sender, recipient, amount);
        uint256 amountAfterTax = amount.sub(taxAmount);

        _transfer(sender, recipient, amountAfterTax);

        if (taxAmount > 0 && treasuryHandler != address(0)) {
            _transfer(sender, treasuryHandler, taxAmount);
            emit TaxCollected(sender, recipient, taxAmount);
        }
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        transferWithTax(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        transferWithTax(sender, recipient, amount);
        uint256 currentAllowance = allowance(sender, _msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }
        return true;
    }

}

interface ITaxHandler {
    function getTax(address from, address to, uint256 amount) external returns (uint256);
}