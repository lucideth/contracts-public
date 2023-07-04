pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ICurvePoolOracle.sol";

interface OriginVault {
    function totalValue() external view returns (uint256);
}
interface IERC20 {
    function totalSupply() external view returns (uint256);
}

contract OETHCRVfOracle is ISubOracle {
    IPriceOracle public oracle;

    address public constant POOL = 0x94B17476A93b3262d87B9a326965D1E91f9c13E7;

    constructor(address _parentOracle) public {
        oracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        uint _priceOfOETH = OriginVault(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab).totalValue().mul(1e18).div(IERC20(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3).totalSupply());
        return
            min(oracle.getETHPriceInUSD(), _priceOfOETH.mul(oracle.getETHPriceInUSD()))
                .mul(ICurvePoolOracle(POOL).get_virtual_price())
                .div(1e18);
    }
}
