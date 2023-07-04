pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ICurvePoolOracle.sol";

contract steCRVOracle is ISubOracle {
    IPriceOracle public oracle;

    address public constant POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant STETHUSD = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;

    constructor(address _parentOracle) public {
        oracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        return
            min((oracle.getETHPriceInUSD()), oracle.getChainlinkPrice(AggregatorV2V3Interface(STETHUSD)))
                .mul(ICurvePoolOracle(POOL).get_virtual_price())
                .div(1e18);
    }
}
