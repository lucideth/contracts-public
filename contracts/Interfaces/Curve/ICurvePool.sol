// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface ICurvePool {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);

    function transfer(address to, uint value) external returns (bool);

    function transferFrom(address from, address to, uint value) external returns (bool);

    function get_virtual_price() external view returns (uint256);

    function add_liquidity(uint256[2] calldata _amounts, uint256 min_mint_amount, bool use_eth) external;

    function add_liquidity(uint256[] calldata _amounts, uint256 min_mint_amount) external;
    
    function add_liquidity(uint256[2] calldata _amounts, uint256 min_mint_amount) external;

    function add_liquidity(uint256[3] calldata _amounts, uint256 min_mint_amount) external;
    
    function add_liquidity(uint256[4] calldata _amounts, uint256 min_mint_amount) external;

    function add_liquidity(uint256[3] calldata _amounts, uint256 min_mint_amount, bool use_eth) external;
    
    function add_liquidity(uint256[4] calldata _amounts, uint256 min_mint_amount, bool use_eth) external;

    function balances(uint256) external view returns (uint256);

    function calc_token_amount(address _pool, uint256[4] calldata _amounts, bool _is_deposit) external returns (uint256);

    function calc_token_amount(uint256[2] calldata _amounts) external returns (uint256);

    function calc_token_amount(uint256[] calldata _amounts, bool _is_deposit) external returns (uint256);

    function calc_token_amount(uint256[2] calldata _amounts, bool _is_deposit) external returns (uint256);

    function calc_token_amount(uint256[3] calldata _amounts, bool _is_deposit) external returns (uint256);

    function calc_token_amount(uint256[4] calldata _amounts, bool _is_deposit) external returns (uint256);

    function remove_liquidity(address _pool, uint256 _amount, uint256[4] calldata _min_amounts, bool _use_underlying) external;

    function remove_liquidity(uint256 _amount, uint256[2] calldata _min_amounts, bool _use_underlying) external;

    function remove_liquidity(uint256 _amount, uint256[2] calldata _min_amounts, bool _use_underlying, address _receiver) external;

    function remove_liquidity(uint256 _amount, uint256[2] calldata _min_amounts) external;

    function remove_liquidity_one_coin(address _pool, uint256 _amount, uint256 _index, uint256 _minAmount) external;

    function remove_liquidity_one_coin(uint256 _amount, uint256 _index, uint256 _minAmount) external;

    function remove_liquidity_one_coin(uint256 _amount, int128 _index, uint256 _minAmount) external;
    function remove_liquidity_one_coin(uint256 _amount, int128 _index, uint256 _minAmount, bool _use_underlying) external;

    function remove_liquidity_one_coin(uint256 _amount, uint256 _index, uint256 _minAmount, bool _use_underlying) external;

    function remove_liquidity_one_coin(uint256 _amount, uint256 _index, uint256 _minAmount, bool _use_underlying, address _receiver) external returns (uint256);

    // function calc_withdraw_one_coin(uint256 _token_amount, uint256 _index) external view returns (uint256);
    function calc_withdraw_one_coin(uint256 _token_amount, int128 i) external view returns (uint256);

    function coins(uint256 _index) external view returns (address);

    function remove_liquidity_imbalance(uint256[2] calldata _amounts, uint256 maxBurnAmount) external;
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external view returns (uint256); 

}
