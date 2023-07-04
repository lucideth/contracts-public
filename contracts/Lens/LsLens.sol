pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../Tokens/LLTokens/LLErc20.sol";
import "../Tokens/LLTokens/LLToken.sol";
import "../Oracle/PriceOracle.sol";
import "../Tokens/EIP20Interface.sol";
import "../Tokens/LTOKEN/LTOKEN.sol";
import "../Comptroller/ComptrollerInterface.sol";
import "../Utils/SafeMath.sol";

contract LsLens is ExponentialNoError {
    using SafeMath for uint;

    /// @notice Blocks Per Day
    uint public constant BLOCKS_PER_DAY = 28800;

    struct LLTokenMetadata {
        address llToken;
        uint exchangeRateCurrent;
        uint supplyRatePerBlock;
        uint borrowRatePerBlock;
        uint reserveFactorMantissa;
        uint totalBorrows;
        uint totalReserves;
        uint totalSupply;
        uint totalCash;
        bool isListed;
        uint collateralFactorMantissa;
        address underlyingAssetAddress;
        uint llTokenDecimals;
        uint underlyingDecimals;
        uint lsSupplySpeed;
        uint lsBorrowSpeed;
        uint dailySupplyLtoken;
        uint dailyBorrowLtoken;
    }

    struct LLTokenBalances {
        address llToken;
        uint balanceOf;
        uint borrowBalanceCurrent;
        uint balanceOfUnderlying;
        uint tokenBalance;
        uint tokenAllowance;
    }

    struct LLTokenUnderlyingPrice {
        address llToken;
        uint underlyingPrice;
    }

    struct AccountLimits {
        LLToken[] markets;
        uint liquidity;
        uint shortfall;
    }

    struct LTOKENBalanceMetadata {
        uint balance;
    }

    struct LTOKENBalanceMetadataExt {
        uint balance;
        uint allocated;
    }

    /**
     * @notice Query the metadata of a llToken by its address
     * @param llToken The address of the llToken to fetch LLTokenMetadata
     * @return LLTokenMetadata struct with llToken supply and borrow information.
     */
    function llTokenMetadata(LLToken llToken) public returns (LLTokenMetadata memory) {
        uint exchangeRateCurrent = llToken.exchangeRateCurrent();
        address comptrollerAddress = address(llToken.comptroller());
        ComptrollerInterface comptroller = ComptrollerInterface(comptrollerAddress);
        (bool isListed, uint collateralFactorMantissa) = comptroller.markets(address(llToken));
        address underlyingAssetAddress;
        uint underlyingDecimals;

        if (compareStrings(llToken.symbol(), "llERC")) {
            underlyingAssetAddress = address(0);
            underlyingDecimals = 18;
        } else {
            LLErc20 llErc20 = LLErc20(address(llToken));
            underlyingAssetAddress = llErc20.underlying();
            underlyingDecimals = EIP20Interface(llErc20.underlying()).decimals();
        }

        uint lsSupplySpeedPerBlock = comptroller.lsSupplySpeeds(address(llToken));
        uint lsBorrowSpeedPerBlock = comptroller.lsBorrowSpeeds(address(llToken));

        return
            LLTokenMetadata({
                llToken: address(llToken),
                exchangeRateCurrent: exchangeRateCurrent,
                supplyRatePerBlock: 0,
                borrowRatePerBlock: 0,
                reserveFactorMantissa: llToken.reserveFactorMantissa(),
                totalBorrows: llToken.totalBorrows(),
                totalReserves: llToken.totalReserves(),
                totalSupply: llToken.totalSupply(),
                totalCash: llToken.getCash(),
                isListed: isListed,
                collateralFactorMantissa: collateralFactorMantissa,
                underlyingAssetAddress: underlyingAssetAddress,
                llTokenDecimals: llToken.decimals(),
                underlyingDecimals: underlyingDecimals,
                lsSupplySpeed: lsSupplySpeedPerBlock,
                lsBorrowSpeed: lsBorrowSpeedPerBlock,
                dailySupplyLtoken: lsSupplySpeedPerBlock.mul(BLOCKS_PER_DAY),
                dailyBorrowLtoken: lsBorrowSpeedPerBlock.mul(BLOCKS_PER_DAY)
            });
    }

    /**
     * @notice Get LLTokenMetadata for an array of llToken addresses
     * @param llTokens Array of llToken addresses to fetch LLTokenMetadata
     * @return Array of structs with llToken supply and borrow information.
     */
    function llTokenMetadataAll(LLToken[] calldata llTokens) external returns (LLTokenMetadata[] memory) {
        uint llTokenCount = llTokens.length;
        LLTokenMetadata[] memory res = new LLTokenMetadata[](llTokenCount);
        for (uint i = 0; i < llTokenCount; i++) {
            res[i] = llTokenMetadata(llTokens[i]);
        }
        return res;
    }

    /**
     * @notice Get amount of LTOKEN distributed daily to an account
     * @param account Address of account to fetch the daily LTOKEN distribution
     * @param comptrollerAddress Address of the comptroller proxy
     * @return Amount of LTOKEN distributed daily to an account
     */
    function getDailyLTOKEN(address payable account, address comptrollerAddress) external returns (uint) {
        ComptrollerInterface comptrollerInstance = ComptrollerInterface(comptrollerAddress);
        LLToken[] memory llTokens = comptrollerInstance.getAllMarkets();
        uint dailyLtokenPerAccount = 0;

        for (uint i = 0; i < llTokens.length; i++) {
            LLToken llToken = llTokens[i];
            if (!compareStrings(llToken.symbol(), "vUST") && !compareStrings(llToken.symbol(), "vLUNA")) {
                LLTokenMetadata memory metaDataItem = llTokenMetadata(llToken);

                //get balanceOfUnderlying and borrowBalanceCurrent from llTokenBalance
                LLTokenBalances memory llTokenBalanceInfo = llTokenBalances(llToken, account);

                LLTokenUnderlyingPrice memory underlyingPriceResponse = llTokenUnderlyingPrice(llToken);
                uint underlyingPrice = underlyingPriceResponse.underlyingPrice;
                Exp memory underlyingPriceMantissa = Exp({ mantissa: underlyingPrice });

                //get dailyLtokenSupplyMarket
                uint dailyLtokenSupplyMarket = 0;
                uint supplyInUsd = mul_ScalarTruncate(underlyingPriceMantissa, llTokenBalanceInfo.balanceOfUnderlying);
                uint marketTotalSupply = (metaDataItem.totalSupply.mul(metaDataItem.exchangeRateCurrent)).div(1e18);
                uint marketTotalSupplyInUsd = mul_ScalarTruncate(underlyingPriceMantissa, marketTotalSupply);

                if (marketTotalSupplyInUsd > 0) {
                    dailyLtokenSupplyMarket = (metaDataItem.dailySupplyLtoken.mul(supplyInUsd)).div(
                        marketTotalSupplyInUsd
                    );
                }

                //get dailyLtokenBorrowMarket
                uint dailyLtokenBorrowMarket = 0;
                uint borrowsInUsd = mul_ScalarTruncate(
                    underlyingPriceMantissa,
                    llTokenBalanceInfo.borrowBalanceCurrent
                );
                uint marketTotalBorrowsInUsd = mul_ScalarTruncate(underlyingPriceMantissa, metaDataItem.totalBorrows);

                if (marketTotalBorrowsInUsd > 0) {
                    dailyLtokenBorrowMarket = (metaDataItem.dailyBorrowLtoken.mul(borrowsInUsd)).div(
                        marketTotalBorrowsInUsd
                    );
                }

                dailyLtokenPerAccount += dailyLtokenSupplyMarket + dailyLtokenBorrowMarket;
            }
        }

        return dailyLtokenPerAccount;
    }

    /**
     * @notice Get the current llToken balance (outstanding borrows) for an account
     * @param llToken Address of the token to check the balance of
     * @param account Account address to fetch the balance of
     * @return LLTokenBalances with token balance information
     */
    function llTokenBalances(LLToken llToken, address payable account) public returns (LLTokenBalances memory) {
        uint balanceOf = llToken.balanceOf(account);
        uint borrowBalanceCurrent = 0;
        uint balanceOfUnderlying = llToken.balanceOfUnderlying(account);
        uint tokenBalance;
        uint tokenAllowance;

        if (compareStrings(llToken.symbol(), "llERC")) {
            tokenBalance = account.balance;
            tokenAllowance = account.balance;
        } else {
            LLErc20 llErc20 = LLErc20(address(llToken));
            EIP20Interface underlying = EIP20Interface(llErc20.underlying());
            tokenBalance = underlying.balanceOf(account);
            tokenAllowance = underlying.allowance(account, address(llToken));
        }
        return
            LLTokenBalances({
                llToken: address(llToken),
                balanceOf: balanceOf,
                borrowBalanceCurrent: borrowBalanceCurrent,
                balanceOfUnderlying: balanceOfUnderlying,
                tokenBalance: tokenBalance,
                tokenAllowance: tokenAllowance
            });
    }

    /**
     * @notice Get the current llToken balances (outstanding borrows) for all llTokens on an account
     * @param llTokens Addresses of the tokens to check the balance of
     * @param account Account address to fetch the balance of
     * @return LLTokenBalances Array with token balance information
     */
    function llTokenBalancesAll(
        LLToken[] calldata llTokens,
        address payable account
    ) external returns (LLTokenBalances[] memory) {
        uint llTokenCount = llTokens.length;
        LLTokenBalances[] memory res = new LLTokenBalances[](llTokenCount);
        for (uint i = 0; i < llTokenCount; i++) {
            res[i] = llTokenBalances(llTokens[i], account);
        }
        return res;
    }

    /**
     * @notice Get the price for the underlying asset of a llToken
     * @param llToken address of the llToken
     * @return response struct with underlyingPrice info of llToken
     */
    function llTokenUnderlyingPrice(LLToken llToken) public view returns (LLTokenUnderlyingPrice memory) {
        ComptrollerInterface comptroller = ComptrollerInterface(address(llToken.comptroller()));
        PriceOracle priceOracle = comptroller.oracle();

        return
            LLTokenUnderlyingPrice({
                llToken: address(llToken),
                underlyingPrice: priceOracle.getUnderlyingPrice(llToken)
            });
    }

    /**
     * @notice Query the underlyingPrice of an array of llTokens
     * @param llTokens Array of llToken addresses
     * @return array of response structs with underlying price information of llTokens
     */
    function llTokenUnderlyingPriceAll(
        LLToken[] calldata llTokens
    ) external view returns (LLTokenUnderlyingPrice[] memory) {
        uint llTokenCount = llTokens.length;
        LLTokenUnderlyingPrice[] memory res = new LLTokenUnderlyingPrice[](llTokenCount);
        for (uint i = 0; i < llTokenCount; i++) {
            res[i] = llTokenUnderlyingPrice(llTokens[i]);
        }
        return res;
    }

    /**
     * @notice Query the account liquidity and shortfall of an account
     * @param comptroller Address of comptroller proxy
     * @param account Address of the account to query
     * @return Struct with markets user has entered, liquidity, and shortfall of the account
     */
    function getAccountLimits(
        ComptrollerInterface comptroller,
        address account
    ) public view returns (AccountLimits memory) {
        (uint errorCode, uint liquidity, uint shortfall) = comptroller.getAccountLiquidity(account);
        require(errorCode == 0, "account liquidity error");

        return AccountLimits({ markets: comptroller.getAssetsIn(account), liquidity: liquidity, shortfall: shortfall });
    }

    /**
     * @notice Query the LTOKENBalance info of an account
     * @param ltoken LTOKEN contract address
     * @param account Account address
     * @return Struct with LTOKEN balance and voter details
     */
    function getLTOKENBalanceMetadata(
        LTOKEN ltoken,
        address account
    ) external view returns (LTOKENBalanceMetadata memory) {
        return LTOKENBalanceMetadata({ balance: ltoken.balanceOf(account) });
    }

    /**
     * @notice Query the LTOKENBalance extended info of an account
     * @param ltoken LTOKEN contract address
     * @param comptroller Comptroller proxy contract address
     * @param account Account address
     * @return Struct with LTOKEN balance and voter details and LTOKEN allocation
     */
    function getLTOKENBalanceMetadataExt(
        LTOKEN ltoken,
        ComptrollerInterface comptroller,
        address account
    ) external returns (LTOKENBalanceMetadataExt memory) {
        uint balance = ltoken.balanceOf(account);
        comptroller.claimLs(account);
        uint newBalance = ltoken.balanceOf(account);
        uint accrued = comptroller.lsAccrued(account);
        uint total = add_(accrued, newBalance, "sum ltoken total");
        uint allocated = sub_(total, balance, "sub allocated");

        return LTOKENBalanceMetadataExt({ balance: balance, allocated: allocated });
    }

    // utilities
    /**
     * @notice Compares if two strings are equal
     * @param a First string to compare
     * @param b Second string to compare
     * @return Boolean depending on if the strings are equal
     */
    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
