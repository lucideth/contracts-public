// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";

contract SwapCRVToOETH {
    // @dev CRV token address
    address public crllToken;
    // @dev Curve swapping pool address
    address public swappingPool;
    // @dev oETH token address
    address public oETH;

    /**
     * Initialize the contract
     * @param _crllToken CRV token address
     * @param _swappingPool Curve swapping pool address
     * @param _oETH oETH token address
     */
    constructor(address _crllToken, address _swappingPool, address _oETH) {
        crllToken = _crllToken;
        swappingPool = _swappingPool;
        oETH = _oETH;
    }

    /**
     * Get the oETH equivalent for the given CRV amount
     * @param _amountInCRV Amount of CRV
     */
    function toGetByOracle(uint _amountInCRV) public view returns (uint256) {
        uint _crvToETH = uint(IOracle(0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e).latestAnswer());
        // Considering OETH ~= ETH
        return (_amountInCRV * _crvToETH) / 10 ** 18;
    }

    /**
     * Swap CRV to oETH
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
