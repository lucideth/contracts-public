pragma solidity ^0.5.16;

import "../interfaces/IPriceOracle.sol";
import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";

contract cbETHOracle is ISubOracle {
    IPriceOracle public priceOracle;

    constructor(address _parentOracle) public {
        priceOracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        return priceOracle.getChainlinkPrice(AggregatorV2V3Interface(0xF017fcB346A1885194689bA23Eff2fE6fA5C483b)).mul(priceOracle.getETHPriceInUSD()).div(1e18);
    }

}