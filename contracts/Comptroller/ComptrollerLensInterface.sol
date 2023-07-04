pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../Tokens/LLTokens/LLToken.sol";

interface ComptrollerLensInterface {
    function liquidateCalculateSeizeTokens(
        address comptroller,
        address llTokenBorrowed,
        address llTokenCollateral,
        uint actualRepayAmount
    ) external view returns (uint, uint);

    function liquidateDSDCalculateSeizeTokens(
        address comptroller,
        address llTokenCollateral,
        uint actualRepayAmount
    ) external view returns (uint, uint);

    function getHypotheticalAccountLiquidity(
        address comptroller,
        address account,
        LLToken llTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) external view returns (uint, uint, uint);
}
