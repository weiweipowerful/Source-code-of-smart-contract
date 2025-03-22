Data Format

contract/

├── part1/ ~ part7/  

│   ├── 0x0000....4321.sol    

│   ├── 0x6A1B....feBf.sol

│   └── ...

├── address.txt      

├── source_address.txt    

├── README.md                    


Data Description

1.address.txt - records all acquired contract addresses. Each address corresponds to a folder to store its contract source code.

2.source_address.txt - records the contract address of the successfully crawled source code, which is convenient for filtering valid data.

3.Each contract address folder - named after the contract address, contains all smart contract source codes (.sol files) under the address

Applicable scenarios

1.Smart contract vulnerability detection

2.Blockchain security analysis

Notes

1.The contract data comes from the blockchain network to ensure compliance.

2.Some smart contracts may not be open source, and source_address.txt only records the address where the source code has been successfully obtained.
