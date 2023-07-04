pragma solidity ^0.5.16;

import "../Tokens/LLTokens/LLErc20.sol";
import "../Tokens/ERC20Interface.sol";
import "../Utils/SafeMath.sol";
import "./PriceOracle.sol";
import "./interfaces/AggregatorV2V3Interface.sol";
import "./interfaces/ISubOracle.sol";

import "hardhat/console.sol";
contract LsChainlinkOracle is PriceOracle {
    using SafeMath for uint;

    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Number of seconds before price data is considered stale
     */
    uint public maxStalePeriod;

    /**
     * @notice Direct prices in USD (1e18) to set for testing and for assets which don't have feeds
     */
    mapping(address => uint) internal prices;
    /**
     * @notice Direct prices in ETH (1e18) to set for testing and for assets which don't have feeds
     */
    mapping(address => uint) internal pricesInEth;
    /**
     * @notice Chainlink (x/USD) feeds to use as fallbacks for prices
     */
    mapping(address => AggregatorV2V3Interface) internal feeds;
    /**
     * @notice Chainlink feeds (x/ETH) to use as fallbacks for prices
     */
    mapping(address => AggregatorV2V3Interface) internal feedsInETH;
    /**
     * @notice Token to sub oracle mapping
     */
    mapping(address => address) internal tokenToSubOracle;

    /**
     * @notice Switch to enable/disable test mode
     */
    bool public testMode;

    /**
     * @notice Event emitted when a direct price is set
     */
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);
    /**
     * @notice Event emitted when a new admin is set
     */
    event NewAdmin(address oldAdmin, address newAdmin);
    /**
     * @notice Event emitted when a new feed is set
     */
    event FeedSet(address feed, address token);
    /**
     * @notice Event emitted when stale period is updated.
     */
    event MaxStalePeriodUpdated(uint oldMaxStalePeriod, uint newMaxStalePeriod);

    constructor(uint maxStalePeriod_) public {
        admin = msg.sender;
        maxStalePeriod = maxStalePeriod_;
        testMode = false;
    }

    /**
     * Sets the new maximum stale time allowed
     * @param newMaxStalePeriod The new max stale period.
     */
    function setMaxStalePeriod(uint newMaxStalePeriod) external onlyAdmin {
        require(newMaxStalePeriod > 0, "stale period can't be zero");
        uint oldMaxStalePeriod = maxStalePeriod;
        maxStalePeriod = newMaxStalePeriod;
        emit MaxStalePeriodUpdated(oldMaxStalePeriod, newMaxStalePeriod);
    }

    /**
     * Function to invoke security checks required by corresponding sub-iorcle.
     * @param llToken The llToken to check the underlying price of
     */
    function validateUnderlyingPrice(LLToken llToken) public {
        address _token = LLErc20(address(llToken)).underlying();
        if (tokenToSubOracle[_token] != address(0)) {
            ISubOracle(tokenToSubOracle[_token]).validate();
        }
    }

    /**
     * Returns the USD equivalent of the asset in 1e18
     * @param llToken The llToken to get the underlying price of
     */
    function getUnderlyingPrice(LLToken llToken) public view returns (uint) {
        string memory symbol = llToken.symbol();
        if (compareStrings(symbol, "llERC")) {
            return getChainlinkPrice(getFeed(address(llToken)));
        } else if (compareStrings(symbol, "DSD")) {
            return 1e18; // DSD always worth 1$
        } else if (compareStrings(symbol, "LTOKEN")) {
            return prices[address(llToken)];
        } else {
            return getPriceByLLToken(llToken);
        }
    }
    /**
     * Sets the test mode on or off. When on, the oracle will return the prices set in `prices` and `pricesInEth` mappings.
     * @param _testMode Switch to enable/disable test mode
     */
    function setTestMode(bool _testMode) external onlyAdmin {
        testMode = _testMode;
    }
    /**
     * Returns the price of the given asset in USD (1e18)
     * @param _token The token to get the price of
     */
    function getPriceInETH(address _token) public view returns (uint _price) {
        if (testMode) {
            return pricesInEth[_token];
        }
        return _getPrice(_token).mul(1e18).div(getETHPriceInUSD());
    }
    /**
     * Returns the price of the underlying in USD (1e18)
     * @param llToken The llToken to get the underlying price of
     */
    function getPriceByLLToken(LLToken llToken) internal view returns (uint price) {
        ERC20Interface token = ERC20Interface(LLErc20(address(llToken)).underlying());
        return _getPrice(address(token));
    }

    /**
     *
     * @param token The token to get the price of
     */
    function getPrice(address token) external view returns (uint) {
        return _getPrice(token);
    }

    /**
     * Returns the price of the given asset in USD (1e18)
     * @param token The token to get the USD price of
     */
    function _getPrice(address token) internal view returns (uint price) {
        if (testMode == true) {
            price = prices[address(token)];
        } else {
            if (tokenToSubOracle[token] != address(0)) {
                price = ISubOracle(tokenToSubOracle[token]).latestAnswer();
            } else {
                price = getChainlinkPrice(getFeed(token));
            }
        }

        uint decimalDelta = uint(18).sub(uint(ERC20Interface(token).decimals()));
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            return price.mul(10 ** decimalDelta);
        } else {
            return price;
        }
    }

    /**
     * Returns the USD equivalent of the ETH in 1e18
     */
    function getETHPriceInUSD() public view returns (uint) {
        if (testMode) {
            return prices[address(0)];
        }
        return getChainlinkPrice(AggregatorV2V3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419));
    }
    /**
     * Get the chainlink price for a feed
     * @param feed Chainlike feed for x/USD
     */
    function getChainlinkPrice(AggregatorV2V3Interface feed) public view returns (uint) {
        // Chainlink USD-denominated feeds store answers at 8 decimals
        uint decimalDelta = uint(18).sub(feed.decimals());

        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();

        // Ensure that we don't multiply the result by 0
        if (block.timestamp.sub(updatedAt) > maxStalePeriod && testMode == false) {
            revert("PRICE_OUTDATED");
        }

        if (decimalDelta > 0) {
            return uint(answer).mul(10 ** decimalDelta);
        } else {
            return uint(answer);
        }
    }

    /**
     * Manually set the price of underlying asset of a llToken
     * @param llToken The llToken to set the price of
     * @param underlyingPriceMantissa The mantissa of the underlying price
     */
    function setUnderlyingPrice(LLToken llToken, uint underlyingPriceMantissa) external onlyAdmin {
        address asset = address(LLErc20(address(llToken)).underlying());
        emit PricePosted(asset, prices[asset], underlyingPriceMantissa, underlyingPriceMantissa);
        prices[asset] = underlyingPriceMantissa;
    }

    /**
     * Manually set the price for test mode
     * @param asset Token address
     * @param price Price to set
     * @param isInETH Is the price provided in terms of USD or ETH
     */
    function setDirectPrice(address asset, uint price, bool isInETH) external onlyAdmin {
        if (isInETH) {
            pricesInEth[asset] = price;
            emit PricePosted(asset, pricesInEth[asset], price, price);
        } else {
            prices[asset] = price;
            emit PricePosted(asset, prices[asset], price, price);
        }
    }

    /**
     * Set the feed for a token in USD
     * @param _token The address of the asset to set the price of
     * @param feed The address of the feed
     */
    function setFeed(address _token, address feed) external onlyAdmin {
        require(feed != address(0) && feed != address(this), "invalid feed address");
        emit FeedSet(feed, _token);
        feeds[_token] = AggregatorV2V3Interface(feed);
    }
    /**
     * Set the feed for a symbol in ETH
     * @param _token The address of the asset to set the price of
     * @param feed The address of the feed
     */
    function setFeedInETH(address _token, address feed) external onlyAdmin {
        require(feed != address(0) && feed != address(this), "invalid feed address");
        emit FeedSet(feed, _token);
        feedsInETH[_token] = AggregatorV2V3Interface(feed);
    }

    /**
     * Price of Curve LP tokens is calculated from their pool's virtual price
     * @param _token Token address
     * @param _subOracle Corresponding Sub oracle
     */

    function setTokenToSubOracle(address _token, address _subOracle) external onlyAdmin {
        tokenToSubOracle[_token] = _subOracle;
    }

    /**
     * Get the feed for a token in USD
     * @param _token The address of the asset to get the price of
     */
    function getFeed(address _token)  public view returns  (AggregatorV2V3Interface) {
        return feeds[_token];
    }

    /**
     * Get the feed for a token in ETH
     * @param _token The address of the asset to get the price of
     */
    function getFeedInETH(address _token) public view returns (AggregatorV2V3Interface) {
        return feedsInETH[_token];
    }

    /**
     * Get the pre-set price for a token in USD
     * @param asset The address of the asset to get the price of
     */
    function assetPrices(address asset) external view returns (uint) {
        return prices[asset];
    }

    /**
     * Compare two strings
     * @param a First string
     * @param b Second string
     */
    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    /**
     * Sets the new admininistrator address
     * @param newAdmin The new admin address
     */
    function setAdmin(address newAdmin) external onlyAdmin {
        address oldAdmin = admin;
        admin = newAdmin;

        emit NewAdmin(oldAdmin, newAdmin);
    }

    /**
     * Modifier to check if the caller is the admin
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin may call");
        _;
    }
}
