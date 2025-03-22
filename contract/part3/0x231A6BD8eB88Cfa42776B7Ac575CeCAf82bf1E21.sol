//        .                                        .                                                         .   
// Name: Beraplug Coin                . ..           .                                                           
// Ticker: PLUG                 .                       .    .  .        .                                       
//       .                                                                                       .               
//           .                    ..             .            .                                              .   
//                                                                              .                 .           .  
//    .               ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░      .           
//                    ░       ░░        ░       ░░░      ░░       ░░  ░░░░░░░  ░░░░  ░░      ░░                  
//                    ▒  ▒▒▒▒  ▒  ▒▒▒▒▒▒▒  ▒▒▒▒  ▒  ▒▒▒▒  ▒  ▒▒▒▒  ▒  ▒▒▒▒▒▒▒  ▒▒▒▒  ▒  ▒▒▒▒▒▒▒  .          .    
//              .     ▓       ▓▓      ▓▓▓       ▓▓  ▓▓▓▓  ▓       ▓▓  ▓▓▓▓▓▓▓  ▓▓▓▓  ▓  ▓▓▓   ▓.                 
//      .         .   █  ████  █  ███████  ███  ██        █  ███████  ███████  ████  █  ████  █    .         .   
// .                  █       ██        █  ████  █  ████  █  ███████        ██      ███      ██          .     . 
//                    █████████████████████████████████████████████████████████████████████████     .          . 
//       .                                                .                            .                         
//                                                     ..-----. .                                                
//                    .                           .  .----------..     .                            .            
//                                     .            .-------------             .     .            .              
//                   .             .               .---------------.           .     .                       .   
//         .          .          .                .-----------------.                                   .        
//                                                -------------------.            .                           .  
//           .                   .               ---------------------.                                          
// .                                            .----------------------            .        .          ..        
//  .                               .          .-----------------------.   .                         .           
//           .                                .-------------------------.                      .                 
//                                            ---------------------------.       ..                           .  
//                                        .  .---------------------------.                             .      .  
//                                          .------------------------......                                      
//                                          -.+##...---------------...-#-.-   .              .                   
//                       .                 .-..#+....------------..+.###-.-.                              .      
//           .              .              --....-...------------.......---.                                     
//  .              .                      .------....--+#######-------------.                                    
//                           ..           .----------############+----------.               .                    
//    .                                   ----------###############----------            .                       
//                       .               .---------#################+--------       ..                    .      
//                                       .--------#####+-.     ..+####-------.                              .    
//              .           .            .--------###.      .      ####------.                                   
// .    .                                 -------+####-           -####+-----.   .              .                
//  .         .                           .------+######+..    .-#######-----                   .     .          
//                         .         .    .-------+##########+++++####+-----.        .      .     .              
// .                                       .-----------++###########-------.     .          .               .    
//     .                                     .----------+########+------.                .                       
//                           .                 ..--------------------..                          .               
//                                                  .--------------.                 .       . . .               
//    .                  .          .                ..----------.                             .    . .          
//                             ..                  ###----------.##+            .                                
//              .                             .-+###+#.---------.++##++..              .                         
//                                          +#########-.-------..#########.                                      
//               .    .        .           .++++++++#####+++++####+++++++++                                      
//        .                                        .+#+-+-#+#+++##-.                              .     .       .
//                                                  -####++####+#+.        .                                     
//         .                        .    ..   .      .-----------.               .          .                    
//                       .       .                                            .                         .        
//          .                    ██████████████████████████████████████████████████                             
//               .               ██      ███  ████  ███      ███  ████  ███      ██                              
//                               █  ████████  ████  ██  ████  ██  ███  ███  ███████     .                        
//                               ▓▓      ▓▓▓  ▓▓▓▓  ▓▓  ▓▓▓▓▓▓▓▓     ▓▓▓▓▓▓      ▓▓                              
//                        .      ▒▒▒▒▒▒▒  ▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒▒  ▒▒▒  ▒▒▒▒▒▒▒▒▒  ▒                     .        
//                      .        ░░      ░░░░      ░░░░      ░░░  ░░░░  ░░░      ░░                 .            
//      .                        ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░        .         .      .    
//                                                                           .                                .  
//                  .                            .         .    .                .            .          .     ..
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@layerzerolabs/solidity-examples/contracts/token/oft/v2/fee/OFTWithFee.sol";

