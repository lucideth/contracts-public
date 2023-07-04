// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";

contract SwapCVXToOETH {
    // @dev CVX token address
    address public cvxToken;
    // @dev Curve swapping pool address
    address public swappingPool;
    // @dev oETH token address
    address public oETH;

    /**
     * Initialize the contract
     * @param _cvxToken CVX token address
     * @param _swappingPool Curve swapping pool address
     * @param _oETH oETH token address
     */
    constructor(address _cvxToken, address _swappingPool, address _oETH) {
        cvxToken = _cvxToken;
        swappingPool = _swappingPool;
        oETH = _oETH;
    }

    /**
     * Get the oETH equivalent for the given CVX amount
     * @param _amountInCVX Amount of CVX
     */
    function toGetByOracle(uint _amountInCVX) public view returns (uint256) {
        uint _cvxToETH = uint(IOracle(0xC9CbF687f43176B302F03f5e58470b77D07c61c6).latestAnswer());
        // Considering OETH ~= ETH
        return (_amountInCVX * _cvxToETH) / 10 ** 18;
    }

    /**
     * Swap CVX to oETH
     */
    function swap(uint _amount) public returns (uint256) {
        if (_amount == 0) return 0;
        IERC20(cvxToken).transferFrom(msg.sender, address(this), _amount);
        IERC20(cvxToken).approve(swappingPool, _amount);
        ICurveSwap(swappingPool).exchange_multiple(
            [
                0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B,
                0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4,
                0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                0x94B17476A93b3262d87B9a326965D1E91f9c13E7,
                0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3,
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
        uint256 _oETHBalance = IERC20(oETH).balanceOf(address(this));
        IERC20(oETH).transfer(msg.sender, IERC20(oETH).balanceOf(address(this)));
        return _oETHBalance;
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
