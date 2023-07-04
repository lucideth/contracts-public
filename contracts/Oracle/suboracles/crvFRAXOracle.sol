pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ICurvePoolOracle.sol";

contract crvFRAXOracle is ISubOracle {
    IPriceOracle public oracle;

    address public constant POOL = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2;
    address public constant FRAXUSD = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address public constant USDCUSD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    constructor(address _parentOracle) public {
        oracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        return
            min(oracle.getChainlinkPrice(AggregatorV2V3Interface(FRAXUSD)), oracle.getChainlinkPrice(AggregatorV2V3Interface(USDCUSD)))
                .mul(ICurvePoolOracle(POOL).get_virtual_price()).mul(oracle.getETHPriceInUSD())
                .div(1e36);
    }
}
