// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface ICurveGauge {
    function balanceOf(address account) external view returns (uint256);

    function deposit(uint256 value, address account) external;
    function deposit(uint256 value, address account, bool claimRewards) external;
    function deposit(uint256 value) external;
    
    function withdraw(uint256 value) external;
    function withdraw(uint256 value, bool claimRewards) external;
    function withdraw(uint256 value, address _user, bool claimRewards) external;

    function claim_rewards() external;
    function claim_rewards(address account) external;
}
