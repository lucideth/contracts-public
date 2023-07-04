// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

interface ISwap {
    function name() external pure returns (string memory);
    function swap(uint _amount) external returns (uint256);
}