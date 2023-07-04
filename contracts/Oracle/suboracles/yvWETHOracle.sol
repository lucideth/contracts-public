pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/ISFRXETH.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";

contract yvWETHOracle is ISubOracle {
    IPriceOracle public priceOracle;
    constructor(address _parentOracle) public {
        priceOracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        uint _ethPriceInUsd = priceOracle.getETHPriceInUSD(); // 1e18
        return _ethPriceInUsd.mul(ISFRXETH(0xa258C4606Ca8206D8aA700cE2143D7db854D168c).pricePerShare()).div(1e18); // ISFRXETH is compatible with Yearn Tokens
    }

}