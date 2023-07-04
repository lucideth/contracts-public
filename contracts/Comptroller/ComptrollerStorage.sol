pragma solidity ^0.5.16;

import "../Tokens/LLTokens/LLToken.sol";
import "../Oracle/PriceOracle.sol";
import "../Tokens/DSD/DSDControllerInterface.sol";
import "./ComptrollerLensInterface.sol";

contract ComptrollerAdminStorage {
    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address public pendingAdmin;
}

contract ComptrollerV1Storage is ComptrollerAdminStorage {
    /**
     * @notice Oracle which gives the price of any given asset
     */
    PriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    uint public closeFactorMantissa;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    uint public liquidationIncentiveMantissa;

    /**
     * @notice Max number of assets a single account can participate in (borrow or use as collateral)
     */
    uint public maxAssets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => LLToken[]) public accountAssets;

    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;
        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint collateralFactorMantissa;
        /// @notice Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        /// @notice Whether or not this market receives LTOKEN
        bool isLs;
    }

    /**
     * @notice Official mapping of llTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;

    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     */
    address public pauseGuardian;

    /// @notice Whether minting is paused (deprecated, superseded by actionPaused)
    bool private _mintGuardianPaused;
    /// @notice Whether borrowing is paused (deprecated, superseded by actionPaused)
    bool private _borrowGuardianPaused;
    /// @notice Whether borrowing is paused (deprecated, superseded by actionPaused)
    bool internal transferGuardianPaused;
    /// @notice Whether borrowing is paused (deprecated, superseded by actionPaused)
    bool internal seizeGuardianPaused;
    /// @notice Whether borrowing is paused (deprecated, superseded by actionPaused)
    mapping(address => bool) internal mintGuardianPaused;
    /// @notice Whether borrowing is paused (deprecated, superseded by actionPaused)
    mapping(address => bool) internal borrowGuardianPaused;

    struct LsMarketState {
        /// @notice The market's last updated lsBorrowIndex or lsSupplyIndex
        uint224 index;
        /// @notice The block number the index was last updated at
        uint32 block;
    }

    /// @notice A list of all markets
    LLToken[] public allMarkets;

    /// @notice The rate at which the flywheel distributes LTOKEN, per block
    uint public lsRate;

    /// @notice The portion of lsRate that each market currently receives
    mapping(address => uint) public lsSpeeds;

    /// @notice The LS market supply state for each market
    mapping(address => LsMarketState) public lsSupplyState;

    /// @notice The LS market borrow state for each market
    mapping(address => LsMarketState) public lsBorrowState;

    /// @notice The LS supply index for each market for each supplier as of the last time they accrued LTOKEN
    mapping(address => mapping(address => uint)) public lsSupplierIndex;

    /// @notice The LS borrow index for each market for each borrower as of the last time they accrued LTOKEN
    mapping(address => mapping(address => uint)) public lsBorrowerIndex;

    /// @notice The LTOKEN accrued but not yet transferred to each user
    mapping(address => uint) public lsAccrued;

    /// @notice The Address of DSDController
    DSDControllerInterface public dsdController;

    /// @notice The minted DSD amount to each user
    mapping(address => uint) public mintedDSDs;

    /// @notice DSD Mint Rate as a percentage
    uint public dsdMintRate;

    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     */
    bool public mintDSDGuardianPaused;
    bool public repayDSDGuardianPaused;

    /**
     * @notice Pause/Unpause whole protocol actions
     */
    bool public protocolPaused;

    /// @notice The rate at which the flywheel distributes LTOKEN to DSD Minters, per block (deprecated)
    uint private lsDSDRate;
}

contract ComptrollerV2Storage is ComptrollerV1Storage {
    /// @notice The rate at which the flywheel distributes LTOKEN to DSD Vault, per block
    uint public lsDSDVaultRate;

    // address of DSD Vault
    address public dsdVaultAddress;

    // start block of release to DSD Vault
    uint256 public releaseStartBlock;

    // minimum release amount to DSD Vault
    uint256 public minReleaseAmount;
}

contract ComptrollerV3Storage is ComptrollerV2Storage {
    /// @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    /// @notice Borrow caps enforced by borrowAllowed for each llToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint) public borrowCaps;
}

contract ComptrollerV4Storage is ComptrollerV3Storage {
    /// @notice Treasury Guardian address
    address public treasuryGuardian;

    /// @notice Treasury address
    address public treasuryAddress;

    /// @notice Fee percent of accrued interest with decimal 18
    uint256 public treasuryPercent;
}

contract ComptrollerV5Storage is ComptrollerV4Storage {
    /// @notice The portion of LTOKEN that each contributor receives per block (deprecated)
    mapping(address => uint) private lsContributorSpeeds;

    /// @notice Last block at which a contributor's LTOKEN rewards have been allocated (deprecated)
    mapping(address => uint) private lastContributorBlock;
}

contract ComptrollerV6Storage is ComptrollerV5Storage {
    address public liquidatorContract;
}

contract ComptrollerV7Storage is ComptrollerV6Storage {
    ComptrollerLensInterface public comptrollerLens;
}

contract ComptrollerV8Storage is ComptrollerV7Storage {
    /// @notice Supply caps enforced by mintAllowed for each llToken address. Defaults to zero which corresponds to minting notAllowed
    mapping(address => uint256) public supplyCaps;
}

contract ComptrollerV9Storage is ComptrollerV8Storage {
    /// @notice AccessControlManager address
    address internal accessControl;

    enum Action {
        MINT,
        REDEEM,
        BORROW,
        REPAY,
        SEIZE,
        LIQUIDATE,
        TRANSFER,
        ENTER_MARKET,
        EXIT_MARKET
    }

    /// @notice True if a certain action is paused on a certain market
    mapping(address => mapping(uint => bool)) internal _actionPaused;
}

contract ComptrollerV10Storage is ComptrollerV9Storage {
    /// @notice The rate at which LS is distributed to the corresponding borrow market (per block)
    mapping(address => uint) public lsBorrowSpeeds;

    /// @notice The rate at which LS is distributed to the corresponding supply market (per block)
    mapping(address => uint) public lsSupplySpeeds;
}

contract ComptrollerV11Storage is ComptrollerV10Storage {
    /// @notice Whether the delegate is allowed to borrow on behalf of the borrower
    //mapping(address borrower => mapping (address delegate => bool approved)) public approvedDelegates;
    mapping(address => mapping(address => bool)) public approvedDelegates;
    address public ltokenAddress; // This should be esLTOKEN address
    /// @notice requires user to explicitly enable each llToken
    bool public requireEnablingCollateral;
    // token    => boolean [is an allowed token?]
    mapping(address => bool) public isWhitelisted;
}
