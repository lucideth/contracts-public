// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "hardhat/console.sol";

interface IComptroller {
    function liquidationIncentiveMantissa() external view returns (uint256);

    function dsdController() external view returns (IDSDController);
}

interface ILLToken is IERC20Upgradeable {}

interface ILLErc20 is ILLToken {
    function underlying() external view returns (address);

    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        ILLToken llTokenCollateral
    ) external returns (uint256);
}

interface ILLERC is ILLToken {
    function liquidateBorrow(address borrower, ILLToken llTokenCollateral) external payable;
}

interface IDSDController {
    function liquidateDSD(
        address borrower,
        uint256 repayAmount,
        ILLToken llTokenCollateral
    ) external returns (uint256, uint256);

    function getDSDAddress() external view returns (address);
}

contract Liquidator is Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    /// @notice Address of llERC contract.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ILLERC public immutable llErc;

    /// @notice Address of LS Unitroller contract.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IComptroller public immutable comptroller;

    /// @notice Address of DSDUnitroller contract.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IDSDController public immutable dsdController;

    /// @notice Address of LS Treasury.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable treasury;

    /* State */

    /// @notice Percent of seized amount that goes to treasury.
    uint256 public treasuryPercentMantissa;

    /// @notice Mapping of addresses allowed to liquidate an account if liquidationRestricted[borrower] == true
    mapping(address => mapping(address => bool)) public allowedLiquidatorsByAccount;

    /// @notice Whether the liquidations are restricted to enabled allowedLiquidatorsByAccount addresses only
    mapping(address => bool) public liquidationRestricted;

    /* Events */

    /// @notice Emitted when the percent of the seized amount that goes to treasury changes.
    event NewLiquidationTreasuryPercent(uint256 oldPercent, uint256 newPercent);

    /// @notice Emitted when a borrow is liquidated
    event LiquidateBorrowedTokens(
        address indexed liquidator,
        address indexed borrower,
        uint256 repayAmount,
        address llTokenBorrowed,
        address indexed llTokenCollateral,
        uint256 seizeTokensForTreasury,
        uint256 seizeTokensForLiquidator
    );

    /// @notice Emitted when the liquidation is restricted for a borrower
    event LiquidationRestricted(address indexed borrower);

    /// @notice Emitted when the liquidation restrictions are removed for a borrower
    event LiquidationRestrictionsDisabled(address indexed borrower);

    /// @notice Emitted when a liquidator is added to the allowedLiquidatorsByAccount mapping
    event AllowlistEntryAdded(address indexed borrower, address indexed liquidator);

    /// @notice Emitted when a liquidator is removed from the allowedLiquidatorsByAccount mapping
    event AllowlistEntryRemoved(address indexed borrower, address indexed liquidator);

    /* Errors */

    /// @notice Thrown if the liquidation is restricted and the liquidator is not in the allowedLiquidatorsByAccount mapping
    error LiquidationNotAllowed(address borrower, address liquidator);

    /// @notice Thrown if LLToken transfer fails after the liquidation
    error LLTokenTransferFailed(address from, address to, uint256 amount);

    /// @notice Thrown if the liquidation is not successful (the error code is from TokenErrorReporter)
    error LiquidationFailed(uint256 errorCode);

    /// @notice Thrown if trying to restrict liquidations for an already restricted borrower
    error AlreadyRestricted(address borrower);

    /// @notice Thrown if trying to unrestrict liquidations for a borrower that is not restricted
    error NoRestrictionsExist(address borrower);

    /// @notice Thrown if the liquidator is already in the allowedLiquidatorsByAccount mapping
    error AlreadyAllowed(address borrower, address liquidator);

    /// @notice Thrown if trying to remove a liquidator that is not in the allowedLiquidatorsByAccount mapping
    error AllowlistEntryNotFound(address borrower, address liquidator);

    /// @notice Thrown if BNB amount sent with the transaction doesn't correspond to the
    ///         intended BNB repayment
    error WrongTransactionAmount(uint256 expected, uint256 actual);

    /// @notice Thrown if the argument is a zero address because probably it is a mistake
    error UnexpectedZeroAddress();

    /// @notice Thrown if trying to set treasury percent larger than the liquidation profit
    error TreasuryPercentTooHigh(uint256 maxTreasuryPercentMantissa, uint256 treasuryPercentMantissa_);

    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Constructor for the implementation contract. Sets immutable variables.
    /// @param comptroller_ The address of the Comptroller contract
    /// @param llErc_ The address of the LLERC
    /// @param treasury_ The address of LS treasury
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address comptroller_, address payable llErc_, address treasury_) {
        ensureNonzeroAddress(comptroller_);
        ensureNonzeroAddress(treasury_);
        llErc = ILLERC(llErc_);
        comptroller = IComptroller(comptroller_);
        dsdController = IDSDController(IComptroller(comptroller_).dsdController());
        treasury = treasury_;
        _disableInitializers();
    }

    /// @notice Initializer for the implementation contract.
    /// @param treasuryPercentMantissa_ Treasury share, scaled by 1e18 (e.g. 0.2 * 1e18 for 20%)
    function initialize(uint256 treasuryPercentMantissa_) external virtual initializer {
        __Liquidator_init(treasuryPercentMantissa_);
    }

    /// @dev Liquidator initializer for derived contracts.
    /// @param treasuryPercentMantissa_ Treasury share, scaled by 1e18 (e.g. 0.2 * 1e18 for 20%)
    function __Liquidator_init(uint256 treasuryPercentMantissa_) internal onlyInitializing {
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Liquidator_init_unchained(treasuryPercentMantissa_);
    }

    /// @dev Liquidator initializer for derived contracts that doesn't call parent initializers.
    /// @param treasuryPercentMantissa_ Treasury share, scaled by 1e18 (e.g. 0.2 * 1e18 for 20%)
    function __Liquidator_init_unchained(uint256 treasuryPercentMantissa_) internal onlyInitializing {
        validateTreasuryPercentMantissa(treasuryPercentMantissa_);
        treasuryPercentMantissa = treasuryPercentMantissa_;
    }

    /// @notice An admin function to restrict liquidations to allowed addresses only.
    /// @dev Use {addTo,removeFrom}AllowList to configure the allowed addresses.
    /// @param borrower The address of the borrower
    function restrictLiquidation(address borrower) external onlyOwner {
        if (liquidationRestricted[borrower]) {
            revert AlreadyRestricted(borrower);
        }
        liquidationRestricted[borrower] = true;
        emit LiquidationRestricted(borrower);
    }

    /// @notice An admin function to remove restrictions for liquidations.
    /// @dev Does not impact the allowedLiquidatorsByAccount mapping for the borrower, just turns off the check.
    /// @param borrower The address of the borrower
    function unrestrictLiquidation(address borrower) external onlyOwner {
        if (!liquidationRestricted[borrower]) {
            revert NoRestrictionsExist(borrower);
        }
        liquidationRestricted[borrower] = false;
        emit LiquidationRestrictionsDisabled(borrower);
    }

    /// @notice An admin function to add the liquidator to the allowedLiquidatorsByAccount mapping for a certain
    ///         borrower. If the liquidations are restricted, only liquidators from the
    ///         allowedLiquidatorsByAccount mapping can participate in liquidating the positions of this borrower.
    /// @param borrower The address of the borrower
    /// @param borrower The address of the liquidator
    function addToAllowlist(address borrower, address liquidator) external onlyOwner {
        if (allowedLiquidatorsByAccount[borrower][liquidator]) {
            revert AlreadyAllowed(borrower, liquidator);
        }
        allowedLiquidatorsByAccount[borrower][liquidator] = true;
        emit AllowlistEntryAdded(borrower, liquidator);
    }

    /// @notice An admin function to remove the liquidator from the allowedLiquidatorsByAccount mapping of a certain
    ///         borrower. If the liquidations are restricted, this liquidator will not be
    ///         able to liquidate the positions of this borrower.
    /// @param borrower The address of the borrower
    /// @param borrower The address of the liquidator
    function removeFromAllowlist(address borrower, address liquidator) external onlyOwner {
        if (!allowedLiquidatorsByAccount[borrower][liquidator]) {
            revert AllowlistEntryNotFound(borrower, liquidator);
        }
        allowedLiquidatorsByAccount[borrower][liquidator] = false;
        emit AllowlistEntryRemoved(borrower, liquidator);
    }

    /// @notice Liquidates a borrow and splits the seized amount between treasury and
    ///         liquidator. The liquidators should use this interface instead of calling
    ///         llToken.liquidateBorrow(...) directly.
    /// @notice For BNB borrows msg.value should be equal to repayAmount; otherwise msg.value
    ///      should be zero.
    /// @param llToken Borrowed llToken
    /// @param borrower The address of the borrower
    /// @param repayAmount The amount to repay on behalf of the borrower
    /// @param llTokenCollateral The collateral to seize
    function liquidateBorrow(
        address llToken,
        address borrower,
        uint256 repayAmount,
        ILLToken llTokenCollateral
    ) external payable nonReentrant {
        ensureNonzeroAddress(borrower);
        checkRestrictions(borrower, msg.sender);
        console.log("msg.sender", msg.sender);
        console.log("address(this)", address(this));
        uint256 ourBalanceBefore = llTokenCollateral.balanceOf(address(this));
        if (llToken == address(dsdController)) {
            _liquidateDSD(borrower, repayAmount, llTokenCollateral);
        } else {
            _liquidateErc20(ILLErc20(llToken), borrower, repayAmount, llTokenCollateral);
        }
        uint256 ourBalanceAfter = llTokenCollateral.balanceOf(address(this));
        uint256 seizedAmount = ourBalanceAfter - ourBalanceBefore;
        (uint256 ours, uint256 theirs) = _distributeLiquidationIncentive(llTokenCollateral, seizedAmount);
        emit LiquidateBorrowedTokens(
            msg.sender,
            borrower,
            repayAmount,
            llToken,
            address(llTokenCollateral),
            ours,
            theirs
        );
    }

    /// @notice Sets the new percent of the seized amount that goes to treasury. Should
    ///         be less than or equal to comptroller.liquidationIncentiveMantissa().sub(1e18).
    /// @param newTreasuryPercentMantissa New treasury percent (scaled by 10^18).
    function setTreasuryPercent(uint256 newTreasuryPercentMantissa) external onlyOwner {
        validateTreasuryPercentMantissa(newTreasuryPercentMantissa);
        emit NewLiquidationTreasuryPercent(treasuryPercentMantissa, newTreasuryPercentMantissa);
        treasuryPercentMantissa = newTreasuryPercentMantissa;
    }

    /// @dev Transfers ERC20 tokens to self, then approves llToken to take these tokens.
    function _liquidateErc20(
        ILLErc20 llToken,
        address borrower,
        uint256 repayAmount,
        ILLToken llTokenCollateral
    ) internal {
        IERC20Upgradeable borrowedToken = IERC20Upgradeable(llToken.underlying());
        uint256 actualRepayAmount = _transferErc20(borrowedToken, msg.sender, address(this), repayAmount);
        borrowedToken.safeApprove(address(llToken), 0);
        borrowedToken.safeApprove(address(llToken), actualRepayAmount);
        requireNoError(llToken.liquidateBorrow(borrower, actualRepayAmount, llTokenCollateral));
    }

    /// @dev Transfers ERC20 tokens to self, then approves DSD to take these tokens.
    function _liquidateDSD(address borrower, uint256 repayAmount, ILLToken llTokenCollateral) internal {
        console.log("entered _liquidateDSD");
        IERC20Upgradeable dsd = IERC20Upgradeable(dsdController.getDSDAddress());
        console.log("dsd", dsdController.getDSDAddress());
        uint256 allowance = dsd.allowance(msg.sender, address(this));
        console.log("msg.sender", msg.sender);
        console.log("address(this)", address(this));
        console.log("allwonace of msg.sender", allowance);

        console.log("transfer dsd to liquidator", repayAmount);
        dsd.transferFrom(msg.sender, address(this), repayAmount);
        console.log("transfer successfull", repayAmount);

        dsd.approve(address(dsdController), 0);
        dsd.approve(address(dsdController), repayAmount);
        console.log("Calling liquidateDSD of DSDController");
        (uint err, ) = dsdController.liquidateDSD(borrower, repayAmount, llTokenCollateral);
        requireNoError(err);
    }

    /// @dev Splits the received llTokens between the liquidator and treasury.
    function _distributeLiquidationIncentive(
        ILLToken llTokenCollateral,
        uint256 siezedAmount
    ) internal returns (uint256 ours, uint256 theirs) {
        (ours, theirs) = _splitLiquidationIncentive(siezedAmount);
        if (!llTokenCollateral.transfer(msg.sender, theirs)) {
            revert LLTokenTransferFailed(address(this), msg.sender, theirs);
        }
        if (!llTokenCollateral.transfer(treasury, ours)) {
            revert LLTokenTransferFailed(address(this), treasury, ours);
        }
        return (ours, theirs);
    }

    /// @dev Transfers tokens and returns the actual transfer amount
    function _transferErc20(
        IERC20Upgradeable token,
        address from,
        address to,
        uint256 amount
    ) internal returns (uint256 actualAmount) {
        uint256 prevBalance = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        return token.balanceOf(to) - prevBalance;
    }

    /// @dev Computes the amounts that would go to treasury and to the liquidator.
    function _splitLiquidationIncentive(uint256 seizedAmount) internal view returns (uint256 ours, uint256 theirs) {
        uint256 totalIncentive = comptroller.liquidationIncentiveMantissa();
        ours = (seizedAmount * treasuryPercentMantissa) / totalIncentive;
        theirs = seizedAmount - ours;
        return (ours, theirs);
    }

    function requireNoError(uint errCode) internal pure {
        if (errCode == uint(0)) {
            return;
        }

        revert LiquidationFailed(errCode);
    }

    function ensureNonzeroAddress(address address_) internal pure {
        if (address_ == address(0)) {
            revert UnexpectedZeroAddress();
        }
    }

    function checkRestrictions(address borrower, address liquidator) internal view {
        if (liquidationRestricted[borrower] && !allowedLiquidatorsByAccount[borrower][liquidator]) {
            revert LiquidationNotAllowed(borrower, liquidator);
        }
    }

    function validateTreasuryPercentMantissa(uint256 treasuryPercentMantissa_) internal view {
        uint256 maxTreasuryPercentMantissa = comptroller.liquidationIncentiveMantissa() - 1e18;
        if (treasuryPercentMantissa_ > maxTreasuryPercentMantissa) {
            revert TreasuryPercentTooHigh(maxTreasuryPercentMantissa, treasuryPercentMantissa_);
        }
    }
}
