/**
 *Submitted for verification at Etherscan.io on 2024-08-06
*/

// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.7 ^0.8.0 ^0.8.7;

// contracts/interfaces/ISyrupRouter.sol

interface ISyrupRouter {

    /**
     *  @dev   Optional Deposit Data for off-chain processing.
     *  @param owner       The receiver of the shares.
     *  @param amount      The amount of assets to deposit.
     *  @param depositData Optional deposit data.
     */
    event DepositData(address indexed owner, uint256 amount, bytes32 depositData);

    /**
     *  @dev    The address of the underlying asset used by the ERC4626 Vault.
     *  @return asset The address of the underlying asset.
     */
    function asset() external view returns (address asset);

    /**
     *  @dev    Authorizes and deposits assets into the Vault.
     *  @param  bitmap_      The bitmap of the permission.
     *  @param  deadline_    The timestamp after which the `authorize` signature is no longer valid.
     *  @param  auth_v       ECDSA signature v component.
     *  @param  auth_r       ECDSA signature r component.
     *  @param  auth_s       ECDSA signature s component.
     *  @param  amount_      The amount of assets to deposit.
     *  @param  depositData_ Optional deposit data.
     *  @return shares_      The amount of shares minted.
     */
    function authorizeAndDeposit(
        uint256 bitmap_,
        uint256 deadline_,
        uint8   auth_v,
        bytes32 auth_r,
        bytes32 auth_s,
        uint256 amount_,
        bytes32 depositData_
    ) external returns (uint256 shares_);

    /**
     *  @dev    Authorizes and deposits assets into the Vault with a ERC-2612 `permit`.
     *  @param  bitmap_         The bitmap of the permission.
     *  @param  auth_deadline_  The timestamp after which the `authorize` signature is no longer valid.
     *  @param  auth_v          ECDSA signature v component of the authorization.
     *  @param  auth_r          ECDSA signature r component of the authorization.
     *  @param  auth_s          ECDSA signature s component of the authorization.
     *  @param  amount_         The amount of assets to deposit.
     *  @param  depositData_    Optional deposit data.
     *  @param  permit_deadline The timestamp after which the `permit` signature is no longer valid.
     *  @param  permit_v_       ECDSA signature v component of the token permit.
     *  @param  permit_r_       ECDSA signature r component of the token permit.
     *  @param  permit_s_       ECDSA signature s component of the token permit.
     *  @return shares_         The amount of shares minted.
     */
    function authorizeAndDepositWithPermit(
        uint256 bitmap_,
        uint256 auth_deadline_,
        uint8   auth_v,
        bytes32 auth_r,
        bytes32 auth_s,
        uint256 amount_,
        bytes32 depositData_,
        uint256 permit_deadline,
        uint8   permit_v_,
        bytes32 permit_r_,
        bytes32 permit_s_
    ) external returns (uint256 shares_);

    /**
     *  @dev    Mints `shares` to sender by depositing `assets` into the Vault.
     *  @param  assets      The amount of assets to deposit.
     *  @param  depositData Optional deposit data.
     *  @return shares      The amount of shares minted.
     */
    function deposit(uint256 assets, bytes32 depositData) external returns (uint256 shares);

    /**
     *  @dev    Does a ERC4626 `deposit` into a Maple Pool with a ERC-2612 `permit`.
     *  @param  amount     The amount of assets to deposit.
     *  @param  deadline   The timestamp after which the `permit` signature is no longer valid.
     *  @param  v          ECDSA signature v component.
     *  @param  r          ECDSA signature r component.
     *  @param  s          ECDSA signature s component.
     *  @param depositData Optional deposit data.
     *  @return shares     The amount of shares minted.
     */
    function depositWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s, bytes32 depositData)
        external returns (uint256 shares);

    /**
      *  @dev    Returns the nonce for the given owner.
      *  @param  owner_ The address of the owner account.
      *  @return nonce_ The nonce for the given owner.
     */
    function nonces(address owner_) external view returns (uint256 nonce_);

    /**
     *  @dev    The address of the ERC4626 Vault.
     *  @return pool The address of the ERC4626 Vault.
     */
    function pool() external view returns (address pool);

    /**
     *  @dev    The address of the Pool Manager.
     *  @return poolManager The address of the Pool Manager.
     */
    function poolManager() external view returns (address poolManager);

    /**
     *  @dev    The address of the Pool Permission Manager.
     *  @return poolPermissionManager The address of the Pool Permission Manager.
     */
    function poolPermissionManager() external view returns (address poolPermissionManager);

}

// contracts/interfaces/Interfaces.sol

interface IBalancerVaultLike {

    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    function swap(
        SingleSwap calldata singleSwap,
        FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256 assetDelta);

}

interface IERC20Like_0 {

    function allowance(address owner, address spender) external view returns (uint256 allowance);

    function balanceOf(address account) external view returns (uint256 balance);

