// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Oracle/ICurvePoolWithOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";

contract SwapCRVToFrxETH {
    // @dev CRV token address
    address public crllToken;
    // @dev Curve swapping pool address
    address public swappingPool;
    // @dev frxETH token address
    address public frxETH;

    /**
     * Initialize the contract
     * @param _crllToken CRV token address
     * @param _swappingPool Curve swapping pool address
     * @param _frxETH frxETH token address
     */
    constructor(address _crllToken, address _swappingPool, address _frxETH) {
        crllToken = _crllToken;
        swappingPool = _swappingPool;
        frxETH = _frxETH;
    }

    /**
     * Get the frxETH equivalent for the given CRV amount
     * @param _amountInCRV Amount of CRV
     */
    function toGetByOracle(uint _amountInCRV) public view returns (uint256) {
        uint _crvToETH = uint(IOracle(0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e).latestAnswer());
        uint _frxETHToEth = uint(ICurvePoolWithOracle(0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577).price_oracle());
        return (_amountInCRV * _crvToETH) / _frxETHToEth;
    }

    /**
     * Swap CRV to frxETH
     */
    function swap(uint _amount) public returns (uint256) {
        if (_amount == 0) return 0;
        IERC20(crllToken).transferFrom(msg.sender, address(this), _amount);
        IERC20(crllToken).approve(swappingPool, _amount);
        ICurveSwap(swappingPool).exchange_multiple(
            [
                0xD533a949740bb3306d119CC777fa900bA034cd52,
                0x442F37cfD85D3f35e576AD7D63bBa7Bb36fCFe4a,
                0x5E8422345238F34275888049021821E8E08CAa1f,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000,
                0x0000000000000000000000000000000000000000
            ],
            [
                [uint(0), uint(1), uint(3)],
                [uint(0), uint(0), uint(0)],
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
