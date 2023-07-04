// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.13;
/**
 * @title esLTOKENMinter is a stripped down version of Synthetix StakingRewards.sol, to reward esLTOKEN to DSD minters.
 * Differences from the original contract,
 * - Get `totalStaked` from totalSupply() in contract DSD.
 * - Get `stakedOf(user)` from getBorrowedOf(user) in contract DSD.
 * - When an address borrowed DSD amount changes, call the refreshReward method to update rewards to be claimed.
 */

import "../../Interfaces/IDSD.sol";
import "../../Interfaces/IesLTOKEN.sol";
import "../../Interfaces/IComptroller.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract esLTOKENMinter is Ownable {
    IDSD public immutable dsd;
    IComptroller public immutable comptroller;
    address public esLTOKEN;

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
    mapping(address => bool) public isAllowedToMint;

    event RewardsRefreshed(address indexed account);

    constructor(address _dsd, address _comptroller) {
        dsd = IDSD(_dsd);
        comptroller = IComptroller(_comptroller);
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

    function setEsLTOKEN(address _esltoken) external onlyOwner {
        esLTOKEN = _esltoken;
    }

    function setIsAllowedToMint(address _account, bool _state) external onlyOwner {
        isAllowedToMint[_account] = _state;
    }

    function totalStaked() internal view returns (uint256) {
        return dsd.totalSupply();
    }

    /**
     * @notice get mintedDSDs of user
     * @param user address of user
     * @dev returns minted DSD amount by user
     */
    function stakedOf(address user) public view returns (uint256) {
        return comptroller.mintedDSDs(user);
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
     * @dev This function is called every time a user mints or burns DSD.
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
     * @dev This function mints esLTOKEN rewards to user for minting DSD.
     */
    function getReward() external updateReward(msg.sender) {
        require(rewards[msg.sender] > 0, "No rewards available");
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            _mint(msg.sender, reward);
        }
    }

    /**
     * @notice mint esLTOKEN rewards to user
     * @dev This function can be used by MultiReward contracts  to mint esLTOKEN rewards to user.
     */
    function mint(address _account, uint _amount) external {
        require(isAllowedToMint[msg.sender], "Not Allowed");
        _mint(_account, _amount);
    }

    function _mint(address _account, uint _amount) internal {
        IesLTOKEN(esLTOKEN).mint(_account, _amount);
    }

    /**
     * @notice Update reward rate and reward finish timestamp.
     * @param amount amount of esLTOKEN to be distributed
     * @dev This function updates reward rate based on extra esLTOKEN amount.
     */
    function notifyRewardAmount(uint256 amount, uint256 duration) external onlyOwner updateReward(address(0)) {
        require(amount > 0, "amount = 0");
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
