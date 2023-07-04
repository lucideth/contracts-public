// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;
interface IComptroller {
    function mintedDSDs(address account) external view returns (uint);
}