contract Beraplug is Ownable, OFTWithFee {
    address public taxWallet; // establish a tax wallet to receive fees
    uint16 public taxPct; // establish a tax rate
    uint16 public burnPct; // establish a burn rate
    bool private _transfersUnrestricted = false;

    mapping(address => bool) _isExemptFromFee; // establish list of addresses exempt from tax
    mapping(address => bool) _allowlist; // establish list of addresses who can transfer while _transfersUnrestricted is false
    mapping(uint16 => bool) public chainIdSendingEnabled; // establish list of chains this contract can send to


    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _sharedDecimals,
        address _lzEndpoint
    ) OFTWithFee(_name, _symbol, _sharedDecimals, _lzEndpoint) {
        taxWallet = _msgSender(); // set tax wallet to the depoyer
        taxPct = 80;
        burnPct = 1;
        _mint(_msgSender(), 3.3e9 * 1e18); // initial supply = 3.3 billion plugs
    }

    // change tax wallet
    function setTaxWallet(address _taxWallet) external onlyOwner {
        require(_taxWallet != address(0), "Invalid taxWallet address"); // make sure taxWallet is not the 0 address
        taxWallet = _taxWallet;
    }

    // change total tax taken from transactions
    function setTaxRate(uint16 _taxPct) external onlyOwner {
        require(_taxPct >= 0, "tax rate cannot be negative");
        require(_taxPct <= 100, "tax rate cannot be more than 100%");
        taxPct = _taxPct;
    }

    // change amount to burn from total tax
    function setBurnRate(uint16 _burnPct) external onlyOwner {
        require(_burnPct >= 0, "burn rate cannot be negative");
        require(_burnPct <= taxPct, "burn rate cannot be more than tax rate");
        burnPct = _burnPct;
    }

    // change tax exemption list
    function setFeeExemption(address account, bool exempt) public onlyOwner {
        _isExemptFromFee[account] = exempt;
    }

    // change transfer allowlist
    function setAllowlist(address account, bool allow) public onlyOwner {
        _allowlist[account] = allow;
    }

    // enable unrestricted transfers
    function enableUnrestrictedTransfers() public onlyOwner {
        _transfersUnrestricted = true;
    }

    function setChainIdSending(uint16 _dstChainId, bool enable) public onlyOwner {
        chainIdSendingEnabled[_dstChainId] = enable;
    }

    // do not call this function
    function _ooga() public pure returns (string memory) {
        return "booga";
    }

    // definitely do not call this function
    function _plug() public pure returns (string memory) {
        return "sucks";
    }

    // override transfer function to add tax & logic
    function _transfer(address sender, address recipient, uint256 _amount) internal override {
        // Check if transfers are unrestricted or sender is allowlisted
        require(_transfersUnrestricted || _allowlist[sender], "Transfers are restricted to allowlisted addresses");

        uint256 amount = _amount;

        if (!_isExemptFromFee[sender] && !_isExemptFromFee[recipient]) {
            uint256 burnAmt = amount * burnPct / 100;
            _burn(sender, burnAmt);

            uint256 taxAmt = amount * taxPct / 100;
            uint payableTax = taxAmt - burnAmt;
            super._transfer(sender, taxWallet, payableTax);

            amount -= taxAmt;
        }
        super._transfer(sender, recipient, amount);
    }

    // override LZ sendFrom to require chainIdSendingEnabled
    function sendFrom(
        address _from, 
        uint16 _dstChainId, 
        bytes32 _toAddress, 
        uint _amount, 
        uint _minAmount, 
        LzCallParams calldata _callParams
    ) public payable override {
        require(chainIdSendingEnabled[_dstChainId], "Sending to this chain ID is disabled");
        (_amount,) = _payOFTFee(_from, _dstChainId, _amount);
        _amount = _send(_from, _dstChainId, _toAddress, _amount, _callParams.refundAddress, _callParams.zroPaymentAddress, _callParams.adapterParams);
        require(_amount >= _minAmount, "BaseOFTWithFee: amount is less than minAmount");
    }

}