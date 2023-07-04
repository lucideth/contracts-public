pragma solidity ^0.5.16;

interface IwstETH {
    function getStETHByWstETH(uint _steth) external view returns (uint256);
    function tokensPerStEth() external view returns (uint256);
}