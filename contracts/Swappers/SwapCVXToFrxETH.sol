// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";
import "../Interfaces/Oracle/ICurvePoolWithOracle.sol";

contract SwapCVXToFrxETH {
    // @dev CVX token address
    address public cvxToken;
    // @dev Curve swapping pool address
    address public swappingPool;
    // @dev frxETH token address
    address public frxETH;

    /**
     * Initialize the contract
     * @param _cvxToken CVX token address
     * @param _swappingPool Curve swapping pool address
     * @param _frxETH frxETH token address
     */
    constructor(address _cvxToken, address _swappingPool, address _frxETH) {
        cvxToken = _cvxToken;
        swappingPool = _swappingPool;
        frxETH = _frxETH;
    }

    /**
     * Get the frxETH equivalent for the given CVX amount
     * @param _amountInCVX Amount of CVX
     */
    function toGetByOracle(uint _amountInCVX) public view returns (uint256) {
        uint _cvxToETH = uint(IOracle(0xC9CbF687f43176B302F03f5e58470b77D07c61c6).latestAnswer());
        uint _frxETHToEth = uint(ICurvePoolWithOracle(0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577).price_oracle());
        return (_amountInCVX * _cvxToETH) / _frxETHToEth;
    }

    /**
     * Swap CVX to frxETH
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
                0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577,
                0x5E8422345238F34275888049021821E8E08CAa1f,
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
        uint256 _frxETHBalance = IERC20(frxETH).balanceOf(address(this));
        IERC20(frxETH).transfer(msg.sender, IERC20(frxETH).balanceOf(address(this)));
        return _frxETHBalance;
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
