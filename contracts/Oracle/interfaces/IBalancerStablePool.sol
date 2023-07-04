pragma solidity ^0.5.16;

interface IBalancerStablePool {
    function getRate() external view returns (uint256);
    function getRateProviders() external view returns (address[] memory);

}