pragma solidity ^0.5.16;

import "../Tokens/LLTokens/LLToken.sol";
import "../Oracle/PriceOracle.sol";

contract ComptrollerInterfaceG1 {
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;


    /*** Policy Hooks ***/

    function mintAllowed(address llToken, address minter, uint mintAmount) external returns (uint);

    function mintVerify(address llToken, address minter, uint mintAmount, uint mintTokens) external;

    function redeemAllowed(address llToken, address redeemer, uint redeemTokens) external returns (uint);

    function redeemVerify(address llToken, address redeemer, uint redeemAmount, uint redeemTokens) external;


    function liquidateBorrowAllowed(
        address llTokenBorrowed,
        address llTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external returns (uint);

    function liquidateBorrowVerify(
        address llTokenBorrowed,
        address llTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens
    ) external;

    function seizeAllowed(
        address llTokenCollateral,
        address llTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external returns (uint);

    function seizeVerify(
        address llTokenCollateral,
        address llTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external;

    function transferAllowed(address llToken, address src, address dst, uint transferTokens) external returns (uint);

    function transferVerify(address llToken, address src, address dst, uint transferTokens) external;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address llTokenBorrowed,
        address llTokenCollateral,
        uint repayAmount
    ) external view returns (uint, uint);

    function setMintedDSDOf(address owner, uint amount) external returns (uint);

}

contract ComptrollerInterfaceG2 is ComptrollerInterfaceG1 {
    function liquidateDSDCalculateSeizeTokens(
        address llTokenCollateral,
        uint repayAmount
    ) external view returns (uint, uint);
}

contract ComptrollerInterfaceG3 is ComptrollerInterfaceG2 {
    function liquidateDSDCalculateSeizeTokens(
        address llTokenCollateral,
        uint repayAmount
    ) external view returns (uint, uint);
}

contract ComptrollerInterfaceG4 is ComptrollerInterfaceG3 {
    function getLTOKENAddress() public view returns (address);
}

contract ComptrollerInterface is ComptrollerInterfaceG4 {
    function markets(address) external view returns (bool, uint);

    function oracle() external view returns (PriceOracle);

    function getAccountLiquidity(address) external view returns (uint, uint, uint);

    function getAssetsIn(address) external view returns (LLToken[] memory);

    function claimLs(address) external;

    function lsAccrued(address) external view returns (uint);

    function lsSupplySpeeds(address) external view returns (uint);

    function lsBorrowSpeeds(address) external view returns (uint);

    function getAllMarkets() external view returns (LLToken[] memory);

    function lsSupplierIndex(address, address) external view returns (uint);

    function lsInitialIndex() external view returns (uint224);

    function lsBorrowerIndex(address, address) external view returns (uint);

    function lsBorrowState(address) external view returns (uint224, uint32);

    function lsSupplyState(address) external view returns (uint224, uint32);

    function approvedDelegates(address borrower, address delegate) external view returns (bool);
}

interface IDSDVault {
    function updatePendingRewards() external;
}

interface IComptroller {
    function liquidationIncentiveMantissa() external view returns (uint);
     function dsdController() external view returns (address);

    /*** Treasury Data ***/
    function treasuryAddress() external view returns (address);

    function treasuryPercent() external view returns (uint);
}
