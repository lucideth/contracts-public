pragma solidity ^0.5.16;

import "../../Oracle/PriceOracle.sol";
import "../../Comptroller/ComptrollerInterface.sol";

contract LLTokenStorage {
    /**
     * @dev Guard variable for re-entrancy checks
     */
    bool internal _notEntered;

    /**
     * @notice EIP-20 token name for this token
     */
    string public name;

    /**
     * @notice EIP-20 token symbol for this token
     */
    string public symbol;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint8 public decimals;

    /**
     * @notice Maximum borrow rate that can ever be applied (.0005% / block)
     */

    // uint internal constant borrowRateMaxMantissa = 0.0005e16;

    /**
     * @notice Maximum fraction of interest that can be set aside for reserves
     */
    uint internal constant reserveFactorMaxMantissa = 1e18;

    /**
     * @notice Administrator for this contract
     */
    address payable public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address payable public pendingAdmin;

    /**
     * @notice Contract which oversees inter-llToken operations
     */
    ComptrollerInterface public comptroller;

    /**
     * @notice Initial exchange rate used when minting the first LLTokens (used when totalSupply = 0)
     */
    uint internal initialExchangeRateMantissa;

    /**
     * @notice Fraction of interest currently set aside for reserves
     */
    uint public reserveFactorMantissa;

    /**
     * @notice Total amount of outstanding borrows of the underlying in this market
     */
    uint public totalBorrows;

    /**
     * @notice Total amount of reserves of the underlying held in this market
     */
    uint public totalReserves;

    /**
     * @notice Total number of tokens in circulation
     */
    uint public totalSupply;

    /**
     * @notice Official record of token balances for each account
     */
    mapping(address => uint) internal accountTokens;

    /**
     * @notice Approved token transfer amounts on behalf of others
     */
    mapping(address => mapping(address => uint)) internal transferAllowances;

    /**
     * @notice Total number token deposited at this time in underlying
     */
    uint public totalUseableBalanceInUnderlying;
    uint public redeemableInUnderlying;

    /**
     * @notice Total number token deposited at this time in ether
     */
    uint public totalUseableBalanceInEther;
    uint public redeemableInEther;

    /**
     * @notice Total number token deposited in ether for a user
     */

    // mapping(address => uint) public totalUseableBalanceInEtherForUser;

    /**
     * @notice Total number token deposited at last rebase
     */
    uint public totalDepositedAtLastRebase;

    /**
     * @notice Wrapping factor of the underlying token if IERC4626
     */
    uint public wrappingFactor;

    /**
     * @notice Protocol token
     */
    address public DSD;

    /**
     * @notice Flag to set whether underlying token is a rebasing token
     */
    bool public isRebasing;

    /**
     * @notice Flag to set whether underlying token is reward accumulating
     */
    bool public isRewardAccumulating;
    /**
     * @notice Flag to set whether underlying token is a wrapped token
     */
    bool public isWrapped;

    /**
     * @notice Mix max values to allow rebase within
     */
    uint public limitRebaseMin;
    uint public limitRebaseMax;

    /**
     * @notice Oracle to provide prices of tokens
     */
    PriceOracle public oracle;

    /**
     * @notice State of redeem from yield
     */
    bool public isRedeemFromYieldAllowed;

    /**
     * @notice MultiRewardHandler Address
     */
    address public multiReward;

    /**
     * @notice Strategy Address
     */
    address public strategy;

    /**
     * @notice Yield distribution
     */
    uint public multiRewardShareInBps; // 1% = 100
    uint public esLTOKENShareInBps; // 1% = 100

    /**
     * @notice Fund contract
     */
    address public fund;

    /**
     * @notice Rigid Redemption essentials
     */
    mapping(address => bool) redemptionProvider;
    uint public rigidRedeemFeeInBps; // 1% = 100

    /**
     * @notice Redeem from yield fee
     */
    uint public redeemFromYieldFeeInBps; // 1% = 100
}

