pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/ICurvePoolOracle.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IRocketTokenRETH.sol";


contract CrvREthWstETHOracle is ISubOracle {
    IRocketTokenRETH private constant RETH = IRocketTokenRETH(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ICurvePoolOracle private constant RETH_WSTETH = ICurvePoolOracle(0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08);
    AggregatorV2V3Interface private constant STETH = AggregatorV2V3Interface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);
    IPriceOracle public priceOracle;

    constructor(address _parentOracle) public {
        priceOracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        uint256 rETH_Price = RETH.getExchangeRate(); // 1eth * exchangeRate / 1e18
        uint256 stETH_Price = uint256(STETH.latestAnswer());
        if (rETH_Price > stETH_Price) return RETH_WSTETH.get_virtual_price().mul(rETH_Price).mul(priceOracle.getETHPriceInUSD()).div(1e36);

        return RETH_WSTETH.get_virtual_price().mul(rETH_Price).mul(priceOracle.getETHPriceInUSD()).div(1e36);
    }

}