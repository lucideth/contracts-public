// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

interface IBaseRewardPool {
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);
    function getReward(address _account, bool _claimExtras) external returns (bool);
}
