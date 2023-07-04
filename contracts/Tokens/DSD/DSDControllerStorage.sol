pragma solidity ^0.5.16;

import "../../Comptroller/ComptrollerInterface.sol";

interface IesLTOKENMinter {
    function refreshReward(address account) external;
}

contract DSDControllerAdminStorage {
    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address public pendingAdmin;
}

contract DSDControllerStorageG1 is DSDControllerAdminStorage {
    ComptrollerInterface public comptroller;

    struct LsDSDState {
        /// @notice The last updated lsDSDMintIndex
        uint224 index;
        /// @notice The block number the index was last updated at
        uint32 block;
    }

    /// @notice The LS DSD state
    LsDSDState public lsDSDState;

    /// @notice The LS DSD state initialized
    bool public isLsDSDInitialized;

    /// @notice The LS DSD minter index as of the last time they accrued LTOKEN
    mapping(address => uint) public lsDSDMinterIndex;

    /// @notice Address of DSD contract
    address internal DSDAddress;
}

contract DSDControllerStorageG2 is DSDControllerStorageG1 {
    /// @notice Treasury Guardian address
    address public treasuryGuardian;

    /// @notice Treasury address
    address public treasuryAddress;

    /// @notice Fee percent of accrued interest with decimal 18
    uint256 public treasuryPercent;

    /// @notice Guard variable for re-entrancy checks
    bool internal _notEntered;

    // /// @notice The base rate for stability fee
    // uint public baseRateMantissa;

    // /// @notice The float rate for stability fee
    // uint public floatRateMantissa;

    /// @notice The address for DSD interest receiver
    address public receiver;

    // /// @notice Accumulator of the total earned interest rate since the opening of the market. For example: 0.6 (60%)
    // uint public dsdMintIndex;

    /// @notice Block number that interest was last accrued at
    uint internal accrualBlockNumber;

    // /// @notice Global dsdMintIndex as of the most recent balance-changing action for user
    // mapping(address => uint) internal dsdMinterInterestIndex;

    // /// @notice Tracks the amount of mintedDSD of a user that represents the accrued interest
    // mapping(address => uint) public pastDSDInterest;

    /// @notice DSD mint cap
    uint public mintCap;

    /// @notice Access control manager address
    address public accessControl;

    // 🟡 - esLTOKENMinter changes
    IesLTOKENMinter public esltokenMinter;
}
