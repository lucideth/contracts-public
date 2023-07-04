pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import '../../Interfaces/Balancer/IVault.sol';
import '../../Utils/VaultReentrancyLib.sol';

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ICurvePoolOracle.sol";
import "../interfaces/IBalancerRateProvider.sol";
import "../interfaces/IBalancerStablePool.sol";
import "../interfaces/IwstETH.sol";
import "hardhat/console.sol";

contract BalwstETHrETHsfrxETHOracle is ISubOracle {
    IPriceOracle public oracle;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    constructor(address _parentOracle) public {
        oracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        uint _stETHPriceInUsd = oracle.getChainlinkPrice(AggregatorV2V3Interface(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8)); // 1e18
        uint _ethPriceInUsd = oracle.getChainlinkPrice(AggregatorV2V3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419)); // 1e18
        IBalancerStablePool _bpt = IBalancerStablePool(0x5aEe1e99fE86960377DE9f88689616916D5DcaBe);
        uint _rateForWstETHFromRP = IBalancerRateProvider(_bpt.getRateProviders()[1]).getRate();
        uint _wstETH = _stETHPriceInUsd.mul(_rateForWstETHFromRP).div(1e18);

        uint _frxETHPriceInUsd = ICurvePoolOracle(0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577).price_oracle().mul(oracle.getETHPriceInUSD()).div(1e18); // 1e18
        uint _rateForsfrxETHFromRP = IBalancerRateProvider(_bpt.getRateProviders()[2]).getRate();
        uint _sfrxETH = _frxETHPriceInUsd.mul(_rateForsfrxETHFromRP).div(1e18);

        uint _rETHPriceInUsd = oracle.getChainlinkPrice(AggregatorV2V3Interface(0x536218f9E9Eb48863970252233c8F271f554C2d0)).mul(_ethPriceInUsd).div(1e18); // 1e18
        uint _rateForrETHFromRP = IBalancerRateProvider(_bpt.getRateProviders()[3]).getRate();
        uint _rETH = _rETHPriceInUsd.mul(_rateForrETHFromRP).div(1e18);

        uint _minPrice = min(min(_wstETH, _sfrxETH), _rETH);
        return _minPrice.mul(_bpt.getRate()).div(1e18);
    }
    function validate() external {
        VaultReentrancyLib.ensureNotInVaultContext(IVault(BALANCER_VAULT));
    }

}