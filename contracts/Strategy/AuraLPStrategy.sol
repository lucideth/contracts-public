// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8;
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../Interfaces/Swapper/ISwap.sol";
import "../Interfaces/Balancer/pkg/IBalancerStablePreview.sol";
import "../Interfaces/Balancer/pkg/IBasePool.sol";
import "../Interfaces/Aura/IBooster.sol";
import "../Interfaces/Aura/IRewards.sol";
import "../Interfaces/Balancer/pkg/StablePoolUserData.sol";

import "hardhat/console.sol";

/**
 * @title AuraLPStrategy
 * @notice Strategy for Balancer LP tokens to be staked in Aura
 */
contract AuraLPStrategy {
    using SafeERC20 for IERC20Metadata;

    /**
     * @notice llToken address
     */
    address public lltoken;

    /**
     * @notice Aura related addresses
     */

    address internal constant AURA_BOOSTER = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    uint256 internal constant DEFAULT_GAS_REENTRANCY_CHECK = 7000;
    address public balLp;
    bytes32 public balPoolId;
    uint256 public auraPid;
    address public auraRewardManager;
    address public auraDepositToken;

    /**
     * @notice The ERC20 token to which reward tokens will be swapped into
     */
    address public swappedToken;

    /*
     * @notice Reward tokens
     */
    address[] public rewardTokens;

    /*
     * @notice Swapping pools in order of rewardTokens
     */
    address[] public swappingPools;

    uint256 public gasForReentrancyCheck;

    /*
     * @notice Batch swapper contract (ISwap)
     */
    address public batchSwapper;

    /*
     * @notice Underlying tokens in the balancer pool
     */
    address[] public underlyingTokens;

    /*
     * @notice Modifier to check only llToken can call the function
     */
    modifier onlyLLToken() {
        require(msg.sender == lltoken, "only lltoken");
        _;
    }

    /**
     * Initialize the strategy
     */
    constructor(
        address _lltoken,
        uint256 _auraPid,
        address _balLp,
        address _swappedToken,
        address _batchSwapper,
        address[] memory _underlyingTokens,
        address[] memory _rewardTokens,
        address[] memory _swappingPools
    ) {
        lltoken = _lltoken;
        balPoolId = IBasePool(_balLp).getPoolId();
        auraPid = _auraPid;

        (balLp, auraRewardManager) = _getPoolInfo(_auraPid);
        if (balLp != _balLp) revert("Invalid balancer pool");

        gasForReentrancyCheck = DEFAULT_GAS_REENTRANCY_CHECK;
        underlyingTokens = _underlyingTokens;
        rewardTokens = _rewardTokens;
        swappingPools = _swappingPools;
        swappedToken = _swappedToken;
        batchSwapper = _batchSwapper;
    }

    function _getPoolTokenAddresses() internal view virtual returns (address[] memory) {
        return underlyingTokens;
    }

    function _getPoolInfo(uint256 _auraPid) internal returns (address _auraLp, address _auraRewardManager) {
        if (_auraPid > IBooster(AURA_BOOSTER).poolLength()) {
            revert("Invalid pool id");
        }
        (_auraLp, auraDepositToken, , _auraRewardManager, , ) = IBooster(AURA_BOOSTER).poolInfo(_auraPid);
    }

    /**
     * @notice Return the net asset value of the underlying assets (in underlying units)
     */
    function nav() public view returns (uint256) {
        return balance();
    }

    /**
     * @notice Get the underlying balance of the strategy (including the staked)
     * @return uint256 balance
     */
    function balance() internal view returns (uint256) {
        return
            IERC20Metadata(balLp).balanceOf(address(this)) + IERC20Metadata(auraRewardManager).balanceOf(address(this));
    }

    /**
     * @notice Raw token present in the contract
     */
    function available() internal view returns (uint256) {
        return IERC20Metadata(balLp).balanceOf(address(this));
    }

    /**
     * @notice Deposit the LP token present in the strategy to the aura gauge
     */
    function deposit() external onlyLLToken {
        _deposit();
    }

    /**
     * @notice Deposit the LP token present in the strategy to the aura gauge
     */
    function _deposit() internal {
        uint256 _lpTokenBalance = balance() - IERC20Metadata(auraRewardManager).balanceOf(address(this));
        IERC20Metadata(balLp).approve(AURA_BOOSTER, _lpTokenBalance);
        IBooster(AURA_BOOSTER).deposit(auraPid, _lpTokenBalance, true);
    }

    /**
     * Withdraw the LP tokens from the aura gauge
     * @param _amount Amount of LP tokens to be withdrawn
     */
    function withdraw(uint256 _amount) external onlyLLToken {
        _withdraw(_amount);
    }

    function _withdraw(uint256 _amount) internal {
        if (_amount > balance()) {
            _amount = balance();
        }
        if (_amount > available() && (_amount - available()) > 0) {
            IRewards(auraRewardManager).withdrawAndUnwrap(_amount - available(), false);
        }
        IERC20Metadata(balLp).safeTransfer(lltoken, _amount);
    }

    /**
     * Convert the swapped token to LP tokens
     */
    function _convertToLP() internal {
        if (IERC20Metadata(swappedToken).balanceOf(address(this)) == 0) return;
        IERC20Metadata(swappedToken).approve(BALANCER_VAULT, type(uint256).max);
        IVault.JoinPoolRequest memory request = _assembleJoinRequest(
            swappedToken,
            IERC20Metadata(swappedToken).balanceOf(address(this))
        );
        IVault(BALANCER_VAULT).joinPool(balPoolId, address(this), address(this), request);
    }

    function find(address[] memory array, address element) internal pure returns (uint256 index) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; ) {
            if (array[i] == element) return i;
            unchecked {
                i++;
            }
        }
        return type(uint256).max;
    }

    function _assembleJoinRequest(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual returns (IVault.JoinPoolRequest memory request) {
        // max amounts in
        address[] memory assets = _getPoolTokenAddresses();
        uint256[] memory maxAmountsIn = new uint256[](underlyingTokens.length);
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            maxAmountsIn[i] = type(uint256).max;
        }
        uint256 _index = find(assets, tokenIn);
        uint256[] memory _actualLiquidity = new uint256[](underlyingTokens.length);
        _actualLiquidity[_index] = amountTokenToDeposit;
        bytes memory userData = abi.encode(1, _actualLiquidity, 0);

        request = IVault.JoinPoolRequest(assets, maxAmountsIn, userData, false);
    }

    function _getBPTIndex() internal view virtual returns (uint256) {
        return type(uint256).max;
    }

    /**
     * Collect the rewards, swap them to swapped token, convert them to LP and stake them
     */
    function collectRewards() external onlyLLToken returns (uint256) {
        uint _initial = balance();
        try IRewards(auraRewardManager).getReward(address(this), true) {} catch {
            console.log("Claim rewards failed");
        }
        for (uint8 i = 0; i < rewardTokens.length; i++) {
            uint _reward = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
            if (_reward < 10 ** 4) {
                continue;
            }
            IERC20Metadata(rewardTokens[i]).approve(swappingPools[i], _reward);
            ISwap(swappingPools[i]).swap(_reward);
        }
        if (IERC20Metadata(swappedToken).balanceOf(address(this)) < 10 ** 4) {
            return 0;
        }
        if (batchSwapper != address(0)) {
            IERC20Metadata(swappedToken).approve(batchSwapper, IERC20Metadata(swappedToken).balanceOf(address(this)));
            ISwap(batchSwapper).swap(IERC20Metadata(swappedToken).balanceOf(address(this)));
        } else {
            _convertToLP();
        }
        if (balance() > _initial) {
            _deposit();
            return balance() - _initial;
        }
        return 0;
    }

    /**
     * @notice Remove all liquidity from the strategy, leaving rewards behind
     */
    function exit() external onlyLLToken {
        _withdraw(balance());
    }
}
