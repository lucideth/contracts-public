//SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

interface IMultiRewardInterface {
    function updateReward(address account) external;

    function earned(address account, address _rewardsToken) external view returns (uint256);

    function getRewardFor(address account) external;

    function notifyRewardAmount(address _rewardsToken, uint256 rewardAmount, uint duration) external;
}
