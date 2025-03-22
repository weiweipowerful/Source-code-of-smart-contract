//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './erc404/ERC404.sol';
import './erc404/Strings.sol';

contract LoongCity is ERC404 {
    string public dataURI;
    string public baseTokenURI;
    uint epoch = 0; // 0-not start 1-start 2-end

    mapping(address => uint) userHasMinted;
    mapping (address => bool) public whitelists;

    mapping(uint => address) public mintIndex;

    uint public totalMinted;

    constructor() ERC404('LoongCity', 'LoongCity', 18, 210000000, msg.sender) {
        balanceOf[address(this)] = 210000000 * 10 ** 18;
        whitelist[msg.sender] = true;
        whitelist[address(this)] = true;
    }

    function withdraw() public onlyOwner {
        uint balance = balanceOf[address(this)];
        balanceOf[address(this)] = 0;
        balanceOf[owner] += balance;
    }

    function withdrawETH() public onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    function setEpoch(uint _epoch) public onlyOwner {
        epoch = _epoch;
    }

    function setWhitelist(address[] calldata users) public onlyOwner {
        for(uint i=0;i<users.length;){

            whitelists[users[i]] = true;
            unchecked{
                i++;
            }
        }
    }

    function mint(uint256 _amount) public payable {
        require(epoch != 0, 'Minting is not start');
        require(
            balanceOf[address(this)] >= _amount * _getUnit(),
            'Not enough balance of pool'
        );
        require((totalMinted + _amount) < 21000, 'Not enough NFTs');

        if (epoch == 1) {
            require(whitelists[msg.sender], 'You are not in whitelist');
            require(_amount == 1, 'Minting amount must be 1');
            require(userHasMinted[msg.sender] == 0, 'You have already minted');
            _transfer(address(this),msg.sender, _getUnit());
            userHasMinted[msg.sender] += 1;
            _updateMintIndex(_amount);
            totalMinted += 1;
        }

        if (epoch == 2) {
            require(
                _amount >= 1 && _amount <= 20,
                'Minting amount must be between 1 and 20'
            );
            require(
                (userHasMinted[msg.sender] + _amount) <= 20,
                'You have already minted'
            );
            require((_amount * 0.01688 ether) == msg.value, 'Incorrect ETH value');
            _transfer(address(this),msg.sender, _getUnit() * _amount);
            userHasMinted[msg.sender] += _amount;
            _updateMintIndex(_amount);
            totalMinted += _amount;
        }
    }

    function _updateMintIndex(uint _amount) internal {
         for (uint i = totalMinted; i < (totalMinted + _amount); ) {
            mintIndex[i] = msg.sender;
            unchecked {
                i++;
            }
        }
    }

    function setDataURI(string memory _dataURI) public onlyOwner {
        dataURI = _dataURI;
    }

    function setTokenURI(string memory _tokenURI) public onlyOwner {
        baseTokenURI = _tokenURI;
    }

    function setNameSymbol(
        string memory _name,
        string memory _symbol
    ) public onlyOwner {
        _setNameSymbol(_name, _symbol);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (bytes(baseTokenURI).length > 0) {
            return string.concat(baseTokenURI, Strings.toString(id));
        } else {
            return 'https://loongcity.4everland.store/box.jpg';
        }
    }
}