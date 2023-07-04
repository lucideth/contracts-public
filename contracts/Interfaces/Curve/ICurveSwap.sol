// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface ICurveSwap {
    function mint(address gauge_addr) external;
    function exchange_multiple(
        address[9] calldata _route,
        uint256[3][4] calldata _swap_params,
        uint256 _amount,
        uint256 _expected,
        address[4] calldata _pools,
        address _receiver
    ) external returns (uint256);
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy)
        external
        returns (uint256);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy)
        external
        returns (uint256);
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_uamount)
        external
        returns (uint256);
}