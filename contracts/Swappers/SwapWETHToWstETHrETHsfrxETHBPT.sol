// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/Oracle/IOracle.sol";
import "../Interfaces/Oracle/ICurvePoolWithOracle.sol";
import "../Interfaces/Curve/ICurveSwap.sol";
import "./Exchanges/Balancer/BalancerExchange.sol";
import "./Exchanges/Balancer/interfaces/IAsset.sol";
import "./Exchanges/Balancer/interfaces/IVault.sol";

contract SwapWETHToWstETHrETHsfrxETHBPT is BalancerExchange {
    // @dev WETH token address
    address public weth;
    // @dev swapping pool address
    address public swappingPool;
    // @dev wstETHrETHsfrxETHBPT token address
    address public wstETHrETHsfrxETHBPT;

    /**
     * Initialize the contract
     * @param _weth WETH token address
     * @param _swappingPool swapping pool address
     * @param _wstETHrETHsfrxETHBPT wstETHrETHsfrxETHBPT token address
     */
    constructor(address _weth, address _swappingPool, address _wstETHrETHsfrxETHBPT) {
        weth = _weth;
        swappingPool = _swappingPool;
        wstETHrETHsfrxETHBPT = _wstETHrETHsfrxETHBPT;
        setVault(_swappingPool);
    }

    /**
     * Get the wstETHrETHsfrxETHBPT equivalent for the given WETH amount
     * @param _amountInWETH Amount of WETH
     */
    function toGetByOracle(uint _amountInWETH) public view returns (uint256) {
        return 0;
    }

    /**
     * Swap WETH to wstETHrETHsfrxETHBPT
     */
    function swap(uint _amount) public returns (uint256) {
        if (_amount == 0) return 0;
        IERC20(weth).transferFrom(msg.sender, address(this), _amount);
        super.batchExchange(
            0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080,
            0x5aee1e99fe86960377de9f88689616916d5dcabe000000000000000000000467,
            IVault.SwapKind.GIVEN_IN,
            IAsset(weth),
            IAsset(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0),
            IAsset(wstETHrETHsfrxETHBPT),
            address(this),
            payable(address(this)),
            _amount
        );

        uint256 _wstETHrETHsfrxETHBPTBalance = IERC20(wstETHrETHsfrxETHBPT).balanceOf(address(this));
        IERC20(wstETHrETHsfrxETHBPT).transfer(msg.sender, _wstETHrETHsfrxETHBPTBalance);
        return _wstETHrETHsfrxETHBPTBalance;
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