    function DOMAIN_SEPARATOR() external view returns (bytes32 domainSeparator);

    function PERMIT_TYPEHASH() external view returns (bytes32 permitTypehash);

    function approve(address spender, uint256 amount) external returns (bool success);

    function permit(address owner, address spender, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    function transfer(address recipient, uint256 amount) external returns (bool success);

    function transferFrom(address owner, address recipient, uint256 amount) external returns (bool success);

}

interface IGlobalsLike {

    function governor() external view returns (address governor);

    function operationalAdmin() external view returns (address operationalAdmin);

}

interface IMigratorLike {

    function migrate(address receiver, uint256 mplAmount) external returns (uint256 syrupAmount);

}

interface IPoolLike is IERC20Like_0 {

    function asset() external view returns (address asset);

    function convertToExitAssets(uint256 shares) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function manager() external view returns (address manager);

}

interface IPoolManagerLike {

    function poolPermissionManager() external view returns (address poolPermissionManager);

}

interface IPoolPermissionManagerLike {

    function hasPermission(address poolManager, address lender, bytes32 functionId) external view returns (bool hasPermission);

    function permissionAdmins(address account) external view returns (bool isAdmin);

    function setLenderBitmaps(address[] calldata lenders, uint256[] calldata bitmaps) external;

}

interface IPSMLike {

    function buyGem(address account, uint256 daiAmount) external;

    function tout() external view returns (uint256 tout);  // This is the fee charged for conversion

}

interface ISDaiLike {

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

}

interface IRDTLike {

    function asset() external view returns (address asset);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

}

interface IStakedSyrupLike {

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

}

// modules/erc20-helper/src/interfaces/IERC20Like.sol

/// @title Interface of the ERC20 standard as needed by ERC20Helper.
interface IERC20Like_1 {

    function approve(address spender_, uint256 amount_) external returns (bool success_);

    function transfer(address recipient_, uint256 amount_) external returns (bool success_);

