// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";

contract SwapLDOToStETH {
    address public ldoToken;
    address public swappingPool;
    address public stETH;

    constructor(address _ldoToken, address _swappingPool, address _stETH) {
        ldoToken = _ldoToken;
        swappingPool = _swappingPool;
        stETH = _stETH;
    }

    // @dev returns in 1e18
    function toGetByOracle(uint _amountInLDO) public view returns (uint256) {
        uint _ldoToETH = uint(IOracle(0x4e844125952D32AcdF339BE976c98E22F6F318dB).latestAnswer());
        uint _stETHToEth = uint(IOracle(0x86392dC19c0b719886221c78AB11eb8Cf5c52812).latestAnswer());
        return (_amountInLDO * _ldoToETH) / _stETHToEth;
    }

    function swap(uint _amount) external {
        if (_amount == 0) return;
        IERC20(ldoToken).transferFrom(msg.sender, address(this), _amount);
        IERC20(ldoToken).approve(swappingPool, _amount);
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
        IERC20(stETH).transfer(msg.sender, IERC20(stETH).balanceOf(address(this)));
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
