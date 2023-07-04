// SPDX-License-Identifier: MIT
pragma solidity ^0.5.16;

interface ILLToken {
    function isRedeemFromYieldAllowed() external view returns (bool);
    function redeemableInEther() external view returns (uint256);
    function redeemableInUnderlying() external view returns (uint256);
    function redeemFromYield(uint256 _usdValue, address _recipient) external returns (uint256);
    function rigidRedeem(address payable _provider, address payable _redeemer, uint _amountInDSD) external returns (uint256);
    function rebase() external;
}