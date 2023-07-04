// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface IOracle {
    function latestAnswer() external view returns (int256);
}