contract LLTokenInterface is LLTokenStorage {
    /**
     * @notice Indicator that this is a llToken contract (for inspection)
     */
    bool public constant isLLToken = true;

    /*** Market Events ***/

    /**
     * @notice Event emitted when tokens are Deposited
     */
    event Deposit(address minter, uint depositAmount, address depositToken);
    /**
     * @notice Event emitted when tokens are minted
     */
    event Mint(address minter, uint mintAmount, uint mintTokens);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

    /**
     * @notice Event emitted when a yield distribution is invoked
     */
    event Distribution(address llToken, uint mr, uint fund, uint dsd);

    /**
     * @notice Event emitted when a rigid redemption is invoked
     */
    event RigidRedemption(address provider, address redeemer, uint _amountInDSD, uint _worthInUnderlying);

    /**
     * @notice Event emitted when a rebase is invoked
     */
    event Rebased(address llToken, uint liquidityIndex, uint oldSupply, uint newSupply);

    /**
     * @notice Event emitted when reward collection is invoked
     */
    event RewardCollected(address llToken, uint collected);

    /*** Admin Events ***/

    /**
     * @notice Event emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Event emitted when pendingAdmin is accepted, which means admin has been updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    /**
     * @notice Event emitted when comptroller is changed
     */
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /**
     * @notice EIP20 Transfer event
     */
    event Transfer(address indexed from, address indexed to, uint amount);

    /**
     * @notice EIP20 Approval event
     */
    event Approval(address indexed owner, address indexed spender, uint amount);

    /**
     * @notice Failure event
     */
    event Failure(uint error, uint info, uint detail);

    event RedeemedFromYield(address _recipient, uint _amountInDSD, uint _amountInUnderlying);

    /*** User Interface ***/

    function transfer(address dst, uint amount) external returns (bool);

    function transferFrom(address src, address dst, uint amount) external returns (bool);

    function approve(address spender, uint amount) external returns (bool);

    function balanceOfUnderlying(address owner) external returns (uint);

    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint);

    /*** Admin Function ***/
    function _setPendingAdmin(address payable newPendingAdmin) external returns (uint);

    /*** Admin Function ***/
    function _acceptAdmin() external returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function allowance(address owner, address spender) external view returns (uint);

    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint, uint);

    function getCash() external view returns (uint);

    function exchangeRateCurrent() public returns (uint);

    /*** Admin Function ***/
    function _setComptroller(ComptrollerInterface newComptroller) public returns (uint);

    function setRebasingLimit(uint _min, uint _max) public returns (uint);

    function setRewardShareBps(uint _mr, uint _esltoken) public returns (uint);

    function exchangeRateStored() public view returns (uint);
}

contract LLErc20Storage {
    /**
     * @notice Underlying asset for this LLToken
     */
    address public underlying;
}

contract LLErc20Interface is LLErc20Storage {
    /*** User Interface ***/

    function mint(uint mintAmount) external returns (uint);

    function redeemUnderlying(uint redeemAmount) external returns (uint);
}

contract VDelegationStorage {
    /**
     * @notice Implementation address for this contract
     */
    address public implementation;
}

contract VDelegatorInterface is VDelegationStorage {
    /**
     * @notice Emitted when implementation is changed
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     * @param allowResign Flag to indicate whether to call _resignImplementation on the old implementation
     * @param becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
     */
    function _setImplementation(
        address implementation_,
        bool allowResign,
        bytes memory becomeImplementationData
    ) public;
}

contract VDelegateInterface is VDelegationStorage {
    /**
     * @notice Called by the delegator on a delegate to initialize it for duty
     * @dev Should revert if any issues arise which make it unfit for delegation
     * @param data The encoded bytes data for any initialization
     */
    function _becomeImplementation(bytes memory data) public;

    /**
     * @notice Called by the delegator on a delegate to forfeit its responsibility
     */
    function _resignImplementation() public;
}
