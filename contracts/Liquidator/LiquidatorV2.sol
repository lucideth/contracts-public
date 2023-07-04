pragma solidity ^0.5.16;

import "../Comptroller/ComptrollerInterface.sol";
import "../Tokens/DSD/DSDControllerInterface.sol";
import "../Tokens/LLTokens/LLTokenInterfaces.sol";
import "../Utils/ReentrancyGuard.sol";
import "../Utils/WithAdmin.sol";
import "../Utils/SafeMath.sol";
import "../Utils/IERC20.sol";
import "../Utils/SafeERC20.sol";
import "hardhat/console.sol";

contract LiquidatorV2 is WithAdmin, ReentrancyGuard {
    /// @notice Address of Brainiac Unitroller contract.
    IComptroller comptroller;

    /// @notice Address of DSDUnitroller contract.
    DSDControllerInterface dsdController;

    /// @notice Address of Brainiac Treasury.
    address public treasury;

    /// @notice Percent of seized amount that goes to treasury.
    uint256 public treasuryPercentMantissa;

    /// @notice Emitted when once changes the percent of the seized amount
    ///         that goes to treasury.
    event NewLiquidationTreasuryPercent(uint256 oldPercent, uint256 newPercent);

    /// @notice Event emitted when a borrow is liquidated
    event LiquidateBorrowedTokens(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        address llTokenCollateral,
        uint256 seizeTokensForTreasury,
        uint256 seizeTokensForLiquidator
    );

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    constructor(
        address admin_,
        address comptroller_,
        address treasury_,
        uint256 treasuryPercentMantissa_
    ) public WithAdmin(admin_) ReentrancyGuard() {
        ensureNonzeroAddress(admin_);
        ensureNonzeroAddress(comptroller_);
        ensureNonzeroAddress(treasury_);
        comptroller = IComptroller(comptroller_);
        dsdController = DSDControllerInterface(IComptroller(comptroller_).dsdController());
        treasury = treasury_;
        treasuryPercentMantissa = treasuryPercentMantissa_;
    }

    /// @notice Liquidates a borrow and splits the seized amount between treasury and
    ///         liquidator. The liquidators should use this interface instead of calling
    ///         llToken.liquidateBorrow(...) directly.
    /// @dev For CKB borrows msg.value should be equal to repayAmount; otherwise msg.value
    ///      should be zero.
    /// @param llToken Borrowed llToken
    /// @param borrower The address of the borrower
    /// @param repayAmount The amount to repay on behalf of the borrower
    /// @param llTokenCollateral The collateral to seize
    function liquidateBorrow(
        address llToken,
        address borrower,
        uint256 repayAmount,
        LLTokenInterface llTokenCollateral
    ) external payable nonReentrant {
        ensureNonzeroAddress(borrower);
        console.log("msg.sender", msg.sender);
        console.log("address(this)", address(this));
        uint256 ourBalanceBefore = llTokenCollateral.balanceOf(address(this));
        require(msg.value == 0, "you shouldn't pay for this");
        if (llToken == address(dsdController)) {
            _liquidateDSD(borrower, repayAmount, llTokenCollateral);
        }
        uint256 ourBalanceAfter = llTokenCollateral.balanceOf(address(this));
        uint256 seizedAmount = ourBalanceAfter.sub(ourBalanceBefore);
        (uint256 ours, uint256 theirs) = _distributeLiquidationIncentive(llTokenCollateral, seizedAmount);
        emit LiquidateBorrowedTokens(msg.sender, borrower, repayAmount, address(llTokenCollateral), ours, theirs);
    }

    /// @notice Sets the new percent of the seized amount that goes to treasury. Should
    ///         be less than or equal to comptroller.liquidationIncentiveMantissa().sub(1e18).
    /// @param newTreasuryPercentMantissa New treasury percent (scaled by 10^18).
    function setTreasuryPercent(uint256 newTreasuryPercentMantissa) external onlyAdmin {
        require(newTreasuryPercentMantissa <= comptroller.liquidationIncentiveMantissa().sub(1e18), "appetite too big");
        emit NewLiquidationTreasuryPercent(treasuryPercentMantissa, newTreasuryPercentMantissa);
        treasuryPercentMantissa = newTreasuryPercentMantissa;
    }

    /// @dev Transfers ERC20 tokens to self, then approves dsd to take these tokens.
    function _liquidateDSD(address borrower, uint256 repayAmount, LLTokenInterface llTokenCollateral) internal {
        IERC20 dsd = IERC20(dsdController.getDSDAddress());

        uint256 allowance = dsd.allowance(msg.sender, address(this));
        console.log("msg.sender", msg.sender);
        console.log("address(this)", address(this));
        console.log("allwonace of msg.sender", allowance);

        console.log("transfer dsd to liquidator", repayAmount);
        console.log("@LIQUIDATE_DSD:: DSD_balance %s RepayAmount %s", dsd.balanceOf(msg.sender), repayAmount);

        dsd.safeTransferFrom(msg.sender, address(this), repayAmount);
        dsd.safeApprove(address(dsdController), 0);
        dsd.safeApprove(address(dsdController), repayAmount);
        console.log("@LIQUIDATE_DSD:: calling dsdController.liquidateDSD");
        (uint err, ) = dsdController.liquidateDSD(borrower, repayAmount, llTokenCollateral);
        requireNoError(err, "failed to liquidate");
    }

    /// @dev Splits the received llTokens between the liquidator and treasury.
    function _distributeLiquidationIncentive(
        LLTokenInterface llTokenCollateral,
        uint256 siezedAmount
    ) internal returns (uint256 ours, uint256 theirs) {
        (ours, theirs) = _splitLiquidationIncentive(siezedAmount);
        console.log("@BalanceOf:: msg.sender before: %s", llTokenCollateral.balanceOf(msg.sender));
        require(llTokenCollateral.transfer(msg.sender, theirs), "failed to transfer to liquidator");
        require(llTokenCollateral.transfer(treasury, ours), "failed to transfer to treasury");
        console.log("@LIQUIDATE_DSD:: ours %s theirs %s", ours, theirs);
        console.log("@BalanceOf:: msg.sender after: %s", llTokenCollateral.balanceOf(msg.sender));
        return (ours, theirs);
    }

    /// @dev Transfers tokens and returns the actual transfer amount
    function _transferErc20(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal returns (uint256 actualAmount) {
        uint256 prevBalance = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        return token.balanceOf(to).sub(prevBalance);
    }

    /// @dev Computes the amounts that would go to treasury and to the liquidator.
    function _splitLiquidationIncentive(uint256 seizedAmount) internal view returns (uint256 ours, uint256 theirs) {
        uint256 totalIncentive = comptroller.liquidationIncentiveMantissa();
        uint256 seizedForRepayment = seizedAmount.mul(1e18).div(totalIncentive);
        ours = seizedForRepayment.mul(treasuryPercentMantissa).div(1e18);
        theirs = seizedAmount.sub(ours);
        return (ours, theirs);
    }

    function requireNoError(uint errCode, string memory message) internal pure {
        if (errCode == uint(0)) {
            return;
        }

        bytes memory fullMessage = new bytes(bytes(message).length + 5);
        uint i;

        for (i = 0; i < bytes(message).length; i++) {
            fullMessage[i] = bytes(message)[i];
        }

        fullMessage[i + 0] = bytes1(uint8(32));
        fullMessage[i + 1] = bytes1(uint8(40));
        fullMessage[i + 2] = bytes1(uint8(48 + (errCode / 10)));
        fullMessage[i + 3] = bytes1(uint8(48 + (errCode % 10)));
        fullMessage[i + 4] = bytes1(uint8(41));

        revert(string(fullMessage));
    }

    function ensureNonzeroAddress(address addr) internal pure {
        require(addr != address(0), "address should be nonzero");
    }
}
