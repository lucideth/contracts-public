// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";

contract SwapCVXToStETH {
    // @dev CVX token address
    address public cvxToken;
    // @dev Curve swapping pool address
    address public swappingPool;
    // @dev stETH token address
    address public stETH;

    /**
     * Initialize the contract
     * @param _cvxToken CVX token address
     * @param _swappingPool Curve swapping pool address
     * @param _stETH stETH token address
     */
    constructor(address _cvxToken, address _swappingPool, address _stETH) {
        cvxToken = _cvxToken;
        swappingPool = _swappingPool;
        stETH = _stETH;
    }

    /**
     * Get the stETH equivalent for the given CVX amount
     * @param _amountInCVX Amount of CVX
     */
    function toGetByOracle(uint _amountInCVX) public view returns (uint256) {
        uint _cvxToETH = uint(IOracle(0xC9CbF687f43176B302F03f5e58470b77D07c61c6).latestAnswer());
        uint _stETHToEth = uint(IOracle(0x86392dC19c0b719886221c78AB11eb8Cf5c52812).latestAnswer());
        return (_amountInCVX * _cvxToETH) / _stETHToEth;
    }

    /**
     * Swap CVX to stETH
     */
    function swap(uint _amount) public returns (uint256) {
        if (_amount == 0) return 0;
        IERC20(cvxToken).transferFrom(msg.sender, address(this), _amount);
        IERC20(cvxToken).approve(swappingPool, _amount);
        ICurveSwap(swappingPool).exchange_multiple(
            [
                0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B,
                0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4,
                0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                0x828b154032950C8ff7CF8085D841723Db2696056,
                0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000
            ],
            [
                [uint(1), uint(0), uint(3)],
                [uint(0), uint(1), uint(1)],
                [uint(0), uint(0), uint(0)],
                [uint(0), uint(0), uint(0)]
            ],
            _amount,
            subtractBasisPoints(toGetByOracle(_amount), 300), // -3%
            [
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000
            ],
            address(this)
        );
        uint256 _stETHBalance = IERC20(stETH).balanceOf(address(this));
        IERC20(stETH).transfer(msg.sender, IERC20(stETH).balanceOf(address(this)));
        return _stETHBalance;
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
