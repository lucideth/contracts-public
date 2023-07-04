pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";

contract rETHOracle is ISubOracle {
    IPriceOracle public priceOracle;

    constructor(address _parentOracle) public {
        priceOracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        return priceOracle.getChainlinkPrice(AggregatorV2V3Interface(0x536218f9E9Eb48863970252233c8F271f554C2d0)).mul(priceOracle.getETHPriceInUSD()).div(1e18);
    }

}