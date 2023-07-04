//SPDX-License-Identifier: MIT
pragma solidity ^0.5.16;

import "./LLToken.sol";
import "../../Interfaces/IERC4626.sol";
import "../../Interfaces/IMiniComptroller.sol";
import "../../Interfaces/IStrategy.sol";
import "../../Interfaces/IDSD.sol";
import "../../Interfaces/IFund.sol";
import "hardhat/console.sol";

/**
 * @title LS's LLErc20 Contract
 * @notice llTokens which wrap an EIP-20 underlying
 * @author LS
 */
contract LLErc20 is LLToken, LLErc20Interface {
    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives llTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint Returns 0 on success, otherwise returns a failure code (see ErrorReporter.sol for details).
     */
    // @custom:event Emits Transfer event
    // @custom:event Emits Mint event
    function mint(uint mintAmount) external returns (uint) {
        IMultiRewardInterface(multiReward).updateReward(msg.sender);
        (uint err, ) = mintInternal(mintAmount);
        return err;
    }

    /**
     * @notice Sender redeems llTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @return uint Returns 0 on success, otherwise returns a failure code (see ErrorReporter.sol for details).
     */
    // @custom:event Emits Redeem event on success
    // @custom:event Emits Transfer event on success
    // @custom:event Emits RedeemFee when fee is charged by the treasury
    function redeemUnderlying(uint redeemAmount) external returns (uint) {
        IMultiRewardInterface(multiReward).updateReward(msg.sender);
        return redeemUnderlyingInternal(redeemAmount);
    }

    /**
     * @notice Initialize the new money market
     * @param underlying_ The address of the underlying asset
     * @param comptroller_ The address of the Comptroller
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     * @param protocolToken_ DSD Token
     * @param isRebasing_ Is the underlying token is itself rebasing
     * @param isRewardAccumulating_ Is the underlying token is reward accumulating
     */
    constructor(
        address underlying_,
        address multiRewardHandler_,
        ComptrollerInterface comptroller_,
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address protocolToken_,
        bool isRebasing_,
        bool isRewardAccumulating_,
        bool isWrapped_
    ) public LLToken(comptroller_, initialExchangeRateMantissa_, name_, symbol_, decimals_, multiRewardHandler_) {
        // LLToken initialize does the bulk of the work
        setParams(protocolToken_, isRebasing_, isRewardAccumulating_, isWrapped_);
        // Set underlying and sanity check it
        underlying = underlying_;
        EIP20Interface(underlying_).totalSupply();
        isRedeemFromYieldAllowed = true;
    }

    /*** Safe Token ***/

    /**
     * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
     *      This will revert due to insufficient balance or insufficient allowance.
     *      This function returns the actual amount received,
     *      which may be less than `amount` if there is a fee attached to the transfer.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferIn(address from, uint amount) internal returns (uint) {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        uint balanceBefore = EIP20Interface(underlying).balanceOf(address(this));
        token.transferFrom(from, address(this), amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "TOKEN_TRANSFER_IN_FAILED");

        // Calculate the amount that was *actually* transferred
        uint balanceAfter = EIP20Interface(underlying).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
     *      error code rather than reverting. If caller has not called checked protocol's balance, this may revert due to
     *      insufficient cash held in this contract. If caller has checked protocol's balance prior to this call, and verified
     *      it is >= amount, this should not revert in normal conditions.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferOut(address payable to, uint amount) internal {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        token.transfer(to, amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a complaint ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "TOKEN_TRANSFER_OUT_FAILED");
    }

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @return The quantity of underlying tokens excluding redeemable
     */
    function getCashPrior() internal view returns (uint) {
        return nav().sub(redeemableInUnderlying);
    }

    /**
     * @notice Return the underlying token address
     */
    function underlyingToken() internal view returns (address) {
        return underlying;
    }

    /**
     * Set the parameters of the llToken
     * @param _protocolToken Parameter of the llToken i.e. DSD
     * @param _isRebasing Is the underlying token is itself rebasing
     * @param _isRewardAccumulating Is the underlying token is reward accumulating
     * @param _isWrapped Is the underlying token is wrapped
     */
    function setParams(address _protocolToken, bool _isRebasing, bool _isRewardAccumulating, bool _isWrapped) internal {
        DSD = _protocolToken;
        isRebasing = _isRebasing;
        isRewardAccumulating = _isRewardAccumulating;
        isWrapped = _isWrapped;
        wrappingFactor = 1e18;
    }

    /**
     * Set the redeem from yield allowed
     * @param _allowed Is the redeem from yield allowed
     */
    function allowRedeemFromYield(bool _allowed) public returns (uint) {
        require(msg.sender == admin, "!admin");
        isRedeemFromYieldAllowed = _allowed;
        return 0;
    }

    /**
     * Set the rebasing limit
     * @param _min Minimum percentage
     * @param _max Maximum percentage
     */
    function setRebasingLimit(uint _min, uint _max) public returns (uint) {
        require(msg.sender == admin, "!admin");
        require(_min <= _max, "MIN_MAX_ERR");
        limitRebaseMin = _min;
        limitRebaseMax = _max;
        return 0;
    }

    /**
     * Share in BPS for rewards
     * @param _mr Multirewards Bps (100 = 1%)
     * @param _esltoken esLTOKEN reward bps (100 = 1%)
     */
    function setRewardShareBps(uint _mr, uint _esltoken) public returns (uint) {
        require(msg.sender == admin, "!admin");
        require(_mr + _esltoken <= 9900, ">99%");
        multiRewardShareInBps = _mr;
        esLTOKENShareInBps = _esltoken;
        return 0;
    }

    /**
     * Set the Fund address
     * @param _fund Fund address
     */
    function setFund(address _fund) public returns (uint) {
        require(msg.sender == admin, "!admin");
        fund = _fund;
        return 0;
    }

    /**
     * Retursn the net asset value of the LLToken (considering strategy)
     */
    function nav() public view returns (uint) {
        if (strategy != address(0)) {
            return (IStrategy(strategy).nav()).add(EIP20Interface(underlying).balanceOf(address(this)));
        }
        return EIP20Interface(underlying).balanceOf(address(this));
    }

    /**
     * Collect rewards from the strategy (if present)
     */
    function _collectRewards() internal returns (uint) {
        if (isRewardAccumulating) {
            if (strategy != address(0)) {
                uint _underlyingIncreased = IStrategy(strategy).collectRewards();
                redeemableInUnderlying = redeemableInUnderlying.add(_underlyingIncreased);
                redeemableInEther = redeemableInEther.add(
                    PriceOracle(oracle).getPriceInETH(underlying).mul(_underlyingIncreased).div(1e18)
                );
                emit RewardCollected(address(this), _underlyingIncreased);
                return _underlyingIncreased;
            }
            return 0;
        }
        return 0;
    }

    /**
     * Get the worth of all the underlying tokens in ether
     */
    function getWorthInEther() public view returns (uint) {
        return PriceOracle(oracle).getPriceInETH(underlying).mul(nav()).div(1e18);
    }

    /*
     *   Handle the unaccounted underlying tokens as yield
     */
    function _calculateAndHandleUnaccountedUnderlying() internal returns (uint) {
        if (nav() <= (totalUseableBalanceInUnderlying + redeemableInUnderlying)) {
            return 0;
        }
        uint _unaccounted = nav().sub(totalUseableBalanceInUnderlying.add(redeemableInUnderlying));
        redeemableInUnderlying = redeemableInUnderlying.add(_unaccounted);
        redeemableInEther = redeemableInEther.add(
            PriceOracle(oracle).getPriceInETH(underlying).mul(_unaccounted).div(1e18)
        );
        return _unaccounted;
    }

    /*
     *   Pre-rebase actions includes handling unaccounted underlying funds,
     *   collecting rewards and checking if there is increase in the worth
     *   of the underlying tokens wrt to ETH
     */
    function _doPreRebaseAndReturnDifference() internal returns (uint, uint) {
        uint _unaccountedUnderlying = _calculateAndHandleUnaccountedUnderlying();
        uint _underlyingFromRewards = _collectRewards();
        if (totalUseableBalanceInEther == 0) {
            return (0, 0);
        }

        if (getWorthInEther() < (totalUseableBalanceInEther + redeemableInEther)) {
            return (_underlyingFromRewards + _unaccountedUnderlying, _unaccountedUnderlying + _underlyingFromRewards);
        }
        uint _extra = getWorthInEther() - (totalUseableBalanceInEther + redeemableInEther); // Using redeemableInEther for yield also
        if (_extra == 0) {
            return (_underlyingFromRewards + _unaccountedUnderlying, _unaccountedUnderlying + _underlyingFromRewards);
        }

        redeemableInEther += _extra;
        _extra = _extra.mul(1e18).div(PriceOracle(oracle).getPriceInETH(underlying));
        redeemableInUnderlying += _extra;
        uint _propotionOfExtra = _extra.mul(1e18).div(totalUseableBalanceInUnderlying);
        totalUseableBalanceInUnderlying -= _extra;
        totalUseableBalanceInEther -= _propotionOfExtra.mul(totalUseableBalanceInEther).div(1e18);
        return (
            _extra + _underlyingFromRewards + _unaccountedUnderlying,
            _underlyingFromRewards + _unaccountedUnderlying
        );
    }

    /*
     * Calculate yield from underlying wrapped token
     */
    function _calculateWrappedRebaseAmount() internal returns (uint, bool) {
        uint256 _currentWrappingFactor = IERC4626(underlying).convertToAssets(1e18);
        if (_currentWrappingFactor <= wrappingFactor) return (0, true);
        uint _difference = 0;
        bool _positive = true;
        _difference = (totalUseableBalanceInUnderlying.mul(_currentWrappingFactor).div(wrappingFactor)).sub(
            totalUseableBalanceInUnderlying
        );
        wrappingFactor = _currentWrappingFactor;
        return (_difference, _positive);
    }

    /*
     * Update the deposited and redeemable balances
     */
    function _updateDepositedAndRedeemable(uint _difference) internal {
        if (_difference == 0) return;
        uint _differenceInUnderlying = _difference.mul(1e18).div(PriceOracle(oracle).getUnderlyingPrice(this));
        PriceOracle(oracle).validateUnderlyingPrice(LLToken(this));

        uint _proportion = _differenceInUnderlying.mul(1e18).div(totalUseableBalanceInUnderlying);
        totalUseableBalanceInUnderlying = totalUseableBalanceInUnderlying.sub(_differenceInUnderlying);
        uint _redeemableInEtherBasedOnProportion = totalUseableBalanceInEther.mul(_proportion).div(1e18);
        totalUseableBalanceInEther = (totalUseableBalanceInEther).sub(_redeemableInEtherBasedOnProportion);
        redeemableInEther = redeemableInEther.add(_redeemableInEtherBasedOnProportion);
        redeemableInUnderlying = redeemableInUnderlying.add(_differenceInUnderlying);
    }

    /*
     * Rebase the protocol token i.e. DSD
     */
    function rebase() external nonReentrant returns (uint) {
        require(msg.sender == address(comptroller), "!comptroller");
        (uint256 _difference, uint256 _alreadyAccounted) = _doPreRebaseAndReturnDifference();
        bool _positiveRebase = true;
        ComptrollerInterface _comptroller = ComptrollerInterface(comptroller);
        PriceOracle _oracle = _comptroller.oracle();

        if (isWrapped) {
            (uint _differenceWrapped, bool _positiveRebaseWrapped) = _calculateWrappedRebaseAmount();
            if (_positiveRebaseWrapped) {
                _difference = _difference.add(_differenceWrapped);
            }
        }
        _difference = _difference.mul(_oracle.getUnderlyingPrice(this)).div(1e18);
        PriceOracle(_oracle).validateUnderlyingPrice(LLToken(this));

        uint256 _protocolTokenYieldedSupplyWad = IDSD(DSD).totalSupply();
        if (_protocolTokenYieldedSupplyWad == 0) {
            revert("Rebase: TS = 0");
        }

        uint256 _assetDecimals = EIP20Interface(underlying).decimals(); // Reusing EIP20 for ERC20
        uint256 _protocolTokenDecimals = DSDInterface(DSD).decimals();
        if (_assetDecimals > _protocolTokenDecimals) {
            _difference = _difference / (10 ** (_assetDecimals - _protocolTokenDecimals));
        } else {
            _difference = _difference * (10 ** (_protocolTokenDecimals - _assetDecimals));
        }
        if (_difference == 0) {
            emit Distribution(address(this), 0, 0, 0);
            return 0;
        }
        _difference = _distributeDifferenceAndCalculateRebaseAmount(_difference, _positiveRebase);
        _updateDepositedAndRedeemable(_difference.sub(_alreadyAccounted));

        console.log("Rebase: %s", _difference);

        uint256 _newLiquidityIndex;
        if (_positiveRebase) {
            _newLiquidityIndex = (_protocolTokenYieldedSupplyWad + _difference).mul(1e36).div(
                _protocolTokenYieldedSupplyWad
            );
        }
        (uint256 currentLiquidityIndex, ) = IDSD(DSD).getMultiplier();
        uint256 delta = (_newLiquidityIndex * 1e6) / currentLiquidityIndex;
        if (delta <= limitRebaseMin) {
            revert("Delta limit:min");
        }
        if (limitRebaseMax <= delta) {
            revert("Delta limit:max");
        }

        IDSD(DSD).setMultiplier(_newLiquidityIndex);
        emit Rebased(
            address(this),
            _newLiquidityIndex,
            _protocolTokenYieldedSupplyWad,
            DSDInterface(DSD).totalSupply()
        );
    }

    /**
     * Diverge the yield for all DSD holders, multi-rewards (collateral providers share) and esLTOKEN holders(via Fund)
     * @param _difference Yield got from all possible sources
     * @param _positive There is a yield and not a loss
     */
    function _distributeDifferenceAndCalculateRebaseAmount(uint _difference, bool _positive) internal returns (uint) {
        console.log("Total Yield", _difference);
        if (_positive == false) return _difference;
        if (_difference == 0) return 0;
        uint _partForMultirewards = _difference.mul(multiRewardShareInBps).div(10000);
        uint _partForEsLTOKEN = _difference.mul(esLTOKENShareInBps).div(10000);
        IDSD(DSD).rbmMint(address(this), _partForEsLTOKEN + _partForMultirewards);

        EIP20Interface(DSD).approve(multiReward, _partForMultirewards);
        IMultiRewardInterface(multiReward).notifyRewardAmount(DSD, _partForMultirewards, 86400);
        console.log("MultiReward: %s", _partForMultirewards);

        EIP20Interface(DSD).approve(fund, _partForEsLTOKEN);
        IFund(fund).notifyRewardAmount(_partForEsLTOKEN);
        console.log("Fund: %s", _partForEsLTOKEN);
        console.log("Rebase: %s", _difference.sub(_partForMultirewards).sub(_partForEsLTOKEN));

        emit Distribution(
            address(this),
            _partForMultirewards,
            _partForEsLTOKEN,
            _difference.sub(_partForMultirewards).sub(_partForEsLTOKEN)
        );
        return _difference.sub(_partForMultirewards).sub(_partForEsLTOKEN);
    }

    /**
     * Redeem yield from the protocol in exchange of DSD
     * @param _amountInDSD amount in DSD to redeem
     * @param _recipient address to send the yield
     */
    function redeemDsd(uint _amountInDSD, address _recipient) external nonReentrant returns (uint) {
        address _dsdController = IMiniComptroller(address(comptroller)).dsdController();
        require(msg.sender == address(_dsdController), "!dsd_controller");
        require(_amountInDSD > 0, "!=0");
        uint _redeembleInUnderlyingInUsd = redeemableInUnderlying.mul(PriceOracle(oracle).getUnderlyingPrice(this)).div(
            1e18
        );
        require(_amountInDSD <= _redeembleInUnderlyingInUsd, "NE_UNDRLYING");

        if (redeemFromYieldFeeInBps > 0) {
            uint _fee = _amountInDSD.mul(redeemFromYieldFeeInBps).div(10000);
            _amountInDSD = _amountInDSD.sub(_fee);
        }

        uint256 _worthInEther = _amountInDSD.mul(1e18).div(PriceOracle(oracle).getETHPriceInUSD());
        uint256 _worthInUnderlying = _amountInDSD.mul(1e18).div(PriceOracle(oracle).getUnderlyingPrice(this));
        PriceOracle(oracle).validateUnderlyingPrice(LLToken(this));

        redeemableInEther -= _worthInEther;
        redeemableInUnderlying -= _worthInUnderlying;

        EIP20Interface(underlying).transfer(_recipient, _worthInUnderlying);
        emit RedeemedFromYield(_recipient, _amountInDSD, _worthInUnderlying);
        return _worthInUnderlying;
    }

    /**
     * Rigid Redeem DSD in exchange of underlying
     * @param _provider Rigid Provider
     * @param _redeemer Redeemer
     * @param _amountInDSD Amount to redeem in DSD
     */
    function rigidRedeem(
        address payable _provider,
        address payable _redeemer,
        uint _amountInDSD
    ) external payable nonReentrant returns (uint) {
        address _dsdController = IMiniComptroller(address(comptroller)).dsdController();
        require(msg.sender == address(_dsdController), "!dsd_controller");
        require(_amountInDSD > 0, "!=0");
        require(redemptionProvider[_provider], "NOT_PROVIDER");

        uint256 _worthInUnderlying = _amountInDSD.mul(1e18).div(PriceOracle(oracle).getUnderlyingPrice(this));
        if (rigidRedeemFeeInBps > 0) {
            _worthInUnderlying = _worthInUnderlying.mul(10000 - rigidRedeemFeeInBps).div(10000);
        }

        PriceOracle(oracle).validateUnderlyingPrice(LLToken(this));
        redeemFresh(_provider, 0, _worthInUnderlying, _redeemer);
        emit RigidRedemption(_provider, _redeemer, _amountInDSD, _worthInUnderlying);
    }

    /**
     * @notice Opt-in for providing redemption
     */
    function becomeRedemptionProvider() external {
        require(!redemptionProvider[msg.sender], "ALRDY");
        redemptionProvider[msg.sender] = true;
    }

    /**
     * @notice Opt-out from providing redemption
     */
    function stopRedemptionProvider() external {
        require(redemptionProvider[msg.sender], "ALRDY");
        redemptionProvider[msg.sender] = false;
    }

    /**
     * Set the fee deducted from rigid redeem
     * @param _rigidRedeemFeeInBps Rigid Redeem Fee in Bps
     */
    function setRigidRedeemFeeInBps(uint _rigidRedeemFeeInBps) external {
        require(msg.sender == admin, "!admin");
        require(_rigidRedeemFeeInBps <= 1000, ">1000");
        rigidRedeemFeeInBps = _rigidRedeemFeeInBps;
    }

    /**
     * Set the fee deducted from soft redeem
     * @param _redeemFromYieldFeeInBps Redeem Fee in Bps
     */
    function setRedeemFromYieldFeeInBps(uint _redeemFromYieldFeeInBps) external {
        require(msg.sender == admin, "!admin");
        require(_redeemFromYieldFeeInBps <= 1000, ">1000");
        redeemFromYieldFeeInBps = _redeemFromYieldFeeInBps;
    }

    /*
     * Set the strategy contract address
     * @param _strategy address of the strategy contract
     */
    function setStrategy(address _strategy) external {
        require(msg.sender == admin, "!admin");
        require(_strategy != address(0), "0");
        strategy = _strategy;
        if (EIP20Interface(underlying).balanceOf(address(this)) > 0) {
            bool _success = EIP20Interface(underlying).transfer(
                strategy,
                EIP20Interface(underlying).balanceOf(address(this))
            );
            require(_success, "STRT_TRNFR_FAIL");
            IStrategy(strategy).deposit();
        }
    }

    /**
     * @notice Remove the strategy from the LLToken
     */
    function removeStrategy() external {
        require(msg.sender == admin, "!admin");
        require(strategy != address(0), "ALRDY");
        IStrategy(strategy).exit();
        strategy = address(0);
    }
}
