// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Oracle/ICurvePoolWithOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";
import "./Exchanges/Balancer/BalancerExchange.sol";
import "./Exchanges/Balancer/interfaces/IAsset.sol";
import "./Exchanges/Balancer/interfaces/IVault.sol";

contract SwapBalToWETH is BalancerExchange {
    // @dev BAL token address
    address public bal;
    // @dev swapping pool address
    address public swappingPool;
    // @dev weth token address
    address public weth;

    /**
     * Initialize the contract
     * @param _bal BAL token address
     * @param _swappingPool swapping pool address
     * @param _weth weth token address
     */
    constructor(address _bal, address _swappingPool, address _weth) {
        bal = _bal;
        swappingPool = _swappingPool;
        weth = _weth;
        setVault(_swappingPool);
    }

    /**
     * Get the weth equivalent for the given BAL amount
     * @param _amountInBAL Amount of BAL
     */
    function toGetByOracle(uint _amountInBAL) public view returns (uint256) {
        return 0;
    }

    /**
     * Swap BAL to weth
     */
    function swap(uint _amount) public returns (uint256) {
        if (_amount == 0) return 0;
        IERC20(bal).transferFrom(msg.sender, address(this), _amount);
        super.exchange(
            0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014,
            IVault.SwapKind.GIVEN_IN,
            IAsset(bal),
            IAsset(weth),
            address(this),
            address(this),
            _amount,
            0
        );
        uint256 _wethBalance = IERC20(weth).balanceOf(address(this));
        IERC20(weth).transfer(msg.sender, IERC20(weth).balanceOf(address(this)));
        return _wethBalance;
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
