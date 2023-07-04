pragma solidity ^0.5.16;

import "../../Oracle/PriceOracle.sol";
import "../../Utils/ErrorReporter.sol";
import "../../Utils/Exponential.sol";
import "../../Comptroller/ComptrollerStorage.sol";
import "../../Comptroller/Comptroller.sol";
import "../../Interfaces/IAccessControlManager.sol";
import "../LLTokens/LLToken.sol";
import "./DSDControllerStorage.sol";
import "../../Utils/SafeMath.sol";
import "../../Interfaces/ILLToken.sol";
import "hardhat/console.sol";

interface ComptrollerImplInterface {
    function protocolPaused() external view returns (bool);

    function mintedDSDs(address account) external view returns (uint);

    function dsdMintRate() external view returns (uint);

    function lsAccrued(address account) external view returns (uint);

    function getAssetsIn(address account) external view returns (LLToken[] memory);

    function oracle() external view returns (PriceOracle);
}

/**
 * @title LS's DSD Comptroller Contract
 * @author LS
 */
contract DSDController is DSDControllerStorageG2, DSDControllerErrorReporter, Exponential {
    using SafeMath for uint;
    /// @notice Initial index used in interest computations
    uint public constant INITIAL_DSD_MINT_INDEX = 1e18;

    /// @notice Emitted when Comptroller is changed
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /// @notice Event emitted when DSD is minted
    event MintDSD(address minter, uint mintDSDAmount);

    /// @notice Event emitted when DSD is repaid
    event RepayDSD(address payer, address borrower, uint repayDSDAmount);

    /// @notice Event emitted when a borrow is liquidated
    event LiquidateDSD(
        address liquidator,
        address borrower,
        uint repayAmount,
        address llTokenCollateral,
        uint seizeTokens
    );

    /// @notice Emitted when treasury guardian is changed
    event NewTreasuryGuardian(address oldTreasuryGuardian, address newTreasuryGuardian);

    /// @notice Emitted when treasury address is changed
    event NewTreasuryAddress(address oldTreasuryAddress, address newTreasuryAddress);

    /// @notice Emitted when treasury percent is changed
    event NewTreasuryPercent(uint oldTreasuryPercent, uint newTreasuryPercent);

    /// @notice Event emitted when DSDs are minted and fee are transferred
    event MintFee(address minter, uint feeAmount);

    /// @notice Emiitted when DSD base rate is changed
    event NewDSDBaseRate(uint256 oldBaseRateMantissa, uint256 newBaseRateMantissa);

    /// @notice Emiitted when DSD float rate is changed
    event NewDSDFloatRate(uint oldFloatRateMantissa, uint newFlatRateMantissa);

    /// @notice Emiitted when DSD receiver address is changed
    event NewDSDReceiver(address oldReceiver, address newReceiver);

    /// @notice Emiitted when DSD mint cap is changed
    event NewDSDMintCap(uint oldMintCap, uint newMintCap);

    /// @notice Emitted when access control address is changed by admin
    event NewAccessControl(address oldAccessControlAddress, address newAccessControlAddress);

    /*** Main Actions ***/
    struct MintLocalVars {
        uint oErr;
        MathError mathErr;
        uint mintAmount;
        uint accountMintDSDNew;
        uint accountMintableDSD;
    }

    constructor() public {
        admin = msg.sender;
        mintCap = uint256(-1);
        // The counter starts true to prevent changing it from zero to non-zero (i.e. smaller cost/refund)
        _notEntered = true;
    }

    // solhint-disable-next-line code-complexity
    function mintDSD(uint mintDSDAmount) external nonReentrant returns (uint) {
        require(address(comptroller) != address(0), "comptroller not set");
        require(mintDSDAmount > 0, "mintDSDAmount cannot be zero");
        require(!ComptrollerImplInterface(address(comptroller)).protocolPaused(), "protocol is paused");
        MintLocalVars memory vars;

        address minter = msg.sender;
        uint dsdTotalSupply = EIP20Interface(getDSDAddress()).totalSupply();
        uint dsdNewTotalSupply;

        esltokenMinter.refreshReward(minter);

        (vars.mathErr, dsdNewTotalSupply) = addUInt(dsdTotalSupply, mintDSDAmount);
        require(dsdNewTotalSupply <= mintCap, "mint cap reached");

        if (vars.mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.MINT_FEE_CALCULATION_FAILED, uint(vars.mathErr));
        }

        (vars.oErr, vars.accountMintableDSD) = getMintableDSD(minter);
        if (vars.oErr != uint(Error.NO_ERROR)) {
            return uint(Error.REJECTION);
        }

        // check that user have sufficient mintableDSD balance
        if (mintDSDAmount > vars.accountMintableDSD) {
            revert("mintDSDAmount exceeds mintableDSD balance");
        }

        // Calculate the minted balance based on interest index
        uint totalMintedDSD = ComptrollerImplInterface(address(comptroller)).mintedDSDs(minter);
        if (totalMintedDSD > 0) {
            uint256 repayAmount = getDSDRepayAmount(minter);
            uint remainedAmount;

            (vars.mathErr, remainedAmount) = subUInt(repayAmount, totalMintedDSD);
            if (vars.mathErr != MathError.NO_ERROR) {
                return failOpaque(Error.MATH_ERROR, FailureInfo.MINT_FEE_CALCULATION_FAILED, uint(vars.mathErr));
            }
            totalMintedDSD = repayAmount;
        }

        (vars.mathErr, vars.accountMintDSDNew) = addUInt(totalMintedDSD, mintDSDAmount);
        require(vars.mathErr == MathError.NO_ERROR, "DSD_MINT_AMOUNT_CALCULATION_FAILED");
        uint error = comptroller.setMintedDSDOf(minter, vars.accountMintDSDNew);
        if (error != 0) {
            return error;
        }

        vars.mintAmount = mintDSDAmount;
        IDSD(getDSDAddress()).mint(minter, mintDSDAmount);
        emit MintDSD(minter, mintDSDAmount);
        return uint(Error.NO_ERROR);
    }

    // 🟡 - esLTOKENMinter changes
    function setESLTOKENMinter(address addr) external {
        require(msg.sender == admin, "!admin");
        esltokenMinter = IesLTOKENMinter(addr);
    }

    /**
     * @notice Repay DSD
     */
    function repayDSD(uint repayDSDAmount) external nonReentrant returns (uint, uint) {
        if (address(comptroller) != address(0)) {
            require(repayDSDAmount > 0, "repayDSDAmount cannt be zero");

            require(!ComptrollerImplInterface(address(comptroller)).protocolPaused(), "protocol is paused");

            return repayDSDFresh(msg.sender, msg.sender, repayDSDAmount);
        }
    }

    /**
     * @notice Repay DSD Internal
     * @notice Borrowed DSDs are repaid by another user (possibly the borrower).
     * @param payer the account paying off the DSD
     * @param borrower the account with the debt being payed off
     * @param repayAmount the amount of DSD being returned
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function repayDSDFresh(address payer, address borrower, uint repayAmount) internal returns (uint, uint) {
        MathError mErr;
        uint burn = getDSDCalculateRepayAmount(
            borrower,
            repayAmount
        );
        esltokenMinter.refreshReward(payer);

        IDSD(getDSDAddress()).burn(payer, burn);

        uint dsdBalanceBorrower = ComptrollerImplInterface(address(comptroller)).mintedDSDs(borrower);
        uint accountDSDNew;

        (mErr, accountDSDNew) = subUInt(dsdBalanceBorrower, burn);
        require(mErr == MathError.NO_ERROR, "DSD_BURN_AMOUNT_CALCULATION_FAILED");

        uint error = comptroller.setMintedDSDOf(borrower, accountDSDNew);
        if (error != 0) {
            return (error, 0);
        }

        emit RepayDSD(payer, borrower, burn);
        return (uint(Error.NO_ERROR), burn);
    }

    /**
     * @notice The sender liquidates the dsd minters collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of dsd to be liquidated
     * @param llTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function liquidateDSD(
        address borrower,
        uint repayAmount,
        LLTokenInterface llTokenCollateral
    ) external nonReentrant returns (uint, uint) {
        require(!ComptrollerImplInterface(address(comptroller)).protocolPaused(), "protocol is paused");

        // liquidateDSDFresh emits borrow-specific logs on errors, so we don't need to
        return liquidateDSDFresh(msg.sender, borrower, repayAmount, llTokenCollateral);
    }

    /**
     * @notice The liquidator liquidates the borrowers collateral by repay borrowers DSD.
     *  The collateral seized is transferred to the liquidator.
     * @param liquidator The address repaying the DSD and seizing collateral
     * @param borrower The borrower of this DSD to be liquidated
     * @param llTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the DSD to repay
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment DSD.
     */
    function liquidateDSDFresh(
        address liquidator,
        address borrower,
        uint repayAmount,
        LLTokenInterface llTokenCollateral
    ) internal returns (uint, uint) {
        if (address(comptroller) != address(0)) {
            /* Fail if liquidate not allowed */
            uint allowed = comptroller.liquidateBorrowAllowed(
                address(this),
                address(llTokenCollateral),
                liquidator,
                borrower,
                repayAmount
            );

            console.log("DSD_LIQUIDATE_COMPTROLLER_REJECTION");
            if (allowed != 0) {
                return (failOpaque(Error.REJECTION, FailureInfo.DSD_LIQUIDATE_COMPTROLLER_REJECTION, allowed), 0);
            }

            /* Fail if borrower = liquidator */
            if (borrower == liquidator) {
                return (fail(Error.REJECTION, FailureInfo.DSD_LIQUIDATE_LIQUIDATOR_IS_BORROWER), 0);
            }

            /* Fail if repayAmount = 0 */
            if (repayAmount == 0) {
                return (fail(Error.REJECTION, FailureInfo.DSD_LIQUIDATE_CLOSE_AMOUNT_IS_ZERO), 0);
            }

            /* Fail if repayAmount = -1 */
            if (repayAmount == uint(-1)) {
                return (fail(Error.REJECTION, FailureInfo.DSD_LIQUIDATE_CLOSE_AMOUNT_IS_UINT_MAX), 0);
            }

            console.log("DSD_LIQUIDATE_REPAY_BORROW_FRESH_FAILED");

            /* Fail if repayDSD fails */
            (uint repayBorrowError, uint actualRepayAmount) = repayDSDFresh(liquidator, borrower, repayAmount);
            if (repayBorrowError != uint(Error.NO_ERROR)) {
                return (fail(Error(repayBorrowError), FailureInfo.DSD_LIQUIDATE_REPAY_BORROW_FRESH_FAILED), 0);
            }

            /////////////////////////
            // EFFECTS & INTERACTIONS
            // (No safe failures beyond this point)

            console.log("@Comptroller: liquidateDSDCalculateSeizeTokens");

            /* We calculate the number of collateral tokens that will be seized */
            (uint amountSeizeError, uint seizeTokens) = comptroller.liquidateDSDCalculateSeizeTokens(
                address(llTokenCollateral),
                actualRepayAmount
            );
            require(
                amountSeizeError == uint(Error.NO_ERROR),
                "DSD_LIQUIDATE_COMPTROLLER_CALCULATE_AMOUNT_SEIZE_FAILED"
            );

            /* Revert if borrower collateral token balance < seizeTokens */
            require(llTokenCollateral.balanceOf(borrower) >= seizeTokens, "DSD_LIQUIDATE_SEIZE_TOO_MUCH");

            console.log("@llTokenCollateral: seize");
            uint seizeError;
            seizeError = llTokenCollateral.seize(liquidator, borrower, seizeTokens);

            /* Revert if seize tokens fails (since we cannot be sure of side effects) */
            require(seizeError == uint(Error.NO_ERROR), "token seizure failed");

            /* We emit a LiquidateBorrow event */
            emit LiquidateDSD(liquidator, borrower, actualRepayAmount, address(llTokenCollateral), seizeTokens);

            console.log("@Comptroller: liquidateBorrowVerify");
            /* We call the defense hook */
            comptroller.liquidateBorrowVerify(
                address(this),
                address(llTokenCollateral),
                liquidator,
                borrower,
                actualRepayAmount,
                seizeTokens
            );

            return (uint(Error.NO_ERROR), actualRepayAmount);
        }
    }

    /**
     * @notice Redeem from Yield
     * @param _lltoken The address of the llToken
     * @param _dsdAmount The amount of DSD to redeem
     */
    function redeemFromYield(address _lltoken, uint _dsdAmount) external returns (uint) {
        return redeemFromYieldInternal(_lltoken, _dsdAmount);
    }

    function redeemFromYieldInternal(address _lltoken, uint _dsdAmount) public returns (uint) {
        require(_dsdAmount > 0, "ZERO_AMOUNT");
        require(IDSD(getDSDAddress()).balanceOf(msg.sender) >= _dsdAmount, "DSD_NEF");
        require(ILLToken(_lltoken).isRedeemFromYieldAllowed(), "!allowed");
        uint _borrowed = ComptrollerImplInterface(address(comptroller)).mintedDSDs(msg.sender);
        require(_borrowed == 0, "REPAY_FIRST");
        uint _redeemAmount = _dsdAmount.sub(_borrowed);

        PriceOracle oracle = ComptrollerImplInterface(address(comptroller)).oracle();
        uint _redeemableInUnderlying = ILLToken(_lltoken).redeemableInUnderlying();
        uint _redeemableUnderlyingInUSD = _redeemableInUnderlying.mul(oracle.getUnderlyingPrice(LLToken(_lltoken))).div(
            1e18
        );

        require(_redeemableUnderlyingInUSD >= _redeemAmount, "MORE_THAN_REDEEMABLE");
        ILLToken(_lltoken).redeemFromYield(_redeemAmount, msg.sender);
        IDSD(getDSDAddress()).burn(msg.sender, _redeemAmount);
        oracle.validateUnderlyingPrice(LLToken(_lltoken));
        return _redeemAmount;
    }

    function rigidRedeem(address _lltoken, address payable _provider, uint _dsdAmount) public returns (uint) {
        require(_dsdAmount > 0, "ZERO_AMOUNT");
        require(IDSD(getDSDAddress()).balanceOf(msg.sender) >= _dsdAmount, "DSD_NEF");
        require(ILLToken(_lltoken).isRedeemFromYieldAllowed(), "!allowed");

        uint _borrowed = ComptrollerImplInterface(address(comptroller)).mintedDSDs(msg.sender);
        require(_borrowed == 0, "REPAY_FIRST");

        _borrowed = ComptrollerImplInterface(address(comptroller)).mintedDSDs(_provider);
        require(_borrowed >= _dsdAmount, "PROVIDER_NEF");

        repayDSDFresh(msg.sender, _provider, _dsdAmount);

        ILLToken(_lltoken).rigidRedeem(_provider, msg.sender, _dsdAmount);

    }

    /*** Admin Functions ***/

    /**
     * @notice Sets a new comptroller
     * @dev Admin function to set a new comptroller
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setComptroller(ComptrollerInterface comptroller_) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COMPTROLLER_OWNER_CHECK);
        }

        ComptrollerInterface oldComptroller = comptroller;
        comptroller = comptroller_;
        emit NewComptroller(oldComptroller, comptroller_);

        return uint(Error.NO_ERROR);
    }

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account total supply balance.
     *  Note that `llTokenBalance` is the number of llTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountAmountLocalVars {
        uint oErr;
        MathError mErr;
        uint sumSupply;
        uint marketSupply;
        uint sumBorrowPlusEffects;
        uint llTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
        uint totalDepositedInEtherForUser;
    }

    // solhint-disable-next-line code-complexity
    function getMintableDSD(address minter) public view returns (uint, uint) {
        PriceOracle oracle = ComptrollerImplInterface(address(comptroller)).oracle();
        LLToken[] memory enteredMarkets = ComptrollerImplInterface(address(comptroller)).getAssetsIn(minter);

        AccountAmountLocalVars memory vars; // Holds all our calculation results

        uint accountMintableDSD;
        uint i;

        /**
         * We use this formula to calculate mintable DSD amount.
         * totalSupplyAmount * DSDMintRate - (totalBorrowAmount + mintedDSDOf)
         */
        for (i = 0; i < enteredMarkets.length; i++) {
            (
                vars.oErr,
                vars.llTokenBalance,
                vars.borrowBalance,
                vars.exchangeRateMantissa,
                vars.totalDepositedInEtherForUser
            ) = enteredMarkets[i].getAccountSnapshot(minter);
            if (vars.oErr != 0) {
                // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (uint(Error.SNAPSHOT_ERROR), 0);
            }
            vars.exchangeRate = Exp({ mantissa: vars.exchangeRateMantissa });

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = oracle.getETHPriceInUSD();

            if (vars.oraclePriceMantissa == 0) {
                return (uint(Error.PRICE_ERROR), 0);
            }
            vars.oraclePrice = Exp({ mantissa: vars.oraclePriceMantissa });

            (vars.mErr, vars.tokensToDenom) = mulExp(vars.exchangeRate, vars.oraclePrice);
            if (vars.mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }

            // marketSupply = tokensToDenom * llTokenBalance
            (vars.mErr, vars.marketSupply) = mulScalarTruncate(vars.oraclePrice, vars.totalDepositedInEtherForUser);
            if (vars.mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }

            (, uint collateralFactorMantissa, ) = Comptroller(address(comptroller)).markets(address(enteredMarkets[i]));
            (vars.mErr, vars.marketSupply) = mulUInt(vars.marketSupply, collateralFactorMantissa);
            if (vars.mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }

            (vars.mErr, vars.marketSupply) = divUInt(vars.marketSupply, 1e18);
            if (vars.mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }

            (vars.mErr, vars.sumSupply) = addUInt(vars.sumSupply, vars.marketSupply);
            if (vars.mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            (vars.mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(
                vars.oraclePrice,
                vars.borrowBalance,
                vars.sumBorrowPlusEffects
            );
            if (vars.mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }
        }

        uint totalMintedDSD = ComptrollerImplInterface(address(comptroller)).mintedDSDs(minter);
        uint256 repayAmount = 0;

        if (totalMintedDSD > 0) {
            repayAmount = getDSDRepayAmount(minter);
        }

        (vars.mErr, vars.sumBorrowPlusEffects) = addUInt(vars.sumBorrowPlusEffects, repayAmount);
        if (vars.mErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0);
        }

        (vars.mErr, accountMintableDSD) = mulUInt(
            vars.sumSupply,
            ComptrollerImplInterface(address(comptroller)).dsdMintRate()
        );
        require(vars.mErr == MathError.NO_ERROR, "DSD_MINT_AMOUNT_CALCULATION_FAILED");

        (vars.mErr, accountMintableDSD) = divUInt(accountMintableDSD, 10000);
        require(vars.mErr == MathError.NO_ERROR, "DSD_MINT_AMOUNT_CALCULATION_FAILED");

        (vars.mErr, accountMintableDSD) = subUInt(accountMintableDSD, vars.sumBorrowPlusEffects);
        if (vars.mErr != MathError.NO_ERROR) {
            return (uint(Error.REJECTION), 0);
        }

        return (uint(Error.NO_ERROR), accountMintableDSD);
    }

    function _setTreasuryData(
        address newTreasuryGuardian,
        address newTreasuryAddress,
        uint newTreasuryPercent
    ) external returns (uint) {
        // Check caller is admin
        if (!(msg.sender == admin || msg.sender == treasuryGuardian)) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_TREASURY_OWNER_CHECK);
        }

        require(newTreasuryPercent < 1e18, "treasury percent cap overflow");

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

    // function getDSDRepayRate() public view returns (uint) {
    //     PriceOracle oracle = ComptrollerImplInterface(address(comptroller)).oracle();
    //     MathError mErr;

    //     if (baseRateMantissa > 0) {
    //         if (floatRateMantissa > 0) {
    //             uint oraclePrice = oracle.getUnderlyingPrice(LLToken(getDSDAddress()));
    //             if (1e18 > oraclePrice) {
    //                 uint delta;
    //                 uint rate;

    //                 (mErr, delta) = subUInt(1e18, oraclePrice);
    //                 require(mErr == MathError.NO_ERROR, "DSD_REPAY_RATE_CALCULATION_FAILED");

    //                 (mErr, delta) = mulUInt(delta, floatRateMantissa);
    //                 require(mErr == MathError.NO_ERROR, "DSD_REPAY_RATE_CALCULATION_FAILED");

    //                 (mErr, delta) = divUInt(delta, 1e18);
    //                 require(mErr == MathError.NO_ERROR, "DSD_REPAY_RATE_CALCULATION_FAILED");

    //                 (mErr, rate) = addUInt(delta, baseRateMantissa);
    //                 require(mErr == MathError.NO_ERROR, "DSD_REPAY_RATE_CALCULATION_FAILED");

    //                 return rate;
    //             } else {
    //                 return baseRateMantissa;
    //             }
    //         } else {
    //             return baseRateMantissa;
    //         }
    //     } else {
    //         return 0;
    //     }
    // }


    /**
     * @notice Get the current total DSD a user needs to repay
     * @param account The address of the DSD borrower
     * @return (uint) The total amount of DSD the user needs to repay
     */
    function getDSDRepayAmount(address account) public view returns (uint) {
        uint amount = ComptrollerImplInterface(address(comptroller)).mintedDSDs(account);
        return amount;
    }

    /**
     * @notice Calculate how much DSD the user needs to repay
     * @param borrower The address of the DSD borrower
     * @param repayAmount The amount of DSD being returned
     * @return (uint, uint, uint) Amount of DSD to be burned, amount of DSD the user needs to pay in current interest and amount of DSD the user needs to pay in past interest
     */
    function getDSDCalculateRepayAmount(address borrower, uint256 repayAmount) public view returns (uint) {
        uint256 totalRepayAmount = getDSDRepayAmount(borrower);
        require(repayAmount <= totalRepayAmount, "Repaying Higher than Borrowed");
        uint burn = repayAmount;
        return burn;
    }

    /**
     * @notice Sets the address of the access control of this contract
     * @dev Admin function to set the access control address
     * @param newAccessControlAddress New address for the access control
     */
    function setAccessControl(address newAccessControlAddress) external onlyAdmin {
        _ensureNonzeroAddress(newAccessControlAddress);

        address oldAccessControlAddress = accessControl;
        accessControl = newAccessControlAddress;
        emit NewAccessControl(oldAccessControlAddress, accessControl);
    }

    // /**
    //  * @notice Set DSD borrow base rate
    //  * @param newBaseRateMantissa the base rate multiplied by 10**18
    //  */
    // function setBaseRate(uint newBaseRateMantissa) external {
    //     _ensureAllowed("setBaseRate(uint256)");

    //     uint old = baseRateMantissa;
    //     baseRateMantissa = newBaseRateMantissa;
    //     emit NewDSDBaseRate(old, baseRateMantissa);
    // }

    // /**
    //  * @notice Set DSD borrow float rate
    //  * @param newFloatRateMantissa the DSD float rate multiplied by 10**18
    //  */
    // function setFloatRate(uint newFloatRateMantissa) external {
    //     _ensureAllowed("setFloatRate(uint256)");

    //     uint old = floatRateMantissa;
    //     floatRateMantissa = newFloatRateMantissa;
    //     emit NewDSDFloatRate(old, floatRateMantissa);
    // }

    /**
     * @notice Set DSD stability fee receiver address
     * @param newReceiver the address of the DSD fee receiver
     */
    function setReceiver(address newReceiver) external onlyAdmin {
        require(newReceiver != address(0), "invalid receiver address");

        address old = receiver;
        receiver = newReceiver;
        emit NewDSDReceiver(old, newReceiver);
    }

    /**
     * @notice Set DSD mint cap
     * @param _mintCap the amount of DSD that can be minted
     */
    function setMintCap(uint _mintCap) external {
        _ensureAllowed("setMintCap(uint256)");

        uint old = mintCap;
        mintCap = _mintCap;
        emit NewDSDMintCap(old, _mintCap);
    }

    /**
     * @notice Return the address of the DSD token
     * @return The address of DSD
     */
    function getDSDAddress() public view returns (address) {
        return DSDAddress;
    }

    /**
     * @notice Set the address of DSD token
     */
    function setDSDAddress(address _DSD) external onlyAdmin {
        DSDAddress = _DSD;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin can");
        _;
    }

    /*** Reentrancy Guard ***/

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        require(_notEntered, "re-entered");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }

    function _ensureAllowed(string memory functionSig) private view {
        require(IAccessControlManager(accessControl).isAllowedToCall(msg.sender, functionSig), "access denied");
    }

    /// @notice Reverts if the passed address is zero
    function _ensureNonzeroAddress(address someone) private pure {
        require(someone != address(0), "can't be zero address");
    }
}
