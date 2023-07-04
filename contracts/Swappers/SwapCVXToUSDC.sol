// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Oracle/ICurvePoolWithOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";

contract SwapCVXToUSDC {
    // @dev CVX token address
    address public cvx;
    // @dev Curve swapping pool address
    address public swappingPool;
    // @dev usdc token address
    address public usdc;

    /**
     * Initialize the contract
     * @param _cvx CVX token address
     * @param _swappingPool Curve swapping pool address
     * @param _usdc usdc token address
     */
    constructor(address _cvx, address _swappingPool, address _usdc) {
        cvx = _cvx;
        swappingPool = _swappingPool;
        usdc = _usdc;
    }

    function name() public pure returns (string memory) {
        return "SwapCVXToUSDC";
    }

    /**
     * Get the usdc equivalent for the given CVX amount
     * @param _amountInCVX Amount of CVX
     */
    function toGetByOracle(uint _amountInCVX) public view returns (uint256) {
        uint _cvxToUSD = uint(IOracle(0xd962fC30A72A84cE50161031391756Bf2876Af5D).latestAnswer());
        return (_amountInCVX * _cvxToUSD) / 10 ** 20;
    }

    /**
     * Swap CVX to usdc
     */
    function swap(uint _amount) public returns (uint256) {
        if (_amount == 0) return 0;
        IERC20(cvx).transferFrom(msg.sender, address(this), _amount);

        IERC20(cvx).approve(swappingPool, _amount);
        ICurveSwap(swappingPool).exchange_multiple(
            [
                0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B,
                0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4,
                0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B,
                0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000
            ],
            [
                [uint(1), uint(0), uint(3)],
                [uint(0), uint(1), uint(15)],
                [uint(2), uint(0), uint(3)],
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
        uint256 _usdcBalance = IERC20(usdc).balanceOf(address(this));
        IERC20(usdc).transfer(msg.sender, _usdcBalance);
        return _usdcBalance;
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
