pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import '../../Interfaces/Balancer/IVault.sol';
import '../../Utils/VaultReentrancyLib.sol';

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IBalancerRateProvider.sol";
import "../interfaces/IBalancerStablePool.sol";
import "../interfaces/IwstETH.sol";
import "hardhat/console.sol";

contract BalWstETHWethOracle is ISubOracle {
    IPriceOracle public oracle;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    constructor(address _parentOracle) public {
        oracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        uint _stETHPriceInUsd = oracle.getChainlinkPrice(AggregatorV2V3Interface(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8)); // 1e18
        uint _ethPriceInUsd = oracle.getChainlinkPrice(AggregatorV2V3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419)); // 1e18
        IBalancerStablePool _bpt = IBalancerStablePool(0x32296969Ef14EB0c6d29669C550D4a0449130230);
        uint _rateForWstETHFromRP = IBalancerRateProvider(_bpt.getRateProviders()[0]).getRate();
        uint _minPrice = min(_stETHPriceInUsd.mul(_rateForWstETHFromRP).div(1e18), _ethPriceInUsd.div(1e18));
        return _minPrice.mul(_bpt.getRate());
    }
    function validate() external {
        VaultReentrancyLib.ensureNotInVaultContext(IVault(BALANCER_VAULT));
    }

}