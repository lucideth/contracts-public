// SPDX-License-Identifier: MIT
pragma solidity ^0.5.16;

interface IMiniComptroller {
    function dsdController() external view returns (address);
}