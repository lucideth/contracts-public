pragma solidity ^0.5.16;

import "../Oracle/PriceOracle.sol";
import "../Tokens/LLTokens/LLToken.sol";
import "../Utils/ErrorReporter.sol";
import "../Tokens/LTOKEN/LTOKEN.sol";
import "./../Interfaces/IDSD.sol";
import "./../Interfaces/IAccessControlManager.sol";
import "./ComptrollerLensInterface.sol";
import "./ComptrollerInterface.sol";
import "./ComptrollerStorage.sol";
import "./../Interfaces/ILLToken.sol";

/**
 * @title LS's Comptroller Contract
 * @author LS
 */
contract Comptroller is ComptrollerV11Storage, ComptrollerInterfaceG2, ComptrollerErrorReporter, ExponentialNoError {
    /// @notice Emitted when an admin supports a market
    event MarketListed(LLToken llToken);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(LLToken llToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint oldLiquidationIncentiveMantissa, uint newLiquidationIncentiveMantissa);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused on a market
    event ActionPausedMarket(LLToken indexed llToken, Action indexed action, bool pauseState);

    /// @notice Emitted when LS DSD Vault rate is changed
    event NewLsDSDVaultRate(uint oldLsDSDVaultRate, uint NewLsDSDVaultRate);

    /// @notice Emitted when DSDController is changed
    event NewDSDController(DSDControllerInterface oldDSDController, DSDControllerInterface newDSDController);

    /// @notice Emitted when DSD mint rate is changed by admin
    event NewDSDMintRate(uint oldDSDMintRate, uint newDSDMintRate);

    /// @notice Emitted when protocol state is changed by admin
    event ActionProtocolPaused(bool state);

    /// @notice Emitted when borrow cap for a llToken is changed
    event NewBorrowCap(LLToken indexed llToken, uint newBorrowCap);

    /// @notice Emitted when treasury guardian is changed
    event NewTreasuryGuardian(address oldTreasuryGuardian, address newTreasuryGuardian);

    /// @notice Emitted when treasury address is changed
    event NewTreasuryAddress(address oldTreasuryAddress, address newTreasuryAddress);

    /// @notice Emitted when treasury percent is changed
    event NewTreasuryPercent(uint oldTreasuryPercent, uint newTreasuryPercent);

    // @notice Emitted when liquidator adress is changed
    event NewLiquidatorContract(address oldLiquidatorContract, address newLiquidatorContract);

    /// @notice Emitted whe ComptrollerLens address is changed
    event NewComptrollerLens(address oldComptrollerLens, address newComptrollerLens);

    /// @notice Emitted when supply cap for a llToken is changed
    event NewSupplyCap(LLToken indexed llToken, uint newSupplyCap);

    /// @notice Emitted when access control address is changed by admin
    event NewAccessControl(address oldAccessControlAddress, address newAccessControlAddress);

    /// @notice Emitted when the borrowing delegate rights are updated for an account
    event DelegateUpdated(address borrower, address delegate, bool allowDelegatedBorrows);

    /// @notice The initial LS index for a market
    uint224 public constant lsInitialIndex = 1e36;

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    constructor() public {
        admin = msg.sender;
    }

    /// @notice Reverts if the protocol is paused
    function checkProtocolPauseState() private view {
        require(!protocolPaused, "protocol is paused");
    }

    /// @notice Reverts if a certain action is paused on a market
    function checkActionPauseState(address market, Action action) private view {
        require(!actionPaused(market, action), "action is paused");
    }

    /// @notice Reverts if the caller is not admin
    function ensureAdmin() private view {
        require(msg.sender == admin, "only admin can");
    }

    /// @notice Checks the passed address is nonzero
    function ensureNonzeroAddress(address someone) private pure {
        require(someone != address(0), "can't be zero address");
    }

    /// @notice Reverts if the market is not listed
    function ensureListed(Market storage market) private view {
        require(market.isListed, "market not listed");
    }

    /// @notice Reverts if the caller is neither admin nor the passed address
    function ensureAdminOr(address privilegedAddress) private view {
        require(msg.sender == admin || msg.sender == privilegedAddress, "access denied");
    }

    function ensureAllowed(string memory functionSig) private view {
        require(IAccessControlManager(accessControl).isAllowedToCall(msg.sender, functionSig), "access denied");
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (LLToken[] memory) {
        return requireEnablingCollateral ? accountAssets[account] : allMarkets;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param llToken The llToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, address llToken) external view returns (bool) {
        return checkAccountAccessForLLToken(account, llToken);
    }

    /**
     * @notice Returns whether the given account is entered in the given asset based on whether the global requirement flag is set
     * @param account The address of the account to check
     * @param llToken The llToken to check
     * @return True if the account is in the asset, otherwise false in case global requirement flag is set, true in all cases otherwise
     */
    function checkAccountAccessForLLToken(address account, address llToken) private view returns (bool) {
        if (requireEnablingCollateral) return markets[llToken].accountMembership[account];
        return true;
    }

    /**
     * @notice Grants or revokes the borrowing delegate rights to / from an account.
     *  If allowed, the delegate will be able to borrow funds on behalf of the sender.
     *  Upon a delegated borrow, the delegate will receive the funds, and the borrower
     *  will see the debt on their account.
     * @param delegate The address to update the rights for
     * @param allowBorrows Whether to grant (true) or revoke (false) the rights
     */
    function updateDelegate(address delegate, bool allowBorrows) external {
        _updateDelegate(msg.sender, delegate, allowBorrows);
    }

    function _updateDelegate(address borrower, address delegate, bool allowBorrows) internal {
        approvedDelegates[borrower][delegate] = allowBorrows;
        emit DelegateUpdated(borrower, delegate, allowBorrows);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param llToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowed(address llToken, address minter, uint mintAmount) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        checkProtocolPauseState();
        checkActionPauseState(llToken, Action.MINT);
        ensureListed(markets[llToken]);

        uint256 supplyCap = supplyCaps[llToken];
        require(supplyCap != 0, "market supply cap is 0");

        uint256 llTokenSupply = LLToken(llToken).totalSupply();
        Exp memory exchangeRate = Exp({ mantissa: LLToken(llToken).exchangeRateStored() });
        uint256 nextTotalSupply = mul_ScalarTruncateAddUInt(exchangeRate, llTokenSupply, mintAmount);
        require(nextTotalSupply <= supplyCap, "market supply cap reached");

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param llToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    function mintVerify(address llToken, address minter, uint actualMintAmount, uint mintTokens) external {}

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param llToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of llTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowed(address llToken, address redeemer, uint redeemTokens) external returns (uint) {
        checkProtocolPauseState();
        checkActionPauseState(llToken, Action.REDEEM);

        uint allowed = redeemAllowedInternal(llToken, redeemer, redeemTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        return uint(Error.NO_ERROR);
    }

    function redeemAllowedInternal(address llToken, address redeemer, uint redeemTokens) internal view returns (uint) {
        ensureListed(markets[llToken]);

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!checkAccountAccessForLLToken(redeemer, llToken)) {
            return uint(Error.NO_ERROR);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(
            redeemer,
            LLToken(llToken),
            redeemTokens,
            0
        );
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall != 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param llToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    // solhint-disable-next-line no-unused-vars
    function redeemVerify(address llToken, address redeemer, uint redeemAmount, uint redeemTokens) external {
        require(redeemTokens != 0 || redeemAmount == 0, "redeemTokens zero");
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param llTokenBorrowed Asset which was borrowed by the borrower
     * @param llTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address llTokenBorrowed,
        address llTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external returns (uint) {
        checkProtocolPauseState();

        // if we want to pause liquidating to llTokenCollateral, we should pause seizing
        checkActionPauseState(llTokenBorrowed, Action.LIQUIDATE);

        if (liquidatorContract != address(0) && liquidator != liquidatorContract) {
            return uint(Error.UNAUTHORIZED);
        }

        ensureListed(markets[llTokenCollateral]);
        if (address(llTokenBorrowed) != address(dsdController)) {
            ensureListed(markets[llTokenBorrowed]);
        }

        /* The borrower must have shortfall in order to be liquidatable */
        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(borrower, LLToken(0), 0, 0);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall == 0) {
            return uint(Error.INSUFFICIENT_SHORTFALL);
        }

        /* The liquidator may not repay more than what is allowed by the closeFactor */
        uint borrowBalance = dsdController.getDSDRepayAmount(borrower);

        // maxClose = multipy of closeFactorMantissa and borrowBalance
        if (repayAmount > mul_ScalarTruncate(Exp({ mantissa: closeFactorMantissa }), borrowBalance)) {
            return uint(Error.TOO_MUCH_REPAY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param llTokenBorrowed Asset which was borrowed by the borrower
     * @param llTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     * @param seizeTokens The amount of collateral token that will be seized
     */
    function liquidateBorrowVerify(
        address llTokenBorrowed,
        address llTokenCollateral,
        address liquidator,
        address borrower,
        uint actualRepayAmount,
        uint seizeTokens
    ) external {}

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param llTokenCollateral Asset which was used as collateral and will be seized
     * @param llTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address llTokenCollateral,
        address llTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens // solhint-disable-line no-unused-vars
    ) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        checkProtocolPauseState();
        checkActionPauseState(llTokenCollateral, Action.SEIZE);

        // We've added DSDController as a borrowed token list check for seize
        ensureListed(markets[llTokenCollateral]);
        if (address(llTokenBorrowed) != address(dsdController)) {
            ensureListed(markets[llTokenBorrowed]);
        }

        if (LLToken(llTokenCollateral).comptroller() != LLToken(llTokenBorrowed).comptroller()) {
            return uint(Error.COMPTROLLER_MISMATCH);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param llTokenCollateral Asset which was used as collateral and will be seized
     * @param llTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address llTokenCollateral,
        address llTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external {}

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param llToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of llTokens to transfer
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function transferAllowed(address llToken, address src, address dst, uint transferTokens) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        checkProtocolPauseState();
        checkActionPauseState(llToken, Action.TRANSFER);

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint allowed = redeemAllowedInternal(llToken, src, transferTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param llToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of llTokens to transfer
     */
    function transferVerify(address llToken, address src, address dst, uint transferTokens) external {}

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code (semi-opaque),
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account) external view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(
            account,
            LLToken(0),
            0,
            0
        );

        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param llTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code (semi-opaque),
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address llTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) external view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(
            account,
            LLToken(llTokenModify),
            redeemTokens,
            borrowAmount
        );
        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param llTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral llToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        LLToken llTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) internal view returns (Error, uint, uint) {
        (uint err, uint liquidity, uint shortfall) = comptrollerLens.getHypotheticalAccountLiquidity(
            address(this),
            account,
            llTokenModify,
            redeemTokens,
            borrowAmount
        );
        return (Error(err), liquidity, shortfall);
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in llToken.liquidateBorrowFresh)
     * @param llTokenBorrowed The address of the borrowed llToken
     * @param llTokenCollateral The address of the collateral llToken
     * @param actualRepayAmount The amount of llTokenBorrowed underlying to convert into llTokenCollateral tokens
     * @return (errorCode, number of llTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(
        address llTokenBorrowed,
        address llTokenCollateral,
        uint actualRepayAmount
    ) external view returns (uint, uint) {
        (uint err, uint seizeTokens) = comptrollerLens.liquidateCalculateSeizeTokens(
            address(this),
            llTokenBorrowed,
            llTokenCollateral,
            actualRepayAmount
        );
        return (err, seizeTokens);
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in llToken.liquidateBorrowFresh)
     * @param llTokenCollateral The address of the collateral llToken
     * @param actualRepayAmount The amount of llTokenBorrowed underlying to convert into llTokenCollateral tokens
     * @return (errorCode, number of llTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateDSDCalculateSeizeTokens(
        address llTokenCollateral,
        uint actualRepayAmount
    ) external view returns (uint, uint) {
        (uint err, uint seizeTokens) = comptrollerLens.liquidateDSDCalculateSeizeTokens(
            address(this),
            llTokenCollateral,
            actualRepayAmount
        );
        return (err, seizeTokens);
    }

    /*** Admin Functions ***/

    /**
     * @notice Sets a new price oracle for the comptroller
     * @dev Admin function to set a new price oracle
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setPriceOracle(PriceOracle newOracle) external returns (uint) {
        // Check caller is admin
        ensureAdmin();
        ensureNonzeroAddress(address(newOracle));

        // Track the old oracle for the comptroller
        PriceOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Set the address of the LTOKEN token
     * @param _ltokenAddress address of LTOKEN
     */
    function _setLTOKENAddress(address _ltokenAddress) external {
        ensureAdmin();
        ensureNonzeroAddress(_ltokenAddress);
        ltokenAddress = _ltokenAddress;
    }

    function whitelistToken(address _token) external {
        ensureAdmin();
        ensureNonzeroAddress(_token);
        isWhitelisted[_token] = true;
    }

    /**
     * @notice Sets the closeFactor used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     * @return uint 0=success, otherwise will revert
     */
    function _setCloseFactor(uint newCloseFactorMantissa) external returns (uint) {
        // Check caller is admin
        ensureAdmin();

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, newCloseFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets the address of the access control of this contract
     * @dev Admin function to set the access control address
     * @param newAccessControlAddress New address for the access control
     * @return uint 0=success, otherwise will revert
     */
    function _setAccessControl(address newAccessControlAddress) external returns (uint) {
        // Check caller is admin
        ensureAdmin();
        ensureNonzeroAddress(newAccessControlAddress);

        address oldAccessControlAddress = accessControl;
        accessControl = newAccessControlAddress;
        emit NewAccessControl(oldAccessControlAddress, accessControl);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Restricted function to set per-market collateralFactor
     * @param llToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    function _setCollateralFactor(LLToken llToken, uint newCollateralFactorMantissa) external returns (uint) {
        // Check caller is allowed by access control manager
        ensureAllowed("_setCollateralFactor(address,uint256)");
        ensureNonzeroAddress(address(llToken));
        // Verify market is listed
        Market storage market = markets[address(llToken)];
        ensureListed(market);
        Exp memory newCollateralFactorExp = Exp({ mantissa: newCollateralFactorMantissa });

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({ mantissa: collateralFactorMaxMantissa });
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }
        // If collateral factor != 0, fail if price == 0
        if (newCollateralFactorMantissa != 0 && oracle.getUnderlyingPrice(llToken) == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }
        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        oracle.validateUnderlyingPrice(llToken);

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(llToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);
        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external returns (uint) {
        ensureAllowed("_setLiquidationIncentive(uint256)");
        require(newLiquidationIncentiveMantissa >= 1e18, "incentive must be over 1e18");

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);

        return uint(Error.NO_ERROR);
    }

    function _setLiquidatorContract(address newLiquidatorContract_) external {
        // Check caller is admin
        ensureAdmin();
        address oldLiquidatorContract = liquidatorContract;
        liquidatorContract = newLiquidatorContract_;
        emit NewLiquidatorContract(oldLiquidatorContract, newLiquidatorContract_);
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param llToken The address of the market (token) to list
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _supportMarket(LLToken llToken) external returns (uint) {
        ensureAllowed("_supportMarket(address)");

        if (markets[address(llToken)].isListed) {
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        llToken.isLLToken(); // Sanity check to make sure its really a LLToken

        // Note that isLS is not in active use anymore
        markets[address(llToken)] = Market({ isListed: true, isLs: false, collateralFactorMantissa: 0 });

        _addMarketInternal(llToken);
        // _initializeMarket(address(llToken));

        emit MarketListed(llToken);

        return uint(Error.NO_ERROR);
    }

    function _addMarketInternal(LLToken llToken) internal {
        for (uint i; i < allMarkets.length; ++i) {
            require(allMarkets[i] != llToken, "market already added");
        }
        allMarkets.push(llToken);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) external returns (uint) {
        ensureAdmin();
        ensureNonzeroAddress(newPauseGuardian);

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, newPauseGuardian);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Set the given borrow caps for the given llToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev Access is controled by ACM. A borrow cap of 0 corresponds to unlimited borrowing.
     * @param llTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
     */
    function _setMarketBorrowCaps(LLToken[] calldata llTokens, uint[] calldata newBorrowCaps) external {
        ensureAllowed("_setMarketBorrowCaps(address[],uint256[])");

        uint numMarkets = llTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for (uint i; i < numMarkets; ++i) {
            borrowCaps[address(llTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(llTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Set the given supply caps for the given llToken markets. Supply that brings total Supply to or above supply cap will revert.
     * @dev Admin function to set the supply caps. A supply cap of 0 corresponds to Minting NotAllowed.
     * @param llTokens The addresses of the markets (tokens) to change the supply caps for
     * @param newSupplyCaps The new supply cap values in underlying to be set. A value of 0 corresponds to Minting NotAllowed.
     */
    function _setMarketSupplyCaps(LLToken[] calldata llTokens, uint256[] calldata newSupplyCaps) external {
        ensureAllowed("_setMarketSupplyCaps(address[],uint256[])");

        uint numMarkets = llTokens.length;
        uint numSupplyCaps = newSupplyCaps.length;

        require(numMarkets != 0 && numMarkets == numSupplyCaps, "invalid input");

        for (uint i; i < numMarkets; ++i) {
            supplyCaps[address(llTokens[i])] = newSupplyCaps[i];
            emit NewSupplyCap(llTokens[i], newSupplyCaps[i]);
        }
    }

    /**
     * @notice Set whole protocol pause/unpause state
     */
    function _setProtocolPaused(bool state) external returns (bool) {
        ensureAllowed("_setProtocolPaused(bool)");

        protocolPaused = state;
        emit ActionProtocolPaused(state);
        return state;
    }

    /**
     * @notice Pause/unpause certain actions
     * @param markets Markets to pause/unpause the actions on
     * @param actions List of action ids to pause/unpause
     * @param paused The new paused state (true=paused, false=unpaused)
     */
    function _setActionsPaused(address[] calldata markets, Action[] calldata actions, bool paused) external {
        ensureAllowed("_setActionsPaused(address[],uint256[],bool)");

        uint256 numMarkets = markets.length;
        uint256 numActions = actions.length;
        for (uint marketIdx; marketIdx < numMarkets; ++marketIdx) {
            for (uint actionIdx; actionIdx < numActions; ++actionIdx) {
                setActionPausedInternal(markets[marketIdx], actions[actionIdx], paused);
            }
        }
    }

    /**
     * @dev Pause/unpause an action on a market
     * @param market Market to pause/unpause the action on
     * @param action Action id to pause/unpause
     * @param paused The new paused state (true=paused, false=unpaused)
     */
    function setActionPausedInternal(address market, Action action, bool paused) internal {
        ensureListed(markets[market]);
        _actionPaused[market][uint(action)] = paused;
        emit ActionPausedMarket(LLToken(market), action, paused);
    }

    /**
     * @notice Sets a new DSD controller
     * @dev Admin function to set a new DSD controller
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setDSDController(DSDControllerInterface dsdController_) external returns (uint) {
        // Check caller is admin
        ensureAdmin();
        ensureNonzeroAddress(address(dsdController_));

        DSDControllerInterface oldDsdController = dsdController;
        dsdController = dsdController_;
        emit NewDSDController(oldDsdController, dsdController_);

        return uint(Error.NO_ERROR);
    }

    function _setDSDMintRate(uint newDSDMintRate) external returns (uint) {
        // Check caller is admin
        ensureAdmin();
        uint oldDSDMintRate = dsdMintRate;
        dsdMintRate = newDSDMintRate;
        emit NewDSDMintRate(oldDSDMintRate, newDSDMintRate);

        return uint(Error.NO_ERROR);
    }

    function _setTreasuryData(
        address newTreasuryGuardian,
        address newTreasuryAddress,
        uint newTreasuryPercent
    ) external returns (uint) {
        // Check caller is admin
        ensureAdminOr(treasuryGuardian);

        require(newTreasuryPercent < 1e18, "treasury percent cap overflow");
        ensureNonzeroAddress(newTreasuryGuardian);
        ensureNonzeroAddress(newTreasuryAddress);

        address oldTreasuryGuardian = treasuryGuardian;
        address oldTreasuryAddress = treasuryAddress;
        uint oldTreasuryPercent = treasuryPercent;

        treasuryGuardian = newTreasuryGuardian;
        treasuryAddress = newTreasuryAddress;
        treasuryPercent = newTreasuryPercent;

        emit NewTreasuryGuardian(oldTreasuryGuardian, newTreasuryGuardian);
        emit NewTreasuryAddress(oldTreasuryAddress, newTreasuryAddress);
        emit NewTreasuryPercent(oldTreasuryPercent, newTreasuryPercent);

        return uint(Error.NO_ERROR);
    }

    /**
     * @dev Set ComptrollerLens contract address
     */
    function _setComptrollerLens(ComptrollerLensInterface comptrollerLens_) external returns (uint) {
        ensureAdmin();
        ensureNonzeroAddress(address(comptrollerLens_));
        address oldComptrollerLens = address(comptrollerLens);
        comptrollerLens = comptrollerLens_;
        emit NewComptrollerLens(oldComptrollerLens, address(comptrollerLens));

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() external view returns (LLToken[] memory) {
        return allMarkets;
    }

    /**
     * @notice Return the address of the LTOKEN
     * @return The address of LTOKEN
     */
    function getLTOKENAddress() public view returns (address) {
        return ltokenAddress;
    }

    /**
     * @notice Checks if a certain action is paused on a market
     * @param action Action id
     * @param market llToken address
     */
    function actionPaused(address market, Action action) public view returns (bool) {
        return _actionPaused[market][uint(action)];
    }

    /*** DSD functions ***/

    /**
     * @notice Set the minted DSD amount of the `owner`
     * @param owner The address of the account to set
     * @param amount The amount of DSD to set to the account
     * @return The number of minted DSD by `owner`
     */
    function setMintedDSDOf(address owner, uint amount) external returns (uint) {
        checkProtocolPauseState();

        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintDSDGuardianPaused && !repayDSDGuardianPaused, "DSD is paused");
        // Check caller is dsdController
        if (msg.sender != address(dsdController)) {
            return fail(Error.REJECTION, FailureInfo.SET_MINTED_DSD_REJECTION);
        }
        mintedDSDs[owner] = amount;

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Set requirement for enabling each asset explicitly by user
     * @param status The new status of the flag
     */
    function setRequirementForEnablingCollateral(bool status) external {
        ensureAdmin();
        requireEnablingCollateral = status;
    }

    /**
     * @notice Perform rebase on all LLTokens
     */
    function rebase() external {
        require(IDSD(dsdController.getDSDAddress()).rebaseManagers(msg.sender) == 1, "!RBM");
        for (uint i = 0; i < allMarkets.length; i++) {
            ILLToken(address(allMarkets[i])).rebase();
        }
    }
}
