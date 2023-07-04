// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface ICurvePoolWithOracle {
    function price_oracle() external view returns (int256);
}