// SPDX-License-Identifier: -- BCOM --

pragma solidity =0.8.25;

import "./IERC20.sol";
import "./MerkleProof.sol";

error InvalidClaim();
error InvalidAmount();
error AlreadyCreated();
error AlreadyClaimed();

/**
  * @title Verse Merkle Airdrop
  * @author Vitally Marinchenko
  */

contract VerseAirdrop {

    uint256 public rewardsCount;
    uint256 public totalRequired;
    uint256 public totalCollected;
    uint256 public latestRootAdded;

    address public masterAccount;
    address public workerAccount;

    struct Reward {
        bytes32 root;
        uint256 total;
        uint256 claimed;
        uint256 created;
    }

    IERC20 public immutable REWARD_TOKEN;

    mapping(uint256 => string) public ipfsData;
    mapping(bytes32 => Reward) public rewardsData;

    mapping(bytes32 => mapping(address => bool)) public hasClaimed;

    modifier onlyMaster() {
        require(
            msg.sender == masterAccount,
            "VerseRewards: INVALID_MASTER"
        );
        _;
    }

    modifier onlyWorker() {
        require(
            msg.sender == workerAccount,
            "VerseRewards: INVALID_WORKER"
        );
        _;
    }

    event Deposit(
        address indexed account,
        uint256 amount
    );

    event Withdraw(
        address indexed account,
        uint256 amount
    );

    event NewRewards(
        bytes32 indexed hash,
        address indexed master,
        string indexed ipfsAddress,
        uint256 total
    );

    event Claimed(
        uint256 indexed index,
        address indexed account,
        uint256 amount
    );

    event Thanks(
        address indexed account,
        uint256 indexed amount
    );

    event DestroyedRewards(
        bytes32 indexed hash,
        address indexed master,
        string indexed ipfsAddress,
        uint256 total
    );

    receive()
        external
        payable
    {
        payable(masterAccount).transfer(
            msg.value
        );

        emit Thanks(
            msg.sender,
            msg.value
        );
    }

    constructor(
        address _rewardToken,
        address _masterAccount,
        address _workerAccount
    ) {
        REWARD_TOKEN = IERC20(
            _rewardToken
        );

        masterAccount = _masterAccount;
        workerAccount = _workerAccount;
    }

    function createRewards(
        bytes32 _root,
        uint256 _total,
        string calldata _ipfsAddress
    )
        external
        onlyMaster
    {
        if (_total == 0) {
            revert InvalidAmount();
        }

        bytes32 ipfsHash = getHash(
            _ipfsAddress
        );

        if (rewardsData[ipfsHash].total > 0) {
            revert AlreadyCreated();
        }

        rewardsData[ipfsHash] = Reward({
            root: _root,
            total: _total,
            created: block.timestamp,
            claimed: 0
        });

        rewardsCount =
        rewardsCount + 1;

        ipfsData[rewardsCount] = _ipfsAddress;

        totalRequired =
        totalRequired + _total;

        latestRootAdded = block.timestamp;

        emit NewRewards(
            _root,
            masterAccount,
            _ipfsAddress,
            _total
        );
    }

    function destroyRewards(
        uint256 _index,
        string calldata ipfsAddress
    )
        external
        onlyMaster
    {
        bytes32 ipfsHash = getHash(
            ipfsAddress
        );

        Reward storage reward = rewardsData[
            ipfsHash
        ];

        totalRequired =
        totalRequired - (reward.total - reward.claimed);

        delete ipfsData[
            _index
        ];

        delete rewardsData[
            ipfsHash
        ];

        emit DestroyedRewards(
            ipfsHash,
            masterAccount,
            ipfsData[_index],
            reward.total
        );
    }

    function getHash(
        string calldata _ipfsAddress
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                _ipfsAddress
            )
        );
    }

    function isClaimed(
        bytes32 _hash,
        address _account
    )
        public
        view
        returns (bool)
    {
        return hasClaimed[_hash][_account];
    }

    function isClaimedBulk(
        bytes32[] calldata _hash,
        address _account
    )
        external
        view
        returns (bool[] memory)
    {
        uint256 i;
        uint256 l = _hash.length;
        bool[] memory result = new bool[](l);

        while (i < l) {
            result[i] = isClaimed(
                _hash[i],
                _account
            );

            unchecked {
                ++i;
            }
        }

        return result;
    }

    function getClaim(
        bytes32 _hash,
        uint256 _index,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    )
        external
    {
        _doClaim(
            _hash,
            _index,
            _amount,
            msg.sender,
            _merkleProof
        );
    }

    function getClaimBulk(
        bytes32[] calldata _hash,
        uint256[] calldata _index,
        uint256[] calldata _amount,
        bytes32[][] calldata _merkleProof
    )
        external
    {
        uint256 i;
        uint256 l = _hash.length;

        while (i < l) {
            _doClaim(
                _hash[i],
                _index[i],
                _amount[i],
                msg.sender,
                _merkleProof[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    function giveClaim(
        bytes32 _hash,
        uint256 _index,
        uint256 _amount,
        address _account,
        bytes32[] calldata _merkleProof
    )
        external
        onlyWorker
    {
        _doClaim(
            _hash,
            _index,
            _amount,
            _account,
            _merkleProof
        );
    }

    function giveClaimBulk(
        bytes32[] calldata _hash,
        uint256[] calldata _index,
        uint256[] calldata _amount,
        address[] calldata _account,
        bytes32[][] calldata _merkleProof
    )
        external
        onlyWorker
    {
        uint256 i;
        uint256 l = _hash.length;

        while (i < l) {
            _doClaim(
                _hash[i],
                _index[i],
                _amount[i],
                _account[i],
                _merkleProof[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    function _doClaim(
        bytes32 _hash,
        uint256 _index,
        uint256 _amount,
        address _account,
        bytes32[] calldata _merkleProof
    )
        private
    {
        if (isClaimed(_hash, _account) == true) {
            revert AlreadyClaimed();
        }

        bytes32 node = keccak256(
            abi.encodePacked(
                _index,
                _account,
                _amount
            )
        );

        require(
            MerkleProof.verify(
                _merkleProof,
                rewardsData[_hash].root,
                node
            ),
            "VerseRewards: INVALID_PROOF"
        );

        totalCollected =
        totalCollected + _amount;

        rewardsData[_hash].claimed =
        rewardsData[_hash].claimed + _amount;

        if (rewardsData[_hash].claimed > rewardsData[_hash].total) {
            revert InvalidClaim();
        }

        _setClaimed(
            _hash,
            _account
        );

        REWARD_TOKEN.transfer(
            _account,
            _amount
        );

        emit Claimed(
            _index,
            _account,
            _amount
        );
    }

    function _setClaimed(
        bytes32 _hash,
        address _account
    )
        private
    {
        hasClaimed[_hash][_account] = true;
    }

    function donateFunds(
        uint256 _donationAmount
    )
        external
    {
        if (_donationAmount == 0) {
            revert InvalidAmount();
        }

        REWARD_TOKEN.transferFrom(
            msg.sender,
            address(this),
            _donationAmount
        );

        emit Deposit(
            msg.sender,
            _donationAmount
        );
    }

    function withdrawEth(
        uint256 _amount
    )
        external
        onlyMaster
    {
        payable(
            masterAccount
        ).transfer(
            _amount
        );

        emit Withdraw(
            masterAccount,
            _amount
        );
    }

    function changeMaster(
        address _newMaster
    )
        external
        onlyMaster
    {
        masterAccount = _newMaster;
    }

    function changeWorker(
        address _newWorker
    )
        external
        onlyMaster
    {
        workerAccount = _newWorker;
    }

    function getBalance()
        public
        view
        returns (uint256)
    {
        return REWARD_TOKEN.balanceOf(
            address(this)
        );
    }

    function showRemaining(
        bytes32 _hash
    )
        public
        view
        returns (uint256)
    {
        return rewardsData[_hash].total - rewardsData[_hash].claimed;
    }

    function showExcess(
        bytes32 _hash
    )
        external
        view
        returns (int256)
    {
        return int256(getBalance()) - int256(showRemaining(_hash));
    }

    function showRemaining()
        public
        view
        returns (uint256)
    {
        return totalRequired - totalCollected;
    }

    function showExcess()
        external
        view
        returns (int256)
    {
        return int256(getBalance()) - int256(showRemaining());
    }

    function rescueTokens(
        address _token,
        address _target,
        uint256 _amount
    )
        external
        onlyMaster
    {
        IERC20(_token).transfer(
            _target,
            _amount
        );
    }
}
