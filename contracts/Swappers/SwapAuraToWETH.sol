// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Oracle/ICurvePoolWithOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";
import "./Exchanges/Balancer/BalancerExchange.sol";
import "./Exchanges/Balancer/interfaces/IAsset.sol";
import "./Exchanges/Balancer/interfaces/IVault.sol";

contract SwapAuraToWETH is BalancerExchange {
    // @dev AURA token address
    address public aura;
    // @dev swapping pool address
    address public swappingPool;
    // @dev weth token address
    address public weth;

    /**
     * Initialize the contract
     * @param _aura AURA token address
     * @param _swappingPool swapping pool address
     * @param _weth weth token address
     */
    constructor(address _aura, address _swappingPool, address _weth) {
        aura = _aura;
        swappingPool = _swappingPool;
        weth = _weth;
        setVault(_swappingPool);
    }

    /**
     * Get the reth equivalent for the given AURA amount
     * @param _amountInAURA Amount of AURA
     */
    function toGetByOracle(uint _amountInAURA) public view returns (uint256) {
        return 0;
    }

    /**
     * Swap AURA to reth
     */
    function swap(uint _amount) public returns (uint256) {
        if (_amount == 0) return 0;
        IERC20(aura).transferFrom(msg.sender, address(this), _amount);
        super.exchange(
            0xc29562b045d80fd77c69bec09541f5c16fe20d9d000200000000000000000251,
            IVault.SwapKind.GIVEN_IN,
            IAsset(aura),
            IAsset(weth),
            address(this),
            address(this),
            _amount,
            0
        );
        uint256 _wethBalance = IERC20(weth).balanceOf(address(this));
        IERC20(weth).transfer(msg.sender, _wethBalance);
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
