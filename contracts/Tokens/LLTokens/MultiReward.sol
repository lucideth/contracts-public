//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface LLTokenInterface {
    function totalSupply() external view returns (uint);

    function balanceOf(address _account) external view returns (uint);
}

interface IComptroller {
    function isWhitelisted(address _tokenAddress) external view returns (bool);
}

interface IEsLTOKENMinter {
    function mint(address _account, uint _amount) external;
}

contract MultiReward is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    uint internal constant MAX_REWARD_TOKENS = 16;

    /**
     * @notice Administrator for this contract
     */
    address public llToken;
    address public comptroller;
    address public esLTOKENMinter;
    address public esLTOKEN;

    struct Reward {
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed rewardsToken, uint256 reward);
    event RewardsDurationUpdated(address token, uint256 newDuration);
    event Recovered(address token, uint256 amount);

    mapping(address => Reward) public rewardData;
    address[] public rewardTokens;
    mapping(address => bool) public isReward;

    // user -> reward token -> amount
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public rewards;

    constructor(
        address _comptroller,
        address _esLTOKENMinter,
        address _esLTOKEN,
        address[] memory _allowedRewardTokens
    ) {
        comptroller = _comptroller;
        esLTOKENMinter = _esLTOKENMinter;
        esLTOKEN = _esLTOKEN;
        _registerRewardToken(_esLTOKEN);
        for (uint i = 0; i < _allowedRewardTokens.length; i++) {
            _registerRewardToken(_allowedRewardTokens[i]);
        }
    }

    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return Math.min(block.timestamp, rewardData[_rewardsToken].periodFinish);
    }

    function rewardPerToken(address _rewardsToken) public view returns (uint256) {
        uint totalSupply = LLTokenInterface(llToken).totalSupply();
        if (totalSupply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }
        return
            rewardData[_rewardsToken].rewardPerTokenStored.add(
                lastTimeRewardApplicable(_rewardsToken)
                    .sub(rewardData[_rewardsToken].lastUpdateTime)
                    .mul(rewardData[_rewardsToken].rewardRate)
                    .mul(1e18)
                    .div(totalSupply)
            );
    }

    function earned(address account, address _rewardsToken) public view returns (uint256) {
        uint accountTokens = LLTokenInterface(llToken).balanceOf(account);
        return
            accountTokens
                .mul(rewardPerToken(_rewardsToken).sub(userRewardPerTokenPaid[account][_rewardsToken]))
                .div(1e18)
                .add(rewards[account][_rewardsToken]);
    }

    function getRewardForDuration(address _rewardsToken, uint _duration) external view returns (uint256) {
        return rewardData[_rewardsToken].rewardRate.mul(_duration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function getReward() public nonReentrant {
        updateReward(msg.sender);
        for (uint i; i < rewardTokens.length; i++) {
            address _rewardsToken = rewardTokens[i];
            uint256 reward = rewards[msg.sender][_rewardsToken];
            if (reward > 0) {
                rewards[msg.sender][_rewardsToken] = 0;
                if (_rewardsToken == esLTOKEN) {
                    IEsLTOKENMinter(esLTOKENMinter).mint(msg.sender, reward);
                } else {
                    IERC20(_rewardsToken).safeTransfer(msg.sender, reward);
                }
                emit RewardPaid(msg.sender, _rewardsToken, reward);
            }
        }
    }

    function getRewardFor(address account) public nonReentrant {
        require(msg.sender == llToken);
        updateReward(account);
        for (uint i; i < rewardTokens.length; i++) {
            address _rewardsToken = rewardTokens[i];
            uint256 reward = rewards[account][_rewardsToken];
            if (reward > 0) {
                rewards[account][_rewardsToken] = 0;
                if (_rewardsToken == esLTOKEN) {
                    IEsLTOKENMinter(esLTOKENMinter).mint(account, reward);
                } else {
                    IERC20(_rewardsToken).safeTransfer(account, reward);
                }
                emit RewardPaid(account, _rewardsToken, reward);
            }
        }
    }

    function setLLTokenAddress(address _llToken) external onlyOwner {
        llToken = _llToken;
    }

    function setComptroller(address _comptroller) external onlyOwner {
        comptroller = _comptroller;
    }

    function setEsLTOKEN(address _esLTOKEN) external onlyOwner {
        esLTOKEN = _esLTOKEN;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(address _rewardsToken, uint256 rewardAmount, uint duration) external {
        require(rewardAmount > 0, "Zero Value");
        if (!isReward[_rewardsToken]) {
            require(IComptroller(comptroller).isWhitelisted(_rewardsToken), "rewards tokens must be whitelisted");
            require(rewardTokens.length < MAX_REWARD_TOKENS, "too many rewards tokens");
        }
        updateReward(address(0));
        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the reward amount
        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), rewardAmount);

        if (block.timestamp >= rewardData[_rewardsToken].periodFinish) {
            rewardData[_rewardsToken].rewardRate = rewardAmount.div(duration);
        } else {
            uint256 remaining = rewardData[_rewardsToken].periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardData[_rewardsToken].rewardRate);
            rewardData[_rewardsToken].rewardRate = rewardAmount.add(leftover).div(duration);
        }

        // // Ensure the provided reward amount is not more than the balance in the contract.
        // // This keeps the reward rate in the right range, preventing overflows due to
        // // very high values of rewardRate in the earned and rewardsPerToken functions;
        // // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        // uint256 balance = IERC20(_rewardsToken).balanceOf(address(this));
        // require(rewardData[_rewardsToken].rewardRate <= balance.div(duration), "Provided reward too high");

        rewardData[_rewardsToken].lastUpdateTime = block.timestamp;
        rewardData[_rewardsToken].periodFinish = block.timestamp.add(duration);

        if (!isReward[_rewardsToken]) {
            isReward[_rewardsToken] = true;
            rewardTokens.push(_rewardsToken);
        }
        emit RewardAdded(rewardAmount);
    }

    function notifyEsLTOKENRewardAmount(uint256 rewardAmount, uint duration) external onlyOwner {
        require(rewardAmount > 0, "Zero Value");
        updateReward(address(0));

        if (block.timestamp >= rewardData[esLTOKEN].periodFinish) {
            rewardData[esLTOKEN].rewardRate = rewardAmount.div(duration);
        } else {
            uint256 remaining = rewardData[esLTOKEN].periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardData[esLTOKEN].rewardRate);
            rewardData[esLTOKEN].rewardRate = rewardAmount.add(leftover).div(duration);
        }

        rewardData[esLTOKEN].lastUpdateTime = block.timestamp;
        rewardData[esLTOKEN].periodFinish = block.timestamp.add(duration);

        emit RewardAdded(rewardAmount);
    }

    function registerRewardToken(address token) external onlyOwner {
        return _registerRewardToken(token);
    }

    function _registerRewardToken(address token) internal {
        require(rewardTokens.length < MAX_REWARD_TOKENS, "Too many reward tokens");
        require(!isReward[token], "Already registered");
        isReward[token] = true;
        rewardTokens.push(token);
    }

    function removeRewardToken(address token) external onlyOwner {
        require(block.timestamp > rewardData[token].periodFinish, "Reward period still active");
        require(isReward[token], "Not reward token");

        isReward[token] = false;
        uint length = rewardTokens.length;
        require(length > 3, "First 3 tokens should not be removed");
        // keep 3 tokens as guarantee against malicious actions
        uint i = 3;
        bool found = false;
        for (; i < length; i++) {
            address t = rewardTokens[i];
            if (t == token) {
                found = true;
                break;
            }
        }
        require(found, "First tokens forbidden to remove");
        rewardTokens[i] = rewardTokens[length - 1];
        rewardTokens.pop();
    }

    function rewardTokensLength() external view returns (uint) {
        return rewardTokens.length;
    }

    /* ========== MODIFIERS ========== */

    function updateReward(address account) public {
        for (uint i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            rewardData[token].rewardPerTokenStored = rewardPerToken(token);
            rewardData[token].lastUpdateTime = lastTimeRewardApplicable(token);
            if (account != address(0)) {
                rewards[account][token] = earned(account, token);
                userRewardPerTokenPaid[account][token] = rewardData[token].rewardPerTokenStored;
            }
        }
    }
}
