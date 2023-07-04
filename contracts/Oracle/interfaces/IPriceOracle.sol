pragma solidity ^0.5.16;

import "../../Tokens/LLTokens/LLToken.sol";
import "./AggregatorV2V3Interface.sol";

contract IPriceOracle {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /**
     * @notice Get the underlying price of a llToken asset
     * @param llToken The llToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18).
     *  Zero means the price is unavailable.
     */
    function getUnderlyingPrice(LLToken llToken) external view returns (uint);

    /**
     * Get the price of ETH in USD
     */
    function getETHPriceInUSD() external view returns (uint);

    /**
     * Returns the price of the given asset in ETH
     * @param _token The token to get the price of
     */
    function getPriceInETH(address _token) external view returns (uint _price);

    function getChainlinkPrice(AggregatorV2V3Interface feed) external view returns (uint);

    function getFeed(string memory symbol) public view returns (AggregatorV2V3Interface feed);

    function getFeedInETH(string memory symbol) public view returns (AggregatorV2V3Interface);
}
