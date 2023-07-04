// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IGeneralPool.sol";
import "./interfaces/IMinimalSwapInfoPool.sol";
import "./interfaces/IPoolSwapStructs.sol";


abstract contract BalancerExchange {

    int256 public constant MAX_VALUE = 10 ** 27;

    IVault private vault;

    function setVault(address _vault) internal {
        vault = IVault(_vault);
    }

    function exchange(
        bytes32 poolId,
        IVault.SwapKind kind,
        IAsset tokenIn,
        IAsset tokenOut,
        address sender,
        address recipient,
        uint256 amount,
        uint256 limit
    ) internal returns (uint256) {

        IERC20(address(tokenIn)).approve(address(vault), IERC20(address(tokenIn)).balanceOf(address(this)));

        IVault.SingleSwap memory sSwap;
        sSwap.poolId = poolId;
        sSwap.kind = kind;
        sSwap.assetIn = tokenIn;
        sSwap.assetOut = tokenOut;
        sSwap.amount = amount;

        IVault.FundManagement memory fM;
        fM.sender = sender;
        fM.fromInternalBalance = false;
        fM.recipient = payable(recipient);
        fM.toInternalBalance = false;

        return vault.swap(sSwap, fM, limit, block.timestamp + 600);
    }
    function batchExchange(
        bytes32 poolId1,
        bytes32 poolId2,
        IVault.SwapKind kind,
        IAsset tokenIn,
        IAsset tokenMid,
        IAsset tokenOut,
        address sender,
        address payable recipient,
        uint256 amount
    ) internal returns (uint256) {

        IERC20(address(tokenIn)).approve(address(vault), amount);

        IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](2);

        IVault.BatchSwapStep memory batchSwap1;
        batchSwap1.poolId = poolId1;
        batchSwap1.assetInIndex = 0;
        batchSwap1.assetOutIndex = 1;
        batchSwap1.amount = amount;
        swaps[0] = batchSwap1;

        IVault.BatchSwapStep memory batchSwap2;
        batchSwap2.poolId = poolId2;
        batchSwap2.assetInIndex = 1;
        batchSwap2.assetOutIndex = 2;
        batchSwap2.amount = 0;
        swaps[1] = batchSwap2;

        IAsset[] memory assets = new IAsset[](3);
        assets[0] = tokenIn;
        assets[1] = tokenMid;
        assets[2] = tokenOut;

        IVault.FundManagement memory fM;
        fM.sender = sender;
        fM.fromInternalBalance = false;
        fM.recipient = recipient;
        fM.toInternalBalance = false;

        int256[] memory limits = new int256[](3);
        if (kind == IVault.SwapKind.GIVEN_IN) {
            limits[0] = MAX_VALUE;
            limits[1] = MAX_VALUE;
            limits[2] = MAX_VALUE;
        } else {
            limits[0] = 0;
            limits[1] = 0;
            limits[2] = 0;
        }

        return uint256(- vault.batchSwap(kind, swaps, assets, fM, limits, block.timestamp + 600)[2]);
    }
}
