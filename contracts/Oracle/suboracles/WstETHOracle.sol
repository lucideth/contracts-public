pragma solidity ^0.5.16;

import "../interfaces/ISubOracle.sol";
import "../interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IwstETH.sol";

contract WstETHOracle is ISubOracle {

    IPriceOracle public priceOracle;

    constructor(address _parentOracle) public {
        priceOracle = IPriceOracle(_parentOracle);
    }

    function latestAnswer() external view returns (uint256) {
        uint _tokensPerStEth = IwstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0).tokensPerStEth();
        return priceOracle.getChainlinkPrice(AggregatorV2V3Interface(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8)).mul(_tokensPerStEth).div(1e18);
    }

}