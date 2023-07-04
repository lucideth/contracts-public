// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.13;
/**
 * @title Fund accepts 10% protocol revenue and distributes it to esLTOKEN holders in
 * proportions of their holdings to total supply of esLTOKEN
 */

import "../../Interfaces/IDSD.sol";
import "../../Interfaces/IesLTOKEN.sol";
import "../../Interfaces/IComptroller.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Fund is Ownable {
    using SafeERC20 for IERC20;
    IesLTOKEN public immutable esLTOKEN;
    // IComptroller public immutable comptroller;
    address public dsd;

    // Duration of rewards to be paid out (in seconds)
    uint256 public duration = 86400; // 1 day
    // Timestamp of when the rewards finish
    uint256 public finishAt;
    // Minimum of last updated time and reward finish time
    uint256 public updatedAt;
    // Reward to be paid out per second
    uint256 public rewardRate;
    // Sum of (reward rate * dt * 1e18 / total supply)
    uint256 public rewardPerTokenStored;
    // User address => rewardPerTokenStored
    mapping(address => uint256) public userRewardPerTokenPaid;
    // User address => rewards to be claimed
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public userUpdatedAt;

    event RewardsRefreshed(address indexed account);

    constructor(address _esLTOKEN, address _dsd) {
        esLTOKEN = IesLTOKEN(_esLTOKEN);
        dsd = _dsd;
    }

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
            userUpdatedAt[_account] = block.timestamp;
        }
        _;
    }

    function setRewardsDuration(uint256 _duration) external onlyOwner {
        require(finishAt < block.timestamp, "reward duration not finished");
        duration = _duration;
    }

    function totalStaked() internal view returns (uint256) {
        return esLTOKEN.totalSupply();
    }

    /**
     * @notice get esLTOKEN balance of user
     * @param user address of user
     * @dev returns esLTOKEN balance
     */
    function stakedOf(address user) public view returns (uint256) {
        return esLTOKEN.balanceOf(user);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return _min(finishAt, block.timestamp);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked() == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) / totalStaked();
    }

    /**
     * @notice Update user's claimable reward data and record the timestamp.
     * @param _account address of user
     * @dev This function is called everytime user claims reward.
     */
    function refreshReward(address _account) external updateReward(_account) {
        emit RewardsRefreshed(_account);
    }

    /**
     * @notice get earned rewards by user
     * @param _account address of user
     * @dev This function returns earned rewards by user.
     */
    function earned(address _account) public view returns (uint256) {
        return
            ((stakedOf(_account) * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18) + rewards[_account];
    }

    /**
     * @notice get rewards earned by user
     * @dev This function sends DSD rewards to user
     */
    function getReward() external updateReward(msg.sender) {
        require(rewards[msg.sender] > 0, "No rewards available");
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            IERC20(dsd).transfer(msg.sender, reward);
        }
    }

    /**
     * @notice Update reward rate and reward finish timestamp. Should be called every 24 hours by LLTOKENS.
     * @param amount amount of DSD to be distributed
     * @dev This function updates reward rate based on extra esLTOKEN amount.
     */
    function notifyRewardAmount(uint256 amount) external updateReward(address(0)) {
        require(amount > 0, "amount = 0");

        // IERC20(dsd).safeIncreaseAllowance(msg.sender, amount);
        IERC20(dsd).safeTransferFrom(msg.sender, address(this), amount);

        if (block.timestamp >= finishAt) {
            rewardRate = amount / duration;
        } else {
            uint256 remainingRewards = (finishAt - block.timestamp) * rewardRate;
            rewardRate = (amount + remainingRewards) / duration;
        }

        require(rewardRate > 0, "reward rate = 0");

        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
    }

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }
}
