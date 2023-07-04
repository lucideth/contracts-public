// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";

contract SwapCRVToStETH {
    // @dev CRV token address
    address public crllToken;
    // @dev Curve swapping pool address
    address public swappingPool;
    // @dev stETH token address
    address public stETH;

    /**
     * Initialize the contract
     * @param _crllToken CRV token address
     * @param _swappingPool Curve swapping pool address
     * @param _stETH stETH token address
     */
    constructor(address _crllToken, address _swappingPool, address _stETH) {
        crllToken = _crllToken;
        swappingPool = _swappingPool;
        stETH = _stETH;
    }

    /**
     * Get the stETH equivalent for the given CRV amount
     * @param _amountInCRV Amount of CRV
     */
    function toGetByOracle(uint _amountInCRV) public view returns (uint256) {
        uint _crvToETH = uint(IOracle(0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e).latestAnswer());
        uint _stETHToEth = uint(IOracle(0x86392dC19c0b719886221c78AB11eb8Cf5c52812).latestAnswer());
        return (_amountInCRV * _crvToETH) / _stETHToEth;
    }

    /**
     * Swap CRV to stETH
     */
    function swap(uint _amount) public returns (uint256) {
        if (_amount == 0) return 0;
        IERC20(crllToken).transferFrom(msg.sender, address(this), _amount);
        IERC20(crllToken).approve(swappingPool, _amount);
        ICurveSwap(swappingPool).exchange_multiple(
            [
                0xD533a949740bb3306d119CC777fa900bA034cd52,
                0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511,
                0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                0x21E27a5E5513D6e65C4f830167390997aA84843a,
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
