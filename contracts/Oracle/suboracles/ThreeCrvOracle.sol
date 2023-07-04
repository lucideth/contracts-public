pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ICurvePoolOracle.sol";

contract ThreeCrvOracle is ISubOracle {
    IPriceOracle public oracle;

    address public constant POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address public constant DAIUSD = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public constant USDCUSD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public constant USDTUSD = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

    constructor(address _parentOracle) public {
        oracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        return
            min(min(oracle.getChainlinkPrice(AggregatorV2V3Interface(DAIUSD)), oracle.getChainlinkPrice(AggregatorV2V3Interface(USDCUSD))), oracle.getChainlinkPrice(AggregatorV2V3Interface(USDTUSD)))
                .mul(ICurvePoolOracle(POOL).get_virtual_price()).mul(oracle.getETHPriceInUSD())
                .div(1e36);
    }
}
