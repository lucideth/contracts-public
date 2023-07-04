// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Oracle/ICurvePoolWithOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";

contract SwapCRVToUSDC {
    // @dev CRV token address
    address public crv;
    // @dev Curve swapping pool address
    address public swappingPool;
    // @dev usdc token address
    address public usdc;

    /**
     * Initialize the contract
     * @param _crv CRV token address
     * @param _swappingPool Curve swapping pool address
     * @param _usdc usdc token address
     */
    constructor(address _crv, address _swappingPool, address _usdc) {
        crv = _crv;
        swappingPool = _swappingPool;
        usdc = _usdc;
    }

    function name() public pure returns (string memory) {
        return "SwapCRVToUSDC";
    }

    /**
     * Get the usdc equivalent for the given CRV amount
     * @param _amountInCRV Amount of CRV
     */
    function toGetByOracle(uint _amountInCRV) public view returns (uint256) {
        uint _crvToUSD = uint(IOracle(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f).latestAnswer());
        return (_amountInCRV * _crvToUSD) / 10 ** 20;
    }

    /**
     * Swap CRV to usdc
     */
    function swap(uint _amount) public returns (uint256) {
        if (_amount == 0) return 0;
        IERC20(crv).transferFrom(msg.sender, address(this), _amount);

        IERC20(crv).approve(0x9D0464996170c6B9e75eED71c68B99dDEDf279e8, _amount);
        ICurveSwap(0x9D0464996170c6B9e75eED71c68B99dDEDf279e8).exchange(int128(0), int128(1), _amount, 0);

        uint256 _convexCRVBalance = IERC20(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7).balanceOf(address(this));
        IERC20(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7).approve(
            0x31c325A01861c7dBd331a9270296a31296D797A0,
            _convexCRVBalance
        );
        ICurveSwap(0x31c325A01861c7dBd331a9270296a31296D797A0).exchange(uint256(0), uint256(1), _convexCRVBalance, 0);

        uint256 _frxUSDCBalance = IERC20(0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC).balanceOf(address(this));
        IERC20(0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC).approve(
            0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2,
            _frxUSDCBalance
        );
        ICurveSwap(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2).remove_liquidity_one_coin(_frxUSDCBalance, int128(1), 0);

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
