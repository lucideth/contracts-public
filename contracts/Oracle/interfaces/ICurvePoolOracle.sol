pragma solidity ^0.5.16;

interface ICurvePoolOracle {
    function price_oracle() external view returns (uint256);
    function get_virtual_price() external view returns (uint256);

}