    function transferFrom(address owner_, address recipient_, uint256 amount_) external returns (bool success_);

}

// modules/erc20-helper/src/ERC20Helper.sol

/**
 * @title Small Library to standardize erc20 token interactions.
 */
library ERC20Helper {

    /**************************************************************************************************************************************/
    /*** Internal Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function transfer(address token_, address to_, uint256 amount_) internal returns (bool success_) {
        return _call(token_, abi.encodeWithSelector(IERC20Like_1.transfer.selector, to_, amount_));
    }

    function transferFrom(address token_, address from_, address to_, uint256 amount_) internal returns (bool success_) {
        return _call(token_, abi.encodeWithSelector(IERC20Like_1.transferFrom.selector, from_, to_, amount_));
    }

    function approve(address token_, address spender_, uint256 amount_) internal returns (bool success_) {
        // If setting approval to zero fails, return false.
        if (!_call(token_, abi.encodeWithSelector(IERC20Like_1.approve.selector, spender_, uint256(0)))) return false;

        // If `amount_` is zero, return true as the previous step already did this.
        if (amount_ == uint256(0)) return true;

        // Return the result of setting the approval to `amount_`.
        return _call(token_, abi.encodeWithSelector(IERC20Like_1.approve.selector, spender_, amount_));
    }

    function _call(address token_, bytes memory data_) private returns (bool success_) {
        if (token_.code.length == uint256(0)) return false;

        bytes memory returnData;
        ( success_, returnData ) = token_.call(data_);

        return success_ && (returnData.length == uint256(0) || abi.decode(returnData, (bool)));
    }

}

// contracts/SyrupRouter.sol

/*

███████╗██╗   ██╗██████╗ ██╗   ██╗██████╗     ██████╗  ██████╗ ██╗   ██╗████████╗███████╗██████╗
██╔════╝╚██╗ ██╔╝██╔══██╗██║   ██║██╔══██╗    ██╔══██╗██╔═══██╗██║   ██║╚══██╔══╝██╔════╝██╔══██╗
███████╗ ╚████╔╝ ██████╔╝██║   ██║██████╔╝    ██████╔╝██║   ██║██║   ██║   ██║   █████╗  ██████╔╝
╚════██║  ╚██╔╝  ██╔══██╗██║   ██║██╔═══╝     ██╔══██╗██║   ██║██║   ██║   ██║   ██╔══╝  ██╔══██╗
███████║   ██║   ██║  ██║╚██████╔╝██║         ██║  ██║╚██████╔╝╚██████╔╝   ██║   ███████╗██║  ██║
╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝         ╚═╝  ╚═╝ ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝╚═╝  ╚═╝

*/

contract SyrupRouter is ISyrupRouter {

    address public immutable override asset;
    address public immutable override pool;
    address public immutable override poolManager;
    address public immutable override poolPermissionManager;

    mapping(address => uint256) public override nonces;

    constructor(address pool_) {
        pool = pool_;

        // Get the addresses of all the associated contracts.
        address asset_ = asset = IPoolLike(pool_).asset();
        address poolManager_ = poolManager = IPoolLike(pool_).manager();

        poolPermissionManager = IPoolManagerLike(poolManager_).poolPermissionManager();

        // Perform an infinite approval.
        require(ERC20Helper.approve(asset_, pool_, type(uint256).max), "SR:C:APPROVE_FAIL");
    }

    /**************************************************************************************************************************************/
    /*** External Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function authorizeAndDeposit(
        uint256 bitmap_,
        uint256 deadline_,
        uint8   auth_v,
        bytes32 auth_r,
        bytes32 auth_s,
        uint256 amount_,
        bytes32 depositData_
    )
        external override returns (uint256 shares_)
    {
        _authorize(deadline_, bitmap_, auth_v, auth_r, auth_s);

        shares_ = _deposit(msg.sender, amount_, depositData_);
    }

    function authorizeAndDepositWithPermit(
        uint256 bitmap_,
        uint256 auth_deadline_,
        uint8   auth_v,
        bytes32 auth_r,
        bytes32 auth_s,
        uint256 amount_,
        bytes32 depositData_,
        uint256 permit_deadline,
        uint8   permit_v_,
        bytes32 permit_r_,
        bytes32 permit_s_
    )
        external override returns (uint256 shares_)
    {
        _authorize(auth_deadline_, bitmap_, auth_v, auth_r, auth_s);
        _permit(asset, permit_deadline, amount_, permit_v_, permit_r_, permit_s_);

        shares_ = _deposit(msg.sender, amount_, depositData_);
    }

    function deposit(uint256 amount_, bytes32 depositData_) external override returns (uint256 shares_) {
        shares_ = _deposit(msg.sender, amount_, depositData_);
    }

    function depositWithPermit(
        uint256 amount_,
        uint256 deadline_,
        uint8   v_,
        bytes32 r_,
        bytes32 s_,
        bytes32 depositData_
    )
        external override returns (uint256 shares_)
    {
        _permit(asset, deadline_, amount_, v_, r_, s_);

        shares_ = _deposit(msg.sender, amount_, depositData_);
    }

    /**************************************************************************************************************************************/
    /*** Internal Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function _authorize(uint256 deadline_, uint256 bitmap_, uint8 v_, bytes32 r_, bytes32 s_) internal {
        require(deadline_ >= block.timestamp, "SR:A:EXPIRED");

        // Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}.
        require(
            uint256(s_) <= uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) &&
            (v_ == 27 || v_ == 28),
            "SR:A:MALLEABLE"
        );

        bytes32 digest_ = keccak256(abi.encodePacked(
            "\x19\x01",
            block.chainid,  // Chain id + address(this) serves as domain separator to avoid replay attacks.
            address(this),
            msg.sender,
            nonces[msg.sender]++,
            bitmap_,
            deadline_
        ));

        address recoveredAddress_ = ecrecover(digest_, v_, r_, s_);

        IPoolPermissionManagerLike ppm_ = IPoolPermissionManagerLike(poolPermissionManager);

        // Any valid permission admin can authorize the deposit.
        require(recoveredAddress_ != address(0) && ppm_.permissionAdmins(recoveredAddress_), "SR:A:NOT_PERMISSION_ADMIN");

        address[] memory lender = new address[](1);
        uint256[] memory bitmap = new uint256[](1);

        lender[0] = msg.sender;
        bitmap[0] = bitmap_;

        ppm_.setLenderBitmaps(lender, bitmap);
    }

    function _deposit(address owner_, uint256 amount_, bytes32 depositData_) internal returns (uint256 shares_) {
        // Check the owner has permission to deposit into the pool.
        require(
            IPoolPermissionManagerLike(poolPermissionManager).hasPermission(poolManager, owner_, "P:deposit"),
            "SR:D:NOT_AUTHORIZED"
        );

        // Pull assets from the owner to the router.
        require(ERC20Helper.transferFrom(asset, owner_, address(this), amount_), "SR:D:TRANSFER_FROM_FAIL");

        // Deposit assets into the pool and receive the shares personally.
        address pool_ = pool;

        shares_ = IPoolLike(pool_).deposit(amount_, address(this));

        // Route shares back to the caller.
        require(ERC20Helper.transfer(pool_, owner_, shares_), "SR:D:TRANSFER_FAIL");

        emit DepositData(owner_, amount_, depositData_);
    }

    function _permit(address asset_, uint256 deadline_, uint256 amount_, uint8 v_, bytes32 r_, bytes32 s_) internal {
        uint256 allowance_ = IERC20Like_0(asset_).allowance(msg.sender, address(this));

        if (allowance_ < amount_) {
            IERC20Like_0(asset_).permit(msg.sender, address(this), amount_, deadline_, v_, r_, s_);
        }
    }

}