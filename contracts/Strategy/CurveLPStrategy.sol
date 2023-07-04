// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8;
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../Interfaces/Curve/ICurvePool.sol";
import "../Interfaces/Curve/ICurveGauge.sol";
import "../Interfaces/Curve/ICurveMinter.sol";
import "../Interfaces/Convex/IBooster.sol";
import "../Interfaces/Convex/IBaseRewardPool.sol";
import "../Interfaces/Swapper/ISwap.sol";

import "hardhat/console.sol";

/**
 * @title CurveLPStrategy
 * @notice Strategy for Curve LP tokens to be staked in Curve guages
 */
contract CurveLPStrategy {
    using SafeERC20 for IERC20Metadata;

    /**
     * @notice llToken address
     */
    address public lltoken;

    /**
     * @notice Curve related address
     */
    address public curvePool;
    address public curveLPToken;
    address public curveGauge;
    address public crvMinter;

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

    /*
     * @notice depositIndices[0] = Index of deposit token in curve pool
     * @notice depositIndices[1] = Underlying token index in curve pool
     */
    uint8[] public depositIndices;

    /*
     * @notice Convex related parameters
     */
    uint256 public pid;
    address public cvxDepositToken;
    address public cvxRewards;
    address public cvxClaimZap;
    address public cvxBooster;

    /*
     * @notice Modifier to check only llToken can call the function
     */
    modifier onlyLLToken() {
        require(msg.sender == lltoken, "only lltoken");
        _;
    }

    /**
     * Initialize the strategy
     * @param _lltoken LLtoken address
     * @param _curvePool Curve Pool address
     * @param _curveLPToken  Curve LP token address
     * @param _crvMinter  Curve minter address
     * @param _curveGauge  Curve gauge address
     * @param _swappedToken  Token to which reward tokens will be swapped into
     * @param _rewardTokens  Reward tokens
     * @param _swappingPools  Swapping pools in order of rewardTokens
     * @param _depositIndices  Indices of deposit token and underlying token in curve pool
     */
    constructor(
        address _lltoken,
        address _curvePool,
        address _curveLPToken,
        address _crvMinter,
        address _curveGauge,
        address _swappedToken,
        address[] memory _rewardTokens,
        address[] memory _swappingPools,
        uint8[] memory _depositIndices
    ) {
        lltoken = _lltoken;
        curvePool = _curvePool;
        curveLPToken = _curveLPToken;
        crvMinter = _crvMinter;
        curveGauge = _curveGauge;
        swappedToken = _swappedToken;
        rewardTokens = _rewardTokens;
        swappingPools = _swappingPools;
        depositIndices = _depositIndices;
    }

    /**
     * @notice Set the convex parameters
     */
    function setConvexParams(uint256 _pid, address _cvxDepositToken, address _cvxRewards, address _cvxClaimZap, address _booster) external {
        require(pid == 0, "Already set!");
        pid = _pid;
        cvxDepositToken = _cvxDepositToken;
        cvxRewards = _cvxRewards;
        cvxClaimZap = _cvxClaimZap;
        cvxBooster = _booster;
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
        return IERC20Metadata(curveLPToken).balanceOf(address(this)) + IERC20Metadata(cvxRewards).balanceOf(address(this));
    }

    /**
     * @notice Raw token present in the contract
     */
    function available() internal view returns (uint256) {
        return IERC20Metadata(curveLPToken).balanceOf(address(this));
    }

    /**
     * @notice Deposit the LP token present in the strategy to the curve gauge
     */
    function deposit() external onlyLLToken {
        _deposit();
    }

    /**
     * @notice Deposit the LP token present in the strategy to the curve gauge
     */
    function _deposit() internal {
        uint256 _lpTokenBalance = balance() -  IERC20Metadata(cvxRewards).balanceOf(address(this));
        IERC20Metadata(curveLPToken).approve(cvxBooster, _lpTokenBalance);
        IBooster(cvxBooster).depositAll(pid, true);
    }

    /**
     * Withdraw the LP tokens from the curve gauge
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
            IBaseRewardPool(cvxRewards).withdrawAndUnwrap(_amount - available(), false);
        }
        IERC20Metadata(curveLPToken).safeTransfer(lltoken, _amount);
    }

    /**
     * Generate deposit amounts array for 2 assets
     * @param _amount Amount of LP tokens for which deposit array needs to be created
     */
    function _getAmountsForTwoAssets(uint256 _amount) internal view returns (uint256[2] memory) {
        uint256[2] memory _amounts = [uint256(0), uint256(0)];
        _amounts[depositIndices[1]] = _amount;
        return _amounts;
    }

    /**
     * Generate deposit amounts array for 3 assets
     * @param _amount Amount of LP tokens for which deposit array needs to be created
     */
    function _getAmountsForThreeAssets(uint256 _amount) internal view returns (uint256[3] memory) {
        uint256[3] memory _amounts = [uint256(0), uint256(0), uint256(0)];
        _amounts[depositIndices[1]] = _amount;
        return _amounts;
    }

    /**
     * Generate deposit amounts array for 4 assets
     * @param _amount Amount of LP tokens for which deposit array needs to be created
     */
    function _getAmountsForFourAssets(uint256 _amount) internal view returns (uint256[4] memory) {
        uint256[4] memory _amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
        _amounts[depositIndices[1]] = _amount;
        return _amounts;
    }

    /**
     * Convert the swapped token to LP tokens
     */
    function _convertToLP() internal {
        uint _toMint = IERC20Metadata(swappedToken).balanceOf(address(this));
        if (_toMint == 0) return;
        // For 18 decimals: Threshold 10**6
        // For 6 decimals: Threshold 10**2
        if (_toMint < 10 ** (IERC20Metadata(swappedToken).decimals() / 3)) {
            return;
        }
        uint256 _minMintAmount;
        IERC20Metadata(swappedToken).approve(address(curvePool), _toMint);
        if (depositIndices[0] == 2) {
            uint256[2] memory _amounts = _getAmountsForTwoAssets(_toMint);
            _minMintAmount = ICurvePool(curvePool).calc_token_amount(_amounts, true);
            _minMintAmount = subtractBasisPoints(_minMintAmount, 300);
            ICurvePool(curvePool).add_liquidity(_amounts, _minMintAmount);
        } else if (depositIndices[0] == 3) {
            uint256[3] memory _amounts = _getAmountsForThreeAssets(_toMint);
            _minMintAmount = ICurvePool(curvePool).calc_token_amount(_amounts, true);
            _minMintAmount = subtractBasisPoints(_minMintAmount, 300);
            ICurvePool(curvePool).add_liquidity(_amounts, _minMintAmount);
        } else if (depositIndices[0] == 4) {
            uint256[4] memory _amounts = _getAmountsForFourAssets(_toMint);
            _minMintAmount = ICurvePool(curvePool).calc_token_amount(_amounts, true);
            _minMintAmount = subtractBasisPoints(_minMintAmount, 300);
            ICurvePool(curvePool).add_liquidity(_amounts, _minMintAmount);
        }
    }

    /**
     * Collect the rewards, swap them to swapped token, convert them to LP and stake them
     */
    function collectRewards() external onlyLLToken returns (uint256) {
        uint _initial = balance();
        IBaseRewardPool(cvxRewards).getReward(address(this), true);
        for (uint8 i = 0; i < rewardTokens.length; i++) {
            uint _reward = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
            console.log("Reward collected %s: %s", i, _reward);
            if (_reward < 10 ** 10) {
                continue;
            }
            IERC20Metadata(rewardTokens[i]).approve(swappingPools[i], _reward);
            ISwap(swappingPools[i]).swap(_reward);
        }
        _convertToLP();
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

    /**
     * Utility function to subtract basis points
     * @param _value Value to work on
     * @param _points Basis points
     */
    function subtractBasisPoints(uint _value, uint _points) public pure returns (uint256) {
        return (_value * (10 ** 4 - _points)) / 10 ** 4;
    }
}
