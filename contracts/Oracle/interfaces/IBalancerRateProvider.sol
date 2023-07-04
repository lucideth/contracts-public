pragma solidity ^0.5.16;

interface IBalancerRateProvider {
    function getRate() external view returns (uint256);

}