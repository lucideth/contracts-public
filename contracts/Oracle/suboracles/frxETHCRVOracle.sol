pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ICurvePoolOracle.sol";

contract frxETHCRVOracle is ISubOracle {
    IPriceOracle public oracle;

    address public constant POOL = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;

    constructor(address _parentOracle) public {
        oracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        return
            min(oracle.getETHPriceInUSD(), ICurvePoolOracle(POOL).price_oracle().mul(oracle.getETHPriceInUSD()))
                .mul(ICurvePoolOracle(POOL).get_virtual_price())
                .div(1e18);
    }
}
