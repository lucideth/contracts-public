pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ICurvePoolOracle.sol";

contract sfrxETHOracle is ISubOracle {
    IPriceOracle public priceOracle;

    constructor(address _parentOracle) public {
        priceOracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        return ICurvePoolOracle(0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577).price_oracle().mul(priceOracle.getETHPriceInUSD()).div(1e18);
    }

}