// SPDX-License-Identifier: MIT
pragma solidity ^0.5;

interface IStrategy {
    function deposit() external;
    function withdraw(uint256 _amount) external;
    function collectRewards()  external returns (uint256);
    function nav()  external view returns (uint256);
    function exit() external;
}