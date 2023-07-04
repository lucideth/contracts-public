pragma solidity ^0.5.16;

contract DSDInterface  {
    function decimals() external view returns (uint8);
    function scaledTotalSupply() external view returns (uint);
    function totalSupply() external view returns (uint);
    function liquidityIndex() external view returns (uint);
    function setMultiplier(uint256) external;
}