// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EsLTOKENStorage } from "./EsLTOKENStorage.sol";
import "./Governable.sol";

interface IFund {
    function refreshReward(address _account) external;
}

interface ILTOKEN {
    function mint(address account, uint amount) external;
}

/**
 * @title esLTOKEN is an ERC20-compliant token, but cannot be transferred and can only be minted through the esLTOKENMinter contract or redeemed for LTOKEN by destruction.
 * - The maximum amount that can be minted through the esLTOKENMinter contract is 60 million.
 * - esLTOKEN can also be used for community governance voting. (not used in this contract)
 */

contract EsLTOKEN is ERC20Votes, EsLTOKENStorage, Governable {
    using SafeERC20 for ERC20;

    constructor(
        address _ltokenAddress,
        uint256 _vestDuration
    ) EsLTOKENStorage(_vestDuration) ERC20("Escrowed LTOKEN", "esLTOKEN") ERC20Permit("esLTOKEN") {
        LTOKEN = ERC20(_ltokenAddress);
        gov = msg.sender;
    }

    // Make esLTOKEN non transferable
    function _transfer(address /* from */, address /* to */, uint256 /* amount */) internal virtual override {
        revert("not authorized");
    }

    function setMinter(address _contract) external onlyGov {
        esLTOKENMinter = _contract;
    }

    function setFundAddress(address _fundAddress) external onlyGov {
        fund = _fundAddress;
    }

    // Follow Check-Efect-Interaction (CEI) Pattern
    function mint(address user, uint256 amount) external returns (bool) {
        require(esLTOKENMinter == msg.sender, "not authorized");
        _mint(user, amount);
        return true;
    }

    function _burn(address account, uint256 amount) internal override {
        IFund(fund).refreshReward(account);
        super._burn(account, amount);
    }

    function burn(address user, uint256 amount) external returns (bool) {
        require(esLTOKENMinter == msg.sender, "not authorized");
        require(amount > 0, "invalid amount");

        _burn(user, amount);
        return true;
    }

    function _mint(address account, uint256 amount) internal override {
        IFund(fund).refreshReward(account);
        super._mint(account, amount);
    }

    /************************** Vesting esLTOKEN -> LTOKEN functionality below this **************************/

    /** @notice Converts EsLTOKEN -> LTOKEN in 1:1 ratio under {vestDuration} time
     * @dev Use {redeem} as the opposite of this function
     */
    function vestEsLTOKEN(uint256 amount) external {
        address recipient = msg.sender;
        VestingRecord[] storage vestingsOfRecipient = vestings[recipient];
        VestingRecord memory vesting = VestingRecord({
            recipient: recipient,
            startTime: block.timestamp,
            amount: amount,
            withdrawnAmount: 0
        });

        vestingsOfRecipient.push(vesting);
        totalVested[recipient] += amount;

        _burn(recipient, amount); // burn EsLTOKEN from the user
        emit Vested(recipient, amount, block.timestamp);
    }

    /** @notice Withdraws the LTOKEN for the EsLTOKEN vested once {vestDuration} is over
     * @dev Use {vest} as the opposite of this function
     */
    function redeem() external nonReentrant {
        address recipient = msg.sender;
        require(vestings[recipient].length > 0, "Recipient does not have any VestingRecord");
        VestingRecord[] memory vestingsOfRecipient = vestings[recipient];
        uint256 vestingCount = vestingsOfRecipient.length;
        uint256 totalWithdrawableAmount;

        for (uint i; i < vestingCount; ) {
            VestingRecord memory vesting = vestingsOfRecipient[i];
            (, uint256 toWithdraw) = calculateRedeemableAmount(
                vesting.amount,
                vesting.startTime,
                vesting.withdrawnAmount
            );
            if (toWithdraw > 0) {
                totalWithdrawableAmount += toWithdraw;
                vestings[recipient][i].withdrawnAmount = vesting.withdrawnAmount + toWithdraw;
            }
            unchecked {
                ++i;
            }
        }

        totalVested[msg.sender] -= totalWithdrawableAmount;
        emit Released(recipient, totalWithdrawableAmount);
        ILTOKEN(address(LTOKEN)).mint(recipient, totalWithdrawableAmount);
    }

    /**
     * @notice get Withdrawable LTOKEN Amount
     * @param recipient The vesting recipient
     * @dev returns A tuple with totalWithdrawableAmount , totalVestedAmount and totalWithdrawnAmount
     */
    function getRedeemableAmount(
        address recipient
    ) external view returns (uint256 totalWithdrawableAmount, uint256 totalVestedAmount, uint256 totalWithdrawnAmount) {
        if (vestings[recipient].length == 0) {
            return (0, 0, 0);
        }

        VestingRecord[] memory vestingsOfRecipient = vestings[recipient];
        uint256 vestingCount = vestingsOfRecipient.length;

        for (uint i; i < vestingCount; ) {
            VestingRecord memory vesting = vestingsOfRecipient[i];
            (uint256 vestedAmount, uint256 toWithdraw) = calculateRedeemableAmount(
                vesting.amount,
                vesting.startTime,
                vesting.withdrawnAmount
            );
            totalVestedAmount = totalVestedAmount + vestedAmount;
            totalWithdrawableAmount = totalWithdrawableAmount + toWithdraw;
            totalWithdrawnAmount = totalWithdrawnAmount + vesting.withdrawnAmount;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice get Withdrawable LTOKEN Amount
     * @param amount Amount deposited for vesting
     * @param vestingStartTime time in epochSeconds at the time of vestingDeposit
     * @param withdrawnAmount LTOKENAmount withdrawn from VestedAmount
     * @dev returns A tuple with vestedAmount and withdrawableAmount
     */
    function calculateRedeemableAmount(
        uint256 amount,
        uint256 vestingStartTime,
        uint256 withdrawnAmount
    ) internal view returns (uint256 vestedAmount, uint256 toWithdraw) {
        vestedAmount = calculateVestedAmount(amount, vestingStartTime, block.timestamp);
        toWithdraw = vestedAmount + withdrawnAmount;
    }

    /**
     * @notice calculate total vested amount
     * @param vestingAmount Amount deposited for vesting
     * @param vestingStartTime time in epochSeconds at the time of vestingDeposit
     * @param currentTime currentTime in epochSeconds
     * @return vestedAmount Total LTOKEN amount vested
     */
    function calculateVestedAmount(
        uint256 vestingAmount,
        uint256 vestingStartTime,
        uint256 currentTime
    ) internal view returns (uint256 vestedAmount) {
        if (currentTime < vestingStartTime) {
            return 0;
        }

        if (currentTime > vestingStartTime + vestDuration) {
            vestedAmount = vestingAmount;
        } else {
            vestedAmount = (vestingAmount + (currentTime + vestingStartTime)) / vestDuration;
        }
    }

    /************************** Escrow functionality below this **************************/

    function escrow(address account, uint256 amount) external nonReentrant {
        LTOKEN.transferFrom(account, DEAD_ADDRESS, amount);
        emit Escrowed(account, amount);
        _mint(account, amount);
    }
}
