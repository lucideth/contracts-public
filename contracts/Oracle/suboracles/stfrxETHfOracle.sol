pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ICurvePoolOracle.sol";

contract stfrxETHfOracle is ISubOracle {
    IPriceOracle public oracle;

    address public constant POOL = 0x4d9f9D15101EEC665F77210cB999639f760F831E;
    address public constant FRXETHPOOL = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address public constant STETHUSD = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;

    constructor(address _parentOracle) public {
        oracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        return
            min(ICurvePoolOracle(FRXETHPOOL).price_oracle().mul(oracle.getETHPriceInUSD()), oracle.getChainlinkPrice(AggregatorV2V3Interface(STETHUSD)))
                .mul(ICurvePoolOracle(POOL).get_virtual_price())
                .div(1e18);
    }
}
